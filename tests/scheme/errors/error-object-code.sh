#!/bin/bash
# error-object-code accessor tests (KEP-0005 §4, kaappi#1508).
#
# Verifies the Scheme-visible diagnostic accessor exported from the
# (kaappi diagnostics) library: a coded runtime error yields its interned
# KPnnnn symbol, a plain (error ...) and any non-error value yield #f, the
# eq?-dispatch reads naturally in a guard, and the capability is probeable via
# both the `kaappi-diagnostics` cond-expand identifier and (features).

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

# Assert the interpreter's STDOUT for an input equals EXACTLY the expected
# string (trailing newline stripped). Exact match matters here: a substring
# test for "#f" could hide a spurious error line. stderr is dropped on purpose
# — every assertion below checks a `(display …)` value on stdout, and a Debug
# build writes benign DebugAllocator teardown notices to stderr that would
# otherwise concatenate onto the value (kaappi runs `display` with no trailing
# newline). An unexpected error still fails the check: it goes to stderr and
# leaves stdout empty, so `got ''` ≠ the expected value.
assert_output_equals() {
    local label="$1"
    local input="$2"
    local expected="$3"
    local output
    output=$(echo "$input" | "$KAAPPI" 2>/dev/null || true)
    if [ "$output" = "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected', got '$output'"
        FAIL=$((FAIL + 1))
    fi
}

IMPORT='(import (scheme base) (kaappi diagnostics))'

# --- Coded runtime errors: the accessor returns the KP symbol ---------------

# division-by-zero raises through the exception system with the code riding on
# the object.
assert_output_equals "division by zero -> KP3004" \
    "$IMPORT (display (error-object-code (guard (e (#t e)) (/ 1 0))))" \
    "KP3004"

# Natively-propagating runtime errors (type/undefined/arity/index) are coded at
# the with-exception-handler boundary when a guard catches them.
assert_output_equals "type error -> KP3002" \
    "$IMPORT (display (error-object-code (guard (e (#t e)) (car 5))))" \
    "KP3002"
assert_output_equals "undefined variable -> KP3001" \
    "$IMPORT (display (error-object-code (guard (e (#t e)) no-such-binding)))" \
    "KP3001"
assert_output_equals "arity mismatch -> KP3003" \
    "$IMPORT (display (error-object-code (guard (e (#t e)) ((lambda (x) x) 1 2))))" \
    "KP3003"

# --- #f cases: uncoded and non-error inputs never raise ---------------------

assert_output_equals "user (error ...) -> #f" \
    "$IMPORT (display (error-object-code (guard (e (#t e)) (error \"boom\" 1 2))))" \
    "#f"
assert_output_equals "raised non-error value -> #f" \
    "$IMPORT (display (error-object-code (guard (e (#t e)) (raise 'sym))))" \
    "#f"
assert_output_equals "non-error datum -> #f" \
    "$IMPORT (display (error-object-code 42))" \
    "#f"

# --- eq? dispatch, the intended use inside a guard --------------------------

assert_output_equals "eq? on the returned symbol dispatches" \
    "$IMPORT (display (guard (e ((eq? (error-object-code e) 'KP3004) 'caught-div0) (else 'other)) (/ 1 0)))" \
    "caught-div0"

# --- R7RS surface is untouched (additive metadata only) ---------------------

assert_output_equals "error-object-message unchanged for coded errors" \
    "$IMPORT (display (error-object-message (guard (e (#t e)) (error \"plain\" 1))))" \
    "plain"

# --- Feature discoverability (KEP-0004 mechanism) ---------------------------

assert_output_equals "kaappi-diagnostics cond-expand identifier is present" \
    "(cond-expand (kaappi-diagnostics (display 'yes)) (else (display 'no)))" \
    "yes"
assert_output_equals "(features) lists kaappi-diagnostics" \
    "(import (scheme base)) (display (if (memq 'kaappi-diagnostics (features)) 'yes 'no))" \
    "yes"
assert_output_equals "(library (kaappi diagnostics)) is importable per cond-expand" \
    "(cond-expand ((library (kaappi diagnostics)) (display 'yes)) (else (display 'no)))" \
    "yes"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "ERROR-OBJECT-CODE REGRESSION DETECTED"
    exit 1
fi

echo "All error-object-code tests pass."
exit 0
