#!/bin/bash
# Regression test for #2117, #2118 and #2211 (LLVM native backend): a scratch
# IR lowering must carry the lexical scope and the `set!` targets of the point
# it is lowering at, or the native tier silently disagrees with the
# interpreter.
#
# The backend re-lowers every lambda/closure/let body through a fresh IR that
# has no Compiler, so `IR.bound_names` and `IR.set_targets` stand in for the
# Compiler scope. Both were under-supplied:
#
#   * bound_names held only the IMMEDIATE frame's parameter names, so a
#     binding one level out (an upvalue) or a let-local was invisible. That
#     fed two different decisions the wrong answer — the constant folders
#     (#2117 route 2: `(define (outer +) (lambda () (+ 5 2)))` printed 7) and
#     the special-form-vs-call dispatch (#2118: `(define (f if) (if 1 2))`
#     printed 2 where the interpreter printed 99, and `(f quote)` printed a
#     different value entirely).
#   * set_targets was never populated at all, so a `set!` in the enclosing
#     body did not suppress a later fold in that same body (#2117 route 1:
#     `(define (f) (set! + -) (+ 5 2))` printed 7).
#
# Part A compiles the three .scm regression suites that #600/#698, #788/#790
# already own. Every one of them passed under the interpreter and failed
# natively — 6, 1 and 9 assertions respectively — because no suite had ever
# run them through `kaappi compile`. That gap is what this part closes.
#
# Part B pins the individual routes as tier comparisons, including the
# discriminating controls from all three issues (the same shadowing used in
# the frame that binds it; a `set!` reachable only through quoted data) so a
# fix that simply stops folding everywhere would not pass.
#
# #2211 is the same root cause at four sites neither #2117 nor #2118 names:
# `let`/`let*` initializers and bodies, cond/case/do sub-forms, and apply
# operands, which passed NO scope rather than an incomplete one.
#
# Usage: bash tests/scheme/compile/native-lexical-scope-fold-2117-2118.sh [path-to-kaappi]

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail=0
n=0

# --- Part A: the pre-existing .scm suites, on the native tier --------------
#
# These are self-checking: each prints a sentinel and exits nonzero on any
# failed assertion. They are also compared tier-to-tier like everything else,
# with one normalization: each `check` call is a bare top-level expression
# returning #t, and the VM echoes that value while a native binary does not
# (difference 1 in shell-common.sh). Dropping lines that are exactly `#t` from
# the interpreter's stdout removes precisely that echo — none of the three
# files ever displays a boolean itself, and a FAIL line carries its name and
# both values, so nothing else in the transcript is `#t` alone.
strip_echo() { grep -v '^#t$' || true; }

check_suite() {
    local name="$1" sentinel="$2"
    local src="$REPO_DIR/tests/scheme/smoke/$name.scm"
    local bin="$DIR/$name.bin"
    n=$((n + 1))

    local interp_raw interp_out interp_status=0 interp_err="$DIR/$name.interp.err"
    interp_raw="$(interp_stdout "$KAAPPI_ABS" "$REPO_DIR" "$src" "$interp_err")" || interp_status=$?
    interp_out="$(printf '%s\n' "$interp_raw" | strip_echo)"
    if [[ $interp_status -ne 0 ]]; then
        echo "FAIL: $name — interpreter exited $interp_status:" >&2
        printf '%s\n' "$interp_raw" >&2
        show_interp_stderr "$interp_err"
        fail=1
        return
    fi
    # The golden assertion, against the interpreter: these suites announce
    # their own verdict, so the sentinel is what "no assertion failed" looks
    # like. Kept alongside the tier comparison because a bug BOTH tiers share
    # would leave them agreeing on a transcript full of FAIL lines.
    if [[ "$interp_out" != *"$sentinel"* ]]; then
        echo "FAIL: $name — interpreter output missing '$sentinel':" >&2
        printf '%s\n' "$interp_out" >&2
        show_interp_stderr "$interp_err"
        fail=1
        return
    fi

    (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" > /dev/null 2>&1) || {
        echo "FAIL: $name — native compile failed" >&2
        fail=1
        return
    }
    local out status=0
    out="$("$bin" 2> /dev/null)" || status=$?
    assert_tiers_agree "$name" "$interp_out" "$interp_status" "$out" "$status" || fail=1
}

