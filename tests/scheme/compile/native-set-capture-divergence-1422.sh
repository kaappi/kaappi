#!/bin/bash
# Regression test for #1422 / #1497: the native closure tiers copy captured
# variables by value, so a set! of the captured binding after closure creation
# would be invisible to the closure — diverging from the VM's by-location
# semantics.
#
# The fix (#1497) applies assignment conversion: a variable that is both
# captured by a nested lambda and mutated is boxed (a heap cell), closures
# capture the box pointer, and reads/writes go through the box. Such functions
# now compile NATIVELY and match the interpreter. The only remaining fallback
# case is when the capturing lambda itself cannot be a native closure (e.g. a
# variadic inner lambda) — a boxed variable cannot be republished as a global,
# so the whole function falls back to the interpreter.
#
# Usage: bash tests/scheme/compile/native-set-capture-divergence-1422.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

if [[ ! -f "$REPO_DIR/zig-out/lib/libkaappi_rt.a" ]]; then
    (cd "$REPO_DIR" && zig build lib > /dev/null 2>&1)
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail=0

# Compile natively and check output.  When expect_native is "yes", also
# verify that at least one user-defined native function was emitted; when
# "no", verify that none were (the whole program fell back to eval).
check() {
    local name="$1" src="$2" expect_out="$3" expect_native="${4:-}"

    printf '%s' "$src" > "$DIR/$name.scm"

    if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$DIR/$name.scm" -o "$DIR/$name" > /dev/null 2>&1); then
        echo "FAIL: $name — native compilation failed" >&2
        fail=1
        return
    fi

    local out
    if ! out=$("$DIR/$name" 2>/dev/null); then
        echo "FAIL: $name — binary exited nonzero" >&2
        fail=1
        return
    fi

    if [[ "$out" != "$expect_out" ]]; then
        echo "FAIL: $name — expected '$expect_out', got '$out'" >&2
        fail=1
    fi

    # Pin the compilation tier when requested. A native user-function definition
    # is `@lambda_N` (uniform) or, since #1499, a reserved `@rN` / `@rN.fast` /
    # `@lambda_N.fast` fast entry — all tagged `define [internal|tailcc ...] i64`.
    if [[ -n "$expect_native" ]]; then
        (cd "$REPO_DIR" && "$KAAPPI_ABS" --emit-llvm -o "$DIR/$name.ll" "$DIR/$name.scm" > /dev/null 2>&1) || true
        local native_def_re='^define ([a-z]+ )*i64 @(lambda_|r[0-9])'
        if [[ "$expect_native" == "yes" ]]; then
            if ! grep -qE "$native_def_re" "$DIR/$name.ll" 2>/dev/null; then
                echo "FAIL: $name — expected native fn definition in LLVM IR" >&2
                fail=1
            fi
        elif [[ "$expect_native" == "no" ]]; then
            if grep -qE "$native_def_re" "$DIR/$name.ll" 2>/dev/null; then
                echo "FAIL: $name — expected NO native fn definition (should fall back)" >&2
                fail=1
            fi
        fi
    fi
}

# 1. Issue reproducer (define-position): set! of param u in a sibling
#    argument, lambda captures u.  u is boxed; compiles natively, matches VM.
check set-capture-inline \
'(define (f0 u) ((lambda (a) (+ u a)) (let ((b 5)) (set! u 90) b)))
(write (f0 1))
(newline)' \
'95' yes

# 2. Variadic inner lambda captures the boxed u but cannot itself be a native
#    closure; a boxed variable cannot be republished as a global, so the whole
#    function falls back to the interpreter (still matches).
check set-capture-variadic \
'(define (f0 u) ((lambda (a . rest) (+ u a)) (let ((b 5)) (set! u 90) b) 7))
(write (f0 1))
(newline)' \
'95' no

# 3. Retained closure: set! runs between closure creation and call.  x is
#    boxed, so the closure reads the mutated value — compiles natively.
check set-capture-retained \
'(define (f x)
  (let ((g (lambda () x)))
    (set! x 42)
    (g)))
(write (f 1))
(newline)' \
'42' yes

# 4. Inline lambda (tier 2): boxed param u through
#    tryCompilePureLambdaAsNativeClosure.  Compiles natively.
check set-capture-inline-lambda \
'(write ((lambda (u) ((lambda (a) (+ u a)) (let ((b 5)) (set! u 90) b))) 1))
(newline)' \
'95' yes

# 5. Shadowed param: the lambda (x) shadows f's x, so it does NOT capture
#    f's x.  The function should still compile natively.
check set-shadowed-param \
'(define (f x) (set! x 10) ((lambda (x) (+ x 1)) 3))
(write (f 5))
(newline)' \
'4' yes

# 6. No conflict: set! targets x but lambda captures y — no overlap.
#    Should still compile natively.
check set-different-param \
'(define (f x y) (set! x 10) ((lambda () y)))
(write (f 1 99))
(newline)' \
'99' yes

# 7. Mutual visibility (#1497 acceptance): two closures over one boxed binding;
#    a set! through one is visible to the other. Compiles natively.
check set-capture-shared \
'(define (make-counter)
  (let ((n 0))
    (cons (lambda () (set! n (+ n 1)) n)
          (lambda () n))))
(define c (make-counter))
(display ((car c)))
(display ((car c)))
(display ((cdr c)))
(newline)' \
'122' yes

# 8. Accumulator over a boxed parameter, shared across calls. Native.
check set-capture-accumulator \
'(define (make-acc n) (lambda (amt) (set! n (+ n amt)) n))
(define a (make-acc 100))
(display (a 10))
(display " ")
(display (a 5))
(newline)' \
'110 115' yes

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-set-capture-divergence-1422: all cases passed"
