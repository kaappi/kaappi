#!/bin/bash
# Regression test for #1862: a nested let that abandoned native compilation
# mid-emission was handed to kaappi_eval without the ENCLOSING let's bindings in
# scope, so the compiled binary diverged from the interpreter on code the
# interpreter runs fine.
#
# `emitLetFallback` republishes the native frame's names as globals via
# `bindParamsAsGlobals`, which reaches params, the rest param, and upvalues — but
# a let-local lives in an alloca that helper has no name for, so it could not
# publish one. An inner let that fell back therefore evaluated in the global
# environment with the outer binding invisible:
#
#   (let ((outer 7))
#     (let ((v0 0) ... (v32 32))     ; 33 bindings trips emitLet's ceiling
#       (display (+ outer v0))))     ; "undefined variable 'outer'", exit 1
#
# Worse when a same-named global exists: the eval found the GLOBAL instead of
# erroring, so the binary printed 999 where the interpreter printed 7, silently
# (case shadows-global below).
#
# #827 fixed this class for anything a syntactic pre-scan can see, by declining
# native compilation of the whole enclosing scope up front. The triggers here are
# only discoverable mid-emission and no up-front scan can pre-empt them: more
# than 32 bindings, more head defines than emitLet roots, an `ir.lowerSingleExpr`
# or `emitNode` failure on a binding initializer or body form (#1854 added the
# unmodelled-`define` case, which is what surfaced this).
#
# The fix gates `bindParamsAsGlobals` on `self.locals != null`: it declines
# rather than emit an eval that cannot see them, which sends the error up to the
# enclosing let's own abandon path, so the interpreter gets that whole lexical
# scope in one piece — #827's rule, applied to the mid-emission escape hatch.
# Publishing the locals instead would extend that helper's two documented
# weaknesses (it aliases across activations, and it permanently clobbers a
# same-named global) to let-locals, and could not represent a boxed one at all.
#
# 11 of the 13 cases below were verified to diverge against a pre-fix binary.
# The two `native-frame` cases are the coverage guard for the opposite mistake:
# the gate must not decline a fallback inside a plain lambda frame, where
# publishing params/rest/upvalues is exactly the correct #1410 behavior.
#
# Usage: bash tests/scheme/compile/native-nested-let-fallback-scope-1862.sh [path-to-kaappi]

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

# 33 bindings — one past emitLet's 32-binding ceiling, so the let abandons.
BIG_BINDINGS=$(awk 'BEGIN { for (i = 0; i < 33; i++) printf "(v%d %d) ", i, i }')
# 33 head defines — one past emitLet's max_head_defines, same effect.
BIG_DEFINES=$(awk 'BEGIN { for (i = 0; i < 33; i++) printf "(define d%d %d) ", i, i }')

# Compile natively, run, and require the output to match the interpreter's —
# which never had the bug, so it is the oracle. `routing` then asserts HOW the
# form was compiled, so a case cannot pass vacuously:
#
#   whole-scope:<name>  the eval'd form is the OUTER let, i.e. the enclosing
#                       scope was handed to the interpreter as one unit. A bare
#                       "did anything fall back?" count would NOT discriminate
#                       here: pre-fix @main also held exactly one eval — of the
#                       inner let alone, which is the bug.
#   native-frame        a native function still exists and holds the eval, i.e.
#                       the fallback stayed inside the natively compiled lambda.
check() {
    local name="$1" src="$2" routing="$3"

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

    if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" --emit-llvm -o "$DIR/$name.ll" "$DIR/$name.scm" > /dev/null 2>&1); then
        echo "FAIL: $name — --emit-llvm failed, so native routing went unchecked" >&2
        fail=1
        return
    fi

    case "$routing" in
        whole-scope:*)
            # The eval'd source strings are interned as private constants; one of
            # them must open with the OUTER let, proving the abandon propagated
            # out to it instead of stopping at the inner let. These sources hold
            # no quote or backslash, so internString emits them verbatim.
            local binder="${routing#whole-scope:}"
            if ! grep -q "constant \[.*c\"(let\* \?((${binder} \|constant \[.*c\"(let \?((${binder} " "$DIR/$name.ll"; then
                echo "FAIL: $name — no eval of the enclosing '($binder ...)' scope; the inner form fell back alone" >&2
                fail=1
            fi
            ;;
        native-frame)
            # The lambda must still compile natively AND still carry the eval
            # fallback inside its own body — the #1410 path the gate must leave
            # alone. Its fast entry point is the natively emitted function.
            local frame_evals
            frame_evals=$(sed -n '/^define tailcc i64 @r[0-9]*\.fast/,/^}/p' "$DIR/$name.ll" |
                grep -c 'kaappi_eval_cached' || true)
            if [[ "$frame_evals" -eq 0 ]]; then
                echo "FAIL: $name — no native frame carrying the eval fallback; the lambda declined too" >&2
                fail=1
            fi
            ;;
        *)
            echo "FAIL: $name — bad routing '$routing'" >&2
            fail=1
            ;;
    esac
}

# 1. Issue reproducer: the inner let trips the 32-binding ceiling and abandons
#    mid-emission, so pre-fix the binary died with "undefined variable 'outer'".
check over-32-bindings \
"(let ((outer 7))
  (let ($BIG_BINDINGS)
    (display (+ outer v0))
    (newline)))" \
whole-scope:outer

