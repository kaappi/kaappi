#!/bin/bash
# Regression test for #2119: re-invoking a TOP-LEVEL continuation from inside a
# bootstrapped higher-order callback (for-each / map) must resume the captured
# top-level form's *tail* natively, exactly as the interpreter does.
#
# The bug: a top-level form like
#
#     (set! result (+ 100 (call-with-current-continuation (lambda (c) (set! k c) 0))))
#
# lowered natively split the form — the `set!` (and the `(+ 100 …)` around the
# call/cc) became straight-line native code, and only the `call/cc`
# subexpression was eval-fallbacked to the VM. The continuation captured inside
# that subexpression therefore spanned *only* the subexpression, not the
# enclosing `set!`. Invoking it later (from a for-each callback in a subsequent
# form) re-ran just the subexpression and delivered its value to a native
# context that had already completed: the `set!` never re-fired, so `result`
# silently kept its pre-capture value (native printed 100 where the interpreter
# prints 142) and exited 0 with no diagnostic.
#
# The fix (src/native_compiler.zig) forces any top-level form whose own
# evaluation may capture a full continuation onto whole-form VM evaluation, so
# the captured continuation spans the entire form and a later resume re-runs its
# tail. This test runs the issue's exact repro AND its discriminating control
# through `kaappi compile`, with the interpreter as oracle — a `.scm` file that
# only ever runs under the interpreter proves nothing about the native tier
# (kaappi#2117/#2118).
#
# Usage: bash tests/scheme/compile/native-toplevel-continuation-resume-2119.sh [path-to-kaappi]

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

ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# Compile `src`, run both tiers, and assert they agree. `expected` documents
# intent and still catches a value both tiers get wrong. See the "interpreter as
# the native tier's oracle" block in ../shell-common.sh.
check_both() {
    local src="$1" expected="$2" label="$3"
    local bin="$DIR/${label}.bin"

    local interp_out interp_status=0
    interp_out="$(interp_stdout "$KAAPPI_ABS" "$REPO_DIR" "$src")" || interp_status=$?
    if [[ $interp_status -ne 0 ]]; then
        echo "FAIL: $label — interpreter exited $interp_status (output: '$interp_out')" >&2
        exit 1
    fi
    if [[ "$interp_out" != "$expected" ]]; then
        echo "FAIL: $label — interpreter expected '$expected', got '$interp_out'" >&2
        exit 1
    fi

    (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" > /dev/null 2>&1)
    if [[ ! -x "$bin" ]]; then
        echo "FAIL: $label — native compile did not produce a binary" >&2
        exit 1
    fi
    local out status=0
    out="$("$bin" 2> /dev/null)" || status=$?
    assert_tiers_agree "$label" "$interp_out" "$interp_status" "$out" "$status" || exit 1
}

# --- Case 1: the issue's exact repro (was native 100, interpreter 142) ---
cat > "$DIR/repro.scm" << 'SCHEME'
(define k1 #f)
(define result 0)
(set! result (+ 100 (call-with-current-continuation (lambda (c) (set! k1 c) 0))))
(define (go) (for-each (lambda (x) (when (= x 2) (k1 42))) (list 1 2 3)) (display "reached\n"))
(go)
(display result) (newline)
SCHEME

check_both "$DIR/repro.scm" "142" "toplevel-set-resume"

# --- Case 2: capture in a top-level (define value …), resumed through map ---
cat > "$DIR/define-value.scm" << 'SCHEME'
(define k #f)
(define captured (+ 200 (call-with-current-continuation (lambda (c) (set! k c) 0))))
(define (go) (map (lambda (x) (when (= x 3) (k 50))) (list 1 2 3)) (display "reached\n"))
(go)
(display captured) (newline)
SCHEME

check_both "$DIR/define-value.scm" "250" "toplevel-define-resume"

# --- Case 3: the discriminating control — an escape used WITHIN its dynamic
# extent still works on both tiers (this path was never broken). ---
cat > "$DIR/control.scm" << 'SCHEME'
(define (esc)
  (call-with-current-continuation
    (lambda (k) (for-each (lambda (x) (if (= x 2) (k 42))) (list 1 2 3)) 100)))
(display (esc)) (newline)
SCHEME

check_both "$DIR/control.scm" "42" "escape-within-extent"

# --- Case 4: the issue's measured blast radius — the 5-assertion smoke test,
# which mixes for-each, map, and dynamic-wind continuation invocations. ---
check_both "tests/scheme/smoke/call-global-continuation.scm" "5 passed, 0 failed" "call-global-continuation-smoke"

echo "PASS"
