#!/bin/bash
# Regression test for #2469 (LLVM native backend): the builtin `apply`
# fast path is gated at RUN time in compiled binaries, not at compile time.
#
# #2457's interim pre-scanned the compilation unit's top-level define/set!
# targets, so a redefinition it could not see — one that only materializes
# when a macro expands, or one `eval` performs at run time — still baked the
# builtin's flattening semantics into every body compiled before it ran.
# emitApplyForm now resolves the `apply` global at the call, asks
# @kaappi_builtin_is_pristine (runtime_exports.zig) whether it is still the
# genuine primitive, and branches to the structural @kaappi_apply shape or to
# an ordinary indirect call of whatever the global holds — the same decision
# the interpreter's guard_builtin opcode makes.
#
# Usage: bash tests/scheme/compile/native-apply-redefinition-order-2469.sh [path-to-kaappi]

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

# Run one program three ways — a cold interpreter run, a second run that is
# a bytecode-cache HIT (the .sbc round trip; skipped with a third argument
# "nocache" for programs the cache declines by design), and the native binary
# — and require identical, expected output.
check_all() {
    local label="$1" expected="$2" cache_mode="${3:-cache}"
    local src="$DIR/${label}.scm" bin="$DIR/${label}.bin" home="$DIR/home-$label"

    local interp_out interp_status=0
    interp_out="$(cd "$REPO_DIR" && KAAPPI_HOME="$home" "$KAAPPI_ABS" "$src" 2>&1)" || interp_status=$?
    if [[ $interp_status -ne 0 || "$interp_out" != "$expected" ]]; then
        echo "FAIL: $label — interpreter exited $interp_status, expected '$expected', got '$interp_out'" >&2
        FAILED=1
        return
    fi

    # The guard_builtin opcode must survive the .sbc round trip (kaappi#2469
    # appended an opcode; the loader's validator must accept it): the cold run
    # above wrote a cache entry, so this second run loads it instead of
    # compiling.
    if [[ "$cache_mode" == "cache" ]]; then
        if ! (cd "$REPO_DIR" && KAAPPI_HOME="$home" "$KAAPPI_ABS" cache status 2>/dev/null | grep -q "$src"); then
            echo "FAIL: $label — the cold run left no bytecode-cache entry for $src" >&2
            FAILED=1
            return
        fi
        local hit_out hit_status=0
        hit_out="$(cd "$REPO_DIR" && KAAPPI_HOME="$home" "$KAAPPI_ABS" "$src" 2>&1)" || hit_status=$?
        if [[ $hit_status -ne 0 || "$hit_out" != "$expected" ]]; then
            echo "FAIL: $label — cache-HIT run exited $hit_status, expected '$expected', got '$hit_out'" >&2
            FAILED=1
            return
        fi
    fi

    compile_one "$label" || return

    local native_out native_status=0
    native_out="$("$bin" 2>&1)" || native_status=$?
    if [[ $native_status -ne 0 || "$native_out" != "$expected" ]]; then
        echo "FAIL: $label — compiled binary exited $native_status, expected '$expected', got '$native_out'" >&2
        FAILED=1
    fi
}

# 1. A set! that only materializes when a macro expands: invisible to any
#    structure-only scan, decided at run time by the guard. No cache leg: a
#    program with a top-level define-syntax is never cached (by design).
cat > "$DIR/macro.scm" << 'SCHEME'
(import (scheme base) (scheme write))
(define (nt) (let ((v (apply + (list 1 2)))) v))
(define (t) (apply + (list 1 2)))
(define-syntax redef! (syntax-rules () ((_ n v) (set! n v))))
(redef! apply (lambda (f xs) 'macro-set))
(write (list (nt) (t) (apply + '(1 2))))
(newline)
SCHEME
check_all "macro" "(macro-set macro-set macro-set)" nocache

# 2. A redefinition performed by eval at run time.
cat > "$DIR/eval.scm" << 'SCHEME'
(import (scheme base) (scheme write) (scheme eval))
(define (nt) (let ((v (apply + (list 1 2)))) v))
(eval '(define (apply f xs) 'eval-user) (interaction-environment))
(write (nt))
(newline)
SCHEME
check_all "eval" "eval-user"

# 3. The binding changes while the caller is on the stack: each call decides
#    afresh, and restoring the genuine binding brings the builtin back.
cat > "$DIR/flip.scm" << 'SCHEME'
(import (scheme base) (scheme write))
(define orig apply)
(define (go)
  (let* ((a (apply + (list 1 2)))
         (b (begin (set! apply (lambda (f xs) 'flipped)) (apply + (list 1 2))))
         (c (begin (set! apply orig) (apply + (list 1 2)))))
    (list a b c)))
(write (go))
(newline)
SCHEME
check_all "flip" "(3 flipped 3)"

# 4. The emitted IR carries the guard and keeps the structural call site; a
#    clean program still has no eval fallback (#1803's convergence).
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
    if ! grep -q "@kaappi_builtin_is_pristine(ptr %vm" "$LL"; then
        echo "FAIL: clean — no run-time guard (@kaappi_builtin_is_pristine) in emitted IR" >&2
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
