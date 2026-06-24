#!/bin/bash
# Sandbox escape test suite
# Each test runs a Scheme expression under --sandbox and asserts it produces
# an error (the blocked operation must not return a value).
# Exit 0 = all gated capabilities are blocked. Any escape = exit 1.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

assert_blocked() {
    local label="$1"
    local expr="$2"
    local output
    output=$(echo "$expr" 2>&1 | "$KAAPPI" --sandbox 2>&1 || true)
    if echo "$output" | grep -qi "error"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — no error produced, output: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_works() {
    local label="$1"
    local expr="$2"
    local output
    output=$(echo "$expr" 2>&1 | "$KAAPPI" --sandbox 2>&1 || true)
    # Filter out DebugAllocator messages (not Scheme errors)
    local filtered
    filtered=$(echo "$output" | grep -v "DebugAllocator" | grep -v "empty stack trace" | grep -v "^$")
    if echo "$filtered" | grep -q "^error:"; then
        echo "FAIL: $label — should work but got error: $filtered"
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $label (allowed)"
        PASS=$((PASS + 1))
    fi
}

echo "=== Sandbox escape tests ==="
echo

# --- FFI ---
assert_blocked "ffi-open" '(ffi-open "libc.dylib")'
assert_blocked "ffi-fn" '(ffi-fn #f "puts" (list (quote string)) (quote void))'
assert_blocked "ffi-callback" '(ffi-callback (lambda (x) x) (list (quote int)) (quote int))'

# --- File I/O ---
assert_blocked "open-input-file" '(open-input-file "README.md")'
assert_blocked "open-output-file" '(open-output-file "/tmp/sandbox-escape.txt")'
assert_blocked "open-binary-input-file" '(open-binary-input-file "README.md")'
assert_blocked "open-binary-output-file" '(open-binary-output-file "/tmp/sandbox-escape.bin")'
assert_blocked "file-exists?" '(file-exists? "README.md")'
assert_blocked "delete-file" '(delete-file "/tmp/sandbox-escape.txt")'
assert_blocked "call-with-input-file" '(call-with-input-file "README.md" read)'
assert_blocked "call-with-output-file" '(call-with-output-file "/tmp/sandbox-escape.txt" (lambda (p) (write "x" p)))'
assert_blocked "with-input-from-file" '(with-input-from-file "README.md" read)'
assert_blocked "with-output-to-file" '(with-output-to-file "/tmp/sandbox-escape.txt" (lambda () (display "x")))'

# --- eval / load / environment ---
assert_blocked "eval" '(eval (quote (+ 1 2)))'
assert_blocked "load" '(load "README.md")'
assert_blocked "environment" '(environment (quote (scheme base)))'
assert_blocked "get-environment-variable" '(get-environment-variable "HOME")'
assert_blocked "get-environment-variables" '(get-environment-variables)'
assert_blocked "command-line" '(command-line)'
assert_blocked "exit" '(exit 0)'

# --- Gated library imports ---
assert_blocked "import scheme file" '(import (scheme file))'
assert_blocked "import scheme load" '(import (scheme load))'
assert_blocked "import scheme eval" '(import (scheme eval))'
assert_blocked "import scheme process-context" '(import (scheme process-context))'
assert_blocked "import kaappi ffi" '(import (kaappi ffi))'
assert_blocked "import srfi 170" '(import (srfi 170))'
assert_blocked "import srfi 18 (threads)" '(import (srfi 18))'

echo
echo "=== Verifying safe operations work ==="

assert_works "arithmetic" '(+ 1 2)'
assert_works "string ops" '(string-length "hello")'
assert_works "list ops" '(map car (list (list 1 2) (list 3 4)))'
assert_works "string ports" '(let ((p (open-output-string))) (write "ok" p) (get-output-string p))'
assert_works "hash tables" '(let ((h (make-hash-table))) (hash-table-set! h "k" 1) (hash-table-ref h "k"))'
assert_works "green fibers" '(import (kaappi fibers)) (fiber-join (spawn (lambda () 42)))'

echo
echo "=== Resource limits ==="

# Timeout test
output=$(echo '(let loop () (loop))' | "$KAAPPI" --timeout 200 2>&1 || true)
if echo "$output" | grep -qF "timed out"; then
    echo "PASS: --timeout stops infinite loop"
    PASS=$((PASS + 1))
else
    echo "FAIL: --timeout did not stop infinite loop"
    FAIL=$((FAIL + 1))
fi

# Memory limit test
output=$(echo '(define (eat n a) (if (= n 0) a (eat (- n 1) (cons n a)))) (eat 1000000 (list))' | "$KAAPPI" --max-memory 100000 2>&1 || true)
if echo "$output" | grep -qF "OutOfMemory"; then
    echo "PASS: --max-memory stops excessive allocation"
    PASS=$((PASS + 1))
else
    echo "FAIL: --max-memory did not stop excessive allocation"
    FAIL=$((FAIL + 1))
fi

# Normal program works with generous limits
output=$(echo '(display (+ 1 2))' | "$KAAPPI" --timeout 5000 --max-memory 10000000 2>&1 || true)
if echo "$output" | grep -qF "3"; then
    echo "PASS: normal program works with generous limits"
    PASS=$((PASS + 1))
else
    echo "FAIL: normal program broken by limits"
    FAIL=$((FAIL + 1))
fi

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "SANDBOX ESCAPE DETECTED"
    exit 1
fi

echo "All sandbox boundaries hold."
exit 0
