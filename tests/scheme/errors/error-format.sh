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
    '(define x #\invalid-char)' '<stdin>:1:'

assert_output_contains "reader error has 'read error'" \
    '(define x #\invalid-char)' 'read error'

# --- Compile errors include location ---
echo
echo "-- Compile errors --"
assert_output_contains "compile error has location" \
    '(if)' '<stdin>:1:'

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

# --- Uncaught user-raised errors ---
# An uncaught (error ...) must print its message and irritants, not the
# raw Zig error name (was: "runtime error: error.ExceptionRaised").
echo
echo "-- Uncaught (error ...) --"

cat > "$TMPDIR/uncaught-error.scm" << 'SCHEME'
(error "index out of range" 5)
SCHEME

assert_file_output_contains "uncaught (error ...) in script shows message and irritants" \
    "$TMPDIR/uncaught-error.scm" "index out of range 5"

assert_output_contains "uncaught (error ...) in REPL shows message and irritants" \
    '(error "index out of range" 5)' "index out of range 5"

assert_output_contains "uncaught raise of non-error value shows the value" \
    '(raise 42)' "uncaught exception: 42"

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
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1))))) (deep 50000)' "StackOverflow"

# --- Library import errors ---
echo
echo "-- Library import errors --"

assert_output_contains "library not found names the library" \
    '(import (nonexistent library))' "library not found"

assert_output_contains "library not found includes library name" \
    '(import (nonexistent library))' "nonexistent.library"

# Missing dependency reports the actual missing library, not the top-level one
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
dep_output=$("$KAAPPI" --lib-path "$SCRIPT_DIR/fixtures" "$SCRIPT_DIR/fixtures/missing-dep.scm" 2>&1 || true)
if echo "$dep_output" | grep -qF "srfi.999"; then
    echo "PASS: missing dependency names the dependency"
    PASS=$((PASS + 1))
else
    echo "FAIL: missing dependency names the dependency — expected 'srfi.999' in output"
    FAIL=$((FAIL + 1))
fi

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

# Continuation captured inside a native driver (map) and resumed after that
# native call returned must raise a clear error, not silently corrupt results.
echo
echo "-- Continuation across returned native call --"
assert_output_contains "resume across dead native call is an error" \
    '(define k #f) (map (lambda (x) (call/cc (lambda (c) (set! k c) x))) (list 1 2 3)) (k 99)' \
    "continuation cannot resume across a returned native call"

# Issue #78: mismatched-length ellipsis template variables must be rejected
# with a clean compile error, not read uninitialized memory. (Moved from
# tests/scheme/smoke/ellipsis-mismatch.scm: the rejection happens at macro
# expansion time, so guard cannot catch it in-file.)
assert_output_contains "mismatched ellipsis lengths rejected cleanly" \
    '(define-syntax zip (syntax-rules () ((zip (a ...) (b ...)) (quote ((a b) ...))))) (zip (1 2 3) (4 5))' \
    "compile error"

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
