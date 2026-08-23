#!/bin/bash
# Regression test for #550: a *top-level* (define-values <formals> <expr>)
# must match its produced values to <formals> with lambda-style arity, exactly
# as the internal-definition path (compiler_lambda.zig's call-with-values
# desugaring) already did. handleDefineValues in vm_eval.zig used to bind a
# prefix and continue whenever the producer yielded a single non-`values`
# result — so too few / too many / zero-formals mismatches ran with exit 0.
#
# This path only fires for a bare top-level form (not one wrapped in a let /
# lambda body, nor one handed to `eval` with an explicit immutable
# `(environment ...)`), which is why it needs an out-of-process test rather
# than a SRFI-64 assertion — a top-level raise flips the whole file's exit
# code. See tests/scheme/srfi/srfi244.scm.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

# A mismatch must (a) exit non-zero and (b) report KP3003, the same arity
# diagnostic the internal call-with-values consumer lambda raises — not the
# KP2001 "invalid syntax" the multi-value arm used to return.
assert_raises() {
    local label="$1"
    local prog="$2"
    local out status=0
    out=$(printf '%s\n' "$prog" | "$KAAPPI" 2>&1) || status=$?
    if [[ "$status" -ne 0 ]] && grep -q "KP3003" <<< "$out"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — status=$status, output: $out"
        FAIL=$((FAIL + 1))
    fi
}

# A well-matched form must exit 0 and print the expected marker.
assert_ok() {
    local label="$1"
    local prog="$2"
    local expected="$3"
    local out status=0
    out=$(printf '%s\n' "$prog" | "$KAAPPI" 2>&1) || status=$?
    if [[ "$status" -eq 0 ]] && [[ "$out" == "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — status=$status, output: $out (expected: $expected)"
        FAIL=$((FAIL + 1))
    fi
}

P='(import (scheme base) (scheme write))'

# --- mismatches: the #550 reproductions, plus their dotted/multi-value kin ---
assert_raises "too few fixed values (values 1) for (a b)" \
    "$P
(define-values (a b) (values 1))"
assert_raises "too many fixed values (values 1 2 3) for (a b)" \
    "$P
(define-values (a b) (values 1 2 3))"
assert_raises "zero formals against one value" \
    "$P
(define-values () 42)"
assert_raises "single bare value for two formals" \
    "$P
(define-values (a b) 1)"
assert_raises "dotted formals with too few fixed values" \
    "$P
(define-values (a b . rest) (values 1))"
assert_raises "multi-value too few for three formals" \
    "$P
(define-values (a b c) (values 1 2))"

# --- well-matched forms of every <formals> shape must still work ---
assert_ok "exact fixed arity" \
    "$P
(define-values (a b) (values 1 2))
(display (+ a b))(newline)" "3"
assert_ok "zero formals over zero values" \
    "$P
(define-values () (values))
(display 'ok)(newline)" "ok"
assert_ok "single non-values expression is one value" \
    "$P
(define-values (x) (+ 20 22))
(display x)(newline)" "42"
assert_ok "dotted formals collect the rest" \
    "$P
(define-values (h . t) (values 1 2 3))
(write (cons h t))(newline)" "(1 2 3)"
assert_ok "dotted tail may collect nothing" \
    "$P
(define-values (h . t) (values 9))
(write (cons h t))(newline)" "(9)"
assert_ok "bare identifier collects every value as a list" \
    "$P
(define-values xs (values 1 2 3))
(write xs)(newline)" "(1 2 3)"
assert_ok "bare identifier over zero values is the empty list" \
    "$P
(define-values xs (values))
(write xs)(newline)" "()"

echo ""
echo "define-values-toplevel-arity-550: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
