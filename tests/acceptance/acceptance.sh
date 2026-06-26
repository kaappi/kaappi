#!/bin/bash
# Post-release acceptance tests
# Exercises a release binary as an end user would experience it.
# Catches issues invisible to CI (signing, entitlements, bundling).
#
# Usage: KAAPPI=/path/to/kaappi THOTTAM=/path/to/thottam bash acceptance.sh [version]
#   version — expected version string (e.g. "0.6.3"), optional

set -euo pipefail

KAAPPI="${KAAPPI:-kaappi}"
THOTTAM="${THOTTAM:-thottam}"
EXPECTED_VERSION="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

assert_ok() {
    local label="$1"
    local expr="$2"
    local output
    if output=$(echo "$expr" | "$KAAPPI" 2>&1); then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — exit code $?, output: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_output() {
    local label="$1"
    local expr="$2"
    local expected="$3"
    local output
    output=$(echo "$expr" | "$KAAPPI" 2>&1 || true)
    if echo "$output" | grep -qF "$expected"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected', got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_ok() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — exit code $?"
        FAIL=$((FAIL + 1))
    fi
}

assert_command_output() {
    local label="$1"
    local expected="$2"
    shift 2
    local output
    output=$("$@" 2>&1 || true)
    if echo "$output" | grep -qF "$expected"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected', got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_fail() {
    local label="$1"
    local expr="$2"
    local output
    if output=$(echo "$expr" | "$KAAPPI" 2>&1); then
        echo "FAIL: $label — expected failure but got exit 0, output: $output"
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $label"
        PASS=$((PASS + 1))
    fi
}

echo "=== Post-release acceptance tests ==="
echo "Binary: $KAAPPI"
echo

# --- Binary basics ---
echo "-- Binary basics --"
assert_exit_ok "--help exits 0" "$KAAPPI" --help

if [ -n "$EXPECTED_VERSION" ]; then
    assert_command_output "--version matches release" "$EXPECTED_VERSION" "$KAAPPI" --version
fi

# --- Arithmetic (exercises JIT on supported platforms) ---
echo
echo "-- Arithmetic + JIT --"
assert_output "integer addition" '(display (+ 1 2))' '3'
assert_output "integer multiplication" '(display (* 6 7))' '42'
assert_output "integer subtraction" '(display (- 100 58))' '42'
assert_output "nested arithmetic" '(display (+ (* 3 4) (- 10 2)))' '20'
assert_output "negative numbers" '(display (+ -5 8))' '3'
assert_output "division" '(display (/ 10 2))' '5'
assert_output "comparison" '(display (< 1 2))' '#t'
assert_output "zero? predicate" '(display (zero? 0))' '#t'
assert_output "large fixnum" '(display (* 1000000 1000000))' '1000000000000'
assert_output "float arithmetic" '(display (+ 1.5 2.5))' '4.0'

# --- Data structures ---
echo
echo "-- Data structures --"
assert_output "cons/car/cdr" '(display (car (cons 1 2)))' '1'
assert_output "list creation" '(display (list 1 2 3))' '(1 2 3)'
assert_output "vector" '(display (vector-ref (vector 10 20 30) 1))' '20'
assert_output "string ops" '(display (string-length "hello"))' '5'
assert_output "bytevector" '(display (bytevector-u8-ref (bytevector 1 2 3) 2))' '3'

# --- Unicode ---
echo
echo "-- Unicode --"
assert_output "unicode string length" '(display (string-length "café"))' '4'
assert_output "unicode char" '(display #\λ)' 'λ'
assert_output "emoji string" '(display (string-length "🎉"))' '1'

# --- Standard library imports ---
echo
echo "-- Library imports --"
assert_output "scheme base" '(import (scheme base)) (display "ok")' 'ok'
assert_output "scheme write" '(import (scheme write)) (display "ok")' 'ok'
assert_output "srfi 1" '(import (srfi 1)) (display (iota 5))' '(0 1 2 3 4)'
assert_output "srfi 69" '(import (srfi 69)) (let ((h (make-hash-table))) (hash-table-set! h "k" 42) (display (hash-table-ref h "k")))' '42'

# --- File execution ---
echo
echo "-- File execution --"
assert_command_output "run .scm file" "hello from kaappi" "$KAAPPI" "$SCRIPT_DIR/hello.scm"

# --- Tail call optimization ---
echo
echo "-- Tail call optimization --"
assert_output "deep tail recursion" \
    '(define (loop n) (if (= n 0) (display "done") (loop (- n 1)))) (loop 1000000)' \
    'done'

# --- Closures and higher-order functions ---
echo
echo "-- Closures --"
assert_output "closure" '(define (make-adder n) (lambda (x) (+ n x))) (display ((make-adder 10) 32))' '42'
assert_output "map" '(display (map (lambda (x) (* x x)) (list 1 2 3 4)))' '(1 4 9 16)'

# --- Continuations ---
echo
echo "-- Continuations --"
assert_output "call/cc escape" \
    '(display (call-with-current-continuation (lambda (k) (k 42) 99)))' '42'

# --- Error handling ---
echo
echo "-- Error handling --"
assert_output "error raises" '(error "test error")' 'error'
assert_output "guard catches" \
    '(display (guard (e (#t "caught")) (error "boom")))' 'caught'

# --- Sandbox mode ---
echo
echo "-- Sandbox --"
output=$(echo '(open-input-file "README.md")' | "$KAAPPI" --sandbox 2>&1 || true)
if echo "$output" | grep -qi "error"; then
    echo "PASS: sandbox blocks file I/O"
    PASS=$((PASS + 1))
else
    echo "FAIL: sandbox did not block file I/O"
    FAIL=$((FAIL + 1))
fi

# --- thottam ---
echo
echo "-- thottam --"
assert_exit_ok "thottam --help" "$THOTTAM" --help

if [ -n "$EXPECTED_VERSION" ]; then
    assert_command_output "thottam --version" "$EXPECTED_VERSION" "$THOTTAM" --version
fi

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "ACCEPTANCE TEST FAILURES DETECTED"
    exit 1
fi

echo "All acceptance tests pass."
exit 0
