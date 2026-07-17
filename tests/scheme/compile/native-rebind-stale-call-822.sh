#!/bin/bash
# Regression test for #822: LLVM native backend kept invoking stale native code
# after set!/define rebound a procedure name. Three mechanisms were affected:
#
# 1. native_fns direct calls — set! or non-lambda define did not remove the
#    entry, so later call sites still dispatched to the old native function.
# 2. Inline primitives — tryEmitInlineBinary/tryEmitInlineUnary used the
#    original primitive even after a top-level (define + -).
#
# Each case must produce the same output from the native binary as from the
# interpreter.
#
# Usage: bash tests/scheme/compile/native-rebind-stale-call-822.sh [path-to-kaappi]

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

check() {
    local name="$1" src="$2" expect_out="$3" expect_status="$4"

    printf '%s' "$src" > "$DIR/$name.scm"

    if ! (cd "$DIR" && "$KAAPPI_ABS" compile "$name.scm" -o "$name" > /dev/null 2>&1); then
        echo "FAIL: $name — native compilation failed" >&2
        fail=1
        return
    fi

    set +e
    local out status
    out=$("$DIR/$name" 2>/dev/null)
    status=$?
    set -e

    if [[ "$out" != "$expect_out" ]]; then
        echo "FAIL: $name — native stdout '$out' != expected '$expect_out'" >&2
        fail=1
    fi
    if [[ "$status" -ne "$expect_status" ]]; then
        echo "FAIL: $name — native exit $status != expected $expect_status" >&2
        fail=1
    fi
}

# 1. set! replacing a natively compiled function.
check set-replace-native \
'(define (f x) (+ x 1))
(set! f (lambda (x) (* x 2)))
(display (f 5))
(newline)' \
'10' 0

# 2. define aliasing one function to another.
check define-alias \
'(define (f x) (+ x 1))
(define (g x) (* x 3))
(define f g)
(display (f 5))
(newline)' \
'15' 0

# 3. Redefining an arithmetic primitive.
check redefine-primitive \
'(define + -)
(display (+ 10 3))
(newline)' \
'7' 0

# 4. Redefining car/cdr (unary inline primitives).
check redefine-car \
'(define car cdr)
(display (car (cons 1 2)))
(newline)' \
'2' 0

# 5. Redefining cons (binary inline primitive).
check redefine-cons \
'(define original-cons cons)
(define (cons a b) (original-cons b a))
(display (car (cons 1 2)))
(newline)' \
'2' 0

# 6. Redefine then re-define with a new native lambda — the new native
#    version should be used.
check redefine-then-redefine \
'(define (f x) (+ x 1))
(define f (lambda (x) (* x 10)))
(define (f x) (+ x 100))
(display (f 5))
(newline)' \
'105' 0

# 7. null? redefined (unary inline primitive).
check redefine-null \
'(define null? pair?)
(display (null? (list 1 2)))
(newline)' \
'#t' 0

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-rebind-stale-call-822: all cases passed"
