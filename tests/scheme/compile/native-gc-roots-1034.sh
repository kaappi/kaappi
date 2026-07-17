#!/bin/bash
# Regression test for #1034: GC safety of intermediate values in native code.
#
# The LLVM emitter stores intermediate Values in SSA temps/allocas that the
# GC cannot see.  Without shadow-stack rooting, nested allocating calls like
# (cons (make-string ...) (make-string ...)) can lose the first result when
# the second call triggers collection.
#
# KAAPPI_GC_THRESHOLD=1 forces collection on every allocation in the native
# runtime, making this deterministic rather than probabilistic.
#
# Usage: bash tests/scheme/compile/native-gc-roots-1034.sh [path-to-kaappi]

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

# Freshen the runtime library (prebuilt archive suffices without zig)
ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

check_native() {
    local src="$1" expected="$2" label="$3"
    local bin="$DIR/${label}.bin"
    (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" > /dev/null 2>&1)
    if [[ ! -x "$bin" ]]; then
        echo "FAIL: $label — native compile did not produce a binary" >&2
        exit 1
    fi
    local out
    out="$(KAAPPI_GC_THRESHOLD=1 "$bin")"
    if [[ "$out" != "$expected" ]]; then
        echo "FAIL: $label — expected '$expected', got '$out'" >&2
        exit 1
    fi
}

# --- Case 1: nested cons with allocating arguments ---
cat > "$DIR/nested-cons.scm" << 'SCHEME'
(define (make-pair)
  (cons (cons 1 2) (cons 3 4)))
(let ((p (make-pair)))
  (display (car (car p)))
  (display (cdr (car p)))
  (display (car (cdr p)))
  (display (cdr (cdr p)))
  (newline))
SCHEME

check_native "$DIR/nested-cons.scm" "1234" "nested-cons"

# --- Case 2: let bindings with allocating inits ---
cat > "$DIR/let-alloc.scm" << 'SCHEME'
(define (f)
  (let ((a (cons 10 20))
        (b (cons 30 40)))
    (display (car a))
    (display (cdr a))
    (display (car b))
    (display (cdr b))
    (newline)))
(f)
SCHEME

check_native "$DIR/let-alloc.scm" "10203040" "let-alloc"

# --- Case 3: let* bindings with allocating inits ---
cat > "$DIR/let-star-alloc.scm" << 'SCHEME'
(define (g)
  (let* ((a (cons 5 6))
         (b (cons (car a) 7)))
    (display (car b))
    (display (cdr b))
    (newline)))
(g)
SCHEME

check_native "$DIR/let-star-alloc.scm" "57" "let-star-alloc"

# --- Case 4: deeply nested calls building a list ---
cat > "$DIR/deep-nest.scm" << 'SCHEME'
(define (build-three a b c)
  (cons a (cons b (cons c '()))))
(let ((lst (build-three (cons 1 2) (cons 3 4) (cons 5 6))))
  (display (car (car lst)))
  (display (car (car (cdr lst))))
  (display (car (car (cdr (cdr lst)))))
  (newline))
SCHEME

check_native "$DIR/deep-nest.scm" "135" "deep-nest"

# --- Case 5: inline binary (cons) with call arguments ---
cat > "$DIR/inline-cons.scm" << 'SCHEME'
(define (id x) x)
(let ((p (cons (id (cons 1 2)) (id (cons 3 4)))))
  (display (car (car p)))
  (display (car (cdr p)))
  (newline))
SCHEME

check_native "$DIR/inline-cons.scm" "13" "inline-cons"

# --- Case 6: allocation-heavy recursive function ---
cat > "$DIR/recursive-alloc.scm" << 'SCHEME'
(define (make-list n)
  (if (= n 0)
      '()
      (cons n (make-list (- n 1)))))

(define (sum-list lst)
  (if (null? lst)
      0
      (+ (car lst) (sum-list (cdr lst)))))

(display (sum-list (make-list 50)))
(newline)
SCHEME

check_native "$DIR/recursive-alloc.scm" "1275" "recursive-alloc"

echo "PASS"
