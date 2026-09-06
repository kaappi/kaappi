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

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

# `kaappi compile` needs libkaappi_rt.a (searched in <exe_dir>/../lib).
ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail=0

# Compile a program natively and require its stdout + exit status to match the
# interpreter's — which is the oracle here; every one of these is plain lexical
# scoping the VM always got right. `expect_out`/`expect_status` document intent
# and still catch an answer both tiers get wrong, but the comparison no longer
# rests on them. See the "interpreter as the native tier's oracle" block in
# ../shell-common.sh.
#
# stdout and exit status, never stderr: case 4 errors, and after a top-level
# error the VM reports it and moves to the next form while the native binary
# exits at the first — so the two tiers' diagnostics legitimately differ in
# both count and framing.
check() {
    local name="$1" src="$2" expect_out="$3" expect_status="$4"

    printf '%s' "$src" > "$DIR/$name.scm"

    local interp_out interp_status=0 interp_err="$DIR/$name.interp.err"
    interp_out=$(interp_stdout "$KAAPPI_ABS" "$DIR" "$name.scm" "$interp_err") || interp_status=$?
    if [[ "$interp_out" != "$expect_out" ]]; then
        echo "FAIL: $name — interpreter stdout '$interp_out' != expected '$expect_out'" >&2
        show_interp_stderr "$interp_err"
        fail=1
        return
    fi
    if [[ "$interp_status" -ne "$expect_status" ]]; then
        echo "FAIL: $name — interpreter exit $interp_status != expected $expect_status" >&2
        show_interp_stderr "$interp_err"
        fail=1
        return
    fi

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

    assert_tiers_agree "$name" "$interp_out" "$interp_status" "$out" "$status" || fail=1
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

# 5b. The procedure shorthand of case 5, which stayed broken for another six
#     years of issue numbers (#1861): `ir.lowerDefine` turns a pair target into a
#     passthrough, so it never reached the internal-define path case 5 exercises
#     and defined a global instead. Reaching for the let-local in its body makes
#     the pre-fix failure loud — the global function it compiled to looked `x` up
#     as a global and the binary died with "undefined variable 'x'".
#     tests/scheme/compile/native-shorthand-internal-define-scope-1861.sh covers
#     the shape in depth; this is the direct pairing with case 5.
check internal-define-shorthand-local \
'(define (z) 100)
(let ((x 1)) (define (z) x) (display (z)) (newline))
(display (z))
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
