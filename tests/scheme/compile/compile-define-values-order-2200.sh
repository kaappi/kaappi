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

# The producer of the define-values depends on an earlier top-level define, so
# any hoisting into the preamble breaks it.
cat > "$WORK/prog.scm" <<'SCM'
(define x 1)
(define-values (a b) (values x 2))
(display (list a b))
(newline)
SCM

echo "=== interpreter (the tier oracle) ==="
interp_status=0
interp_out="$(interp_stdout "$KAAPPI_ABS" "$WORK" "$WORK/prog.scm")" || interp_status=$?
if [ "$interp_out" == "(1 2)" ] && [ "$interp_status" -eq 0 ]; then
    ok "interpreted run prints (1 2) and exits 0"
else
    bad "interpreted run prints (1 2) and exits 0" \
        "stdout: $interp_out" "exit: $interp_status"
fi

echo "=== standalone binary matches the interpreter ==="
skip_without_zig "the standalone-binary check needs a Zig toolchain"

# The .sbc's compiler hash folds in the producing binary's git build id
# (docs/dev/cache.md), so a .sbc made by a stale zig-out/bin/kaappi goes stale
# against a bundler rebuilt from current source (kaappi#1930). Build the
# interpreter into an isolated prefix from the same source the bundler uses, and
# produce the .sbc with THAT binary. -p keeps zig-out/ and the caller's binary
# untouched.
(cd "$REPO_ROOT" && zig build -p "$WORK/interp" > /dev/null 2>&1)
"$WORK/interp/bin/kaappi" --compile -o "$WORK/prog.sbc" "$WORK/prog.scm" > /dev/null

(cd "$REPO_ROOT" && zig build -Dbundle="$WORK/prog.sbc" -p "$WORK/bundle" > /dev/null 2>&1)
native_status=0
native_out="$("$WORK/bundle/bin/kaappi" 2> /dev/null)" || native_status=$?

if [ "$native_out" == "(1 2)" ] && [ "$native_status" -eq 0 ]; then
    ok "standalone binary prints (1 2) and exits 0"
else
    bad "standalone binary prints (1 2) and exits 0" \
        "stdout: $native_out" "exit: $native_status"
fi

if assert_tiers_agree "standalone binary vs interpreter" \
    "$interp_out" "$interp_status" "$native_out" "$native_status"; then
    ok "the standalone binary agrees with the interpreter on stdout and exit status"
else
    FAIL=$((FAIL + 1))
fi

echo "=== control: an env-setup declaration is still hoisted and works ==="
# A top-level `import` must still reach the preamble and be replayed before the
# compiled forms — that is what a preamble is for. Proving it still works
# compiled guards against over-restricting the hoisting.
cat > "$WORK/env.scm" <<'SCM'
(import (scheme base) (scheme write))
(define-values (p q) (values 10 20))
(display (+ p q))
(newline)
SCM
env_interp_status=0
env_interp_out="$(interp_stdout "$KAAPPI_ABS" "$WORK" "$WORK/env.scm")" || env_interp_status=$?

"$WORK/interp/bin/kaappi" --compile -o "$WORK/env.sbc" "$WORK/env.scm" > /dev/null
(cd "$REPO_ROOT" && zig build -Dbundle="$WORK/env.sbc" -p "$WORK/envbundle" > /dev/null 2>&1)
env_native_status=0
env_native_out="$("$WORK/envbundle/bin/kaappi" 2> /dev/null)" || env_native_status=$?

if assert_tiers_agree "env-setup import + define-values compiled" \
    "$env_interp_out" "$env_interp_status" "$env_native_out" "$env_native_status"; then
    ok "an import is still hoisted and the compiled artifact prints 30"
else
    FAIL=$((FAIL + 1))
fi

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
