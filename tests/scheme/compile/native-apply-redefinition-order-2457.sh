#!/bin/bash
# Regression test for #2457 (LLVM native backend): a top-level redefinition
# of `apply` that runs AFTER the code using it was compiled must win there
# too, in the compiled binary — not just in the interpreter.
#
# emitApplyForm's structural @kaappi_apply shape was gated on
# rebound_globals/native_fns, both populated IN ORDER as forms are emitted, so
# a use preceding the define still baked in the builtin's flattening
# semantics and the user's procedure was silently discarded. #2457's interim
# was a whole-unit pre-scan; since #2469 the emitted code decides at run
# time: it resolves the `apply` global, asks @kaappi_builtin_is_pristine
# whether it is still the genuine primitive, and branches to the structural
# shape or to an ordinary indirect call of whatever the global holds.
#
# The convergence guarantee from #1803 is pinned too: a program that never
# touches these names must keep its native @kaappi_apply call site (the
# guard must not cost the fast path in clean programs).
#
# Usage: bash tests/scheme/compile/native-apply-redefinition-order-2457.sh [path-to-kaappi]

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

# Run one program both ways and require identical output.
check_both() {
    local label="$1" expected="$2"
    local src="$DIR/${label}.scm" bin="$DIR/${label}.bin"

    local interp_out interp_status=0
    interp_out="$(cd "$REPO_DIR" && KAAPPI_HOME="$DIR/home-i" "$KAAPPI_ABS" "$src" 2>&1)" || interp_status=$?
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

# 1. The #2457 shape, non-tail and tail: the caller is compiled before the
#    top-level redefinition runs; the user's binding must win everywhere.
cat > "$DIR/order.scm" << 'SCHEME'
(import (scheme base) (scheme write))
(define (nt) (let ((v (apply + (list 1 2)))) v))
(define (t) (apply + (list 1 2)))
(define (apply f xs) 'user-apply)
(write (list (nt) (t)))
(newline)
SCHEME
check_both "order" "(user-apply user-apply)"

# 2. Restored to the genuine binding, the builtin is reachable again through
#    the same by-name call sites.
cat > "$DIR/restore.scm" << 'SCHEME'
(import (scheme base) (scheme write))
(define (nt) (let ((v (apply + (list 1 2)))) v))
(define orig apply)
(define (apply f xs) 'user-apply)
(define apply orig)
(write (nt))
(newline)
SCHEME
check_both "restore" "3"

# 3. The #1803 convergence guarantee survives the scan: a program that never
#    redefines apply keeps a native @kaappi_apply call site and no eval
#    fallback in the emitted IR.
cat > "$DIR/clean.scm" << 'SCHEME'
(define (work n acc)
  (if (= n 0) (apply + (list acc 0))
      (work (- n 1) (+ acc (* n 3)))))
(display (work 10000 0))
(newline)
SCHEME
LL="$DIR/clean.ll"
if (cd "$REPO_DIR" && "$KAAPPI_ABS" --emit-llvm -o "$LL" "$DIR/clean.scm" > /dev/null 2>&1); then
    evals=$(grep -c "call i64 @kaappi_eval" "$LL" || true)
    if [[ "$evals" -ne 0 ]]; then
        echo "FAIL: clean — expected 0 eval fallbacks in emitted IR, found $evals" >&2
        FAILED=1
    fi
    if ! grep -q "@kaappi_apply(ptr %vm" "$LL"; then
        echo "FAIL: clean — no native @kaappi_apply call site in emitted IR" >&2
        FAILED=1
    fi
else
    echo "FAIL: clean — --emit-llvm failed" >&2
    FAILED=1
fi

if [[ $FAILED -ne 0 ]]; then
    exit 1
fi

echo "PASS"
