#!/bin/bash
# Subcommand-scoped flags at global scope are a usage error, not silently
# accepted (kaappi#2096).
#
# `--check` belongs to `kaappi fmt` and `--no-opt` to `kaappi ir`, but the
# global flag loop used to accept them in any position with no scope check.
# For `--no-opt` that was merely inert; for `--check` it was a live hazard —
# one hyphen-pair from the `check` subcommand whose contract is "executes
# nothing", so `kaappi --check foo.scm` (instead of `check foo.scm`) RAN the
# program. This asserts the file is no longer executed, the two spellings are
# distinguishable by exit code, and the in-scope spellings still work.

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A program whose only observable effect is a side-effecting print, so we can
# tell "the file ran" from "the file did not run" by the presence of "ran".
PROG="$TMP/prog.scm"
printf '(display "ran\\n")\n(car 1)\n' > "$PROG"

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "== --check (global) is rejected and does NOT run the file =="
status=0
out="$("$KAAPPI" --check "$PROG" 2>&1)" || status=$?
if [[ "$status" -eq 2 ]]; then
    pass "kaappi --check exits with the usage-error status (2)"
else
    fail "kaappi --check should exit 2, got $status"
fi
if grep -qE '^ran$' <<< "$out"; then
    fail "kaappi --check executed the file (printed 'ran')"
else
    pass "kaappi --check did not execute the file"
fi
if grep -qE 'kaappi fmt' <<< "$out"; then
    pass "the error names the owning subcommand (kaappi fmt)"
else
    fail "the error should name the owning subcommand; got: $out"
fi
if grep -qE 'check` subcommand' <<< "$out"; then
    pass "the error points at the check subcommand as the likely intent"
else
    fail "the error should point at the check subcommand; got: $out"
fi

echo "== --no-opt (global) is rejected and does NOT run the file =="
status=0
out="$("$KAAPPI" --no-opt "$PROG" 2>&1)" || status=$?
if [[ "$status" -eq 2 ]]; then
    pass "kaappi --no-opt exits with the usage-error status (2)"
else
    fail "kaappi --no-opt should exit 2, got $status"
fi
if grep -qE '^ran$' <<< "$out"; then
    fail "kaappi --no-opt executed the file (printed 'ran')"
else
    pass "kaappi --no-opt did not execute the file"
fi
if grep -qE 'kaappi ir' <<< "$out"; then
    pass "the error names the owning subcommand (kaappi ir)"
else
    fail "the error should name the owning subcommand; got: $out"
fi

echo "== the check subcommand still analyses without executing =="
status=0
out="$("$KAAPPI" check "$PROG" 2>&1)" || status=$?
if [[ "$status" -eq 1 ]]; then
    pass "kaappi check reports the error (exit 1)"
else
    fail "kaappi check should exit 1, got $status"
fi
if grep -qE '^ran$' <<< "$out"; then
    fail "kaappi check executed the file (printed 'ran')"
else
    pass "kaappi check did not execute the file"
fi

echo "== fmt --check still works (in-scope) =="
UGLY="$TMP/ugly.scm"
printf '(define   x     1)\n' > "$UGLY"
status=0
out="$("$KAAPPI" fmt --check "$UGLY" 2>&1)" || status=$?
# --check reports paths needing formatting and exits nonzero without writing.
if [[ "$status" -ne 2 ]]; then
    pass "kaappi fmt --check is accepted (no usage error), exit $status"
else
    fail "kaappi fmt --check was wrongly rejected as a usage error"
fi
if grep -qE 'is a `kaappi' <<< "$out"; then
    fail "kaappi fmt --check emitted the scope-rejection message: $out"
else
    pass "kaappi fmt --check did not emit a scope-rejection message"
fi

echo "== ir --no-opt still works (in-scope) =="
CLEAN="$TMP/clean.scm"
printf '(+ 1 2)\n' > "$CLEAN"
status=0
out="$("$KAAPPI" ir --no-opt "$CLEAN" 2>&1)" || status=$?
if [[ "$status" -eq 0 ]]; then
    pass "kaappi ir --no-opt is accepted (exit 0)"
else
    fail "kaappi ir --no-opt should exit 0, got $status: $out"
fi

echo ""
echo "check-flag-scope: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
