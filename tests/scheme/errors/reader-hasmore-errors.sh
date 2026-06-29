#!/bin/bash
# Regression tests for reader hasMore() error propagation
# Issue #310: unterminated block comments and datum comments at EOF
set -e

KAAPPI="${KAAPPI:-./zig-out/bin/kaappi}"
PASS=0
FAIL=0

check_error() {
    local desc="$1"
    local input="$2"
    if printf '%s' "$input" | $KAAPPI 2>&1 | grep -qi "error"; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

# Unterminated block comments
check_error "unterminated block comment alone" '#|abc'
check_error "valid code then unterminated block comment" '1 #|comment'

# Datum comment at EOF (no datum follows #;)
check_error "datum comment at EOF with space" '1 #; '
check_error "datum comment at EOF no space" '#;'

echo ""
echo "Reader hasMore errors: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
