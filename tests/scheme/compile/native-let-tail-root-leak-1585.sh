#!/bin/bash
# Regression test for #1585: the native `let`/`let*` emitter leaked GC
# shadow-stack roots on tail calls through a let body.
#
# An unboxed let lowers its last body expr in tail position, but the tail-call
# emitters used to pop only the frame-entry roots before `ret` — never the let's
# binding roots. The trailing `kaappi_gc_pop_roots` landed in the dead orphan
# block after the `ret`, so every execution leaked one shadow-stack slot per
# binding. `GC.pushRoot` grows the root buffer to MAX_ROOT_CAPACITY (65536) and
# then panics ("GC root stack overflow"), so any loop that drives such a pattern
# past ~65k iterations crashed a natively-compiled binary while the interpreter
# ran fine.
#
# The self-tail-call path (a loop through a let) leaked the same way: the
# branch-back to the loop header re-entered the let and re-pushed its roots
# without popping the previous iteration's.
#
# Native codegen is NOT covered by -Dgc-stress (a VM/interpreter build option),
# so this compile-and-run test is what guards the regression. Each loop below
# runs well past MAX_ROOT_CAPACITY, so a leak of even one root per iteration
# overflows the buffer and aborts.
#
# Usage: bash tests/scheme/compile/native-let-tail-root-leak-1585.sh [path-to-kaappi]

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

# Compile natively, run, and compare output. Also assert a native user function
# was actually emitted, so a silent fallback to the interpreter (which never had
# the bug) can never make this test pass vacuously.
check() {
    local name="$1" src="$2" expect_out="$3"

    printf '%s' "$src" > "$DIR/$name.scm"

    if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$DIR/$name.scm" -o "$DIR/$name" > /dev/null 2>&1); then
        echo "FAIL: $name — native compilation failed" >&2
        fail=1
        return
    fi

    local out status
    set +e
    out=$("$DIR/$name" 2>&1)
    status=$?
    set -e
    if [[ $status -ne 0 ]]; then
        echo "FAIL: $name — binary aborted (exit $status): $out" >&2
        fail=1
        return
    fi
    if [[ "$out" != "$expect_out" ]]; then
        echo "FAIL: $name — expected '$expect_out', got '$out'" >&2
        fail=1
        return
    fi

    # Confirm this exercised native codegen rather than a fallback.
    (cd "$REPO_DIR" && "$KAAPPI_ABS" --emit-llvm -o "$DIR/$name.ll" "$DIR/$name.scm" > /dev/null 2>&1) || true
    if ! grep -qE '^define ([a-z]+ )*i64 @(lambda_|r[0-9])' "$DIR/$name.ll" 2>/dev/null; then
        echo "FAIL: $name — expected a native fn definition (test would be vacuous otherwise)" >&2
        fail=1
    fi
}

# 1. Issue reproducer: an ordinary tail call in a non-boxed let body, driven
#    100000 times (> MAX_ROOT_CAPACITY). Before the fix this panicked with
#    "GC root stack overflow"; the interpreter printed "done".
check tail-through-let \
'(define (g x) x)
(define (f n) (let ((a (+ n 1))) (g a)))
(define (drive i)
  (if (= i 0) (quote done) (begin (f i) (drive (- i 1)))))
(display (drive 100000)) (newline)' \
'done'

# 2. Self-tail loop through a let: the branch-back path (emitSelfTailCall) must
#    pop the binding roots too, or every iteration leaks one.
check self-tail-loop-let \
'(define (loop i acc)
  (let ((j (+ i 1)))
    (if (= i 300000) acc (loop j (+ acc 1)))))
(display (loop 0 0)) (newline)' \
'300000'

# 3. Self-tail loop through a let* (two bindings — leak of two roots/iteration
#    without the fix).
check self-tail-loop-letstar \
'(define (loop i acc)
  (let* ((j (+ i 1)) (k (+ acc 1)))
    (if (= i 300000) acc (loop j k))))
(display (loop 0 0)) (newline)' \
'300000'

# 4. Two nested lets, both in tail position: a tail call through them must pop
#    BOTH binding roots. Driven past the cap via a non-tail outer driver.
check nested-let-tail \
'(define (g a b) (+ a b))
(define (f n) (let ((a (+ n 1))) (let ((b (+ a 1))) (g a b))))
(define (drive i)
  (if (= i 0) (quote done) (begin (f i) (drive (- i 1)))))
(display (drive 100000)) (newline)' \
'done'

# 5. Variadic self-tail loop through a let: the frame-entry rest-list root lives
#    before the loop header and must persist across iterations, while the let
#    binding root inside the body must be popped on every branch-back.
check variadic-self-tail-let \
'(define (loop i . rest)
  (let ((j (+ i 1)))
    (if (= i 300000) (length rest) (loop j (quote x)))))
(display (loop 0)) (newline)' \
'1'

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-let-tail-root-leak-1585: all cases passed"
