#!/bin/bash
# Regression test for #1410 (LLVM native backend): the closure tiers' free-
# variable analysis treated nested .lambda IR nodes as opaque, so a lambda
# whose only reference to an enclosing binding lived inside an inner lambda
# compiled as a *closed* native closure, and the inner lambda's eval fallback
# resolved the captured name as an (undefined) global at run time.
#
# The fix has three parts, each covered below:
#   1. the analysis descends into nested lambda bodies,
#   2. tier 1 chains captures from the enclosing closure's %upvalues,
#   3. every eval-fallback boundary (emitLambdaViaEval, emitFormEval,
#      emitLetFallback) republishes the full frame — params, the rest
#      parameter, and upvalues — as globals first, and an abandoned native
#      let pops the GC roots it had pushed.
#
# Usage: bash tests/scheme/compile/native-nested-closure-1410.sh [path-to-kaappi]

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

# The native backend needs libkaappi_rt.a; build it once.
(cd "$REPO_DIR" && zig build lib > /dev/null 2>&1)

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

check_native() {
    local label="$1" expected="$2"
    local src="$DIR/${label}.scm" bin="$DIR/${label}.bin"
    (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" > /dev/null 2>&1)
    if [[ ! -x "$bin" ]]; then
        echo "FAIL: $label — native compile did not produce a binary" >&2
        exit 1
    fi
    local out
    if ! out="$("$bin")"; then
        echo "FAIL: $label — binary exited nonzero (output: '$out')" >&2
        exit 1
    fi
    if [[ "$out" != "$expected" ]]; then
        echo "FAIL: $label — expected '$expected', got '$out'" >&2
        exit 1
    fi
}

# 1. The issue's reproducer: capture reaches u only through an inner lambda.
cat > "$DIR/nested.scm" << 'SCHEME'
(define g0 (lambda (u) ((lambda (a) (lambda (c) u)) 1)))
(write ((g0 5) 0))
(newline)
SCHEME
check_native "nested" "5"

# 2. The let-wrapped variant from the issue.
cat > "$DIR/nested-let.scm" << 'SCHEME'
(define g0 (lambda (u) ((lambda (a) (let ((b 1)) (lambda (c) u))) 1)))
(write ((g0 5) 0))
(newline)
SCHEME
check_native "nested-let" "5"

# 3. Chained captures are per-instance copies: closures made by separate
#    calls must not alias (this is what distinguishes real upvalue chaining
#    from the bind-as-global eval fallback).
cat > "$DIR/retention.scm" << 'SCHEME'
(define g0 (lambda (u) ((lambda (a) (lambda (c) u)) 1)))
(define f5 (g0 5))
(define f7 (g0 7))
(write (f5 0)) (newline)
(write (f7 0)) (newline)
(define g1 (lambda (u) (lambda (a) (lambda (b) (lambda (c) u)))))
(define h3 (((g1 3) 1) 2))
(define h9 (((g1 9) 1) 2))
(write (h3 0)) (newline)
(write (h9 0)) (newline)
SCHEME
check_native "retention" "$(printf '5\n7\n3\n9')"

# 4. A variadic inner lambda can never be a native closure; its eval
#    fallback must republish the captured upvalue u.
cat > "$DIR/variadic-inner.scm" << 'SCHEME'
(define g0 (lambda (u) ((lambda (a) (lambda (c . r) u)) 1)))
(write ((g0 5) 0))
(newline)
SCHEME
check_native "variadic-inner" "5"

# 5. Capture of both a let-local and the outer param: the let's eval
#    fallback (#827) must republish the upvalue u alongside the params.
cat > "$DIR/let-mixed.scm" << 'SCHEME'
(define g0 (lambda (u) ((lambda (a) (let ((b 2)) (lambda (c) (cons u b)))) 1)))
(write ((g0 5) 0))
(newline)
SCHEME
check_native "let-mixed" "(5 . 2)"

# 6. The rest parameter must be republished at eval boundaries too.
cat > "$DIR/rest-capture.scm" << 'SCHEME'
(define f (lambda (u . xs) (lambda (c) xs)))
(write ((f 5 1 2) 0))
(newline)
SCHEME
check_native "rest-capture" "(1 2)"

# 7. emitLetFallback must republish the enclosing function's params before
#    evaluating the let form (here u is referenced by a binding init).
cat > "$DIR/let-fallback-param.scm" << 'SCHEME'
(define (f u) (let ((b u)) (lambda (c) b)))
(write ((f 5) 0))
(newline)
SCHEME
check_native "let-fallback-param" "5"

# 8. A closed lambda inside a capturing closure: its own eval fallback must
#    NOT inherit the enclosing closure's upvalue map (a closed function
#    receives null for %upvalues — loading from it would crash).
cat > "$DIR/closed-inside-closure.scm" << 'SCHEME'
(define g0 (lambda (u) ((lambda (a) (cons u ((lambda (x) (lambda (c . r) x)) 2))) 1)))
(define pair (g0 5))
(write (car pair)) (newline)
(write ((cdr pair) 0)) (newline)
SCHEME
check_native "closed-inside-closure" "$(printf '5\n2')"

# 9. An abandoned native let (body lambda exceeds the 16-param tier cap)
#    must pop the GC roots pushed for its bindings: 2000 calls would
#    overflow the 1024-slot root stack if the fallback path leaked them.
cat > "$DIR/root-balance.scm" << 'SCHEME'
(define (f u)
  (let ((b 1))
    (lambda (p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13 p14 p15 p16 p17) p1)))
(define (loop n)
  (if (> n 0)
      (begin (f n) (loop (- n 1)))
      'done))
(write (loop 2000))
(newline)
SCHEME
check_native "root-balance" "done"

# 10. A lambda in a let *binding init* previously aborted native compilation
#     outright (the emission error escaped emitLet); it must fall back.
cat > "$DIR/init-lambda.scm" << 'SCHEME'
(define glob 9)
(let ((b (lambda (c) glob))) (write (b 0)) (newline))
SCHEME
check_native "init-lambda" "9"

echo "PASS"
