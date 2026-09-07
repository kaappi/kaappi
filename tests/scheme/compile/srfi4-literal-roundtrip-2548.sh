#!/bin/bash
# Regression test for #2548 (LLVM native backend): SRFI 4's homogeneous-vector
# literal syntax must survive native compilation.
#
# `#s16(1 -2)` and friends are read to NumericVector constants, and the
# native tier embeds every heap-value constant by PRINTING it and re-reading
# the `(quote ...)` source at run time (LLVMEmitter.emitQuotedEvalExpr).
# That makes the two reader/printer halves of this feature one dependency
# chain: before the fix the reader rejected the literal outright ("read
# error[KP1002]"), and a printer that wrote an unreadable `#<...>` form
# would have produced a native binary that died at run time on its own
# constant. The interpreted run is the oracle, per tests/scheme/CLAUDE.md.
#
# Hermetic: KAAPPI_HOME points at a throwaway dir; the probe file lives in a
# temp dir. The program imports only (scheme base)/(scheme write) — the
# literals are reader syntax, so no SRFI library is needed, which also keeps
# the native gate from refusing disk-resolved .sld imports.
#
# Usage: bash tests/scheme/compile/srfi4-literal-roundtrip-2548.sh [path-to-kaappi]

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")" || exit 1
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

ensure_runtime_lib "$REPO_DIR"

DIR="$(mktemp -d)" || exit 1
KAAPPI_HOME="$(mktemp -d)" || { rm -rf "$DIR"; exit 1; }
export KAAPPI_HOME
cleanup() { rm -rf "$DIR" "$KAAPPI_HOME"; }
trap cleanup EXIT

cat > "$DIR/probe.scm" <<'SCM'
(import (scheme base) (scheme write) (scheme read))
;; The SRFI 231 spec-example shape that found the bug: a u16vector literal
;; in code position, nested inside a vector/list constant.
(write (list 16 #u16(3895))) (newline)
;; Every SRFI 4 element kind, plus SRFI 160's complex extension.
(write #s8(-128 127)) (newline)
(write #u16(1 2 3)) (newline)
(write #s16(1 -2 #xff)) (newline)
(write #u32(4294967295)) (newline)
(write #s32(-2147483648)) (newline)
(write #u64(18446744073709551615)) (newline)
(write #s64(-9223372036854775808)) (newline)
(write #f32(1.5)) (newline)
(write #f64(-1.5)) (newline)
(write #c64(1.5+0.5i)) (newline)
(write #c128(1.5-2.5i)) (newline)
;; Quoted literal; structural equality across two separately read literals;
;; and a native constant equal to a literal read at run time (the print +
;; re-read constant embedding must hold the same element bytes).
(write (bytevector-u8-ref '#u8(5 6) 1)) (newline)
(write (equal? #s16(1 -2) #s16(1 -2))) (newline)
(write (equal? (list 16 #u16(3895)) '(16 #u16(3895)))) (newline)
(write (equal? '#s16(1 -2) (read (open-input-string "#s16(1 -2)")))) (newline)
;; A literal that IS a macro's expansion goes through Compiler.compileExpr,
;; not lowerWithMacros -- the one code position with its own self-evaluating
;; arm.
(define-syntax %lit (syntax-rules () ((_) #s16(1 2))))
(write (%lit)) (newline)
(write (let-syntax ((m (syntax-rules () ((_) #u16(7))))) (m))) (newline)
SCM

n=0
fail=0

ok() {
    echo "PASS: $1"
}

GOLDEN="$(cat <<'GOLD'
(16 #u16(3895))
#s8(-128 127)
#u16(1 2 3)
#s16(1 -2 255)
#u32(4294967295)
#s32(-2147483648)
#u64(18446744073709551615)
#s64(-9223372036854775808)
#f32(1.5)
#f64(-1.5)
#c64(1.5+0.5i)
#c128(1.5-2.5i)
6
#t
#t
#t
#s16(1 2)
#u16(7)
GOLD
)"

n=$((n + 1))
interp_status=0
interp_out="$(interp_stdout "$KAAPPI_ABS" "$DIR" "$DIR/probe.scm" "$DIR/probe.interp.err")" || interp_status=$?
if [ "$interp_status" -ne 0 ]; then
    echo "FAIL: interpreter oracle exited $interp_status" >&2
    show_interp_stderr "$DIR/probe.interp.err"
    exit 1
fi
# Fixed expected output first: both tiers agreeing on WRONG output must fail.
if [ "$interp_out" == "$GOLDEN" ]; then
    ok "interpreted run matches the golden output"
else
    echo "FAIL: interpreter output differs from the golden output" >&2
    diff <(printf '%s\n' "$GOLDEN") <(printf '%s\n' "$interp_out") >&2 || true
    show_interp_stderr "$DIR/probe.interp.err"
    exit 1
fi

n=$((n + 1))
bin="$DIR/probe.bin"
if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$DIR/probe.scm" -o "$bin" > /dev/null 2>&1); then
    echo "FAIL: native compile of the literal program failed" >&2
    exit 1
fi
ok "native compile accepted the literal program"

n=$((n + 1))
native_status=0
native_out="$("$bin" 2> /dev/null)" || native_status=$?
if assert_tiers_agree "native binary vs interpreter" \
    "$interp_out" "$interp_status" "$native_out" "$native_status"; then
    ok "the native binary agrees with the interpreter on stdout and exit status"
else
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "Interpreter output was:" >&2
    printf '%s\n' "$interp_out" >&2
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "Passed: $n"
else
    echo "FAILED: $fail of $n"
    exit 1
fi
