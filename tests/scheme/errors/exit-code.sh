#!/bin/bash
# Exit code tests
# Uncaught read/compile/runtime errors in a script (file or stdin) must make
# the process exit non-zero so test runners can't report PASS on errored
# files. Explicit (exit N) always wins. Interactive REPL is unaffected.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

assert_exit_code() {
    local label="$1"
    local expected="$2"
    shift 2
    local status=0
    "$@" > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $status"
        FAIL=$((FAIL + 1))
    fi
}

assert_stdin_exit_code() {
    local label="$1"
    local expected="$2"
    local input="$3"
    local status=0
    echo "$input" | "$KAAPPI" > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $status"
        FAIL=$((FAIL + 1))
    fi
}

# Clean script exits 0
echo '(display "ok")' > "$TMPDIR_TESTS/ok.scm"
assert_exit_code "clean script exits 0" 0 "$KAAPPI" "$TMPDIR_TESTS/ok.scm"

# Uncaught runtime error exits non-zero
echo '(car 1)' > "$TMPDIR_TESTS/rt-err.scm"
assert_exit_code "uncaught runtime error exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/rt-err.scm"

# Error mid-file still flips exit code even when later forms succeed
printf '(car 1)\n(display "recovered")\n' > "$TMPDIR_TESTS/mid-err.scm"
assert_exit_code "mid-file error exits 1 despite recovery" 1 "$KAAPPI" "$TMPDIR_TESTS/mid-err.scm"

# Undefined variable exits non-zero
echo '(no-such-procedure-xyz)' > "$TMPDIR_TESTS/undef.scm"
assert_exit_code "undefined variable exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/undef.scm"

# Read error exits non-zero
echo '(unclosed (list' > "$TMPDIR_TESTS/read-err.scm"
assert_exit_code "read error exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/read-err.scm"

# Missing file exits non-zero
assert_exit_code "missing file exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/does-not-exist.scm"

# Explicit (exit 0) wins over earlier uncaught error (R7RS: exit sets the code)
printf '(car 1)\n(exit 0)\n' > "$TMPDIR_TESTS/exit0.scm"
assert_exit_code "explicit (exit 0) after error exits 0" 0 "$KAAPPI" "$TMPDIR_TESTS/exit0.scm"

# Guarded error is caught, exits 0
echo '(import (scheme base)) (guard (e (#t (display "caught"))) (car 1))' > "$TMPDIR_TESTS/guarded.scm"
assert_exit_code "guarded error exits 0" 0 "$KAAPPI" "$TMPDIR_TESTS/guarded.scm"

# Stdin scripts behave the same
assert_stdin_exit_code "clean stdin exits 0" 0 '(display "ok")'
assert_stdin_exit_code "stdin runtime error exits 1" 1 '(car 1)'

echo ""
echo "exit-code: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
