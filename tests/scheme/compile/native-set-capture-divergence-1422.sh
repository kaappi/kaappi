#!/bin/bash
# Regression test for #1422: the native closure tiers copy captured variables
# by value, so a set! of the captured binding after closure creation is
# invisible to the closure — diverging from the VM's by-location semantics.
#
# The fix rejects native compilation of a function whose body contains both
# a set! of a parameter and a nested lambda that captures that parameter,
# falling back to the interpreter.
#
# Usage: bash tests/scheme/compile/native-set-capture-divergence-1422.sh [path-to-kaappi]

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

if [[ ! -f "$REPO_DIR/zig-out/lib/libkaappi_rt.a" ]]; then
    (cd "$REPO_DIR" && zig build lib > /dev/null 2>&1)
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail=0

check() {
    local name="$1" src="$2" expect_out="$3"

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
}

# 1. Issue reproducer: set! of param u in a sibling argument, lambda captures u.
check set-capture-inline \
'(define (f0 u) ((lambda (a) (+ u a)) (let ((b 5)) (set! u 90) b)))
(write (f0 1))
(newline)' \
'95'

# 2. Variadic inner lambda (falls to eval fallback, same divergence via
#    bindParamsAsGlobals snapshot).
check set-capture-variadic \
'(define (f0 u) ((lambda (a . rest) (+ u a)) (let ((b 5)) (set! u 90) b) 7))
(write (f0 1))
(newline)' \
'95'

# 3. Retained closure: set! runs between closure creation and call.
check set-capture-retained \
'(define (f x)
  (let ((g (lambda () x)))
    (set! x 42)
    (g)))
(write (f 1))
(newline)' \
'42'

# 4. Shadowed param: the lambda (x) shadows f's x, so it does NOT capture f's x.
#    The function should still compile natively.
check set-shadowed-param \
'(define (f x) (set! x 10) ((lambda (x) (+ x 1)) 3))
(write (f 5))
(newline)' \
'4'

# 5. No conflict: set! targets x but lambda captures y — no overlap.
check set-different-param \
'(define (f x y) (set! x 10) ((lambda () y)))
(write (f 1 99))
(newline)' \
'99'

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-set-capture-divergence-1422: all cases passed"
