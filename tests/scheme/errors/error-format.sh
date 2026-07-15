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

# Assert the interpreter output for an input does NOT leak a raw Zig error
# name. Zig renders an error value as "error.Xxx" (a dotted, capitalized tag),
# which must never reach the user — every path maps to a registry message
# instead (KEP-0005, #1504).
assert_no_zig_leak() {
    local label="$1"
    local input="$2"
    local output
    output=$(echo "$input" | "$KAAPPI" 2>&1 || true)
    if echo "$output" | grep -qE 'error\.[A-Z][A-Za-z]+'; then
        echo "FAIL: $label — leaked a Zig error name: $(echo "$output" | grep -oE 'error\.[A-Z][A-Za-z]+' | head -1)"
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $label"
        PASS=$((PASS + 1))
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

# --- syntax-error includes message and irritants (#1142) ---
echo
echo "-- syntax-error diagnostics --"

assert_output_contains "syntax-error includes message" \
    '(syntax-error "custom msg")' 'syntax-error[KP2002]: custom msg'

assert_output_contains "syntax-error includes irritants" \
    '(syntax-error "custom msg" 42)' 'syntax-error[KP2002]: custom msg 42'

assert_output_contains "syntax-error from macro includes message" \
    '(define-syntax bad (syntax-rules () ((_ x) (syntax-error "bad usage" x)))) (bad 1)' \
    'syntax-error[KP2002]: bad usage 1'

assert_output_contains "syntax-error has location" \
    '(syntax-error "msg")' '<stdin>:1:'

assert_output_contains "caught syntax-error does not leak into next compile error" \
    '(import (scheme base)) (guard (e (#t #t)) (eval (quote (syntax-error "STALE" 999)) (environment (quote (scheme base))))) (if)' \
    'compile error'

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

assert_output_contains "stack overflow is reported with code" \
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1))))) (deep 50000)' "error[KP3008]: stack overflow"

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

# Continuation captured inside map can now be reinvoked (map is bytecode-driven).
# The old "dead native call" error no longer applies — this is a success case.

# Error message must survive dynamic-wind after-thunks that do I/O
assert_output_contains "error message preserved through dynamic-wind after with I/O" \
    '(dynamic-wind (lambda () #t) (lambda () (error "REAL-MSG")) (lambda () (display "")))' \
    "REAL-MSG"

# Issue #1032: malformed let*-values and guard must report a clean compile
# error (KP2001 invalid-syntax), not OOM and not a leaked Zig error name.
assert_output_contains "malformed let*-values reports invalid syntax" \
    '(let*-values (42) 1)' "compile error[KP2001]: invalid syntax"

assert_output_contains "malformed guard clause reports invalid syntax" \
    '(guard (e (#t "ok") . bad) 1)' "compile error[KP2001]: invalid syntax"

# Issue #78: mismatched-length ellipsis template variables must be rejected
# with a clean compile error, not read uninitialized memory. (Moved from
# tests/scheme/smoke/ellipsis-mismatch.scm: the rejection happens at macro
# expansion time, so guard cannot catch it in-file.)
assert_output_contains "mismatched ellipsis lengths rejected cleanly" \
    '(define-syntax zip (syntax-rules () ((zip (a ...) (b ...)) (quote ((a b) ...))))) (zip (1 2 3) (4 5))' \
    "compile error"

# --- Issue #1046: apply-position type errors must include procedure name ---
echo
echo "-- Apply-position error detail (issue #1046) --"
assert_output_contains "apply-position type error includes diagnostic" \
    '(apply + (list 1 "x"))' "type error"

# --- Uncaught exceptions carry message and irritants ---
echo
echo "-- Uncaught exceptions --"

# An uncaught user (error ...) or raised value carries the generic KP3000
# "uncaught exception" code; the specific KP namespace is reserved to the
# implementation, so user errors do not get a more specific code.
assert_output_contains "uncaught (error ...) shows message" \
    '(error "something went wrong" 42)' 'error[KP3000]: something went wrong 42'

assert_output_contains "uncaught (error ...) writes irritants" \
    '(error "kaboom" (list 1 2) "x")' 'error[KP3000]: kaboom (1 2) "x"'

assert_output_contains "uncaught raise of non-error object shows the value" \
    "(raise 'oops)" 'error[KP3000]: uncaught exception: oops'

assert_output_contains "uncaught exception inside procedure shows message" \
    '(define (f) (error "boom" 1)) (f)' 'error[KP3000]: boom 1'

cat > "$TMPDIR/uncaught.scm" << 'SCHEME'
(error "script boom" 7)
SCHEME

assert_file_output_contains "uncaught (error ...) in script shows message" \
    "$TMPDIR/uncaught.scm" 'error[KP3000]: script boom 7'

rm -rf "$TMPDIR"

# --- Issue #1057: error-message consistency sweep ---
echo
echo "-- Consistent error messages (issue #1057) --"

assert_output_contains "caar type error names procedure" \
    '(caar 42)' "caar"

assert_output_contains "caar type error names expected type" \
    '(caar 42)' "pair"

assert_output_contains "cadr type error names procedure" \
    '(cadr 42)' "cadr"

assert_output_contains "string-length type error names expected type" \
    '(string-length 42)' "string"

assert_output_contains "string-append type error includes proc" \
    '(string-append "a" 42)' "string-append"

assert_output_contains "symbol->string type error names expected type" \
    '(symbol->string 42)' "symbol"

assert_output_contains "gcd type error names expected type" \
    '(gcd "x" 3)' "integer"

assert_output_contains "even? type error names procedure" \
    '(even? "x")' "even?"

