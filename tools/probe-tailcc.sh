#!/bin/bash
# Probe whether a target's LLVM backend accepts the fast-entry shape the
# native backend emits for guaranteed constant-stack mutual tail calls
# (docs/dev/llvm-backend.md, "Guaranteed mutual tail calls") -- in either of
# the two spellings `llvm_emit.FastAbi` knows:
#
#   (default)         `tailcc` + `musttail`, exact-arity prototypes: the
#                     aarch64/x86_64 row.
#   --fastcc-padded   `fastcc` + `musttail`, every prototype padded to
#                     max_fast_arity: the riscv64 (kaappi#2602) and
#                     x86_64-windows (kaappi#2604) row, for a backend that
#                     rejects `tailcc` as a function calling convention, or
#                     accepts it but refuses to grow a guaranteed tail
#                     call's stack-argument area. `musttail` under any
#                     convention but tailcc/swifttailcc demands matching
#                     caller and callee prototypes, so a mixed-arity tail
#                     call is only legal when both sides carry the same
#                     padded width -- which also makes every such call a
#                     sibling call into the caller's own argument area.
#
# It compiles that exact shape with the LLVM inside `zig cc` -- the one that
# links every `kaappi compile` output -- so the per-target row in
# src/llvm_emit.zig (porting.md, "Native (LLVM) backend") rests on a
# five-second experiment rather than on a reading of LLVM's sources or
# release notes. Run the default mode first; when it reports UNSUPPORTED,
# run `--fastcc-padded`, and a SUPPORTED there is the `padded_fastcc_abi`
# row.
#
# Both ways this can fail are loud, which is what makes the probe decisive:
#
#   * a backend that does not accept the convention as a *function* calling
#     convention rejects every fast-entry definition with "Unsupported
#     calling convention" -- RISC-V does for `tailcc`, through LLVM 21 and on
#     main as of 2026-09 (kaappi#2593), which is why it has the padded row;
#   * a backend that accepts the convention but cannot honour a particular
#     `musttail` rejects that call site -- "failed to perform tail call
#     elimination on a call site marked musttail" (ppc64le), or Win64's
#     "Can't handle guaranteed tail call under win64 yet" for a call that
#     would grow the caller's stack-argument area (x86_64-windows under
#     `tailcc`, kaappi#2604). The probe therefore uses
#     the widest fast entry the emitter produces -- %vm + max_fast_arity (8)
#     i64 + %upvalues, ten integer arguments, more than most ABIs pass in
#     registers -- and, in the default mode, a 1 -> 8 mixed-arity musttail,
#     which only `tailcc` and `swifttailcc` permit. (In the padded mode that
#     call is padded to the same width, as the emitter pads it.)
#
# A silent miscompile is not a failure mode: LLVM refuses a `musttail` it
# cannot lower, so SUPPORTED means the shape compiles at -O0 and -O2.
# What it does not prove is that the resulting binary keeps a flat stack;
# that is the e2e suite's job (tests/e2e/programs/native-mutual-tail.scm
# at 2,000,000 alternating calls, run on the target -- and, for a
# cross-compiled target, on a 1 MB guest stack by run-e2e-cross.sh).
#
# Only a backend diagnostic is a verdict. A compile that fails for any other
# reason -- an unknown target spelling, a driver error, the probe IR itself
# failing the verifier -- never asked the backend the question, so it is
# reported as PROBE FAILED rather than UNSUPPORTED: a misspelt target must
# not read as a rejection.
#
# Usage:
#   bash tools/probe-tailcc.sh [--fastcc-padded] [<zig-target>]   # default: the host
#   bash tools/probe-tailcc.sh riscv64-linux
#   bash tools/probe-tailcc.sh --fastcc-padded riscv64-linux
#   bash tools/probe-tailcc.sh --fastcc-padded x86_64-windows
#
# Prints one line and exits 0 for SUPPORTED, 1 for UNSUPPORTED (with the
# backend's diagnostic), 2 for PROBE FAILED (with the toolchain's message)
# or when `zig` is missing.

set -euo pipefail

MODE=tailcc
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --fastcc-padded) MODE=fastcc-padded ;;
        --*) echo "PROBE FAILED: unknown option $arg" >&2; exit 2 ;;
        *) TARGET="$arg" ;;
    esac
done
# Zig spells the PowerPC target `powerpc64le`; Kaappi's docs, CI job names
# and support matrix say `ppc64le`. Accept both, so the spelling the porting
# checklist uses cannot come back as a verdict.
case "$TARGET" in
    ppc64le-*) TARGET="powerpc64le-${TARGET#ppc64le-}" ;;
esac
command -v zig >/dev/null 2>&1 || { echo "PROBE FAILED: zig not on PATH" >&2; exit 2; }

TFLAG=()
[[ -n "$TARGET" ]] && TFLAG=(-target "$TARGET")
LABEL="${TARGET:-host}"