check_suite lambda-param-shadows-keyword-788 "all passed"
check_suite lambda-param-shadow-fold-790 "PASS"
check_suite set-redefine-fold "all passed"

# --- Part B: per-route tier comparisons -----------------------------------
#
# The interpreter is the oracle; `expected` documents intent and still catches
# a bug both tiers share. Every program prints explicitly, so the VM's
# top-level echo never enters the comparison.
check_both() {
    local label="$1" expected="$2" src_text="$3"
    local src="$DIR/$label.scm" bin="$DIR/$label.bin"
    n=$((n + 1))
    printf '%s\n' "$src_text" > "$src"

    local interp_out interp_status=0 interp_err="$DIR/$label.interp.err"
    interp_out="$(interp_stdout "$KAAPPI_ABS" "$REPO_DIR" "$src" "$interp_err")" || interp_status=$?
    if [[ $interp_status -ne 0 ]]; then
        echo "FAIL: $label — interpreter exited $interp_status (output: '$interp_out')" >&2
        show_interp_stderr "$interp_err"
        fail=1
        return
    fi
    if [[ "$interp_out" != "$expected" ]]; then
        echo "FAIL: $label — interpreter expected '$expected', got '$interp_out'" >&2
        show_interp_stderr "$interp_err"
        fail=1
        return
    fi

    (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" > /dev/null 2>&1) || {
        echo "FAIL: $label — native compile failed" >&2
        fail=1
        return
    }
    local out status=0
    out="$("$bin" 2> /dev/null)" || status=$?
    assert_tiers_agree "$label" "$interp_out" "$interp_status" "$out" "$status" || fail=1
}

# #2117 route 1 — a set! in the enclosing body makes the compile-time value of
# `+` stale for every call in that body, folded or not.
check_both set-in-lambda-body 3 '(define orig+ +)
(define (f) (set! + -) (+ 5 2))
(define r (f))
(set! + orig+)
(display r) (newline)'

check_both set-in-let-body 3 '(define orig+ +)
(define (f) (let ((x 1)) (set! + -) (+ 5 2)))
(define r (f))
(set! + orig+)
(display r) (newline)'

# The set! sits in the outer body; the fold lives in a nested lambda.
check_both set-suppresses-nested-lambda 3 '(define orig+ +)
(define k (lambda () (set! + -) (lambda () (+ 5 2))))
(define inner (k))
(define r (inner))
(set! + orig+)
(display r) (newline)'

# Route 1 control: the same set!, with non-constant operands. Already correct
# natively (nothing to fold — the inline-primitive path re-reads the global),
# so it must stay correct.
check_both set-in-body-no-fold 3 '(define orig+ +)
(define (f a b) (set! + -) (+ a b))
(define r (f 5 2))
(set! + orig+)
(display r) (newline)'

# A set! reachable only through quoted data must NOT suppress the fold — the
# scan stops at `quote`, and a fix that just gave up on folding would still
# print 7 here, so this is the discriminating control for the whole route.
check_both quoted-set-still-folds 7 '(define (p) (quote (set! + -)) (+ 5 2))
(display (p)) (newline)'

# #2117 route 2 — a shadowing parameter reached through an enclosing frame.
check_both upvalue-shadowed-primitive 3 '(define (outer +) (lambda () (+ 5 2)))
(display ((outer -))) (newline)'

check_both let-local-shadowed-primitive -1 '(define (f) (let ((+ -)) (+ 1 2)))
(display (f)) (newline)'

check_both toplevel-let-shadowed-primitive -1 '(display (let ((+ -)) (+ 1 2))) (newline)'

# Route 2 control: the same shadowing parameter used in the frame that binds
# it — what #790 fixed, and what already worked.
check_both own-param-shadowed-primitive 3 '(define (outer +) (+ 5 2))
(display (outer -)) (newline)'

# #2118 — a parameter shadowing a syntactic keyword hides the keyword for the
# body. `quote` is the sharp one: the wrong answer is a different value, not a
# coincidence.
check_both param-shadows-if 99 '(define (f if) (if 1 2))
(display (f (lambda (x y) 99))) (newline)'

