#!/bin/bash
# Regression test for #2200: a compiled artifact must run a top-level
# `define-values` in program order, not hoist it into the preamble.
#
# `kaappi --compile` records every top-level form `vm_eval.handleTopLevelForm`
# claims into the artifact's PREAMBLE, and the bundle runner replays the whole
# preamble *before* any compiled form. For the five `TopLevelHead.isEnvSetup()`
# declarations (import/include/include-ci/define-library/define-record-type)
# that hoisting is correct — they establish the environment later forms compile
# against. `define-values` is NOT env setup: its producer is arbitrary program
# code that can depend on an earlier top-level form, so hoisting it reorders
# execution and can fail where the interpreter succeeds.
#
# Repro: `(define x 1) (define-values (a b) (values x 2))` — hoisting the
# `define-values` ahead of `(define x 1)` made the artifact die with
# `preamble error[KP3001]: undefined variable 'x'`.
#
# The fix routes `define-values` through ordinary compilation (it has a
# compilable lowering, `compileDefineValues`), so it keeps its position in the
# compiled stream instead of reaching the preamble at all.
#
# The interpreter is this tier's oracle (tests/scheme/CLAUDE.md): the standalone
# binary's stdout and exit status must match the interpreter's.
#
# ONE program, deliberately (kaappi#2431). This used to bundle two — the repro,
# and a control proving an `import` alongside `define-values` still works, so
# that the fix could not have been an over-restriction — and each
# `zig build -Dbundle=` recompiles the whole interpreter around its embedded
# bytecode. Together with an interpreter build of its own that was three full
# builds, which put the script within ordinary runner variance of the 600s
# shell-test timeout and made `test (ubuntu-latest, Debug)` — a required check
# — fail roughly one run in fourteen. The program below carries both
# properties at once: the `define-values` depends on an earlier top-level
# `define` (the repro), and the file imports `(scheme write)` for its `display`
# (the control). `topLevelHead` classifies purely on the head symbol, with no
# dependence on whether an import has been seen, so folding the two together
# changes nothing about which path either form takes. The interpreter build is
# now shared with the rest of the suite via `fixture_interpreter`, leaving one
# `zig build` unique to this script.
#
# Usage: bash tests/scheme/compile/compile-define-values-order-2200.sh [path-to-kaappi]

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${1:-zig-out/bin/kaappi}"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

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

# `(define-values (a b) ...)`'s producer reads `x`, bound by an earlier
# top-level form, so any hoisting into the preamble breaks it. The `import`
# is the control: it must still reach the preamble and be replayed, which is
# what a preamble is for, and `display` resolving at all is the proof.
cat > "$WORK/prog.scm" <<'SCM'
(import (scheme base) (scheme write))
(define x 1)
(define-values (a b) (values x 2))
(display (list a b))
(newline)
(define-values (p q) (values 10 20))
(display (+ p q))
(newline)
SCM

EXPECTED="(1 2)
30"

echo "=== interpreter (the tier oracle) ==="
interp_status=0
interp_out="$(interp_stdout "$KAAPPI_ABS" "$WORK" "$WORK/prog.scm")" || interp_status=$?
if [ "$interp_out" == "$EXPECTED" ] && [ "$interp_status" -eq 0 ]; then
    ok "interpreted run prints (1 2) then 30 and exits 0"
else
    bad "interpreted run prints (1 2) then 30 and exits 0" \
        "stdout: $interp_out" "exit: $interp_status"
fi

echo "=== standalone binary matches the interpreter ==="
skip_without_zig "the standalone-binary check needs a Zig toolchain"

# The .sbc's compiler hash folds in the producing binary's git build id
# (docs/dev/cache.md), so a .sbc made by a stale zig-out/bin/kaappi goes stale
# against a bundler rebuilt from current source (kaappi#1930). fixture_interpreter
# builds one from the same source, with the same -Doptimize, as the bundler
# below — and shares it with every other script that needs one, so only the
# first caller in a run pays for it. zig-out/ and the caller's binary are left
# untouched.
INTERP="$(fixture_interpreter "$REPO_ROOT")"
"$INTERP" --compile -o "$WORK/prog.sbc" "$WORK/prog.scm" > /dev/null

(cd "$REPO_ROOT" && zig build -Dbundle="$WORK/prog.sbc" -Doptimize=ReleaseSafe \
    -p "$WORK/bundle" > /dev/null 2>&1)
native_status=0
native_out="$("$WORK/bundle/bin/kaappi" 2> /dev/null)" || native_status=$?

if [ "$native_out" == "$EXPECTED" ] && [ "$native_status" -eq 0 ]; then
    ok "standalone binary prints (1 2) then 30 and exits 0"
else
    bad "standalone binary prints (1 2) then 30 and exits 0" \
        "stdout: $native_out" "exit: $native_status"
fi

if assert_tiers_agree "standalone binary vs interpreter" \
    "$interp_out" "$interp_status" "$native_out" "$native_status"; then
    ok "the standalone binary agrees with the interpreter on stdout and exit status"
else
    FAIL=$((FAIL + 1))
fi

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
