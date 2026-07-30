#!/bin/bash
# Regression test for #1854: the native backend's internal-define path minted an
# unrooted alloca for the binding, so a collection triggered later in the let
# body freed the value out from under it.
#
# emitLet roots every let/let* binding alloca on the shadow stack, but the
# internal-define branch in emitDefine (self.locals != null) created its slot,
# stored the initializer, and never pushed it — so the slot held the ONLY
# reference to a freshly allocated value across every later allocation in the
# body. The value was collected and its memory recycled into whatever the body
# allocated next, silently, with no crash:
#
#   (let ((a 1))
#     (define xs (list 11 22 33))
#     (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
#     (car xs))          ; => 198492, not 11
#
# Every case below printed recycled garbage — `(0.0 . 0.0)`, a loop counter's
# list — from the pre-fix binary. The fix mints and roots these slots in emitLet
# alongside the bindings, which is also what keeps the push count static: a
# define nested inside an `if` would push on one path only while the scope's pop
# count is fixed, so emitDefine declines those and the whole form goes to the
# interpreter (cases 6 and 7 pin that down).
#
# Native codegen is NOT covered by -Dgc-stress (a VM/interpreter build option),
# so this compile-and-run test is what guards the regression. Each case drives
# enough allocation to force several collections while the binding is live.
#
# Usage: bash tests/scheme/compile/native-let-internal-define-root-1854.sh [path-to-kaappi]

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

# `kaappi compile` needs the native runtime archive. The helper freshens it with
# zig when a toolchain is present and otherwise accepts a prebuilt one, so a box
# running cross-compiled binaries still exercises the compile+link path — and it
# knows the archive's per-platform name, which this script must not spell itself.
ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail=0

# Compile natively, run, and require the output to match the interpreter's —
# which never had the bug, so it is the oracle. `native_expected` says whether
# the let must still compile natively ("native") or is expected to route to the
# interpreter ("fallback"); either way the answer must match, and asserting which
# one happened keeps a silent fallback from making a "native" case pass
# vacuously.
check() {
    local name="$1" src="$2" native_expected="$3"

    printf '%s' "$src" > "$DIR/$name.scm"

    local want
    if ! want=$(cd "$REPO_DIR" && "$KAAPPI_ABS" "$DIR/$name.scm" 2>&1); then
        echo "FAIL: $name — interpreter run failed: $want" >&2
        fail=1
        return
    fi

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
    if [[ "$out" != "$want" ]]; then
        echo "FAIL: $name — native '$out' != interpreter '$want'" >&2
        fail=1
        return
    fi

    # Whether the top-level body kept the let native or handed it to the
    # interpreter: a natively emitted let leaves no kaappi_eval_cached in @main,
    # while emitLetFallback is exactly one such call.
    if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" --emit-llvm -o "$DIR/$name.ll" "$DIR/$name.scm" > /dev/null 2>&1); then
        echo "FAIL: $name — --emit-llvm failed, so native routing went unchecked" >&2
        fail=1
        return
    fi
    local evals
    evals=$(sed -n '/^define i32 @main/,/^}/p' "$DIR/$name.ll" | grep -c 'kaappi_eval_cached' || true)
    case "$native_expected" in
        native)
            if [[ "$evals" -ne 0 ]]; then
                echo "FAIL: $name — expected a natively emitted let, got $evals eval fallback(s) (test would be vacuous)" >&2
                fail=1
            fi
            ;;
        fallback)
            if [[ "$evals" -eq 0 ]]; then
                echo "FAIL: $name — expected the let to route to the interpreter, but none did" >&2
                fail=1
            fi
            ;;
        *)
            echo "FAIL: $name — bad native_expected '$native_expected'" >&2
            fail=1
            ;;
    esac
}

# 1. Issue reproducer: one internal define holding a fresh list across a loop
#    that allocates hard. Pre-fix this printed the recycled contents of xs's
#    freed memory (e.g. 198492 / (198472)).
check internal-define-survives-gc \
'(let ((a 1))
  (define xs (list 11 22 33))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display (car xs)) (newline)
  (display xs) (newline))' \
native

# 2. Several defines alongside a heap-valued let binding: every slot must be
#    rooted, not just the binding's.
check multiple-defines \
'(let ((a (list 1 2)))
  (define xs (list 11 22 33))
  (define ys (list 44 55))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display (list a xs ys)) (newline))' \
native

# 3. Nested lets, each with its own define: the inner let owns its slot and pops
#    exactly its own roots, leaving the outer let's define still rooted after it
#    returns.
check nested-let-defines \
'(let ((a (list 1 2)))
  (define xs (list 11 22))
  (let ((b (list 3 4)))
    (define ys (list 44 55))
    (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
    (display (list a xs b ys)) (newline))
  (display xs) (newline))' \
native

# 4. let* — its bindings are rooted one at a time as they are emitted, so the
#    define slots have to be counted into the same pop.
check letstar-define \
'(let* ((a (list 1 2)) (b (cons 0 a)))
  (define xs (list 11 22 33))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display (list a b xs)) (newline))' \
native

