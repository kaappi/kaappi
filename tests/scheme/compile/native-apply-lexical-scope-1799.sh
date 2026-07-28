#!/bin/bash
# Regression test for #1799 (LLVM native backend): `apply` over any LOCAL
# binding miscompiled. `(define (s xs) (apply + xs))` compiled cleanly and then
# died at run time with "undefined variable 'xs'. Did you mean 's'?".
#
# `apply` lowers to an ir `.passthrough` node, which emitPassthrough hands to
# the interpreter as source text — and kaappi_eval runs in the GLOBAL
# environment. Every gate that exists to stop a lexical scope being split
# across the native/interpreted boundary (#827) consults
# ir.eval_fallback_form_names, and `apply` was missing from it: the
# `.passthrough` node carries `.capability = .native` in llvm_node_table (right
# for its `(define (f ...) ...)` shape, wrong for the rest) and nothing else
# contributed the keyword. So the enclosing frame compiled natively — `apply`
# is an isKnownGlobal, so free-variable analysis passed it too — and the
# fallback eval looked for the frame's parameters among the globals.
#
# The same path affected call/cc, call-with-values and eval. The fix derives
# those names from ir.other_special_forms, so the enclosing lambda frame or let
# declines native compilation and the interpreter keeps the bindings.
#
# Every case below asserts the compiled binary agrees with the interpreter, so
# the test stays honest if the backend ever learns to lower `apply` natively.
#
# Usage: bash tests/scheme/compile/native-apply-lexical-scope-1799.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
KAAPPI="${1:-$REPO_DIR/zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

FAILED=0

# Run one program both ways and require identical output. The interpreter is
# the oracle — it was always correct here — so `expected` documents intent
# without being what the comparison actually rests on.
check_both() {
    local label="$1" expected="$2"
    local src="$DIR/${label}.scm" bin="$DIR/${label}.bin"

    local interp_out interp_status=0
    interp_out="$(cd "$REPO_DIR" && "$KAAPPI_ABS" "$src" 2>&1)" || interp_status=$?
    if [[ $interp_status -ne 0 ]]; then
        echo "FAIL: $label — interpreter exited $interp_status (output: '$interp_out')" >&2
        FAILED=1
        return
    fi
    if [[ "$interp_out" != "$expected" ]]; then
        echo "FAIL: $label — interpreter expected '$expected', got '$interp_out'" >&2
        FAILED=1
        return
    fi

    # Both halves matter, and they fail differently: a nonzero exit means the
    # compiler itself rejected the program (keep its diagnostics), while a zero
    # exit with no executable means it claimed success and produced nothing.
    # Checking only for the file would let a failing compile that still left an
    # executable behind pass as a green run.
    local compile_out compile_status=0
    compile_out="$(cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" 2>&1)" || compile_status=$?
    if [[ $compile_status -ne 0 ]]; then
        echo "FAIL: $label — kaappi compile exited $compile_status: $compile_out" >&2
        FAILED=1
        return
    fi
    if [[ ! -x "$bin" ]]; then
        echo "FAIL: $label — kaappi compile succeeded but produced no binary" >&2
        FAILED=1
        return
    fi

    local native_out native_status=0
    native_out="$("$bin" 2>&1)" || native_status=$?
    if [[ $native_status -ne 0 ]]; then
        echo "FAIL: $label — compiled binary exited $native_status (output: '$native_out')" >&2
        FAILED=1
        return
    fi
    if [[ "$native_out" != "$interp_out" ]]; then
        echo "FAIL: $label — native '$native_out' != interpreted '$interp_out'" >&2
        FAILED=1
    fi
}

# 1. The issue's reproducer: apply over a procedure PARAMETER.
cat > "$DIR/param.scm" << 'SCHEME'
(define (s xs) (apply + xs))
(display (s (list 1 2 3)))
(newline)
SCHEME
check_both "param" "6"