assert_output_contains "abs type error names expected type" \
    '(abs "x")' "number"

assert_output_contains "length type error on dotted list" \
    '(length (cons 1 2))' "proper list"

assert_output_contains "reverse type error names procedure" \
    '(reverse (cons 1 2))' "reverse"

assert_output_contains "apply type error for non-procedure" \
    '(apply 42 (list 1))' "procedure"

# --- #1375: bootstrapped iteration procedures report clean arity/type errors,
# not leaked internals ('cdr', 'make-vector', '%push-wind') ---
echo
echo "-- Bootstrapped procedure diagnostics (#1375) --"
assert_output_contains "(map car) reports map arity" \
    '(map car)' "'map': expected at least 2 arguments, got 1"

assert_output_contains "(vector-map +) reports vector-map arity" \
    '(vector-map +)' "'vector-map': expected at least 2 arguments, got 1"

assert_output_contains "(map 5 ...) names map" \
    '(map 5 (list 1 2 3))' "type error in 'map': expected procedure, got 5"

assert_output_contains "dynamic-wind bad after names dynamic-wind" \
    '(dynamic-wind (lambda () #t) (lambda () 1) 42)' \
    "type error in 'dynamic-wind': expected procedure, got 42"

assert_output_contains "%push-wind is not globally reachable" \
    '(%push-wind car car)' "undefined variable"

# --- Diagnostic codes appear per stage (KEP-0005, #1504) ---
echo
echo "-- Diagnostic codes (KEP-0005) --"

# Read stage: KP1xxx, and the raw Zig error name is gone.
assert_output_contains "reader error carries a KP1xxx code" \
    '(define x #\bogus)' 'read error[KP1'
assert_output_contains "unterminated string is KP1006" \
    '(display "abc' 'read error[KP1006]'
assert_output_contains "unexpected right paren is KP1003" \
    '(+ 1 2))' 'read error[KP1003]'

# Compile stage: KP2xxx.
assert_output_contains "empty if is a KP2xxx compile error" \
    '(if)' 'compile error[KP2'

# Runtime stage: KP3xxx, one code per user-distinguishable condition.
assert_output_contains "undefined variable is KP3001" \
    '(display countr)' 'error[KP3001]'
assert_output_contains "type error is KP3002" \
    '(car 5)' 'error[KP3002]'
assert_output_contains "arity mismatch is KP3003" \
    '((lambda (x) x) 1 2)' 'error[KP3003]'
assert_output_contains "division by zero is KP3004" \
    '(/ 1 0)' 'error[KP3004]: division by zero'
assert_output_contains "not a procedure is KP3005" \
    '(5 6)' 'error[KP3005]'
assert_output_contains "index out of bounds is KP3006" \
    '(vector-ref (vector 1 2) 9)' 'error[KP3006]'
# A user (error ...) is uncoded -> generic KP3000, not a specific KP.
assert_output_contains "uncaught user error is KP3000" \
    '(error "boom")' 'error[KP3000]: boom'

# --- Full source columns: file:line:col (#1506) ---
# Spans are threaded from the reader through IR into the bytecode line table, so
# compile and runtime errors now carry a column, not just a line. The column
# points at the offending form's opening paren.
echo
echo "-- Source columns (#1506) --"

# A top-level compile error points at column 1.
assert_output_contains "compile error has column" \
    '(if)' '<stdin>:1:1: compile error'

# Leading indentation shifts the column to the form's open paren.
assert_output_contains "compile error column tracks indentation" \
    '   (if)' '<stdin>:1:4: compile error'

# A compile error nested inside a top-level form points at the inner form, not
# the top-level datum: '(if)' begins at column 13 of '(define (f) (if))'.
assert_output_contains "compile error column points at the inner form" \
    '(define (f) (if))' '<stdin>:1:13: compile error'

# syntax-error carries a column too.
assert_output_contains "syntax-error has column" \
    '(syntax-error "msg")' '<stdin>:1:1: syntax-error'

# Runtime errors carry a column via the bytecode line table (file mode).
COLDIR=$(mktemp -d)
cat > "$COLDIR/rt-col.scm" << 'SCHEME'
(define (foo x) (+ x "hello"))
(foo 42)
SCHEME
assert_file_output_contains "runtime error has column" \
    "$COLDIR/rt-col.scm" "rt-col.scm:1:17: error"

cat > "$COLDIR/rt-col2.scm" << 'SCHEME'
(define (f x)
  (car x))
(f 5)
SCHEME
assert_file_output_contains "runtime error column tracks the failing form" \
    "$COLDIR/rt-col2.scm" "rt-col2.scm:2:3: error"
rm -rf "$COLDIR"

# --- No leaked Zig error names on any path (KEP-0005, #1504) ---
echo
echo "-- No leaked Zig error names --"
assert_no_zig_leak "reader error path"       '(define x #\bogus)'
assert_no_zig_leak "unterminated string"     '(display "abc'
assert_no_zig_leak "empty if compile error"  '(if)'
assert_no_zig_leak "malformed let*-values"   '(let*-values (42) 1)'
assert_no_zig_leak "undefined variable"      '(display countr)'
assert_no_zig_leak "type error"              '(car 5)'
assert_no_zig_leak "arity mismatch"          '((lambda (x) x) 1 2)'
assert_no_zig_leak "division by zero"        '(/ 1 0)'
assert_no_zig_leak "not a procedure"         '(5 6)'
assert_no_zig_leak "stack overflow"          '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1))))) (deep 50000)'
assert_no_zig_leak "uncaught user error"     '(error "boom" 1)'
assert_no_zig_leak "raised non-error value"  '(raise 42)'

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
