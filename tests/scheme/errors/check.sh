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
    if grep -qE "$pattern" <<< "$out"; then
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

echo "== digit-led identifier reclassifies to KP1004 under check (kaappi#1723) =="
assert_out "3-state is KP1004, not KP1002"       'error\[KP1004\]' '(define (3-state x) x) x'
assert_out "3-state message echoes the token"    "invalid number literal '3-state'" '(define (3-state x) x) x'

echo "== a macro-shadowed define-record-type is compiled, not dropped (#2114 review) =="
# R7RS has no reserved words, and SRFI 57/131/136/150 each bind
# `define-record-type` as a macro. `check` classified by head *name*, so a
# shadowed use entered the env-setup branch, `handleTopLevelForm` declined it
# (it does consult the macro table), and the form was dropped uncompiled.
# Diagnostics were lost in both directions.
#
# False negative: a use the shadowing macro cannot match is a real syntax
# error, and `check` reported nothing and exited 0.
assert_exit "malformed shadowed define-record-type use is an error" 1 \
    '(define-syntax define-record-type
       (syntax-rules () ((_ one-only) (display one-only))))
     (define-record-type too many args here)'
assert_out "...and reports KP2001" 'error\[KP2001\]' \
    '(define-syntax define-record-type
       (syntax-rules () ((_ one-only) (display one-only))))
     (define-record-type too many args here)'

# False positive, the more damaging half: dropping the form also dropped
# whatever it was meant to bind, so every later form depending on it drew a
# phantom diagnostic. A synthetic probe can't show this — `check` gathers
# top-level define names structurally and so never sees a binding introduced by
# any macro expansion, shadowed or not. The real SRFI files are the honest
# guard, in the style of the R7RS conformance check below: both bind
# `define-record-type` as a macro, both pass their own suites, and both drew
# hard errors from `check` — srfi136 three KP2001 "invalid syntax" (its type
# names are CPS introspection macros the dropped form never registered) plus a
# phantom KP4001, srfi150 a KP2002.
for probe in srfi136 srfi150; do
    status=0
    "$KAAPPI" check "$SCRIPT_DIR/../srfi/$probe.scm" > "$TMP/probe.out" 2>&1 || status=$?
    if [[ "$status" -eq 0 ]]; then
        echo "PASS: $probe.scm passes check with zero errors"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $probe.scm failed check (exit $status)"
        grep -E 'error\[KP' "$TMP/probe.out" | head -5 || true
        FAIL=$((FAIL + 1))
    fi
done

# The unshadowed form must still be run for its effect, so its accessors are in
# scope for later forms — the behaviour the env-setup branch exists for.
assert_exit "unshadowed define-record-type still establishes accessors" 0 \
    '(define-record-type <pt> (mk x) pt? (x pt-x))
     (display (pt-x (mk 1)))'

echo "== SRFI 211 runtime transformer-spec is not a false positive (kaappi#2007) =="
# `check` executes nothing, so a Transformer that only exists at run time
# cannot be resolved statically. It must still accept the (valid, running)
# program rather than emit KP2001. Both shapes below print "ok" when run.
#
# Shape 1: a runtime-bound Transformer value used as a transformer-spec alias.
assert_exit "runtime-bound transformer alias is clean" 0 \
    '(import (scheme base) (scheme write) (srfi 211 explicit-renaming))
     (define tx (er-macro-transformer (lambda (f r c) (list (r (quote quote)) (quote ok)))))
     (define-syntax m tx)
     (display (m)) (newline)'
# Shape 2: an er-macro-transformer expression that references a global (SRFI
# 211 evaluates the expression at macro-definition time in the global env).
assert_exit "transformer expr referencing a global is clean" 0 \
    '(import (scheme base) (scheme write) (srfi 211 explicit-renaming))
     (define w (quote ok))
     (define-syntax m
       (er-macro-transformer (let ((v w)) (lambda (f r c) (list (r (quote quote)) v)))))
     (display (m)) (newline)'
# The control literal-lambda spec (resolvable without executing) stays clean too.
assert_exit "literal-lambda transformer spec is clean" 0 \
    '(import (scheme base) (scheme write) (srfi 211 explicit-renaming))
     (define-syntax m (er-macro-transformer (lambda (f r c) (list (r (quote quote)) (quote ok)))))
     (display (m)) (newline)'

echo "== genuinely-invalid transformer-specs are STILL reported (kaappi#2007) =="
# A non-symbol, non-pair literal can never be a transformer — reject as before.
assert_exit "a literal transformer-spec is an error"       1 '(define-syntax m 42)'
assert_out  "...and reports KP2001"                        'error\[KP2001\]' '(define-syntax m 42)'
# A bare alias that resolves to a bound, NON-transformer value (a procedure) is
# statically wrong at run time too, so analysis keeps rejecting it — the
# placeholder fallback is only for names that are genuinely unresolvable.
assert_exit "alias to a non-transformer global is an error" 1 \
    '(import (scheme base))
     (define-syntax m car)
     (display (m))'
# A structurally malformed er-macro-transformer (wrong arity) is still rejected.
assert_exit "er-macro-transformer with no argument is an error" 1 \
    '(import (scheme base) (srfi 211 explicit-renaming))
     (define-syntax m (er-macro-transformer))'

echo "== --diagnostics=json parity =="
printf '(car 5)\n' > "$TMP/j.scm"
JSON="$("$KAAPPI" check --diagnostics=json "$TMP/j.scm" 2>&1 || true)"
if grep -q '"code":"KP4003"' <<< "$JSON" && grep -q '"severity":1' <<< "$JSON"; then
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
