#!/bin/bash
# Regression test for #1803 (LLVM native backend): lower `apply` natively
# instead of declining the whole enclosing function.
#
# #1799's fix put `apply` in ir.eval_fallback_form_names, which is correct but
# blunt: ONE apply anywhere in a body sent every other expression in that body
# to the interpreter too (~19x on the issue's arithmetic-loop reproducer).
# emitApplyForm now emits the callee and fixed arguments natively and hands the
# final operand to @kaappi_apply (runtime_exports.zig), which splices it with
# primitives.applyFn's exact semantics. The dispatch mirrors the interpreter's
# (compiler.zig): tail + unshadowed + unrebound = structural built-in apply
# (tail_apply honours a top-level rebinding since #2033, so the fast path is
# gated the same way); everything else resolvable is an ordinary call through
# whatever `apply` denotes in scope.
#
# Every functional case asserts the compiled binary agrees with the
# interpreter; error cases assert both fail and the native diagnostic carries
# applyFn's verbatim typeError detail. The structural case asserts the
# convergence guarantee itself: a hot function containing one apply emits ZERO
# eval fallbacks (that is what closed the 19x gap, and what a silent
# reintroduction of the fallback would break first).
#
# Usage: bash tests/scheme/compile/native-apply-lowering-1803.sh [path-to-kaappi]

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

# Error-shape check: interpreter and compiled binary must BOTH fail (nonzero,
# in bounded time — a circular list must raise, not hang), and the native
# diagnostic must carry applyFn's typeError detail verbatim. Full-output
# equality is impossible here: the interpreter prefixes file:line/excerpt
# framing, and its tail-position apply reports through the tail_apply opcode's
# own texts.
check_both_fail() {
    local label="$1" detail="$2"
    local src="$DIR/${label}.scm" bin="$DIR/${label}.bin"

    local interp_out interp_status=0
    interp_out="$(cd "$REPO_DIR" && "$KAAPPI_ABS" "$src" 2>&1)" || interp_status=$?
    if [[ $interp_status -eq 0 ]]; then
        echo "FAIL: $label — interpreter unexpectedly succeeded: '$interp_out'" >&2
        FAILED=1
        return
    fi

    compile_one "$label" || return

    local native_out native_status=0
    native_out="$("$bin" 2>&1)" || native_status=$?
    if [[ $native_status -eq 0 ]]; then
        echo "FAIL: $label — compiled binary unexpectedly succeeded: '$native_out'" >&2
        FAILED=1
        return
    fi
    if [[ "$native_out" != *"$detail"* ]]; then
        echo "FAIL: $label — native diagnostic '$native_out' lacks '$detail'" >&2
        FAILED=1
    fi
}

# 1. The de-optimization shape from the issue: a hot self-tail arithmetic loop
#    whose exit path holds the program's only apply. The loop total (3M
#    iterations across 100 runs) matches the issue's reproducer; the operands
#    keep every intermediate inside fixnum range.
cat > "$DIR/heavy.scm" << 'SCHEME'
(define (work n acc)
  (if (= n 0) (apply + (list acc 0))
      (work (- n 1) (+ acc (* n 3) (- n 1) (* n n)))))
(define (bench k best)
  (if (= k 0) best (bench (- k 1) (max best (work 30000 0)))))
(display (bench 100 0))
(newline)
SCHEME
check_both "heavy" "9002250035000"

# 1b. The structural convergence guarantee behind the 19x fix: the emitted IR
#     for that program routes NOTHING through the interpreter — `work` and
#     `bench` compile natively and the apply is a @kaappi_apply call site.
LL="$DIR/heavy.ll"
if (cd "$REPO_DIR" && "$KAAPPI_ABS" --emit-llvm -o "$LL" "$DIR/heavy.scm" > /dev/null 2>&1); then
    evals=$(grep -c "call i64 @kaappi_eval" "$LL" || true)
    if [[ "$evals" -ne 0 ]]; then
        echo "FAIL: heavy — expected 0 eval fallbacks in emitted IR, found $evals" >&2
        FAILED=1
    fi
    if ! grep -q "@kaappi_apply(ptr %vm" "$LL"; then
        echo "FAIL: heavy — no native @kaappi_apply call site in emitted IR" >&2
        FAILED=1
    fi
else
    echo "FAIL: heavy — --emit-llvm failed" >&2
    FAILED=1
fi

# 2. Tail apply driving a self-loop, with a let in the body so both
#    frame-entry and body-scope GC roots are live at the tail transfer: a
#    pop-before-ret miss leaks one root set per iteration and overflows the
#    1024-slot shadow stack well before 2000 iterations.
cat > "$DIR/tail-roots.scm" << 'SCHEME'
(define (loop n acc)
  (if (= n 0)
      acc
      (let ((next (cons n acc)))
        (apply loop (list (- n 1) next)))))
