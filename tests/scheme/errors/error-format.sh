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
    if grep -qF "$expected" <<< "$output"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected' in output"
        FAIL=$((FAIL + 1))
    fi
}

assert_output_lacks() {
    local label="$1"
    local input="$2"
    local forbidden="$3"
    local output
    output=$(echo "$input" | "$KAAPPI" 2>&1 || true)
    if grep -qF "$forbidden" <<< "$output"; then
        echo "FAIL: $label — output still contains '$forbidden'"
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $label"
        PASS=$((PASS + 1))
    fi
}

assert_file_output_contains() {
    local label="$1"
    local file="$2"
    local expected="$3"
    local output
    output=$("$KAAPPI" "$file" 2>&1 || true)
    if grep -qF "$expected" <<< "$output"; then
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
    if grep -qE 'error\.[A-Z][A-Za-z]+' <<< "$output"; then
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

# --- Procedural macro transformer failures (SRFI 211, #1846) ---
# A condition an er-macro-transformer/lisp-transformer raises used to be
# computed, stored on the VM, and discarded -- the user only ever saw a bare
# "invalid syntax". #1831 was a one-line resolution bug whose real message
# was "undefined variable 'cadar'"; none of that reached the user, so it was
# filed and chased as a cadar-specific bug for days. This must now match
# syntax-error's own KP2002 path exactly.
echo
echo "-- Procedural macro transformer diagnostics (#1846) --"

assert_output_contains "er-macro-transformer's raised condition reaches the user" \
    '(import (srfi 211 explicit-renaming)) (define-syntax boom (er-macro-transformer (lambda (f r c) (error "field not found" (quote alpha) 42)))) (boom)' \
    'syntax-error[KP2002]: field not found alpha 42'

assert_output_contains "lisp-transformer's raised condition reaches the user" \
    '(import (srfi 211 define-macro)) (define-syntax boom (lisp-transformer (lambda (f) (error "lisp boom" 7)))) (boom)' \
    'syntax-error[KP2002]: lisp boom 7'

assert_output_contains "a failing primitive inside a transformer names itself, not just 'invalid syntax'" \
    '(import (srfi 211 explicit-renaming)) (define-syntax boom2 (er-macro-transformer (lambda (f r c) (car 7)))) (boom2)' \
    "syntax-error[KP2002]: type error in 'car': expected pair, got 7"

assert_output_contains "ordinary syntax-rules rejection keeps the generic message (scope note)" \
    '(define-syntax only-one-arg (syntax-rules () ((_ x) x))) (only-one-arg 1 2 3)' \
    'compile error[KP2001]: invalid syntax'

# --- syntax-rules ellipsis with no driving pattern variable (#1791) ---
# R7RS 4.3.2: a template subform followed by `...` whose element has no
# pattern variable bound at that ellipsis depth is an error, not zero
# copies. `tok` here is not a pattern variable at all — a stand-in for the
# common typo'd bare `...` where the literal-ellipsis escape `(... ...)`
# was meant (kaappi#1787's root cause).
echo
echo "-- syntax-rules ellipsis diagnostics (#1791) --"

assert_output_contains "ellipsis with no pattern variable is a compile error" \
    '(define-syntax demo (syntax-rules () ((_) (quote (head tok ... tail))))) (demo)' \
    'compile error[KP2001]'

assert_output_contains "ellipsis with no pattern variable has location" \
    '(define-syntax demo (syntax-rules () ((_) (quote (head tok ... tail))))) (demo)' \
    '<stdin>:1:'

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

# #1886: a VM limit is not a condition the program raised, so it unwinds past
# every handler. It used to be converted into a bare #<error "error"> that an
# enclosing guard caught, returning a plausible wrong value with exit 0.
assert_output_contains "stack overflow is not catchable by guard" \
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1)))))
     (guard (e (#t (display "SWALLOWED"))) (deep 50000))' \
    "error[KP3008]: stack overflow"

assert_output_lacks "guard clause does not run on stack overflow" \
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1)))))
     (guard (e (#t (display "SWALLOWED"))) (deep 50000))' \
    "SWALLOWED"

assert_output_lacks "with-exception-handler does not see a stack overflow" \
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1)))))
     (with-exception-handler (lambda (e) (display "SWALLOWED")) (lambda () (deep 50000)))' \
    "SWALLOWED"