# 5. `(let () ...)`: zero bindings, so the define slots are the ONLY roots this
#    scope pushes — the pop count comes entirely from them.
check empty-bindings-define \
'(let ()
  (define xs (list 11 22 33))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display xs) (newline))' \
native

# 6. A define that is NOT at the head of the body (inside an `if`) is one the
#    scope cannot root with a statically matched pop, so the whole let goes to
#    the interpreter — which binds it correctly. R7RS puts internal definitions
#    at the head of a body, so this shape is degenerate; it must still agree
#    with the interpreter rather than compile to something unrooted.
check non-head-define-falls-back \
'(let ((a 1))
  (if (> a 0) (define x (list 1 2)) #f)
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display x) (newline))' \
fallback

# 7. The head run ends at the first non-define form: a define after one is
#    outside the modelled set, so this let falls back too.
check define-after-expression-falls-back \
'(let ((a 1))
  (define xs (list 11 22))
  (display a) (newline)
  (define ys (list 33 44))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display (list xs ys)) (newline))' \
fallback

# 8. #819 still holds: an internal define shadows a same-named global for the
#    rest of the body instead of overwriting it, and is still emitted natively.
check shadows-global \
'(define z 100)
(let ((x (list 1)))
  (define z x)
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display z) (newline))
(display z) (newline)' \
native

# 9. A redefinition of the same name in one body reuses that name's single
#    rooted slot — the second define must not strand a root or lose the value.
check redefined-name \
'(let ((a 1))
  (define xs (list 1))
  (define xs (list 11 22 33))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display xs) (newline))' \
native

# 10. letrec* ordering: a later define's initializer referencing an earlier one
#     must see the earlier value, and the referenced list must survive the loop.
check define-references-earlier-define \
'(let ((a 1))
  (define p (list 1 2))
  (define q (cons 0 p))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display (list p q)) (newline))' \
native

# 11. A define whose value is a procedure. The unrooted slot held the closure,
#     so pre-fix this did not merely print garbage — it died with
#     "runtime error in call: not a procedure (NotAProcedure)" once the closure
#     was collected and the slot was calling freed memory.
check define-holding-a-procedure \
'(let ((a (list 1)))
  (define f (lambda (y) (+ y 1)))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i))
  (display (list a (f 1))) (newline))' \
native

# 12. R7RS lets `begin` splice definitions at the head of a body. The head scan
#     does not model that shape, so such a let goes to the interpreter — correct,
#     just not native. Pinned so a future change that starts compiling it
#     natively has to root those slots deliberately rather than by accident.
check begin-spliced-define-falls-back \
'(let ((a 1))
  (begin (define x (list 1 2)))
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))
  (display x) (newline))' \
fallback

# 13. Shadow-stack balance, asserted on the emitted IR rather than on output.
#     A define slot now contributes a push that the scope's single trailing
#     `kaappi_gc_pop_roots <n>` has to account for, so pushing without counting
#     (or counting without pushing) desynchronises the two. Neither shows up as a
#     wrong answer: an over-pop underflows GC.root_count (a ReleaseSafe panic,
#     but only if the program happens to drive it below zero) and an under-pop
#     just strands a slot. In a straight-line body every push and pop is
#     textually reached exactly once, so summing them over @main is exact.
#     Unlike the cases above this one balanced before the fix too — nothing was
#     pushed and nothing counted; it guards the accounting from here on.
check_root_balance() {
    local name="$1" src="$2"

    printf '%s' "$src" > "$DIR/$name.scm"
    if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" --emit-llvm -o "$DIR/$name.ll" "$DIR/$name.scm" > /dev/null 2>&1); then
        echo "FAIL: $name — --emit-llvm failed" >&2
        fail=1
        return
    fi

    local main_ir pushes pops
    main_ir=$(sed -n '/^define i32 @main/,/^}/p' "$DIR/$name.ll")
    pushes=$(printf '%s\n' "$main_ir" | grep -c 'call void @kaappi_gc_push_root' || true)
    pops=$(printf '%s\n' "$main_ir" |
        sed -n 's/.*call void @kaappi_gc_pop_roots(i64 \([0-9]*\)).*/\1/p' |
        awk '{n += $1} END {print n + 0}')

    if [[ "$pushes" -eq 0 ]]; then
        echo "FAIL: $name — no root pushes in @main (test would be vacuous)" >&2
        fail=1
        return
    fi
    if [[ "$pushes" -ne "$pops" ]]; then
        echo "FAIL: $name — @main pushes $pushes roots but pops $pops" >&2
        fail=1
    fi
}

check_root_balance define-slot-root-balance \
'(let ((a (list 1 2)))
  (define xs (list 11 22 33))
  (define ys (list 44 55))
  (let ((b (list 3 4)))
    (define zs (list 66))
    (display (list a xs ys b zs)) (newline)))'

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-let-internal-define-root-1854: all cases passed"