check_both param-shadows-quote -5 '(define (f quote) (quote 5))
(display (f -)) (newline)'

check_both upvalue-shadows-if 99 '(define (outer if) (lambda () (if 1 2)))
(display ((outer (lambda (x y) 99)))) (newline)'

check_both let-local-shadows-if 99 '(define (f) (let ((if (lambda (a b) 99))) (if 1 2)))
(display (f)) (newline)'

# --- #2211: the four sites that carried no scope at all --------------------
#
# `let`/`let*` initializers and bodies, every sub-form of a natively emitted
# cond/case/do (#1496), and apply operands (#1803) each re-lowered through a
# scratch IR built from nothing but an allocator and a GC. The three cases
# just above (let-local-shadowed-primitive, toplevel-let-shadowed-primitive,
# let-local-shadows-if) are the let half; these are the rest.

check_both letstar-shadowed-primitive -1 '(define (f) (let* ((y 1) (+ -)) (+ 1 2)))
(display (f)) (newline)'

# A let-bound keyword, where the wrong answer is a different value rather than
# a coincidence of arithmetic — `quote`s role in #2118, one scope out.
check_both let-local-shadows-quote -5 '(display (let ((quote -)) (quote 5))) (newline)'

# cond/case/do are NOT saved by the enclosing frame's own bound_names: `outer`s
# parameter `+` is in it, and each of these forms re-lowers its sub-forms from
# an empty scratch IR, throwing the shadowing away one level down.
check_both cond-body-shadowed-primitive 3 '(define (outer +) (cond (#t (+ 5 2))))
(display (outer -)) (newline)'

check_both case-body-shadowed-primitive 3 '(define (outer +) (case 1 ((1) (+ 5 2)) (else 0)))
(display (outer -)) (newline)'

check_both do-result-shadowed-primitive 3 '(define (outer +) (do ((i 0 (- i 1))) ((= i -1) (+ 5 2))))
(display (outer -)) (newline)'

check_both apply-operand-shadowed-primitive '(3)' '(define (outer +) (apply list (list (+ 5 2))))
(display (outer -)) (newline)'

# The binding INITIALIZERS are their own lowering sites (llvm_emit_let.zig:212
# for a parallel let, :264 for let*), distinct from the body at :361 — a
# shadowed operator evaluated in an initializer had no coverage until now.
check_both let-init-shadowed-primitive 3 '(define (outer +) (let ((x (+ 5 2))) x))
(display (outer -)) (newline)'

# let* is the sharper of the two: the initializer is shadowed by an EARLIER
# binding of this same let*, not by an enclosing frame.
check_both letstar-init-sees-earlier-binding -1 '(define (f) (let* ((+ -) (x (+ 1 2))) x))
(display (f)) (newline)'

check_both letstar-init-shadowed-by-frame 3 '(define (outer +) (let* ((y 1) (x (+ 5 2))) x))
(display (outer -)) (newline)'

# A let shadowing survives into a nested let, in both nesting directions.
check_both let-shadow-into-inner-let 3 '(define (f) (let ((+ -)) (let ((y 1)) (+ 5 2))))
(display (f)) (newline)'

check_both inner-let-shadows-under-outer-let 3 '(define (f) (let ((x 1)) (let ((+ -)) (+ 5 2))))
(display (f)) (newline)'

# #2211 control: a lambda capturing an unboxed let-local declines native
# compilation outright, so the interpreter runs the whole form — correct on
# both tiers before the fix and after it.
check_both let-shadow-captured-by-lambda 3 '(define (f) (let ((+ -)) (lambda () (+ 5 2))))
(display ((f))) (newline)'

# #2118 control: the same forms with no shadowing binding still compile as the
# special form on both tiers.
check_both unshadowed-if-and-quote '2 5' '(display (if 1 2)) (display " ") (display (quote 5)) (newline)'

# An unshadowed primitive must still fold, so none of the above is achieved by
# disabling the optimizer.
check_both unshadowed-fold-survives 3 '(define (f) (+ 1 2))
(display (f)) (newline)'

if [[ $fail -ne 0 ]]; then
    exit 1
fi

echo "PASS ($n tier comparisons, 3 of them the pre-existing .scm suites)"
