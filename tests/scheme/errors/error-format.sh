#!/bin/bash
# Error format tests
# Verifies that errors include expected location and diagnostic information.

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
    if echo "$output" | grep -qF "$expected"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected' in output"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_output_contains() {
    local label="$1"
    local file="$2"
    local expected="$3"
    local output
    output=$("$KAAPPI" "$file" 2>&1 || true)
    if echo "$output" | grep -qF "$expected"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected' in output"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Error format tests ==="
echo

# --- Reader errors include file:line:col ---
echo "-- Reader errors --"
assert_output_contains "reader error has location" \
    '(define x #\invalid-char)' '<repl>:1:'

assert_output_contains "reader error has 'read error'" \
    '(define x #\invalid-char)' 'read error'

# --- Compile errors include location ---
echo
echo "-- Compile errors --"
assert_output_contains "compile error has location" \
    '(if)' '<repl>:1:'

assert_output_contains "compile error has 'compile error'" \
    '(if)' 'compile error'

# --- Runtime errors include file:line ---
echo
echo "-- Runtime errors from files --"

TMPDIR=$(mktemp -d)
cat > "$TMPDIR/type-err.scm" << 'SCHEME'
(define (foo x) (+ x "hello"))
(foo 42)
SCHEME

assert_file_output_contains "runtime error has file:line" \
    "$TMPDIR/type-err.scm" "type-err.scm:1:"

assert_file_output_contains "runtime error has diagnostic" \
    "$TMPDIR/type-err.scm" "expected number"

# --- Backtrace ---
cat > "$TMPDIR/backtrace.scm" << 'SCHEME'
(define (a x) (b x))
(define (b x) (c x))
(define (c x) (car x))
(a 42)
SCHEME

assert_file_output_contains "runtime error has backtrace" \
    "$TMPDIR/backtrace.scm" "called from"

assert_file_output_contains "backtrace has call site" \
    "$TMPDIR/backtrace.scm" "backtrace.scm:"

# --- Type error details ---
echo
echo "-- Type error diagnostics --"

assert_output_contains "car type error names procedure" \
    '(car 42)' "car"

assert_output_contains "car type error names expected type" \
    '(car 42)' "pair"

assert_output_contains "vector-ref bounds error" \
    '(vector-ref (vector 1 2 3) 10)' "error"

assert_output_contains "division by zero" \
    '(/ 1 0)' "error"

# --- Stack overflow ---
echo
echo "-- Stack overflow --"

assert_output_contains "stack overflow is reported" \
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1))))) (deep 10000)' "StackOverflow"

# --- Library import errors ---
echo
echo "-- Library import errors --"

assert_output_contains "library not found names the library" \
    '(import (nonexistent library))' "library not found"

assert_output_contains "library not found includes library name" \
    '(import (nonexistent library))' "nonexistent.library"

# --- Closure arity errors ---
echo
echo "-- Closure arity errors --"

assert_output_contains "named closure arity error includes name" \
    '(define (greet name) name) (greet 1 2)' "'greet'"

assert_output_contains "named closure arity error shows counts" \
    '(define (greet name) name) (greet 1 2)' "expected 1 arguments, got 2"

assert_output_contains "variadic closure arity error includes name" \
    '(define (f a b . rest) a) (f 1)' "'f'"

assert_output_contains "variadic closure arity error shows counts" \
    '(define (f a b . rest) a) (f 1)' "expected at least 2 arguments, got 1"

assert_output_contains "anonymous lambda arity error has no name" \
    '((lambda (x) x) 1 2)' "expected 1 arguments, got 2"

rm -rf "$TMPDIR"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "ERROR FORMAT REGRESSION DETECTED"
    exit 1
fi

echo "All error format tests pass."
exit 0
