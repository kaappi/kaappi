#!/bin/bash
# Regression test for #1861: the native backend compiled the procedure shorthand
# `(define (f …) …)` in a let or lambda body to a GLOBAL define, so an internal
# definition overwrote an outer one of the same name — or, when the helper
# referenced an enclosing binding, killed the binary outright:
#
#   (define (g) 'global-g)
#   (let ((a 1)) (define (g) 'inner-g) (display (g)) (newline))
#   (display (g))                  ; interpreter: global-g, binary: inner-g
#
#   (let ((a 3)) (define (h n) (* n a)) (display (h 5)))
#                                  ; interpreter: 15, binary: undefined variable 'a'
#
# #819 fixed this class for the symbol form `(define f <expr>)` and #1854 gave it
# a rooted slot, both in `emitDefine` — but `lowerDefine` turns a pair target into
# a `.passthrough` node, so the shorthand never reaches that path. It landed in
# `emitPassthrough`'s define branch, which called kaappi_define_global when the
# body compiled natively and otherwise fell through to an eval that runs in the
# global environment. Neither looked at the enclosing lexical scope.
#
# The fix declines the form whenever a lexical scope is active, so the enclosing
# scope goes to the interpreter whole — a let body abandons via emitLet (#1586's
# transactional rollback, widened to the enclosing scope by #1862), and a function
# body fails emitLambdaFunction so the whole define falls back. That is #827's
# rule: never split one lexical scope across the native/interpreted boundary.
#
# Declining also has to drop the name's entry in `native_fns`/`rebound_globals`
# BEFORE returning. Kaappi's interpreter rebinds a body define that is not at the
# head of its body as a global, and a call site that kept its direct call to the
# top-level function of the same name cannot observe that — a first cut of this
# fix returned before the invalidation and regressed exactly the three
# `non-head` cases below, which had agreed with the interpreter until then.
#
# Twelve of the fourteen cases below were verified to diverge against a pre-fix
# binary: nine against the unfixed backend, and the three `non-head` ones against
# the first cut. The other two are coverage guards that agreed all along —
# `toplevel-define-stays-native` against an over-broad decline, and the root
# balance check against a shadow stack the widened abandon leaves unbalanced.
#
# Usage: bash tests/scheme/compile/native-shorthand-internal-define-scope-1861.sh [path-to-kaappi]

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
# which never had the bug, so it is the oracle. `routing` then asserts HOW the
# form was compiled, so a case cannot pass vacuously by falling back for some
# unrelated reason:
#
#   whole-scope:<binder>  the eval'd form is the enclosing let/let*, i.e. that
#                         whole lexical scope went to the interpreter as one
#                         unit rather than the define alone.
#   whole-define:<name>   the eval'd form is the enclosing `(define (<name> …)`,
#                         i.e. the function body declined native compilation.
#   native                no eval fallback in @main at all: the form still
#                         compiles natively. The guard must decline internal
#                         defines, never top-level ones.
#
# ERE throughout, deliberately: `\?` and `\|` are GNU BRE extensions OpenBSD's
# grep rejects, where they match nothing and every routing check passes
# vacuously while the output comparisons stay clean (kaappi#1862). In ERE the
# parens of the Scheme source are what need escaping instead.
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
            # them must open with the enclosing binder, proving the decline
            # reached that scope. What gets interned is the form re-printed from
            # the datum, so a source `'x` reads back as `(quote x)` and no case
            # here yields a constant holding a quote or backslash for internString
            # to escape. `let\*?` covers let and let* in one branch.
            local binder="${routing#whole-scope:}"
            if ! grep -Eq "constant \\[.*c\"\\(let\\*? ?\\(\\(${binder} " "$DIR/$name.ll"; then
                echo "FAIL: $name — no eval of the enclosing '($binder ...)' scope; the define fell back alone" >&2
                fail=1
            fi
            ;;
        whole-define:*)
            local fname="${routing#whole-define:}"
            if ! grep -Eq "constant \\[.*c\"\\(define \\(${fname}[ )]" "$DIR/$name.ll"; then
                echo "FAIL: $name — no eval of the enclosing '(define ($fname ...)'; the body stayed native" >&2
                fail=1
            fi
            ;;
        native)
            local evals
            evals=$(sed -n '/^define i32 @main/,/^}/p' "$DIR/$name.ll" | grep -c 'kaappi_eval_cached' || true)
            if [[ "$evals" -ne 0 ]]; then
                echo "FAIL: $name — expected a natively compiled define, got $evals eval fallback(s)" >&2
                fail=1
            fi
            ;;
        *)
            echo "FAIL: $name — bad routing '$routing'" >&2
            fail=1
            ;;
    esac
}

