#!/bin/bash
# Regression test for #2156: `kaappi --compile` and `kaappi --disassemble` are
# compile-only commands, and must not run the program's own code.
#
# Both routed every form `vm_eval.handleTopLevelForm` claims through the
# *evaluator*. Three of those eight heads carry ordinary program code —
# `begin`, `cond-expand` and `define-values` — so a `(delete-file ...)` inside
# one really deleted the file while the `.sbc` was being produced. The form was
# then also recorded in the artifact's preamble, so across compile + run the
# effect happened twice.
#
# The discriminating control is a *bare* top-level `(delete-file ...)`, which
# was never executed at compile time: this is not "compiling runs the program",
# it is specific to those heads.
#
# The fix splices top-level `begin` / `cond-expand` into the form stream (their
# bodies are compiled, not run — only a `cond-expand`'s branch *selection* is a
# compile-time question) and records `define-values` for replay without
# evaluating it. That also repaired an ordering divergence: a top-level `begin`
# used to reach the artifact via the preamble, which replays entirely *before*
# the compiled forms, so `one / (begin two) / three` printed `two one three`.
#
# Hermetic: KAAPPI_HOME points at a throwaway dir; every probe file lives in a
# temp dir. Only the last section needs a Zig toolchain (it builds a standalone
# binary to prove the effect still happens exactly once at run time).
#
# Usage: bash tests/scheme/compile/compile-toplevel-side-effects-2156.sh [path-to-kaappi]

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${1:-zig-out/bin/kaappi}"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# Every probe below asserts that a file *survives* a command, so a command that
# never ran would pass every one of them. Resolve and verify the binary up
# front, and fail loudly rather than silently testing nothing.
if [ ! -x "$KAAPPI" ]; then
    echo "FAIL: no kaappi binary at '$KAAPPI' — build it first (zig build)"
    exit 1
fi
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

PASS=0
FAIL=0

HOMEDIR="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$HOMEDIR" "$WORK"' EXIT
export KAAPPI_HOME="$HOMEDIR"

ok() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

bad() {
    echo "FAIL: $1"
    shift
    for line in "$@"; do echo "  $line"; done
    FAIL=$((FAIL + 1))
}

# probe_survives <label> <scheme-form> <kaappi-args...>
#
# Writes a one-form program whose VICTIM placeholder is the path of a file that
# exists, runs the given compile-only command over it, and asserts the file is
# still there afterwards.
probe_survives() {
    local label="$1" form="$2"
    shift 2
    local victim="$WORK/victim.txt"
    local prog="$WORK/probe.scm"
    echo hi > "$victim"
    printf '%s\n(display "compiled")(newline)\n' "${form//VICTIM/$victim}" > "$prog"
    local status=0
    "$KAAPPI_ABS" "$@" "$prog" > /dev/null 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        bad "$label" "the command itself failed (exit $status) — the probe proves nothing"
    elif [ -f "$victim" ]; then
        ok "$label"
    else
        bad "$label" "the compile-only command deleted $victim"
    fi
}

echo "=== --compile does not execute top-level bodies ==="
probe_survives "--compile leaves a cond-expand body unrun" \
    '(cond-expand (else (delete-file "VICTIM")))' --compile -o "$WORK/out.sbc"
probe_survives "--compile leaves a begin body unrun" \
    '(begin (delete-file "VICTIM"))' --compile -o "$WORK/out.sbc"
probe_survives "--compile leaves a define-values producer unrun" \
    '(define-values (a) (values (delete-file "VICTIM")))' --compile -o "$WORK/out.sbc"

echo "=== --disassemble does not execute top-level bodies ==="
probe_survives "--disassemble leaves a cond-expand body unrun" \
    '(cond-expand (else (delete-file "VICTIM")))' --disassemble
probe_survives "--disassemble leaves a begin body unrun" \
    '(begin (delete-file "VICTIM"))' --disassemble
probe_survives "--disassemble leaves a define-values producer unrun" \
    '(define-values (a) (values (delete-file "VICTIM")))' --disassemble

echo "=== control: a bare top-level form was never executed either ==="
probe_survives "--compile leaves a bare delete-file unrun (control)" \
    '(delete-file "VICTIM")' --compile -o "$WORK/out.sbc"

echo "=== control: the declarations a compiler depends on still run ==="
# `include` must still be evaluated at compile time — the included file's
# definitions are what later forms are compiled against. Its inclusion is the
# discriminating control for isEnvSetup(): a compile-only command is allowed to
# read the filesystem for declarations, just not to run the program.
cat > "$WORK/inc-body.scm" <<'SCM'
(define (from-include) 'included)
SCM
cat > "$WORK/uses-include.scm" <<'SCM'
(include "inc-body.scm")
(display (from-include))
(newline)
SCM
if "$KAAPPI_ABS" --compile -o "$WORK/inc.sbc" "$WORK/uses-include.scm" > /dev/null 2>&1 &&
    [ -f "$WORK/inc.sbc" ]; then
    ok "--compile still evaluates a top-level include"
else
    bad "--compile still evaluates a top-level include" "compiling the file failed"
fi

echo "=== the artifact still runs the bodies, once, in program order ==="
skip_without_zig "the standalone-binary check needs a Zig toolchain"

VICTIM="$WORK/run-victim.txt"
echo hi > "$VICTIM"
cat > "$WORK/prog.scm" <<SCM
(display "one")(newline)
(begin (display "two")(newline))
(cond-expand (else (display "three")(newline)))
(define-values (a b) (values 4 5))
(display (+ a b))(newline)
(begin (delete-file "$VICTIM"))
SCM

expected="$("$KAAPPI_ABS" "$WORK/prog.scm")"
if [ "$expected" != "one
two
three
9" ]; then
    bad "interpreted run has the expected output" "actual: $expected"
else
    ok "interpreted run has the expected output"
fi
# The interpreted run consumed the victim; restore it for the compiled run.
echo hi > "$VICTIM"

"$KAAPPI_ABS" --compile -o "$WORK/prog.sbc" "$WORK/prog.scm" > /dev/null

if [ -f "$VICTIM" ]; then
    ok "producing the .sbc left the victim alone"
else
    bad "producing the .sbc left the victim alone" "compile deleted $VICTIM"
fi

# -p isolates the install prefix so a concurrent suite's zig-out is untouched.
(cd "$REPO_ROOT" && zig build -Dbundle="$WORK/prog.sbc" -p "$WORK/bundle" > /dev/null 2>&1)
actual="$("$WORK/bundle/bin/kaappi")"

if [ "$actual" == "$expected" ]; then
    ok "the standalone binary's output matches the interpreted run"
else
    bad "the standalone binary's output matches the interpreted run" \
        "expected: $(printf '%s' "$expected" | tr '\n' '|')" \
        "actual:   $(printf '%s' "$actual" | tr '\n' '|')"
fi

if [ ! -f "$VICTIM" ]; then
    ok "running the standalone binary performed the effect (exactly once)"
else
    bad "running the standalone binary performed the effect (exactly once)" \
        "$VICTIM still exists — the begin body never ran"
fi

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
