#!/bin/bash
# `kaappi check` — compile-only static analysis (kaappi#1511).
#
# Covers the three KP4xxx lint classes, the exit-code and --deny-warnings
# contract, --diagnostics=json parity, the "never reject a valid program"
# invariant (shadowing / redefinition / quoting / macro suppression), and the
# conformance guard: the full R7RS suite must pass `check` with zero errors.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
R7RS_SUITE="$SCRIPT_DIR/../r7rs/r7rs-tests.scm"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# assert_exit <label> <expected-code> <source> [extra check args...]
assert_exit() {
    local label="$1" expected="$2" src="$3"
    shift 3
    printf '%s\n' "$src" > "$TMP/prog.scm"
    local status=0
    "$KAAPPI" check "$@" "$TMP/prog.scm" > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $status"
        FAIL=$((FAIL + 1))
    fi
}

# assert_out <label> <pattern> <source> [extra check args...]
assert_out() {
    local label="$1" pattern="$2" src="$3"
    shift 3
    printf '%s\n' "$src" > "$TMP/prog.scm"
    local out
    out="$("$KAAPPI" check "$@" "$TMP/prog.scm" 2>&1 || true)"
    if echo "$out" | grep -qE "$pattern"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — output did not match /$pattern/"
        echo "  got: $out"
        FAIL=$((FAIL + 1))
    fi
}

echo "== arity (KP4002) =="
assert_exit "(car 1 2) is an error"          1 '(car 1 2)'
assert_out  "(car 1 2) reports KP4002"       'error\[KP4002\]' '(car 1 2)'
assert_exit "(cons 1) is an error"           1 '(cons 1)'
assert_exit "(- ) below variadic minimum"    1 '(-)'

echo "== type of literal argument (KP4003) =="
assert_exit "(car 5) is an error"                    1 '(car 5)'
assert_out  "(car 5) reports KP4003"                 'error\[KP4003\]' '(car 5)'
assert_out  '(vector-ref "s" 0) reports KP4003'      'error\[KP4003\]' '(vector-ref "s" 0)'
assert_exit "(car (quote ())) empty list not a pair" 1 "(car '())"

echo "== unknown top-level variable (KP4001, warning) =="
assert_exit "unknown variable is only a warning"      0 '(display no-such-name)'
assert_out  "unknown variable reports KP4001"         'warning\[KP4001\]' '(display no-such-name)'
assert_exit "--deny-warnings promotes the warning"    1 '(display no-such-name)' --deny-warnings

echo "== valid programs pass (the invariant) =="
assert_exit "(+ 1 2) is clean"                        0 '(+ 1 2)'
assert_exit "(car (quote (1 2))) is clean"            0 "(car '(1 2))"
assert_exit "non-literal argument is not inferred"    0 '(define (f v) (vector-ref v 0))'
assert_exit "a lexically-bound name shadows the builtin" 0 '(define (f car) (car 1 2))'
assert_exit "a top-level redefinition is left alone"  0 '(define (car x) x)
(car 1 2 3)'
assert_exit "quoted data is never a call"             0 "'(car 1 2)"
assert_exit "a forward reference is legal"            0 '(define (f) (g))
(define (g) 1)'

echo "== macro-synthesized calls are suppressed =="
assert_exit "imported test-error use is not linted" 0 '(import (chibi test))
(test-error (car 5))'

echo "== read / compile errors still surface with KP codes =="
assert_out "unclosed list is a read error"  'error\[KP1' '(car 1'
assert_out "malformed if is a compile error" 'error\[KP2' '(if)'

echo "== --diagnostics=json parity =="
printf '(car 5)\n' > "$TMP/j.scm"
JSON="$("$KAAPPI" check --diagnostics=json "$TMP/j.scm" 2>&1 || true)"
if echo "$JSON" | grep -q '"code":"KP4003"' && echo "$JSON" | grep -q '"severity":1'; then
    echo "PASS: json emits an LSP Diagnostic with the KP code and severity"
    PASS=$((PASS + 1))
else
    echo "FAIL: json output malformed: $JSON"
    FAIL=$((FAIL + 1))
fi

echo "== conformance guard: the R7RS suite passes check with zero errors =="
status=0
"$KAAPPI" check "$R7RS_SUITE" > "$TMP/r7rs.out" 2>&1 || status=$?
if [[ "$status" -eq 0 ]]; then
    echo "PASS: R7RS suite passes kaappi check (exit 0)"
    PASS=$((PASS + 1))
else
    echo "FAIL: R7RS suite failed kaappi check (exit $status)"
    grep -E 'error\[KP' "$TMP/r7rs.out" | head -20 || true
    FAIL=$((FAIL + 1))
fi

echo ""
echo "check: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
