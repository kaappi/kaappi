#!/bin/bash
# Regression test for #1808 (LLVM native backend): a compiled binary segfaults
# with no diagnostic once a long-running native loop has executed enough
# passes, regardless of whether the values involved ever become bignums.
#
# Root cause: `alloca` in LLVM frees only at function RETURN, never at "the
# next loop iteration". emitRootPush's per-root shadow-stack slots and the
# generic call path's argument-array `alloca`s (emitCallNode/emitDirectCall)
# are emitted wherever the call site happens to be — which, for a call inside
# a self-tail-call loop body or a `do` loop body, is a block reached via a
# backward branch. Every pass through that block adds another `alloca`'s
# worth of native stack that is never reclaimed until the function returns,
# so a loop that runs long enough overflows the OS thread stack. The original
# issue report suspected a GC-rooting gap around bignum promotion specifically
# (the crash happened to land inside bignum code, since #1808's own reproducer
# also grows into bignum range) — but the reproducer below with `(+ acc 0 0 0)`
# never leaves fixnum range and crashes identically, proving the bug is the
# stack growth itself, independent of bignum-ness.
#
# The fix (llvm_emit.zig's emitStackSave/emitStackRestore) captures the stack
# pointer at the top of every loop pass (the self-tail-call body_lbl header in
# emitLambdaFunction, and the `do`-loop header in llvm_emit_forms.emitDo) and
# restores it right before the back-edge that starts the next pass, reclaiming
# every alloca made during the pass just completed.
#
# Usage: bash tests/scheme/compile/native-loop-alloca-stack-growth-1808.sh [path-to-kaappi]

set -euo pipefail

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

# 1. The issue's own reproducer: a self-tail arithmetic loop whose accumulator
#    grows past the i48 fixnum range into bignum territory.
cat > "$DIR/heavy-pure.scm" << 'SCHEME'
(define (work n acc)
  (if (= n 0) acc
      (work (- n 1) (+ acc (* n 3) (- n 1) (* n n)))))
(display (work 3000000 0))
SCHEME
check_both "heavy-pure" "9000022500003500000"

# 2. Fixnum-only self-tail loop: the accumulator NEVER leaves fixnum range
#    (every term is 0), isolating the bug from bignum promotion entirely. This
#    is the case that disproves the GC-rooting-around-bignum-promotion theory:
#    the pre-fix binary crashed on this too, purely from `alloca` growth in
#    the loop body's call to the 4-arg `+` (not inlined — inlining only
#    applies to exactly 2 args, so this always takes the generic call path
#    with its own argument-array alloca).
cat > "$DIR/fixnum-only-loop.scm" << 'SCHEME'
(define (loop n acc)
  (if (= n 0) acc
      (loop (- n 1) (+ acc 0 0 0))))
(display (loop 3000000 0))
SCHEME
check_both "fixnum-only-loop" "0"

# 3. Same class of bug in a `do` loop (a second, independent loop-establishing
#    site in the LLVM emitter — do's own back-edge in emitDo, not
#    emitSelfTailCall). Also fixnum-only.
cat > "$DIR/do-loop.scm" << 'SCHEME'
(define (run)
  (do ((i 0 (+ i 1))
       (acc 0 (+ acc 0 0 0)))
      ((= i 3000000) acc)))
(display (run))
SCHEME
check_both "do-loop" "0"

# 4. The issue's other named suspect: a single crossing of the i48 fixnum
#    boundary (in both directions) under forced GC pressure at the promotion
#    site. This investigation found the real bug was loop-body stack growth,
#    not a GC-rooting gap here — but the issue explicitly asked for this
#    boundary case, and it is cheap insurance against a regression in the
#    inline arithmetic overflow-to-bignum slow path (llvm_emit_inline.zig).
cat > "$DIR/boundary-positive.scm" << 'SCHEME'
(display (+ 140737488355327 1))
SCHEME
KAAPPI_GC_THRESHOLD=1 check_both "boundary-positive" "140737488355328"

cat > "$DIR/boundary-negative.scm" << 'SCHEME'
(display (- -140737488355328 1))
SCHEME
KAAPPI_GC_THRESHOLD=1 check_both "boundary-negative" "-140737488355329"

if [[ $FAILED -ne 0 ]]; then
    exit 1
fi

echo "PASS"
