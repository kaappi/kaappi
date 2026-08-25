#!/bin/bash
# Regression test for kaappi#1899: a type-error message must name the offending
# value's identity, not render it as an opaque tag.
#
# `primitives.safeValueDescription` (src/primitives.zig) used to print symbol,
# string, vector, bytevector, rational and bignum as `#<symbol>`/`#<string>`/…
# and characters (which are immediates) as `#<char>`. The one thing the user
# needs — WHICH value was wrong — was exactly what got dropped. It now renders
# the identifying content, while staying bounded (long strings/vectors are
# summarised, never dumped) and cycle-safe (a compound value gets a one-level
# summary, never a recursive print).

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

assert_output_contains() {
    local label="$1"
    local input="$2"
    local expected="$3"
    local output
    output=$(echo "$input" | "$KAAPPI" 2>&1 || true)
    if grep -qF "$expected" <<< "$output"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected' in output; got:"
        echo "    $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_output_lacks() {
    local label="$1"
    local input="$2"
    local forbidden="$3"
    local output
    output=$(echo "$input" | "$KAAPPI" 2>&1 || true)
    if grep -qF "$forbidden" <<< "$output"; then
        echo "FAIL: $label — output still contains '$forbidden'"
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $label"
        PASS=$((PASS + 1))
    fi
}

# The length of a bounded description must stay small no matter how big the
# value is: assert the `got ...` field of the message is under a cap.
assert_got_field_bounded() {
    local label="$1"
    local input="$2"
    local cap="$3"
    local output got_field
    output=$(echo "$input" | "$KAAPPI" 2>&1 || true)
    # Everything after the last "got " on the error line.
    got_field=$(grep -oE 'got .*$' <<< "$output" | tail -1 || true)
    if [ -z "$got_field" ]; then
        echo "FAIL: $label — no 'got ...' field in output; got: $output"
        FAIL=$((FAIL + 1))
    elif [ "${#got_field}" -le "$cap" ]; then
        echo "PASS: $label (${#got_field} <= $cap bytes)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — 'got' field is ${#got_field} bytes, over $cap: $got_field"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Type-error value identity (kaappi#1899) ==="
echo

# --- Symbols: name, not #<symbol> ---
echo "-- Symbols --"
assert_output_contains "vector-ref names the symbol argument" \
    "(vector-ref (vector 1 2) 'somesym)" "got somesym"
assert_output_contains "string-length names the symbol argument" \
    "(string-length 'foo)" "got foo"
assert_output_lacks "symbol no longer renders as an opaque tag" \
    "(string-length 'foo)" "#<symbol>"

# --- Strings: bounded, quoted prefix, not #<string> ---
echo
echo "-- Strings --"
assert_output_contains "type error quotes a short string value" \
    '(vector-ref (make-vector 3 0) "hello")' 'got "hello"'
assert_output_lacks "string no longer renders as an opaque tag" \
    '(vector-ref (make-vector 3 0) "hello")' "#<string>"
# A long string is truncated with a trailing ellipsis and stays bounded.
assert_output_contains "a long string is truncated with ..." \
    '(char-upcase "0123456789012345678901234567890123456789 and more")' '...'
assert_got_field_bounded "the rendered long string stays bounded" \
    '(char-upcase "0123456789012345678901234567890123456789 and more")' 50

# --- Vectors / bytevectors: one-level length summary, not #<vector> ---
echo
echo "-- Vectors and bytevectors --"
assert_output_contains "vector renders as a length summary" \
    '(char-upcase (vector 1 2 3 4 5))' "got #<vector length 5>"
assert_output_contains "bytevector renders as a length summary" \
    '(char-upcase (bytevector 1 2 3))' "got #<bytevector length 3>"
# A large vector must be summarised, never dumped element by element.
assert_got_field_bounded "a large vector stays bounded" \
    '(char-upcase (make-vector 100000 0))' 40

# --- Characters: literal #\a form, not #<char> ---
echo
echo "-- Characters (unverified #<char> claim — confirmed real) --"
assert_output_contains "a character renders in its #\\ form" \
    '(+ 1 (integer->char 97))' 'got #\a'
assert_output_lacks "character no longer renders as an opaque tag" \
    '(+ 1 (integer->char 97))' "#<char>"
assert_output_contains "a named character renders by name" \
    '(+ 1 #\newline)' 'got #\newline'

# --- Exact numbers: bignum and rational render their value ---
echo
echo "-- Bignum and rational --"
assert_output_contains "a bignum in u128 range renders its value" \
    '(char-upcase 99999999999999999999)' "got 99999999999999999999"
assert_output_contains "a negative bignum keeps its sign" \
    '(char-upcase -12345678901234567890)' "got -12345678901234567890"
# A bignum beyond u128 falls back conservatively (no heap scratch on the
# error path) but stays bounded and self-describing.
assert_output_contains "a huge bignum falls back to #<bignum>" \
    '(char-upcase 999999999999999999999999999999999999999999999999999999)' "got #<bignum>"
assert_output_contains "a rational renders as num/den" \
    '(char-upcase 1/3)' "got 1/3"

# --- No regression for values that already rendered ---
echo
echo "-- No regression for inline values --"
assert_output_contains "fixnum still renders as its value" \
    '(string-length 42)' "got 42"
assert_output_contains "flonum keeps its .0 (kaappi#1916)" \
    '(vector-ref (vector 1 2) 1.0)' "got 1.0"
assert_output_contains "empty list still renders as ()" \
    "(vector-ref (vector 1 2) '())" "got ()"
assert_output_contains "boolean still renders as #f" \
    '(vector-ref (vector 1 2) #f)' "got #f"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "TYPE-ERROR VALUE IDENTITY REGRESSION DETECTED"
    exit 1
fi

echo "All type-error value identity tests pass."
exit 0
