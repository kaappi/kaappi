#!/bin/bash
# Regression test for #1031: KAAPPI_HOME must be honored by the interpreter
# and ffi-open, not just thottam.

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

assert_exit() {
    local label="$1" expected="$2"
    shift 2
    local status=0
    "$@" > /tmp/kaappi-home-test-out 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $status"
        cat /tmp/kaappi-home-test-out
        FAIL=$((FAIL + 1))
    fi
}

# Create a library in a custom KAAPPI_HOME
mkdir -p "$TMPDIR_TESTS/lib/kaappi"
cat > "$TMPDIR_TESTS/lib/kaappi/test-home.sld" <<'SLD'
(define-library (kaappi test-home)
  (import (scheme base) (scheme write))
  (export test-home-ok)
  (begin
    (define (test-home-ok) (display "home-ok") (newline))))
SLD

# Test script that imports the library
cat > "$TMPDIR_TESTS/test-import.scm" <<'SCM'
(import (kaappi test-home))
(test-home-ok)
SCM

# With KAAPPI_HOME set, the library should be importable
assert_exit "KAAPPI_HOME import succeeds" 0 \
    env KAAPPI_HOME="$TMPDIR_TESTS" "$KAAPPI" "$TMPDIR_TESTS/test-import.scm"

# Without KAAPPI_HOME (and no --lib-path), the library should NOT be found
assert_exit "import fails without KAAPPI_HOME" 1 \
    env -u KAAPPI_HOME "$KAAPPI" "$TMPDIR_TESTS/test-import.scm"

echo ""
echo "$PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
