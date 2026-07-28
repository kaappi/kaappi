#!/bin/bash
# Regression test for #1807 (LLVM native backend): a macro use anywhere inside
# a natively-lowered `let`/`let*` body or binding initializer, or a lambda /
# top-level function body, miscompiled as a call to a same-named global
# instead of expanding.
#
# emitLet (llvm_emit_let.zig) and the lambda closure tiers
# (tryCompileNativeClosure / tryCompilePureLambdaAsNativeClosure /
# tryCompileDefineFunction in llvm_emit_lambda.zig) re-lower their raw
# bindings/body via a scratch IR instance built with NO macro table
# (ir.lowerSingleExpr / lowerAndOptimize(..., macros=null, ...)) — the gate
# that decides whether to attempt this only checked
# freevars.sexprNeedsEvalFallback, which has no notion of macros at all. A
# let body's macro use was unconditionally miscompiled (100% reproducible);
# a lambda/function body's macro use was "accidentally" safe UNLESS the macro
# shadowed an already-known global name (e.g. `(define-syntax car ...)`) — in
# that case free-variable analysis saw a legitimate global reference and
# compiled a call to the real primitive, silently ignoring the macro.
#
# The fix adds freevars.sexprHasMacroUse — a blind raw-sexpr walk mirroring
# sexprNeedsEvalFallback's traversal but checking self.isMacroName (the same
# gate #1496 added for natively-lowered cond/case/do) — to all four gates, so
# any macro use anywhere in the scope declines native compilation of the
# WHOLE enclosing scope, exactly like any other eval-fallback form. Since
# #1803's apply-operand emission (emitScopedOperand) only ever runs once a
# gate has already accepted the enclosing scope, it inherits the same
# protection with no separate fix.
#
# Usage: bash tests/scheme/compile/native-macro-use-in-scope-1807.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
KAAPPI="${1:-$REPO_DIR/zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

FAILED=0

compile_one() {
    local label="$1"
    local src="$DIR/${label}.scm" bin="$DIR/${label}.bin"
    local compile_out compile_status=0
    compile_out="$(cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" 2>&1)" || compile_status=$?
    if [[ $compile_status -ne 0 ]]; then
        echo "FAIL: $label — kaappi compile exited $compile_status: $compile_out" >&2
        FAILED=1
        return 1
    fi
    if [[ ! -x "$bin" ]]; then
        echo "FAIL: $label — kaappi compile succeeded but produced no binary" >&2
        FAILED=1
        return 1
    fi
}

# Run one program both ways and require identical output. The interpreter is
# the oracle; `expected` documents intent without being what the comparison
# rests on.
check_both() {
    local label="$1" expected="$2"
    local src="$DIR/${label}.scm" bin="$DIR/${label}.bin"

    local interp_out interp_status=0
    interp_out="$(cd "$REPO_DIR" && "$KAAPPI_ABS" "$src" 2>&1)" || interp_status=$?
    if [[ $interp_status -ne 0 ]]; then
        echo "FAIL: $label — interpreter exited $interp_status (output: '$interp_out')" >&2
        FAILED=1
        return
    fi
    if [[ "$interp_out" != "$expected" ]]; then
        echo "FAIL: $label — interpreter expected '$expected', got '$interp_out'" >&2
        FAILED=1
        return
    fi

    compile_one "$label" || return

    local native_out native_status=0
    native_out="$("$bin" 2>&1)" || native_status=$?
    if [[ $native_status -ne 0 ]]; then
        echo "FAIL: $label — compiled binary exited $native_status (output: '$native_out')" >&2
        FAILED=1
        return
    fi
    if [[ "$native_out" != "$interp_out" ]]; then
        echo "FAIL: $label — native '$native_out' != interpreted '$interp_out'" >&2
        FAILED=1
    fi
}

# 1. The issue's own reproducer: a macro use in a let body.
cat > "$DIR/let-body.scm" << 'SCHEME'
(define-syntax foo (syntax-rules () ((_ x) (* 2 x))))
(let ((xs 21)) (display (foo xs)) (newline))
SCHEME
check_both "let-body" "42"

