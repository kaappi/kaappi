#!/bin/bash
# Regression test for #819: LLVM native backend compiled set! and internal
# define to kaappi_define_global unconditionally, ignoring lexical scope.
# Mutations to parameters / let-locals were dropped, set! values referencing
# lexical variables crashed, top-level set! on an unbound variable silently
# defined it, and internal defines leaked into global scope.
#
# The native binary's output (and exit status) must match the interpreter's for
# each reproduction.
#
# Usage: bash tests/scheme/compile/set-define-lexical-scope-819.sh [path-to-kaappi]

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

# `kaappi compile` needs libkaappi_rt.a (searched in <exe_dir>/../lib).
if [[ ! -f "$REPO_DIR/zig-out/lib/libkaappi_rt.a" ]]; then
    (cd "$REPO_DIR" && zig build lib > /dev/null 2>&1)
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail=0

# Compile a program natively and check its stdout + exit status match the
# interpreter. For the error case we match the interpreter's exit status and a
# substring (native diagnostics are terser than the interpreter's).
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

# 1. set! on a parameter must mutate the parameter slot, not define a global.
check set-param \
'(define (f x) (set! x 10) x)
(display (f 5))
(newline)' \
'10' 0

# 2. set! value referencing a parameter must be evaluated in the local scope.
check set-param-value \
'(define (f x) (set! x (+ x 1)) x)
(display (f 5))
(newline)' \
'6' 0

# 3. set! on a let-local must mutate the local binding.
check set-let-local \
'(display (let ((x 1)) (set! x 2) x))
(newline)' \
'2' 0

# 4. Top-level set! on an unbound variable must error, not silently define it.
check set-unbound \
'(set! zzz 5)
(display zzz)
(newline)' \
'' 1

# 5. Internal define inside a let body must be local, not overwrite a global.
check internal-define-local \
'(define z 100)
(let ((x 1)) (define z x) (display z) (newline))
(display z)
(newline)' \
'1
100' 0

# 6. set! on a nested let-local inside a natively compiled function body.
check set-nested-let \
'(define (f x)
  (let ((acc 0))
    (set! acc (+ acc x))
    (set! acc (* acc 2))
    acc))
(display (f 5))
(newline)' \
'10' 0

# 7. A closure mutating a captured variable (make-counter) must still produce
#    correct results (it falls back to the interpreter).
check closure-capture-mutate \
'(define (make-counter)
  (let ((n 0))
    (lambda () (set! n (+ n 1)) n)))
(define c (make-counter))
(display (c)) (display " ") (display (c)) (display " ") (display (c))
(newline)' \
'1 2 3' 0

# 8. set! on an existing top-level global must mutate it.
check set-existing-global \
'(define g 1)
(set! g 42)
(display g)
(newline)' \
'42' 0

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "set-define-lexical-scope-819: all cases passed"
