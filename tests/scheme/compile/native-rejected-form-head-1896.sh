#!/bin/bash
# Regression test for #1896 (LLVM native backend): the cond/case/do
# emittability gate was a hand-maintained keyword array parallel to the
# comptime-derived `ir.eval_fallback_form_names`, and it had drifted —
# `define-property` was in the derived set and absent from the array.
#
# `define-property` (SRFI 213) is a COMPILE-time form: compileDefineProperty
# evaluates its expression and stores the property while the enclosing form is
# being compiled, before any of that form runs. The interpreter compiles a
# top-level `cond` whole, so a `define-property` in a clause body takes effect
# before the clause body executes.
#
# With the keyword missing from the gate, the native backend emitted the cond
# natively and left only the `define-property` behind as a run-time
# `kaappi_eval` — so the compile-time effect happened in sequence with the rest
# of the clause body instead of ahead of it. `case` diverged identically.
# `do` failed harder: emitDo installs loop-variable locals before reaching the
# body, and emitFormEval refuses to eval inside a lexical scope, so a program
# the interpreter runs fine could not be compiled at all (KP9001).
#
# The gate is now derived from the comptime set (llvm_emit_forms.rejected_form_heads),
# so these three forms fall back whole and agree with the interpreter again.
#
# The `-nowrap` cases are the discriminating control: the same three top-level
# forms NOT wrapped in cond/case/do agreed between the tiers before the fix and
# still do. That is what pins the divergence to this gate rather than to
# `define-property`'s phase behaviour in general.
#
# Usage: bash tests/scheme/compile/native-rejected-form-head-1896.sh [path-to-kaappi]

set -euo pipefail

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
# the oracle; `expected` documents intent without being what the comparison
# rests on.
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

    # A nonzero exit means the compiler rejected the program (this is the `do`
    # case's pre-fix failure mode, so keep its diagnostics); a zero exit with no
    # executable means it claimed success and produced nothing.
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

# The probe prints "P" when the property expression is evaluated and "B"/"C"
# around it when the clause body runs. Compiling the whole form first means P
# comes out ahead of both: "PBC". Deferring only the define-property to run
# time gives the sequential "BPC" — the pre-fix native answer.

# 1. cond — the shape the issue was filed on.
cat > "$DIR/cond.scm" << 'SCHEME'
(define x 'ident)
(define k 'key)
(cond (#t (display "B")
          (define-property x k (begin (display "P") 1))
          (display "C")))
(newline)
SCHEME
check_both "cond" "PBC"

# 2. case — the same gate, reached through caseArgsEmittable.
cat > "$DIR/case.scm" << 'SCHEME'
(define x 'ident)
(define k 'key)
(case 1
  ((1) (display "B")
       (define-property x k (begin (display "P") 1))
       (display "C")))
(newline)
SCHEME
check_both "case" "PBC"

# 3. do — pre-fix this did not merely diverge, it failed to compile at all
#    with "error[KP9001]: LLVM emit failed: internal error".
cat > "$DIR/do.scm" << 'SCHEME'
(define x 'ident)
(define k 'key)
(do ((i 0 (+ i 1)))
    ((= i 1))
  (display "B")
  (define-property x k (begin (display "P") 1))
  (display "C"))
(newline)
SCHEME
check_both "do" "PBC"

# 4. Discriminating control: the identical forms with no cond/case/do wrapper.
#    Each top-level form is compiled and run before the next is compiled, so
#    the property expression fires between B and C in BOTH tiers — "BPC". This
#    agreed before the fix too; it is what localises the bug to the gate.
cat > "$DIR/nowrap.scm" << 'SCHEME'
(define x 'ident)
(define k 'key)
(display "B")
(define-property x k (begin (display "P") 1))
(display "C")
(newline)
SCHEME
check_both "nowrap" "BPC"

# 5. Second control: a form ALREADY in the rejected list (`delay`) in the same
#    clause position. This always fell back correctly, and must keep doing so —
#    a derivation that dropped names would show up here.
cat > "$DIR/rejected-sibling.scm" << 'SCHEME'
(cond (#t (display "B") (delay (display "P")) (display "C")))
(newline)
SCHEME
check_both "rejected-sibling" "BC"

# 6. Third control: a cond with none of this in it still lowers natively and
#    still agrees. Guards against "fix by rejecting everything".
cat > "$DIR/plain-cond.scm" << 'SCHEME'
(define (f n) (cond ((> n 0) (* n 2)) (else 0)))
(display (f 21))
(newline)
(display (f -1))
(newline)
SCHEME
check_both "plain-cond" "$(printf '42\n0')"

if [[ $FAILED -ne 0 ]]; then
    exit 1
fi

echo "PASS"