# 2. A macro use in a let BINDING INITIALIZER, not the body — emitLet lowers
#    initializers through the same macro-blind path as the body.
cat > "$DIR/let-init.scm" << 'SCHEME'
(define-syntax inc (syntax-rules () ((_ x) (+ x 1))))
(let ((y (inc 41))) (display y) (newline))
SCHEME
check_both "let-init" "42"

# 3. The let* variant (a separate emitLet code path from plain let).
cat > "$DIR/let-star-body.scm" << 'SCHEME'
(define-syntax foo (syntax-rules () ((_ x) (* 2 x))))
(let* ((xs 21) (ys (+ xs 0))) (display (foo ys)) (newline))
SCHEME
check_both "let-star-body" "42"

# 4. A macro use in a lambda body with zero free variables — the "pure"
#    native closure tier (tryCompilePureLambdaAsNativeClosure).
cat > "$DIR/pure-lambda-body.scm" << 'SCHEME'
(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))
(define (run f x) (f x))
(display (run (lambda (x) (dbl x)) 21))
(newline)
SCHEME
check_both "pure-lambda-body" "42"

# 5. A macro use in a lambda body that ALSO captures a free variable — the
#    capturing native closure tier (tryCompileNativeClosure).
cat > "$DIR/capturing-lambda-body.scm" << 'SCHEME'
(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))
(define (make-doubler y) (lambda (x) (dbl (+ x y))))
(display ((make-doubler 0) 21))
(newline)
SCHEME
check_both "capturing-lambda-body" "42"

# 6. The shadowing shape from the issue: a macro named after an existing
#    primitive, used in a top-level function body (tryCompileDefineFunction).
#    Free-variable analysis alone treats `car` as a legitimate global and
#    would compile a call to the real primitive, silently ignoring the macro.
cat > "$DIR/define-shadow.scm" << 'SCHEME'
(define-syntax car (syntax-rules () ((_ x) (+ 1000 x))))
(define (f p) (car p))
(display (f 5))
(newline)
SCHEME
check_both "define-shadow" "1005"

# 7. A macro shadowing a known global, used inside an `apply` FIXED operand
#    (#1803's emitScopedOperand) rather than the function body directly. Like
#    case 6, the collision matters: a non-colliding macro name here is already
#    "accidentally" safe (free-variable analysis flags it as an unrecognized
#    global and declines native compilation on its own — the enclosing
#    function never even reaches emitApplyForm), so this must shadow `car` to
#    exercise the real gap. emitScopedOperand has no macro-use gate of its
#    own: it inherits protection only because the enclosing function's own
#    gate (tryCompileDefineFunction, same as case 6) already declines native
#    compilation before emitApplyForm/emitScopedOperand is ever reached.
cat > "$DIR/apply-operand.scm" << 'SCHEME'
(define-syntax car (syntax-rules () ((_ x) (+ 1000 x))))
(define (f lst) (apply + (car 5) lst))
(display (f (list 1 2 3)))
(newline)
SCHEME
check_both "apply-operand" "1011"

# 8. A let-bound LOCAL VARIABLE that happens to share a macro's name, used as
#    an ordinary value (never called) — the macro-use walk is a blind raw-sexpr
#    scan with no lexical-scope awareness, so it conservatively (and safely)
#    sends the whole let to the interpreter, which resolves the shadowing
#    correctly. Not a call, so this must NOT expand the macro.
cat > "$DIR/shadowed-let-local.scm" << 'SCHEME'
(define-syntax bar (syntax-rules () ((_ x) (* 99 x))))
(let ((bar 5)) (display (+ bar 1)) (newline))
SCHEME
check_both "shadowed-let-local" "6"

# 9. A let-bound local that shadows a macro name AND is called as a
#    procedure: R7RS has no reserved words, so the local binding must win —
#    the interpreter oracle already gets this right (is_shadowed in
#    ir.lowerFormWithMacros), and the whole-form fallback this gate takes
#    must agree, not re-expand the macro.
cat > "$DIR/shadowed-let-local-called.scm" << 'SCHEME'
(define-syntax foo (syntax-rules () ((_ x) (* 2 x))))
(let ((foo (lambda (x) (+ x 100)))) (display (foo 5)) (newline))
SCHEME
check_both "shadowed-let-local-called" "105"

if [[ $FAILED -ne 0 ]]; then
    exit 1
fi

echo "PASS"
