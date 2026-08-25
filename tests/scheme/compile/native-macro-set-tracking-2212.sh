#!/bin/bash
# Regression test for #2212: a top-level MACRO USE that expands to a
# `(set! + -)` must suppress inline-primitive dispatch (and constant folding)
# for the rebound name in later top-level forms, exactly as a literal
# `(set! + -)` already did (#822).
#
# `kaappi compile` never executes program forms, so the syntactic rebinding
# tracker (`collectRedefinedNames`) was the only signal — and it matched only a
# literal define/set!/begin head, never a macro use. A macro expanding to a
# `set!` therefore stayed invisible, so a later `(+ 5 2)` was inlined against
# the stale primitive and the native binary printed 7 while the interpreter
# printed 3. The interpreter is immune because by the time it compiles the
# later form it has already *executed* the rebinding one.
#
# Each case must produce the same output from the native binary as from the
# interpreter (the interpreter is the oracle — see shell-common.sh).
#
# Usage: bash tests/scheme/compile/native-macro-set-tracking-2212.sh [path-to-kaappi]

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

# Compile a program natively and require its stdout + exit status to match the
# interpreter's. `expect_out`/`expect_status` document intent and still catch an
# answer both tiers get wrong.
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

# 1. The issue repro: a macro use rebinds a binary inline primitive at top
#    level; a later `(+ 5 2)` must see the rebinding (3, not 7).
check macro-rebind-binary \
'(define-syntax rebind (syntax-rules () ((_) (set! + -))))
(define orig+ +)
(rebind)
(display (+ 5 2))
(newline)
(set! + orig+)' \
'3' 0

# 2. Same, for a unary inline primitive (car), to exercise tryEmitInlineUnary.
check macro-rebind-unary \
'(define-syntax swap-car (syntax-rules () ((_) (set! car cdr))))
(swap-car)
(display (car (cons 1 2)))
(newline)' \
'2' 0

# 3. A macro that expands to a `begin` wrapping the rebinding set! — the
#    macro-aware scan must recurse through begin.
check macro-rebind-in-begin \
'(define-syntax rebind (syntax-rules () ((_) (begin (set! + -)))))
(rebind)
(display (+ 5 2))
(newline)' \
'3' 0

# ---- Discriminating controls: normal fold/inline must be unaffected. ----

# 4. No rebind anywhere: plain arithmetic still evaluates correctly natively,
#    so the whole-program set_targets gate did not over-blunt inlining.
check no-rebind-plain \
'(display (+ 5 2))
(newline)
(display (* 6 7))
(newline)' \
'7
42' 0

# 5. In-body control: a macro use inside a lambda body must stay tier-agnostic
#    (the body contains a macro use, so native compilation is declined and the
#    interpreter takes over — no top-level cross-form scan is involved). Both
#    tiers fold (+ 5 2) at compile time and yield 7: neither tier's pre-scan
#    suppresses the fold for an *in-body* macro-`set!`. That shared behaviour is
#    a separate question from #2212 (which is specifically about the compiled
#    tier DIVERGING from the interpreter on the top-level case); the point of
#    this control is only that the fix introduces no in-body divergence — the
#    tiers still agree — which assert_tiers_agree enforces regardless of whether
#    the agreed value is 3 or 7.
check in-body-rebind \
'(define-syntax rebind (syntax-rules () ((_) (set! + -))))
(define (f) (rebind) (+ 5 2))
(display (f))
(newline)' \
'7' 0

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-macro-set-tracking-2212: all cases passed"