(display (length (loop 2000 '())))
(newline)
SCHEME
check_both "tail-roots" "2000"

# 3. Fixed arguments ahead of the list, under an adversarial GC (collection
#    pressure on every few allocations): the callee and fixed-argument temps
#    must be rooted across the allocating list-operand emission.
cat > "$DIR/gc-fixed.scm" << 'SCHEME'
(define (s a b xs) (apply + a b (list (car xs) (cadr xs))))
(define (go n acc)
  (if (= n 0) acc (go (- n 1) (+ acc (s 1 2 (list n (* n 2)))))))
(display (go 2000 0))
(newline)
SCHEME
KAAPPI_GC_THRESHOLD=1 check_both "gc-fixed" "6009000"

# 4. A lexically shadowed `apply` is the callee, not the built-in.
cat > "$DIR/shadowed.scm" << 'SCHEME'
(define (weird apply xs) (apply + xs))
(display (weird (lambda (f lst) (f 10 20)) (list 1 2 3)))
(newline)
SCHEME
check_both "shadowed" "30"

# 5. A top-level rebinding of `apply`: the interpreter honors it in BOTH
#    positions since #2033 (R7RS 5.3.1: a top-level definition is essentially
#    an assignment). A non-tail apply is an ordinary call through the current
#    global; a tail apply must also resolve the user's binding instead of
#    firing the structural tail_apply opcode. The native dispatch mirrors both.
cat > "$DIR/rebound.scm" << 'SCHEME'
(define (myapply f lst) 99)
(define apply myapply)
(define (nontail xs) (+ 0 (apply + xs)))
(define (tail xs) (apply + xs))
(display (nontail (list 1 2 3)))
(newline)
(display (tail (list 1 2 3)))
(newline)
SCHEME
check_both "rebound" "$(printf '99\n99')"

# 6. `apply` as a VALUE rather than a call head: resolves to the built-in
#    procedure object and flows through map like any other argument.
cat > "$DIR/as-value.scm" << 'SCHEME'
(define (s) (map apply (list + *) (list (list 1 2) (list 3 4))))
(display (s))
(newline)
SCHEME
check_both "as-value" "(3 12)"

# 7. Inside a natively lowered cond arm (#1496): apply no longer rejects the
#    form, and the arm resolves the parameter correctly.
cat > "$DIR/cond-arm.scm" << 'SCHEME'
(define (f lst) (cond ((null? lst) 0) ((pair? lst) (apply + 100 lst)) (else -1)))
(display (f (list 1 2 3)))
(newline)
(display (f '()))
(newline)
SCHEME
check_both "cond-arm" "$(printf '106\n0')"

# 8. Error shapes, non-tail so both runtimes report applyFn's typeError texts:
#    the native tier through @kaappi_apply, and — since kaappi#2451 — the
#    interpreter through its own non-tail `apply` opcode, which reproduces
#    those texts verbatim precisely so this parity keeps holding. (Tail-position
#    errors go through the interpreter's tail_apply opcode, whose texts differ —
#    dispatch parity for those is covered by the rebound case above.)
cat > "$DIR/err-not-proc.scm" << 'SCHEME'
(define (s x) (+ 0 (apply x (list 1))))
(display (s 5))
SCHEME
check_both_fail "err-not-proc" "type error in 'apply': expected procedure, got 5"

cat > "$DIR/err-improper.scm" << 'SCHEME'
(define (s xs) (+ 0 (apply + xs)))
(display (s (cons 1 2)))
SCHEME
check_both_fail "err-improper" "type error in 'apply': expected proper list"

# 9. A circular final list must raise in bounded time, never hang — the
#    tortoise-and-hare check from applyFn, verbatim in @kaappi_apply.
cat > "$DIR/err-circular.scm" << 'SCHEME'
(define (s xs) (+ 0 (apply + xs)))
(define l (list 1 2 3))
(set-cdr! (cddr l) l)
(display (s l))
SCHEME
check_both_fail "err-circular" "type error in 'apply': expected proper list"

# 10. Too few operands, non-tail: the built-in's own arity check.
cat > "$DIR/err-arity.scm" << 'SCHEME'
(define (s f) (+ 0 (apply f)))
(display (s +))
SCHEME
check_both_fail "err-arity" "expected at least 2 arguments, got 1"

if [[ $FAILED -ne 0 ]]; then
    exit 1
fi

echo "PASS"
