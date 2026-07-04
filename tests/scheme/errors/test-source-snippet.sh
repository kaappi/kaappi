#!/bin/bash
# Test that error messages include source code snippets

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

assert_contains() {
    local label="$1"
    local input="$2"
    local expected="$3"
    local output
    output=$(echo "$input" | "$KAAPPI" 2>&1 || true)
    if echo "$output" | grep -qF "$expected"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected' in output"
        echo "  got: $output"
        FAIL=$((FAIL + 1))
    fi
}

# Test: runtime error shows source snippet
TMPDIR=$(mktemp -d)
TMPFILE="$TMPDIR/test.scm"
echo '(define (foo x) (+ x 1))
(foo "hello")' > "$TMPFILE"
output=$("$KAAPPI" "$TMPFILE" 2>&1 || true)
if echo "$output" | grep -qF '(define (foo x) (+ x 1))'; then
    echo "PASS: runtime error includes source snippet"
    PASS=$((PASS + 1))
else
    echo "FAIL: runtime error should include source snippet"
    echo "  got: $output"
    FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
