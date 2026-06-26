#!/bin/bash
# WASM acceptance tests
# Exercises kaappi.wasm via wasmtime. No JIT, no FFI, no filesystem.
# WASM binary requires file arguments (no REPL/stdin mode), so each
# expression is written to a temp file under cwd (wasmtime pre-opens ".").
#
# Usage: KAAPPI_WASM=/path/to/kaappi.wasm bash test-wasm.sh

set -euo pipefail

KAAPPI_WASM="${KAAPPI_WASM:-kaappi.wasm}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPFILE="_wasm_acceptance_tmp.scm"
trap "rm -f '$TMPFILE'" EXIT
PASS=0
FAIL=0

run_wasm_expr() {
    echo "$1" > "$TMPFILE"
    wasmtime run --dir=. "$KAAPPI_WASM" "$TMPFILE" 2>&1 || true
}

assert_output() {
    local label="$1"
    local expr="$2"
    local expected="$3"
    local output
    output=$(run_wasm_expr "$expr")
    if echo "$output" | grep -qF "$expected"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected', got: $output"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== WASM acceptance tests ==="
echo "Binary: $KAAPPI_WASM"
echo

echo "-- Arithmetic --"
assert_output "addition" '(display (+ 1 2))' '3'
assert_output "multiplication" '(display (* 6 7))' '42'
assert_output "nested" '(display (+ (* 3 4) (- 10 2)))' '20'
assert_output "float" '(display (+ 1.5 2.5))' '4.0'

echo
echo "-- Data structures --"
assert_output "list" '(display (list 1 2 3))' '(1 2 3)'
assert_output "vector" '(display (vector-ref (vector 10 20 30) 1))' '20'
assert_output "string" '(display (string-length "hello"))' '5'

echo
echo "-- Unicode --"
assert_output "unicode string" '(display (string-length "café"))' '4'

echo
echo "-- Higher-order functions --"
assert_output "map" '(display (map (lambda (x) (* x x)) (list 1 2 3)))' '(1 4 9)'
assert_output "closure" '(define (make-adder n) (lambda (x) (+ n x))) (display ((make-adder 10) 32))' '42'

echo
echo "-- Tail calls --"
assert_output "deep tail recursion" \
    '(define (loop n) (if (= n 0) (display "done") (loop (- n 1)))) (loop 100000)' \
    'done'

echo
echo "-- Continuations --"
assert_output "call/cc" \
    '(display (call-with-current-continuation (lambda (k) (k 42) 99)))' '42'

echo
echo "-- Error handling --"
assert_output "guard" \
    '(display (guard (e (#t "caught")) (error "boom")))' 'caught'

echo
echo "-- File execution --"
cp "$SCRIPT_DIR/hello.scm" _wasm_acceptance_hello.scm
trap "rm -f '$TMPFILE' _wasm_acceptance_hello.scm" EXIT
output=$(wasmtime run --dir=. "$KAAPPI_WASM" _wasm_acceptance_hello.scm 2>&1 || true)
if echo "$output" | grep -qF "hello from kaappi"; then
    echo "PASS: file execution"
    PASS=$((PASS + 1))
else
    echo "FAIL: file execution — got: $output"
    FAIL=$((FAIL + 1))
fi

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "WASM ACCEPTANCE TEST FAILURES DETECTED"
    exit 1
fi

echo "All WASM acceptance tests pass."
exit 0
