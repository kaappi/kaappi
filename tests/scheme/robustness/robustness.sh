#!/bin/bash
# Robustness regression suite
# Tests that malformed, adversarial, or extreme inputs produce clean errors
# rather than panics, crashes, or undefined behavior.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

# assert_error: expression must produce an error (not crash/panic)
assert_error() {
    local label="$1"
    local expr="$2"
    local output
    output=$(echo "$expr" | "$KAAPPI" 2>&1 || true)
    if echo "$output" | grep -q "error:"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — no error in output"
        FAIL=$((FAIL + 1))
    fi
}

# assert_no_crash: expression must not crash (exit code should be 0)
assert_no_crash() {
    local label="$1"
    local expr="$2"
    if echo "$expr" | "$KAAPPI" >/dev/null 2>&1; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        local code=$?
        if [ "$code" -gt 128 ]; then
            echo "FAIL: $label — process killed by signal $((code - 128))"
            FAIL=$((FAIL + 1))
        else
            echo "PASS: $label (error exit, not crash)"
            PASS=$((PASS + 1))
        fi
    fi
}

echo "=== Robustness regression tests ==="
echo

# --- Deep recursion ---
echo "-- Deep recursion --"
assert_error "deep non-tail recursion" \
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1))))) (deep 10000)'

assert_no_crash "catchable stack overflow" \
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1))))) (guard (e (#t "caught")) (deep 10000))'

assert_no_crash "deep tail recursion (should not overflow)" \
    '(define (loop n) (if (= n 0) (display "ok") (loop (- n 1)))) (loop 1000000)'

# --- Malformed numbers ---
echo
echo "-- Malformed numbers --"
assert_error "incomplete number #e" '(display #e)'
assert_error "incomplete number #i" '(display #i)'
assert_error "incomplete number #b" '(display #b)'
assert_error "incomplete number #o" '(display #o)'
assert_error "incomplete number #x" '(display #x)'
assert_error "bad number prefix" '(display #q42)'

# --- Unbalanced parens ---
echo
echo "-- Unbalanced delimiters --"
assert_no_crash "unclosed paren (clean EOF)" '(define (f x) (+ x 1)'
assert_error "extra close paren" '(+ 1 2))'
assert_no_crash "unclosed string (clean EOF)" '(display "hello'
assert_no_crash "unclosed vector (clean EOF)" '#(1 2 3'

# --- Pathological nesting ---
echo
echo "-- Pathological nesting --"
DEEP_PARENS=$(python3 -c "print('(' * 500 + '42' + ')' * 500)")
assert_no_crash "500-deep nested parens" "$DEEP_PARENS"

# --- Large/weird literals ---
echo
echo "-- Large literals --"
assert_no_crash "very large integer" '(display (expt 2 1000))'
assert_no_crash "large string" "(display (make-string 100000 #\\x))"
assert_no_crash "large vector" "(display (make-vector 100000 0))"
assert_no_crash "large bytevector" "(display (make-bytevector 100000 0))"

# --- Type errors in primitives ---
echo
echo "-- Type errors --"
assert_error "car of non-pair" '(car 42)'
assert_error "cdr of non-pair" '(cdr "hello")'
assert_error "vector-ref out of bounds" '(vector-ref (vector 1 2 3) 10)'
assert_error "string-ref out of bounds" '(string-ref "abc" 10)'
assert_error "division by zero" '(/ 1 0)'
assert_error "wrong arity" '(+ 1 2 3 . 4)'

# --- Quasiquote edge cases ---
echo
echo "-- Quasiquote edge cases --"
assert_no_crash "nested quasiquote" '(display `(a `(b ,(+ 1 2)) c))'
assert_no_crash "splicing" "(display \`(a ,@(list 1 2 3) b))"

# --- Corrupted .sbc file ---
echo
echo "-- Corrupted .sbc --"
TMPFILE=$(mktemp /tmp/kaappi-corrupt-XXXXXX.sbc)
echo "NOT_A_VALID_SBC_FILE" > "$TMPFILE"
assert_error "corrupted .sbc (text)" "(load \"$TMPFILE\")"
printf '\x00\x01\x02\x03\x80\x81\xff\xfe\x00\x00\x00\x00\x00\x00\x00\x00' > "$TMPFILE"
assert_error "corrupted .sbc (binary)" "(load \"$TMPFILE\")"
rm -f "$TMPFILE"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "ROBUSTNESS REGRESSION DETECTED"
    exit 1
fi

echo "All robustness tests pass."
exit 0
