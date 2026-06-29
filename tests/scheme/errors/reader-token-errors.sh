#!/bin/bash
# Regression tests for reader token validation error cases
# Issues: #313, #312, #311
set -e

KAAPPI="${KAAPPI:-./zig-out/bin/kaappi}"
PASS=0
FAIL=0

check_error() {
    local desc="$1"
    local input="$2"
    if printf '%s\n' "$input" | $KAAPPI 2>&1 | grep -qi "error"; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc — expected error for: $input"
        FAIL=$((FAIL + 1))
    fi
}

# #313: Codepoints above U+10FFFF
check_error "#\\x110000 (above max Unicode)" '#\x110000'
check_error "#\\x1FFFFF (above max Unicode)" '#\x1FFFFF'
check_error "#\\xD800 (surrogate)" '#\xD800'
check_error "#\\xDFFF (surrogate)" '#\xDFFF'

# #312: Missing delimiter after character literals
check_error "#\\x41z (no delimiter after hex char)" '#\x41z'
check_error "#\\a1 (no delimiter after single char)" '#\a1'
check_error "#\\space. (no delimiter after named char)" '#\space.'

# #311: Missing delimiter after boolean literals
check_error "#t1 (no delimiter after #t)" '#t1'
check_error "#f. (no delimiter after #f)" '#f.'
check_error "#true1 (no delimiter after #true)" '#true1'
check_error "#false+ (no delimiter after #false)" '#false+'

echo ""
echo "Reader token errors: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