# A limit must never be reported as out-of-memory: nothing failed to allocate,
# and KP9002 sent readers looking for a memory leak (#1886).
assert_output_lacks "stack overflow is not reported as out-of-memory" \
    '(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1))))) (deep 50000)' \
    "KP9002"

# --- Register-file cap (#2035) ---
# Deeply nested dynamic-wind exhausts the *register file* (65536 registers,
# roughly 5 per nesting level) before the frame stack (32768), so this shape
# is a register-cap test, not a frame-cap one. The register file used to stop
# growing at 4096 — a tail-position call replaced the frame in place without
# re-ensuring room for the callee's locals — so 819 extents already aborted
# the form with a catchable KP9001 "internal error", and a guard turned the
# failure into a bare #<error "error">. Past the real cap it must report the
# same uncatchable KP3008 as every other VM stack.
assert_output_contains "register-file cap is reported as stack overflow, not internal error" \
    '(import (scheme base) (scheme write))
     (define (nd n) (if (= n 0) (quote bottom)
                        (dynamic-wind (lambda () 1) (lambda () (nd (- n 1))) (lambda () 2))))
     (nd 15000)' \
    "error[KP3008]: stack overflow"

assert_output_lacks "register-file cap is not reported as an internal error" \
    '(import (scheme base) (scheme write))
     (define (nd n) (if (= n 0) (quote bottom)
                        (dynamic-wind (lambda () 1) (lambda () (nd (- n 1))) (lambda () 2))))
     (nd 15000)' \
    "KP9001"

