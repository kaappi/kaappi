#!/bin/bash
# Regression test for the #2404/#2401-review conservative fallback: when a
# top-level form's structure-only set! scan truncates (depth cap, or the
# spine cap on a datum-label cycle), the native tier must not keep folding
# later forms against a possibly-stale primitive table.
#
# The hole this pins (second CodeRabbit review of #2401): the truncated
# form is eval-fallbacked (VM-executed), so a macro-produced `(set! + *)`
# inside it rebinds at run time — but the whole-program redefined_names
# map can no more see through the truncation than the scan could, and
# `kaappi compile` never executes forms to find out. A later natively
# lowered `(+ 5 2)` then folded to 7 while the interpreter printed 10.
# The fix eval-fallbacks every remaining top-level form after a truncated
# scan, so the later form runs in the VM and consults the live globals.
#
# The cyclic wrapper shape (macro use whose operand is another macro use
# carrying a datum-label cycle) is the minimal form whose scan truncates —
# verified against the scan's caps; a plain top-level cyclic use expands
# and discards the operand before any scan reaches it.
#
# Each case must produce the same output from the native binary as from the
# interpreter (the interpreter is the oracle — see shell-common.sh).
#
# Usage: bash tests/scheme/compile/native-truncated-scan-fallback-2404.sh [path-to-kaappi]

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

fail=0

check() {
    local name="$1" src="$2" expect_out="$3" expect_status="$4"

    printf '%s' "$src" > "$DIR/$name.scm"

    local interp_out interp_status=0
    interp_out=$(interp_stdout "$KAAPPI_ABS" "$DIR" "$name.scm") || interp_status=$?
    if [[ "$interp_out" != "$expect_out" ]]; then
        echo "FAIL: $name — interpreter stdout '$interp_out' != expected '$expect_out'" >&2
        fail=1
        return
    fi
    if [[ "$interp_status" -ne "$expect_status" ]]; then
        echo "FAIL: $name — interpreter exit $interp_status != expected $expect_status" >&2
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

# 1. The hole: truncated scan (cyclic wrapper operand), then a macro use
#    rebinding `+` to `*`, then a fold-sensitive `(+ 5 2)`. The rebind runs
#    in the VM either way; the later form must see the LIVE `+` (10), not a
#    stale fold (7).
check truncated-then-rebind \
'(define-syntax m (syntax-rules () ((m x) (quote ok))))
(define-syntax w (syntax-rules () ((w e) (begin e (if #f #f)))))
(w (m #0=(zz . #0#)))
(define-syntax rebind (syntax-rules () ((_) (set! + *))))
(rebind)
(display (+ 5 2))
(newline)' \
'10' 0

# 2. Discriminating control: the SAME program without the cyclic form keeps
#    its native lowering (the fallback must be engagement-gated, not
#    unconditional) — output identical, still both tiers.
check no-truncation-plain-rebind \
'(define-syntax rebind (syntax-rules () ((_) (set! + *))))
(rebind)
(display (+ 5 2))
(newline)' \
'10' 0

# 3. A truncated scan with NO rebinding anywhere: later plain forms still
#    evaluate correctly through the eval-fallback path.
check truncated-plain-arithmetic \
'(define-syntax m (syntax-rules () ((m x) (quote ok))))
(define-syntax w (syntax-rules () ((w e) (begin e (if #f #f)))))
(w (m #0=(zz . #0#)))
(display (+ 5 2))
(newline)' \
'7' 0

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-truncated-scan-fallback-2404: all cases passed"