# 2. A LET-bound name — so this is locals in general, not just parameters.
cat > "$DIR/let-bound.scm" << 'SCHEME'
(define (s) (let ((xs (list 1 2 3))) (apply + xs)))
(display (s))
(newline)
SCHEME
check_both "let-bound" "6"

# 3. A bare let at top level, with no enclosing define to decline first: this
#    is emitLet's own gate rather than tryCompileDefineFunction's.
cat > "$DIR/bare-let.scm" << 'SCHEME'
(let ((xs (list 1 2 3))) (display (apply + xs)) (newline))
SCHEME
check_both "bare-let" "6"

# 4. A COMPUTED OPERATOR: the operator position is as lexical as the list, and
#    was named by the same error ("undefined variable 'f'").
cat > "$DIR/computed-operator.scm" << 'SCHEME'
(define (s f xs) (apply f xs))
(display (s + (list 1 2 3)))
(newline)
(display (s max (list 4 9 2)))
(newline)
SCHEME
check_both "computed-operator" "$(printf '6\n9')"

# 5. Fixed leading arguments spliced ahead of the list, and a rest parameter as
#    the list — both mix native frame state into the applied call.
cat > "$DIR/mixed-args.scm" << 'SCHEME'
(define (s a b xs) (apply + a b xs))
(display (s 1 2 (list 3 4)))
(newline)
(define (v . xs) (apply * xs))
(display (v 2 3 4))
(newline)
SCHEME
check_both "mixed-args" "$(printf '10\n24')"

# 6. Recursion: the interpreted frame must be re-entrant. A fix that instead
#    republished the parameters as globals (bindParamsAsGlobals, #1410) would
#    alias every activation here.
cat > "$DIR/recursive.scm" << 'SCHEME'
(define (down n xs) (if (= n 0) (apply + xs) (down (- n 1) (cons n xs))))
(display (down 3 (list 10)))
(newline)
SCHEME
check_both "recursive" "16"

# 7. A same-named global must survive the call: publishing a parameter as a
#    global would leave x = 1 afterwards.
cat > "$DIR/global-untouched.scm" << 'SCHEME'
(define x 100)
(define (s x) (apply + (list x)))
(display (s 1))
(newline)
(display x)
(newline)
SCHEME
check_both "global-untouched" "$(printf '1\n100')"

# 8. Inside the natively lowered forms (#1496) and inside a closure, where the
#    binding reaches the apply through an upvalue rather than a parameter.
cat > "$DIR/nested-forms.scm" << 'SCHEME'
(define (in-cond lst) (cond ((null? lst) 0) (else (apply + lst))))
(display (in-cond (list 1 2 3)))
(newline)
(define (closure xs) (lambda () (apply + xs)))
(display ((closure (list 4 5))))
(newline)
SCHEME
check_both "nested-forms" "$(printf '6\n9')"

# 9. The sibling passthrough forms that took the same broken path.
cat > "$DIR/siblings.scm" << 'SCHEME'
(define (with-values x) (call-with-values (lambda () (values x 2)) +))
(display (with-values 1))
(newline)
(define (with-cc x) (call/cc (lambda (k) (+ x 1))))
(display (with-cc 41))
(newline)
SCHEME
check_both "siblings" "$(printf '3\n42')"

# 10. The program shape the bug was found on: summary statistics over a list
#     argument, which is where `(apply + xs)` is idiomatic.
cat > "$DIR/stats.scm" << 'SCHEME'
(define (sum xs) (apply + xs))
(define (mean xs) (/ (sum xs) (length xs)))
(define (spread xs) (- (apply max xs) (apply min xs)))
(define data (list 2 4 6 8))
(display (sum data)) (newline)
(display (mean data)) (newline)
(display (spread data)) (newline)
SCHEME
check_both "stats" "$(printf '20\n5\n6')"

if [[ $FAILED -ne 0 ]]; then
    exit 1
fi

echo "PASS"
