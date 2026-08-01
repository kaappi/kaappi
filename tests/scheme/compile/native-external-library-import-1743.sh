#!/bin/bash
# Regression test for #1743: `kaappi compile` reported success and produced a
# binary for a program that imports a library resolved from a .sld file (a
# third-party package, or any of the 159 portable SRFIs) — then the binary
# died at runtime with "library not found", because the compiled binary's own
# runtime (kaappi_runtime_init in runtime_exports.zig) starts a fresh VM with
# no library search path, and the native backend does not bundle library
# sources into the binary the way the --compile/-Dbundle-src .sbc pathway
# does.
#
# The fix makes `kaappi compile` (and --emit-llvm, which it calls internally)
# detect at compile time when the program resolved any import from a .sld
# file rather than kaappi's built-in registry, and refuse to produce a binary
# — a loud compile-time diagnostic instead of a silently broken executable
# that exits 0.
#
# Usage: bash tests/scheme/compile/native-external-library-import-1743.sh [path-to-kaappi]

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

# Freshen the runtime library (prebuilt archive suffices without zig)
ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail=0

# A program importing a library kaappi cannot resolve at runtime must be
# REFUSED at compile time: nonzero exit, no binary produced, and a stderr
# diagnostic that names the problem instead of a silent false "success".
expect_refused() {
    local name="$1" src="$2"; shift 2
    printf '%s' "$src" > "$DIR/$name.scm"

    local status=0
    local err
    err=$(cd "$REPO_DIR" && "$KAAPPI_ABS" "$@" compile "$DIR/$name.scm" -o "$DIR/$name" 2>&1 >/dev/null) || status=$?

    if [[ "$status" -eq 0 ]]; then
        echo "FAIL: $name — kaappi compile exited 0 for an unresolvable import" >&2
        fail=1
        return
    fi
    if [[ -e "$DIR/$name" ]]; then
        echo "FAIL: $name — a binary was produced despite the refusal" >&2
        fail=1
        return
    fi
    if [[ "$err" != *"cannot produce a working binary"* ]]; then
        echo "FAIL: $name — stderr did not explain the refusal: $err" >&2
        fail=1
        return
    fi
}

# A program using only built-in libraries, or a self-contained
# define-library, must keep compiling and running exactly as before — and must
# agree with the interpreter, which is the oracle. `expect_out` documents
# intent and still catches an answer both tiers get wrong. See the "interpreter
# as the native tier's oracle" block in ../shell-common.sh.
#
# The refusal cases above have no interpreter counterpart at all: the assertion
# there is that COMPILATION fails, while the interpreter runs the very same
# program successfully. That is the point of the guard, not a divergence.
expect_compiles_and_runs() {
    local name="$1" src="$2" expect_out="$3"; shift 3
    printf '%s' "$src" > "$DIR/$name.scm"

    local interp_out interp_status=0
    interp_out=$(cd "$REPO_DIR" && "$KAAPPI_ABS" "$@" "$DIR/$name.scm" 2>/dev/null) || interp_status=$?
    if [[ $interp_status -ne 0 ]]; then
        echo "FAIL: $name — interpreter exited $interp_status (output: '$interp_out')" >&2
        fail=1
        return
    fi
    if [[ "$interp_out" != "$expect_out" ]]; then
        echo "FAIL: $name — interpreter expected '$expect_out', got '$interp_out'" >&2
        fail=1
        return
    fi

    if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" "$@" compile "$DIR/$name.scm" -o "$DIR/$name" > /dev/null 2>&1); then
        echo "FAIL: $name — native compilation failed" >&2
        fail=1
        return
    fi
    local out status=0
    out=$("$DIR/$name" 2>/dev/null) || status=$?
    assert_tiers_agree "$name" "$interp_out" "$interp_status" "$out" "$status" || fail=1
}

# --- Case 1: third-party-style library, resolved via --lib-path, mirrors
#     the original bug report (kaappi-json) without depending on any
#     sibling repo. ---
mkdir -p "$DIR/thirdparty"
cat > "$DIR/thirdparty/greet.sld" << 'SCHEME'
(define-library (thirdparty greet)
  (export greet)
  (import (scheme base))
  (begin
    (define (greet) "hello")))
SCHEME

expect_refused thirdparty-import \
'(import (scheme base) (scheme write) (thirdparty greet))
(write (greet))
(newline)' \
--lib-path "$DIR"

# --- Case 2: a portable SRFI (not one of the 12 built into the Zig binary)
#     resolved from this repo's own lib/srfi/*.sld — no --lib-path needed,
#     since main() adds the exe-relative lib dir automatically. ---
expect_refused portable-srfi-import \
'(import (scheme base) (scheme write) (srfi 2))
(and-let* ((x 1)) (write x))
(newline)'

# --- Case 3: nested import inside the user's own define-library must also
#     be caught — the whole form (including its internal import) is replayed
#     verbatim in the binary's runtime. ---
expect_refused nested-define-library-import \
'(define-library (my-wrapper)
  (export my-greet)
  (import (scheme base) (thirdparty greet))
  (begin
    (define (my-greet) (greet))))

(import (scheme base) (scheme write) (my-wrapper))
(write (my-greet))
(newline)' \
--lib-path "$DIR"

# --- Case 4: --emit-llvm shares the same guard (kaappi compile calls it
#     internally, but the flag is also reachable directly, e.g. via
#     `zig build native`). ---
status=0
err=$(cd "$REPO_DIR" && "$KAAPPI_ABS" --lib-path "$DIR" --emit-llvm -o "$DIR/emit.ll" "$DIR/thirdparty-import.scm" 2>&1 >/dev/null) || status=$?
if [[ "$status" -eq 0 ]]; then
    echo "FAIL: emit-llvm-refused — --emit-llvm exited 0 for an unresolvable import" >&2
    fail=1
elif [[ -e "$DIR/emit.ll" ]]; then
    echo "FAIL: emit-llvm-refused — a .ll file was produced despite the refusal" >&2
    fail=1
elif [[ "$err" != *"cannot produce a working binary"* ]]; then
    echo "FAIL: emit-llvm-refused — stderr did not explain the refusal: $err" >&2
    fail=1
fi

# --- Case 5 (no false positives): built-in SRFI 1 needs no file resolution
#     at all, so it must keep compiling and running natively. ---
expect_compiles_and_runs builtin-srfi-still-works \
'(import (scheme base) (scheme write) (srfi 1))
(write (filter odd? (list 1 2 3 4 5)))
(newline)' \
'(1 3 5)'

# --- Case 6 (no false positives): a library defined AND used in the same
#     file needs no file resolution either. `sq`, not `square` -- `square`
#     is itself a (scheme base) export, and this file imports both. ---
expect_compiles_and_runs self-contained-library-still-works \
'(define-library (my-math)
  (export sq)
  (import (scheme base))
  (begin
    (define (sq x) (* x x))))

(import (scheme base) (scheme write) (my-math))
(write (sq 7))
(newline)' \
'49'

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-external-library-import-1743: all cases passed"