# 1. The issue's reproducer: the internal define replaced the global instead of
#    shadowing it for the body. Pre-fix the binary printed inner-g twice.
check shadows-global-in-let \
"(define (g) 'global-g)
(let ((a 1))
  (define (g) 'inner-g)
  (display (g))
  (newline))
(display (g))
(newline)" \
whole-scope:a

# 2. With no global of that name to overwrite, the definition still escaped the
#    let: pre-fix the trailing call found it and printed inner-g where the
#    interpreter reports it unbound.
check leaks-past-the-let \
"(let ((a 1))
  (define (g) 'inner-g)
  (display (g))
  (newline))
(display (guard (e (#t 'unbound)) (g)))
(newline)" \
whole-scope:a

# 3. The loud symptom: an internal helper referencing an enclosing binding
#    compiled to a global function whose body looked `a` up as a global, so the
#    binary died with "undefined variable 'a'" on code the interpreter runs.
check helper-closes-over-binding \
"(let ((a 3))
  (define (h n) (* n a))
  (display (h 5))
  (newline))" \
whole-scope:a

# 4. Same, through a self-recursive helper: the recursive call resolves to the
#    same binding, so the failure survives however many frames deep it recurses.
check recursive-helper-closes-over-binding \
"(let ((base 10))
  (define (down k) (if (= k 0) base (down (- k 1))))
  (display (down 3))
  (newline))" \
whole-scope:base

# 5. A variadic shorthand takes a different route through emitPassthrough — the
#    #1500 closure-value gate declines it, so it reached the trailing eval rather
#    than kaappi_define_global. Both paths define a global; both must decline.
check variadic-internal-helper \
"(define (g . r) 'global-g)
(let ((a 1))
  (define (g . r) (cons a r))
  (display (g 2 3))
  (newline))
(display (g))
(newline)" \
whole-scope:a

# 6. let* reaches the same body loop from its own binding path, which roots each
#    alloca as it goes rather than all at the end.
check letstar-shadows-global \
"(define (g) 'global-g)
(let* ((a 1) (b 2))
  (define (g) 'inner-g)
  (display (list a b (g)))
  (newline))
(display (g))
(newline)" \
whole-scope:a

# 7. Nested lets: the inner let's decline has to propagate out through the outer
#    one (#1862), or the fallback eval loses `a`. Pre-fix this died with
#    "undefined variable 'a'".
check nested-let-shorthand-define \
"(define (g) 'global-g)
(let ((a 1))
  (let ((b 2))
    (define (g) (list a b))
    (display (g))
    (newline)))
(display (g))
(newline)" \
whole-scope:a

# 8. The silent one, and the reason output equality is the oracle here: a
#    shorthand define alongside a symbol-form define of a name that also exists
#    globally. The symbol form bound `z` locally (#819/#1854) while the shorthand
#    compiled to a global function whose body read the GLOBAL z — so the binary
#    printed (1 100) against the interpreter's (1 1), no crash, no diagnostic.
check mixed-symbol-and-shorthand \
"(define z 100)
(let ((a 1))
  (define z a)
  (define (g) z)
  (display (list z (g)))
  (newline))
(display z)
(newline)" \
whole-scope:a

# 9. A lambda body, not a let: `self.locals` is null there, so a guard keyed on
#    it alone would miss this — the frame is lexical because of its params. The
#    whole define declines instead.
check shadows-global-in-lambda \
"(define (g) 'global-g)
(define (outer x)
  (define (g) 'inner-g)
  (list x (g)))
(display (outer 1))
(newline)
(display (g))
(newline)" \
whole-define:outer

# 10-12. Non-head defines, which R7RS does not allow in a body and which this
#    interpreter rebinds as globals. The decline must therefore still invalidate
#    the name's direct-call binding: these three agreed with the interpreter
#    before the fix, and a first cut that returned before invalidating regressed
#    all three — the trailing (g) kept its direct call to the top-level function
#    and printed global-g where the interpreter prints inner-g.
check non-head-define-after-expression \
"(define (g) 'global-g)
(let ((a 1))
  (display a)
  (newline)
  (define (g) 'inner-g)
  (display (g))
  (newline))
(display (g))
(newline)" \
whole-scope:a

check non-head-define-in-if-branch \
"(define (g) 'global-g)
(let ((a 1))
  (if (> a 0) (define (g) 'inner-g) #f)
  (display (g))
  (newline))
(display (g))
(newline)" \
whole-scope:a

check non-head-define-spliced-by-begin \
"(define (g) 'global-g)
(let ((a 1))
  (begin (define (g) 'inner-g))
  (display (g))
  (newline))
(display (g))
(newline)" \
whole-scope:a

# 13. Coverage guard for the opposite mistake. The guard keys on "is a lexical
#     scope active", so an over-broad version would decline ordinary top-level
#     defines too and quietly send the whole program to the interpreter. This
#     one must still compile natively, with no eval fallback at all.
check toplevel-define-stays-native \
"(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(display (fib 20))
(newline)" \
native

# 14. Shadow-stack balance across the widened abandon, asserted on the emitted IR
#     rather than on output. A let that abandons from its body loop rolls back
#     every push it had already emitted (#1586); leaving one without its pop (or
#     vice versa) desynchronises the shadow stack rather than printing a wrong
#     answer — an over-pop underflows GC.root_count, an under-pop strands a slot.
#     The abandoning let contributes no pushes of its own once rolled back, so
#     the leading sibling let is what keeps the count from being vacuously zero.
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

check_root_balance shorthand-define-abandon-root-balance \
"(let ((sibling (list 1 2)))
  (display sibling)
  (newline))
(let ((outer (list 3 4)))
  (define xs (list 5 6))
  (define (h) (list outer xs))
  (display (h))
  (newline))"

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-shorthand-internal-define-scope-1861: all cases passed"