# 2. let* abandons on the same ceiling from its own binding loop, which roots
#    each alloca as it goes rather than all at the end.
check over-32-bindings-letstar \
"(let ((outer 7))
  (let* ($BIG_BINDINGS)
    (display (+ outer v0))
    (newline)))" \
whole-scope:outer

# 3. The silent case, and the worst symptom: with a same-named global in scope
#    the eval resolved to it instead of erroring, so the binary printed 999
#    where the interpreter printed 7 — no crash, no diagnostic. The trailing
#    read pins that the let's binding never escapes to the global either.
check shadows-global \
"(define outer 999)
(let ((outer 7))
  (let ($BIG_BINDINGS)
    (display (+ outer v0))
    (newline)))
(display outer)
(newline)" \
whole-scope:outer

# 4. A set! of the outer binding from the abandoned inner let: the mutation has
#    to land on the outer let's own location, which only holds if the whole
#    scope is evaluated together.
check set-through-outer-binding \
"(let ((acc 0))
  (let ($BIG_BINDINGS)
    (set! acc (+ acc v32)))
  (display acc)
  (newline))" \
whole-scope:acc

# 5. More head defines than emitLet roots (#1854's max_head_defines) — a second
#    mid-emission ceiling reaching the same escape hatch.
check over-32-head-defines \
"(let ((outer 7))
  (let ((a 1))
    $BIG_DEFINES
    (display (list outer a d0 d32))
    (newline)))" \
whole-scope:outer

# 6. #1854's trigger: a define inside an `if` is one the scope cannot root with a
#    statically matched pop, so emitDefine declines and the inner let abandons
#    from its body loop — an emitNode failure, not a ceiling.
check unmodelled-define-in-if \
"(let ((outer 7))
  (let ((a 1))
    (if (> a 0) (define x (list 1 2)) #f)
    (display (list outer x))
    (newline)))" \
whole-scope:outer

# 7. A define after a non-define body form is outside the modelled head run,
#    reaching the same emitDefine decline from a different shape.
check define-after-expression \
"(let ((outer 7))
  (let ((a 1))
    (define xs (list 1))
    (display a)
    (newline)
    (define ys (list 2))
    (display (list outer xs ys))
    (newline)))" \
whole-scope:outer

# 8. R7RS lets `begin` splice definitions at the head of a body; the head scan
#    does not model that shape, so the inner let abandons there too.
check begin-spliced-define \
"(let ((outer 7))
  (let ((a 1))
    (begin (define x (list 1 2)))
    (display (list outer x))
    (newline)))" \
whole-scope:outer

# 9. #1497's up-front trigger, reached from a nested position: the inner let's
#    body captures its own binding in an unmutated lambda, so the inner let falls
#    back before emitting anything. The outer let cannot see this in its own
#    capture analysis — the lambda references `a`, not `outer` — so it proceeds
#    natively and the inner fallback is what has to decline.
check captured-unmutated-inner-binding \
"(let ((outer 7))
  (let ((a 1))
    (display (list outer ((lambda () a))))
    (newline)))" \
whole-scope:outer

# 10. Two enclosing levels: the decline has to propagate through the middle let
#     (which abandons and declines in turn) out to the outermost one, where
#     locals are finally absent and the eval is correct.
check triple-nested-lets \
"(let ((o1 1))
  (let ((o2 2))
    (let ($BIG_BINDINGS)
      (display (list o1 o2 v0))
      (newline))))" \
whole-scope:o1

# 11. Coverage guard: a let that abandons directly inside a lambda frame, with no
#     enclosing let. Params ARE publishable, so this must still compile the
#     lambda natively and fall back only for the let (#1410). Verified against a
#     pre-fix binary as the one case here whose emitted IR is unchanged — an
#     over-broad gate (declining on params/upvalues too) would regress it.
check let-fallback-in-lambda-frame \
"(define (f p q)
  (let ($BIG_BINDINGS)
    (list p q v0 v32)))
(display (f 1 2))
(newline)" \
native-frame

# 12. The two rules together: inside a lambda, an inner let abandons and declines
#     to the enclosing let, which then falls back with only the lambda's params
#     in scope — publishable, so the lambda itself stays native.
check nested-let-fallback-in-lambda-frame \
"(define (f p)
  (let ((o 7))
    (let ($BIG_BINDINGS)
      (list p o v0))))
(display (f 5))
(newline)" \
native-frame

# 13. Shadow-stack balance across the widened abandon, asserted on the emitted IR
#     rather than on output. Declining now unwinds an extra level: the outer let
#     had already emitted and rooted its own binding, and published it into the
#     pop-before-tail accounting (#1585), before the inner let's decline made it
#     abandon and roll all of that back. Leaving a push without its pop (or vice
#     versa) desynchronises the shadow stack rather than printing a wrong answer —
#     an over-pop underflows GC.root_count, an under-pop just strands a slot.
#
#     Since every let in the abandoning chain now falls back, its own pushes are
#     truncated away entirely, so the count needs an independent baseline to not
#     be vacuous: the leading sibling let stays native and contributes the pushes.
#     In a straight-line @main every push and pop is textually reached exactly
#     once, so summing them over the function is exact.
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

check_root_balance abandon-rollback-root-balance \
"(let ((sibling (list 1 2)))
  (display sibling)
  (newline))
(let ((outer (list 3 4)))
  (let ($BIG_BINDINGS)
    (display (list outer v0))
    (newline)))"

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-nested-let-fallback-scope-1862: all cases passed"