assert_output_contains "register-file cap is not catchable by guard" \
    '(import (scheme base) (scheme write))
     (define (nd n) (if (= n 0) (quote bottom)
                        (dynamic-wind (lambda () 1) (lambda () (nd (- n 1))) (lambda () 2))))
     (guard (e (#t (display "SWALLOWED"))) (nd 15000))' \
    "error[KP3008]: stack overflow"

assert_output_lacks "guard clause does not run on register-file cap" \
    '(import (scheme base) (scheme write))
     (define (nd n) (if (= n 0) (quote bottom)
                        (dynamic-wind (lambda () 1) (lambda () (nd (- n 1))) (lambda () 2))))
     (guard (e (#t (display "SWALLOWED"))) (nd 15000))' \
    "SWALLOWED"

assert_output_lacks "register-file cap is not reported as out-of-memory" \
    '(import (scheme base) (scheme write))
     (define (nd n) (if (= n 0) (quote bottom)
                        (dynamic-wind (lambda () 1) (lambda () (nd (- n 1))) (lambda () 2))))
     (nd 15000)' \
    "KP9002"

# --- Unbounded re-entrant promise forcing (#2035) ---
# `(delay (force p))` re-enters force on the same promise with no termination
# — genuinely runaway recursion, and the register file is what caps it (the
# SRFI-45 re-entrancy check only sees cycles whose thunk returns). Pre-fix the
# file stopped growing at 4096 and the recursion died there with a catchable
# KP9001 "internal error", which a guard turned into a bare #<error "error">;
# now it must report the same uncatchable KP3008 as any other runaway.
assert_output_contains "unbounded re-entrant force is a stack overflow, not an internal error" \
    '(import (scheme base) (scheme write))
     (define selfp (delay (force selfp)))
     (force selfp)' \
    "error[KP3008]: stack overflow"

assert_output_lacks "unbounded re-entrant force is not an internal error" \
    '(import (scheme base) (scheme write))
     (define selfp (delay (force selfp)))
     (force selfp)' \
    "KP9001"

assert_output_contains "unbounded re-entrant force is not catchable by guard" \
    '(import (scheme base) (scheme write))
     (define selfp (delay (force selfp)))
     (guard (e (#t (display "SWALLOWED"))) (force selfp))' \
    "error[KP3008]: stack overflow"

assert_output_lacks "guard clause does not run on unbounded re-entrant force" \
    '(import (scheme base) (scheme write))
     (define selfp (delay (force selfp)))
     (guard (e (#t (display "SWALLOWED"))) (force selfp))' \
    "SWALLOWED"

# The 255 ceiling on a tail-position `apply` is what the tail_apply opcode's
# nargs byte encodes — a limit on one argument list, not on the stack. It
# reported KP3008, which both misdirected the reader and (once limits stopped
# being catchable) would have made it unrecoverable (#1886). It has to stay
# catchable: it is also what stops the walk of a circular argument list, which
# tests/scheme/audit/primitives_core-audit.scm pins.
assert_output_contains "too many apply arguments names the real limit" \
    '(define (f) (apply + (make-list 300 1))) (f)' \
    "error[KP3007]: apply: too many arguments (limit 255)"

assert_output_lacks "too many apply arguments is not a stack overflow" \
    '(define (f) (apply + (make-list 300 1))) (f)' "KP3008"

assert_output_contains "too many apply arguments stays catchable" \
    '(import (scheme base) (scheme write))
     (define (f) (apply + (make-list 300 1)))
     (write (guard (e (#t (quote caught))) (f)))' \
    "caught"

# The half that used to give a silently wrong answer with exit 0: nested
# `guard` past the old 64-handler cap. Every depth must return 0. 90 is the
# ceiling here, not a round number: `guard` spends two native re-entrancy
# frames per level and callReentrant caps those at 200 in a Debug build, so
# nested guard tops out at 99 there. See the header of
# tests/scheme/smoke/handler-wind-depth-1886.scm.
assert_output_contains "nested guard past the old handler cap returns 0 at every depth" \
    '(import (scheme base) (scheme write))
     (define (f n) (guard (e (#t n)) (if (= n 0) (raise (quote b)) (f (- n 1)))))
     (write (list (f 63) (f 64) (f 65) (f 90)))' \
    "(0 0 0 0)"

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
if grep -qF "srfi.999" <<< "$dep_output"; then
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

# The `read` procedure's error object names what failed instead of a bare
# "read error" (#1920): the reader's KP1xxx registry template (or its richer
# detail string, when one was recorded) rides along in the message.
assert_output_contains "read procedure error names the failure" \
    '(import (scheme read)) (read (open-input-string "\"abc"))' \
    'error[KP3000]: read error: unterminated string literal'

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

# --- Digit-led identifiers reclassify from KP1002 to KP1004 (kaappi#1723) ---
# `3-state`, `5foo`, `1.2.3`, `9x` all look like identifiers, but R7RS forbids
# a bare identifier from starting with a digit: the reader commits to a
# number on the leading digit, then finds characters glued onto it. This used
# to surface as the generic, miscoded KP1002 "unexpected character" (whose
# explanation talks about stray '#'-syntax, irrelevant here) with the caret
# one column past the token's start. It must now be KP1004 "invalid number
# literal", caret at the token's start, with a detail message that echoes the
# token and explains the rule.
echo
echo "-- Digit-led identifier diagnostics (kaappi#1723) --"

assert_output_contains "3-state is KP1004, not KP1002" \
    '(define (3-state x) x)' 'read error[KP1004]'
assert_output_contains "3-state message echoes the token" \
    '(define (3-state x) x)' "invalid number literal '3-state'"
assert_output_contains "3-state message states the identifier rule" \
    '(define (3-state x) x)' 'cannot begin with a digit'
assert_output_contains "3-state caret is at the token start, not the glued char" \
    '(define (3-state x) x)' '<stdin>:1:10: read error[KP1004]'

assert_output_contains "5foo is KP1004" '5foo' 'read error[KP1004]'
assert_output_contains "1.2.3 is KP1004" '1.2.3' 'read error[KP1004]'
assert_output_contains "9x is KP1004" '9x' 'read error[KP1004]'

# A piped digit-led symbol and ordinary valid numbers are untouched.
assert_output_contains "|3-state| reads as a symbol, not an error" \
    "(display '|3-state|)" '3-state'
assert_output_contains "3-4i still reads as a complex number" \
    '(display 3-4i)' '3-4i'
assert_output_contains "1/0 keeps the generic KP1004 message (no stray hint)" \
    '1/0' 'read error[KP1004]: invalid number literal'

# A non-identifier character glued onto a number (not an <subsequent> char) is
# unrelated to the digit-led-identifier rule and must keep the original,
# accurate KP1002 -- not a nonsensical "invalid number literal '3': ...
# identifiers cannot begin with a digit" that both mislabels the valid number
# '3' and drops the actual offending character (review fix).
assert_output_contains "3 followed by a stray backtick keeps KP1002" \
    '3`' 'read error[KP1002]'
assert_output_contains "3 followed by a stray comma keeps KP1002" \
    '3,' 'read error[KP1002]'

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

# --- Thread exception diagnostics (kaappi#1742) ---
# thread-join! used to wrap a child thread's failure in a generic "uncaught
# exception in thread" message with no further detail, and a local (never-
# shared) channel's deadlock message blamed "fibers" even when a live OS
# thread was the actual, relevant context. Neither is a channel/thread bug —
# see #1742's own investigation comment — but both hid the real cause.
echo
echo "-- Thread exception diagnostics (kaappi#1742) --"
THREADDIR=$(mktemp -d)

cat > "$THREADDIR/join-generic.scm" << 'SCHEME'
(import (scheme base) (srfi 18))
(define t (thread-start! (make-thread (lambda () (error "boom" 1)))))
(thread-join! t)
SCHEME
assert_file_output_contains "thread-join! surfaces the child's (error ...) reason" \
    "$THREADDIR/join-generic.scm" "uncaught exception in thread: boom 1"

cat > "$THREADDIR/join-channel-repro.scm" << 'SCHEME'
(import (scheme base) (srfi 18) (kaappi fibers))
(define ch (make-channel))
(define t (thread-start! (make-thread (lambda () (channel-send ch 42)))))
(thread-join! t)
SCHEME
assert_file_output_contains "thread-join! surfaces a channel reached via a shared global (issue's own repro)" \
    "$THREADDIR/join-channel-repro.scm" \
    "uncaught exception in thread: channel belongs to another thread; pass it through the thread thunk to share it"

cat > "$THREADDIR/receive-deadlock-other-thread.scm" << 'SCHEME'
(import (scheme base) (srfi 18) (kaappi fibers))
(define t (thread-start! (make-thread (lambda () (thread-sleep! 0.5)))))
(define ch (make-channel))
(channel-receive ch)
SCHEME
assert_file_output_contains "channel-receive deadlock names the other thread instead of blaming only fibers" \
    "$THREADDIR/receive-deadlock-other-thread.scm" \
    "never shared with it"
rm -rf "$THREADDIR"

# --- Retired bare TypeError returns (kaappi#1868) ---
# These conditions used to return an anonymous PrimitiveError.TypeError. Note
# what that did and did NOT cost: vm_calls.mapNativeError already synthesized
# "type error in '<primitive>': got <args[0]>" for any primitive that set no
# detail, so the procedure name was never the missing piece. What was missing is
# the *expected* type — and for the hash-table cases args[0] is the table, so
# the fallback actively blamed the wrong argument ("got #<hash-table size=0>"
# for a bad key). Assert the message; asserting only "an error was raised", or
# only that the procedure is named, passes against the pre-fix build too.
echo
echo "-- Retired bare TypeErrors (kaappi#1868) --"

# A string-keyed table rejecting a non-string key. This pair is deliberately
# both halves of the same claim: the negative pins the old wrong answer (the
# table) and the positive pins the new right one (the key) -- a "lacks" check
# alone would also pass if the call stopped erroring altogether.
assert_output_lacks "string-keyed table blames the key, not the table itself" \
    '(import (scheme base) (srfi 69)) (hash-table-set! (make-hash-table string=?) 1 2)' \
    'got #<hash-table'

assert_output_contains "string-keyed table names the compare mode, not just 'string'" \
    '(import (scheme base) (srfi 69)) (hash-table-set! (make-hash-table string=?) 1 2)' \
    'expected string key (this table compares with string=?), got 1'

# Each entry point must name ITSELF, not a shared "hash-table" label: the proc
# name is threaded through findKey/findSlot/growIfNeeded, so a regression shows
# up as the wrong procedure in the message rather than as a missing one.
assert_output_contains "string-keyed hash-table-ref names itself, not hash-table-set!" \
    '(import (scheme base) (srfi 69)) (hash-table-ref (make-hash-table string=?) 42)' \
    "type error in 'hash-table-ref': expected string key"

assert_output_contains "a string-ci=? table names string-ci=?, not string=?" \
    '(import (scheme base) (srfi 69)) (hash-table-delete! (make-hash-table string-ci=?) 42)' \
    "type error in 'hash-table-delete!': expected string key (this table compares with string-ci=?), got 42"

# R6RS "parent is sealed" and a uid collision are not type errors at all: both
# arguments are of an acceptable type and the procedure rejects them anyway, so
# they now report as invalid-argument (KP3007), not KP3002.
assert_output_contains "sealed parent rtd is KP3007, not a type error" \
    "(import (scheme base) (srfi 237)) (define l (make-record-type-descriptor 'l #f #f #t #f '#())) (make-record-type-descriptor 'c l #f #f #f '#())" \
    "error[KP3007]: %make-record-type-descriptor: record type 'l' is sealed and cannot be a parent"

assert_output_contains "non-equivalent uid collision is KP3007 and echoes the uid" \
    "(import (scheme base) (srfi 237)) (make-record-type-descriptor 'a #f 'dup #f #f '#((mutable x))) (make-record-type-descriptor 'a #f 'dup #f #f '#((mutable y)))" \
    'error[KP3007]: %make-record-type-descriptor: uid "dup" is already bound to a record type'

# The same two conditions reached SYNTACTICALLY. Until kaappi#1880 these were
# the only two `define-record-type` errors that reported nothing at all: a bare
# "error[KP3002]: type error" naming no procedure, no expected type and no
# value -- the three things KP3007's own registry entry promises. Both now go
# through the same helpers as the procedural twins above, so the pair also pins
# that the two routes cannot drift apart again.
assert_output_contains "syntactic sealed parent is KP3007, and names the parent" \
    "(import (scheme base) (srfi 237)) (define-record-type (p mk-p p?) (fields (immutable x)) (sealed #t)) (define-record-type (c mk-c c?) (parent p) (fields (immutable y)))" \
    "error[KP3007]: define-record-type: record type 'p' is sealed and cannot be a parent"

assert_output_contains "syntactic uid collision is KP3007, and names the axis that differs" \
    "(import (scheme base) (srfi 237)) (define-record-type (a mk-a a?) (fields (immutable x)) (nongenerative dup)) (define-record-type (b mk-b b?) (fields (immutable y)) (nongenerative dup))" \
    'error[KP3007]: define-record-type: uid "dup" is already bound to a record type with a different field set'

# The negative half: the old answer was KP3002, so a regression that reverted
# either site would still satisfy a "contains KP3007" check on the other one.
assert_output_lacks "syntactic sealed parent is not reported as a type error" \
    "(import (scheme base) (srfi 237)) (define-record-type (p mk-p p?) (fields (immutable x)) (sealed #t)) (define-record-type (c mk-c c?) (parent p) (fields (immutable y)))" \
    'error[KP3002]'

# A uid collision names the ONE axis that actually differs, not a list of every
# axis it might have been. Checked on an axis other than the field set so a
# hardcoded tail cannot pass.
assert_output_contains "a uid differing only in sealedness says so" \
    "(import (scheme base) (srfi 237)) (define-record-type (a mk-a a?) (fields (immutable x)) (nongenerative dup)) (define-record-type (b mk-b b?) (fields (immutable x)) (sealed #t) (nongenerative dup))" \
    'is already bound to a record type with a different sealed flag'

# The other half of the uid rule: an EQUIVALENT redefinition is not an error at
# all, it reuses the registered rtd. Without this, "reject everything" passes
# every assertion above.
assert_output_contains "an equivalent nongenerative redefinition still reuses the rtd" \
    "(import (scheme base) (scheme write) (srfi 237)) (define-record-type (a mk-a a?) (fields (immutable x)) (nongenerative dup)) (define-record-type (b mk-b b?) (fields (immutable x)) (nongenerative dup)) (display (a? (mk-b 1)))" \
    '#t'

# A third condition of the same shape, in the same two functions, that
# kaappi#1880's census could not see: RecordType.num_fields is a u8, so 255 is
# the cap on a type's fields INCLUDING inherited ones. Both parsers already cap
# a type's own fields, so only the inherited total can trip it -- and both
# routes signalled it as a `return switch` arm yielding a bare TypeError, a
# spelling the gate's grep does not match either.
gen_fields() {
    prefix="$1"; count="$2"; i=0; out=""
    while [ "$i" -lt "$count" ]; do
        out="$out (immutable $prefix$i)"
        i=$((i + 1))
    done
    printf '%s' "$out"
}
OVERSIZE_SYNTACTIC="(import (scheme base) (srfi 237))
(define-record-type (par mk-par par?) (fields $(gen_fields p 200)))
(define-record-type (chi mk-chi chi?) (parent par) (fields $(gen_fields c 100)))"
OVERSIZE_PROCEDURAL="(import (scheme base) (srfi 237))
(define P (make-record-type-descriptor 'par #f #f #f #f '#($(gen_fields p 200))))
(make-record-type-descriptor 'chi P #f #f #f '#($(gen_fields c 100)))"

assert_output_contains "an oversized inherited field count names both contributions" \
    "$OVERSIZE_SYNTACTIC" \
    'error[KP3007]: define-record-type: record type would have 300 fields (100 of its own plus 200 inherited), but the limit is 255'

assert_output_contains "the procedural route reports the same limit the same way" \
    "$OVERSIZE_PROCEDURAL" \
    'record type would have 300 fields (100 of its own plus 200 inherited), but the limit is 255'

# The procedural route was the worse of the two before the fix: a bare
# TypeError out of a primitive is not anonymous, so mapNativeError synthesized
# "type error in '%make-record-type-descriptor': got \"chi\"" -- blaming the
# type's NAME, the first argument, for a limit the field list broke.
assert_output_lacks "the oversized-field error does not blame the type's name" \
    "$OVERSIZE_PROCEDURAL" \
    'got "chi"'

# %elision-lever-set! is a KEP-0002 gate-harness hook compiled in only with
# -Dchannel-instrument=true, so it is absent from ordinary builds (including
# the one CI runs this suite against). Probe for it rather than assuming.
if echo '(import (scheme base) (kaappi fibers)) (%elision-lever-set! (quote none))' \
    | "$KAAPPI" >/dev/null 2>&1; then
    echo "-- %elision-lever-set! (instrumented build) --"
    assert_output_contains "a non-symbol lever is a type error naming the primitive" \
        "(import (scheme base) (kaappi fibers)) (%elision-lever-set! 42)" \
        "type error in '%elision-lever-set!': expected symbol, got 42"
    assert_output_contains "an unknown lever symbol is KP3007 and echoes the symbol" \
        "(import (scheme base) (kaappi fibers)) (%elision-lever-set! 'bogus)" \
        "error[KP3007]: %elision-lever-set!: expected lever none, c, or cd, got 'bogus'"
else
    echo "SKIP: %elision-lever-set! lever diagnostics (needs -Dchannel-instrument=true)"
fi

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
assert_no_zig_leak "ellipsis with no pattern variable (#1791)" \
    '(define-syntax demo (syntax-rules () ((_) (quote (head tok ... tail))))) (demo)'
assert_no_zig_leak "digit-led identifier (kaappi#1723)" '3-state'
assert_no_zig_leak "string-keyed table, non-string key (kaappi#1868)" \
    '(import (scheme base) (srfi 69)) (hash-table-set! (make-hash-table string=?) 1 2)'
assert_no_zig_leak "sealed parent rtd (kaappi#1868)" \
    "(import (scheme base) (srfi 237)) (define l (make-record-type-descriptor 'l #f #f #t #f '#())) (make-record-type-descriptor 'c l #f #f #f '#())"
assert_no_zig_leak "syntactic sealed parent rtd (kaappi#1880)" \
    "(import (scheme base) (srfi 237)) (define-record-type (p mk-p p?) (fields (immutable x)) (sealed #t)) (define-record-type (c mk-c c?) (parent p) (fields (immutable y)))"

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