# The convention on every definition and call, and the prototype of the
# logically 1-ary entry: exact under tailcc, padded to the same eight i64
# under the padded mode.
case "$MODE" in
    tailcc)
        CC=tailcc
        SHAPE="tailcc/musttail"
        ONE_PARAMS="i64 %a0"
        ;;
    fastcc-padded)
        CC=fastcc
        SHAPE="padded fastcc/musttail"
        ONE_PARAMS="i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7"
        ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kaappi-probe-tailcc.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# No `target triple` in the module: clang takes it from -target (or the
# host), exactly as it does for the emitter's output under a cross link.
# The heredoc is unquoted for $CC/$ONE_PARAMS; nothing else in the IR is
# shell-significant.
cat > "$WORK/probe.ll" <<LL
; Two mutually recursive fast entries at max_fast_arity (8): body in
; registers, %vm first, %upvalues last (always null at a direct call).
; Each keeps a live local args array, as the real prologue does.
define $CC i64 @ev.fast(ptr %vm, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7, ptr %upvalues) {
entry:
  %args = alloca [8 x i64], align 8
  store i64 %a0, ptr %args
  %c = icmp eq i64 %a0, 0
  br i1 %c, label %done, label %rec
rec:
  %n1 = sub i64 %a0, 1
  %r = musttail call $CC i64 @od.fast(ptr %vm, i64 %n1, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7, ptr null)
  ret i64 %r
done:
  ret i64 %a1
}

define $CC i64 @od.fast(ptr %vm, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7, ptr %upvalues) {
entry:
  %args = alloca [8 x i64], align 8
  store i64 %a0, ptr %args
  %c = icmp eq i64 %a0, 0
  br i1 %c, label %done, label %rec
rec:
  %n1 = sub i64 %a0, 1
  %r = musttail call $CC i64 @ev.fast(ptr %vm, i64 %n1, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7, ptr null)
  ret i64 %r
done:
  ret i64 %a1
}

; A logically 1-ary fast entry tail-calling the 8-ary one: mutual recursion
; between functions of different arity. Under tailcc its prototype is the
; exact arity, legal only because tailcc exempts musttail from the
; prototype-match rule; under the padded mode it carries the same eight
; parameters as its callee, which is how the emitter keeps a mixed-arity
; musttail legal under fastcc.
define $CC i64 @one.fast(ptr %vm, $ONE_PARAMS, ptr %upvalues) {
entry:
  %r = musttail call $CC i64 @ev.fast(ptr %vm, i64 %a0, i64 0, i64 0, i64 0, i64 0, i64 0, i64 0, i64 0, ptr null)
  ret i64 %r
}

; The uniform C-ABI trampoline: unpacks the args array and calls the fast
; entry -- the entry kaappi_create_native_closure stores.
define internal i64 @ev(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) {
entry:
  %g0 = getelementptr i64, ptr %args, i64 0
  %v0 = load i64, ptr %g0
  %g1 = getelementptr i64, ptr %args, i64 1
  %v1 = load i64, ptr %g1
  %r = call $CC i64 @ev.fast(ptr %vm, i64 %v0, i64 %v1, i64 0, i64 0, i64 0, i64 0, i64 0, i64 0, ptr %upvalues)
  ret i64 %r
}

define i64 @main(i64 %argc, ptr %argv) {
entry:
  %args = alloca [8 x i64], align 8
  store i64 %argc, ptr %args
  %r = call i64 @ev(ptr null, ptr %args, i64 8, ptr null)
  ret i64 %r
}
LL

# The cpu/abi clang picked (best effort, informational): the default for a
# non-native -target is the baseline model `zig build lib` pins the archive to.
# (An explicit -o inside $WORK: with -v, `zig cc … -o /dev/null` still
# drops a probe.o into the caller's cwd.)
CC1="$(zig cc "${TFLAG[@]}" -v -c "$WORK/probe.ll" -o "$WORK/probe-v.o" 2>&1 | tr -d '"' | tr ' ' '\n' || true)"
CPU="$(printf '%s\n' "$CC1" | grep -A1 -m1 '^-target-cpu$' | sed -n 2p || true)"
ABI="$(printf '%s\n' "$CC1" | grep -A1 -m1 '^-target-abi$' | sed -n 2p || true)"
INFO="cpu ${CPU:-?}${ABI:+, abi $ABI}; $(zig cc --version 2>/dev/null | head -1)"

for opt in -O0 -O2; do
    if ! zig cc "${TFLAG[@]}" "$opt" -c "$WORK/probe.ll" -o "$WORK/probe.o" 2> "$WORK/err"; then
        diag="$(grep -m1 -i 'error' "$WORK/err" | sed 's/^.*error: //' || true)"
        # The two backend diagnostics this probe exists to surface both
        # arrive as "error in backend: ..." (an LLVM fatal error); anything
        # else is the toolchain failing to run the experiment at all.
        if grep -q 'error in backend\|LLVM ERROR' "$WORK/err"; then
            echo "UNSUPPORTED: $SHAPE on $LABEL at $opt ($INFO): ${diag:-see stderr}"
            exit 1
        fi
        echo "PROBE FAILED: could not compile the probe for $LABEL at $opt ($INFO): ${diag:-see stderr}" >&2
        exit 2
    fi
done
echo "SUPPORTED: $SHAPE on $LABEL at -O0 and -O2 ($INFO)"
