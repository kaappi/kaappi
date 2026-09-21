#!/bin/bash
# Native-backend end-to-end tests for a *cross-compiled* target — the
# riscv64-linux native tier, whose only CI machine is QEMU user-mode.
#
# run-e2e.sh assumes the host is the target: it runs `zig build` on the
# machine under test and links every program with the host's own `zig cc`.
# Under QEMU that is a full interpreter build through TCG (hours) plus a
# ~20 s emulated link per program. This script keeps everything that is
# target-independent on the host and emulates only what must run as the
# target:
#
#   * `zig build` / `zig build lib -Dtarget=<target>` cross-compile the
#     interpreter and libkaappi_rt.a on the host (fast, and the exact
#     artifacts release.yml ships for the target).
#   * The cross-built kaappi runs under the emulator to produce the oracle
#     output and to emit each program's .ll — the emitter is a comptime
#     switch on the *host* arch (llvm_emit.targetTriple,
#     fast_tailcalls_supported), so the IR must come from a kaappi that
#     believes it is the target.
#   * `zig cc -target <target>` cross-links each .ll on the host at -O2 with
#     no -w: the same LLVM codegen and the same archive as an on-target
#     `kaappi compile`, minus the on-target driver invocation, which the
#     `smoke` step below covers once with a real on-target `kaappi compile`
#     when a target-arch `zig` is supplied.
#   * The linked binary runs under the emulator and must match the oracle.
#   * native-mutual-tail.scm and native-mixed-arity-tail.scm are
#     additionally checked for `musttail` in their IR and re-run on a 1 MB
#     guest stack (kaappi#2602, kaappi#2604): parity alone cannot tell
#     native constant-stack tail calls from an interpreted cycle the VM's
#     own TCO keeps flat.
#
# Usage:
#   bash tests/e2e/run-e2e-cross.sh <zig-target> [<target-zig-binary>]
#
#   <zig-target>          e.g. riscv64-linux (Zig's musl-static default, so
#                         the linked binaries need no target sysroot to run
#                         under binfmt or in a container).
#   <target-zig-binary>   optional: a `zig` executable built FOR the target.
#                         When given, one program is additionally compiled
#                         on-target with `kaappi compile` (kaappi forks this
#                         zig as its C compiler, both under the emulator).
#
# Environment:
#   KAAPPI_EMU           command prefix that runs a target binary (default:
#                        empty, i.e. binfmt_misc runs it transparently, as
#                        CI's docker/setup-qemu-action arranges). Locally on
#                        macOS, something like:
#                          KAAPPI_EMU="podman run --rm --platform linux/riscv64 \
#                            -v $PWD:$PWD -v /private/tmp:/private/tmp -w $PWD \
#                            kaappi-builder-riscv64"
#                        — the repo and $TMPDIR must be visible at the same
#                        paths inside the container. A bare emulator
#                        (KAAPPI_EMU=qemu-riscv64) runs the parity,
#                        constant-stack and argv phases too; the on-target
#                        smoke runs `env` *inside* the prefix to put the
#                        target zig on PATH, which only the empty and
#                        container forms can do.
#   KAAPPI_CROSS_PREFIX  a prebuilt install prefix (bin/kaappi +
#                        lib/libkaappi_rt.a, both built FOR the target) to
#                        test instead of cross-building one here — e.g. the
#                        release artifacts, or an archive built with
#                        -Dgc-stress=true (kaappi#2594). This is the
#                        script's form of the usual "path to the kaappi under
#                        test" argument: a host kaappi cannot stand in (the
#                        emitter is a comptime switch on the host arch), and
#                        the binary is only meaningful next to its archive.
#   KAAPPI_E2E_PROGRAMS  optional space-separated list of program basenames
#                        (without .scm, e.g. "tak native-fib") to run in the
#                        parity phase instead of every programs/*.scm. The
#                        argv and on-target smoke phases run regardless. A
#                        list that matches nothing is an error, not a pass.
#                        Meant for splitting a slow run -- the gc-stress
#                        archive under TCG (kaappi#2594) -- across steps.
#   TMPDIR               scratch root (default /tmp). The cross-build prefix
#                        lives under it too, per run, so concurrent runs for
#                        the same target never share an install tree.
#
# Exit status is nonzero on any failure; the summary line names the count.

set -euo pipefail

TARGET="${1:?usage: run-e2e-cross.sh <zig-target> [target-zig-binary]}"
TARGET_ZIG="${2:-}"
EMU="${KAAPPI_EMU:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK="${TMPDIR:-/tmp}/kaappi-e2e-cross-$$"
PASS=0
FAIL=0

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK"

cd "$REPO_DIR"

if [[ -n "${KAAPPI_CROSS_PREFIX:-}" ]]; then
    OUT_DIR="$(cd "$KAAPPI_CROSS_PREFIX" && pwd)"
    echo "=== Using prebuilt $TARGET prefix $OUT_DIR ==="
else
    OUT_DIR="$WORK/out"
    echo "=== Cross-building kaappi and libkaappi_rt.a for $TARGET ==="
    zig build -Dtarget="$TARGET" --prefix "$OUT_DIR"
    zig build lib -Dtarget="$TARGET" --prefix "$OUT_DIR"
fi

KAAPPI="$OUT_DIR/bin/kaappi"
LIBDIR="$OUT_DIR/lib"
[[ -x "$KAAPPI" && -f "$LIBDIR/libkaappi_rt.a" ]] \
    || { echo "error: $OUT_DIR lacks bin/kaappi or lib/libkaappi_rt.a" >&2; exit 2; }

# The emulated interpreter must at least start; a wrong KAAPPI_EMU or a
# missing binfmt registration fails here, loudly, not as 38 parity FAILs.
echo "target kaappi: $($EMU "$KAAPPI" --version)"

# Pick an IR verifier once, as run-e2e.sh does (#1492): malformed IR that
# passes -O0 can miscompile under -O2's stricter passes, and a verifier
# failure caught here is attributed as such instead of as a confusing
# cross-link failure. `opt`/`llvm-as` are target-agnostic on a .ll; the
# fallback is a `zig cc -c` for the target, which runs the same verifier
# on its way to an object file and, without -w, shows the diagnostic.
if command -v opt >/dev/null 2>&1; then
    IR_VERIFIER="opt"
elif command -v llvm-as >/dev/null 2>&1; then
    IR_VERIFIER="llvm-as"
else
    IR_VERIFIER="cc"
fi
echo "IR verifier: $IR_VERIFIER"

verify_ir() {
    case "$IR_VERIFIER" in
        opt)     opt -passes=verify -disable-output "$1" ;;
        llvm-as) llvm-as -o /dev/null "$1" ;;
        *)       zig cc -target "$TARGET" -c "$1" -o "$WORK/verify.o" ;;
    esac
}

# Cross-link one .ll against the target archive. -O2 and no -w, as run-e2e.sh
# does: any diagnostic the emitted IR provokes on this target is visible.
# No -mcpu: for a non-native -target, zig cc already defaults to the
# target's baseline model, the same model `zig build lib` pinned the
# archive to (kaappi#2531).
cross_link() {
    zig cc -target "$TARGET" -O2 "$1" -o "$2" -L"$LIBDIR" -lkaappi_rt -lc -lm -lpthread
}

# Interpreter-as-oracle parity, on output AND exit status (the
# assert_tiers_agree shape from tests/scheme/shell-common.sh): a native
# binary that dies the same way the interpreter does is parity, one that
# prints the same text and then exits differently is not, and two crashes
# with matching text are still a divergence unless their statuses match too.
assert_native_parity() {
    local label="$1"
    local program="$2"

    local expected expected_status=0
    expected=$($EMU "$KAAPPI" "$program" 2>&1) || expected_status=$?

    local ll_file="$WORK/$label.ll"
    local native_bin="$WORK/$label"

    local emit_output
    if ! emit_output=$($EMU "$KAAPPI" --emit-llvm -o "$ll_file" "$program" 2>&1); then
        echo "  emit: $emit_output"
        echo "FAIL: $label — emit-llvm failed"
        FAIL=$((FAIL + 1))
        return
    fi

    local verify_output
    if ! verify_output=$(verify_ir "$ll_file" 2>&1); then
        echo "  verify: $verify_output"
        echo "FAIL: $label — IR verification failed"
        FAIL=$((FAIL + 1))
        return
    fi

    local cc_output
    if ! cc_output=$(cross_link "$ll_file" "$native_bin" 2>&1); then
        echo "  cc: $cc_output"
        echo "FAIL: $label — cross-link failed"
        FAIL=$((FAIL + 1))
        return
    fi

    local actual actual_status=0
    actual=$($EMU "$native_bin" 2>&1) || actual_status=$?

    if [[ "$actual" == "$expected" && "$actual_status" == "$expected_status" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  expected (exit $expected_status): $expected"
        echo "  actual   (exit $actual_status): $actual"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== Native compilation parity tests ($TARGET) ==="
# KAAPPI_E2E_PROGRAMS narrows this loop only; the argv and smoke phases
# below still run, so a subset run is still a complete run of the script.
MATCHED=0
for program in "$SCRIPT_DIR"/programs/*.scm; do
    label="$(basename "$program" .scm)"
    if [[ -n "${KAAPPI_E2E_PROGRAMS:-}" ]]; then
        case " $KAAPPI_E2E_PROGRAMS " in
            *" $label "*) ;;
            *) continue ;;
        esac
    fi
    MATCHED=$((MATCHED + 1))
    assert_native_parity "$label" "$program"
done
# A filter that matches nothing must not pass as a 2/2 run of the argv and
# smoke phases alone.
if [[ -n "${KAAPPI_E2E_PROGRAMS:-}" && $MATCHED -eq 0 ]]; then
    echo "error: KAAPPI_E2E_PROGRAMS='$KAAPPI_E2E_PROGRAMS' matched no program under $SCRIPT_DIR/programs" >&2
    exit 2
fi

# Constant-stack mutual tail calls (kaappi#2602). The parity phase proves
# the cycle programs' *output*; this proves each ran as native code and
# kept a flat stack, which parity cannot: on a target with no fast entries
# every function in such a program is interpreted and the VM's own
# tail-call optimisation passes the diff -- the riscv64 situation before
# #2602 (docs/dev/llvm-backend.md, "Per-target gate"). Two programs:
# native-mutual-tail.scm's same-arity cycles at 2,000,000 alternating calls,
# and native-mixed-arity-tail.scm's 1-ary <-> 8-ary cycle at 1,000,000
# (kaappi#2604), whose musttail sites carry filler arguments under a padded
# row -- the one place a padded mixed-arity musttail runs on a real
# (emulated) target with a stack too small to hide a call that grew it.
# Two checks each:
#
#   * the emitted IR must carry `musttail`: the cycle members compiled
#     natively and their tail calls are LLVM-guaranteed, not a hint;
#   * the linked binary must produce the parity output on a 1 MB guest
#     stack, where the program's alternating calls cannot fit as real
#     frames -- a tail call that grew the stack is a crash, not a pass.
#     qemu-user honours QEMU_STACK_SIZE in every launcher form (binfmt_misc
#     on the host, inside the container, a bare `qemu-riscv64` prefix), but
#     only in the environment of the emulator that runs the binary, and
#     which environment that is differs: this shell's for the empty and
#     bare-emulator forms, the container's for a container form. So the
#     variable is set through `env` *inside* $EMU when $EMU can run `env`
#     -- the empty form exec-chains the host's `env` into the binary through
#     binfmt, a container runs its own, the shape the on-target smoke
#     already relies on for PATH -- and outside it otherwise, since a bare
#     emulator would load the host's `env` as the guest binary. Probed once
#     rather than inferred from the prefix's spelling.
echo ""
echo "=== Constant-stack mutual tail calls on a 1 MB guest stack ($TARGET) ==="
if $EMU env true >/dev/null 2>&1; then
    small_stack() { $EMU env QEMU_STACK_SIZE=1048576 "$@"; }
else
    small_stack() { QEMU_STACK_SIZE=1048576 $EMU "$@"; }
fi
for mt_name in native-mutual-tail native-mixed-arity-tail; do
    mt_src="$SCRIPT_DIR/programs/$mt_name.scm"
    mt_ll="$WORK/$mt_name-flat.ll"
    mt_bin="$WORK/$mt_name-flat"
    mt_expected_status=0
    mt_expected=$($EMU "$KAAPPI" "$mt_src" 2>&1) || mt_expected_status=$?
    if ! mt_emit=$($EMU "$KAAPPI" --emit-llvm -o "$mt_ll" "$mt_src" 2>&1); then
        echo "  emit: $mt_emit"
        echo "FAIL: constant-stack mutual tail calls ($mt_name) — emit-llvm failed"
        FAIL=$((FAIL + 1))
    elif ! grep -q 'musttail call' "$mt_ll"; then
        echo "FAIL: constant-stack mutual tail calls ($mt_name) — no musttail in the emitted IR (did the cycle compile natively?)"
        FAIL=$((FAIL + 1))
    elif ! mt_cc=$(cross_link "$mt_ll" "$mt_bin" 2>&1); then
        echo "  cc: $mt_cc"
        echo "FAIL: constant-stack mutual tail calls ($mt_name) — cross-link failed"
        FAIL=$((FAIL + 1))
    else
        mt_status=0
        mt_actual=$(small_stack "$mt_bin" 2>&1) || mt_status=$?
        if [[ "$mt_actual" == "$mt_expected" && "$mt_status" == "$mt_expected_status" ]]; then
            echo "PASS: constant-stack mutual tail calls ($mt_name, $(grep -c 'musttail call' "$mt_ll") musttail sites)"
            PASS=$((PASS + 1))
        else
            echo "FAIL: constant-stack mutual tail calls ($mt_name)"
            echo "  expected (exit $mt_expected_status): $mt_expected"
            echo "  actual   (exit $mt_status): $mt_actual"
            FAIL=$((FAIL + 1))
        fi
    fi
done

# Command-line passthrough (kaappi#1744), as in run-e2e.sh Phase 3.
echo ""
echo "=== Command-line argument passthrough ($TARGET) ==="
argv_ll="$WORK/test-argv.ll"
argv_bin="$WORK/test-argv"
if $EMU "$KAAPPI" --emit-llvm -o "$argv_ll" "$SCRIPT_DIR/test-argv.scm" 2>/dev/null &&
    cross_link "$argv_ll" "$argv_bin" 2>/dev/null; then
    actual_status=0
    actual=$($EMU "$argv_bin" a b c 2>&1) || actual_status=$?
    expected='("a" "b" "c")'
    if [[ "$actual" == "$expected" && "$actual_status" == 0 ]]; then
        echo "PASS: command-line argument passthrough"
        PASS=$((PASS + 1))
    else
        echo "FAIL: command-line argument passthrough"
        echo "  expected (exit 0): $expected"
        echo "  actual   (exit $actual_status): $actual"
        FAIL=$((FAIL + 1))
    fi
else
    echo "FAIL: command-line argument passthrough — emit/link failed"
    FAIL=$((FAIL + 1))
fi

# On-target `kaappi compile` smoke: the one thing cross-linking skips is the
# driver invocation kaappi itself performs on the target (C-compiler search,
# -mcpu=baseline, the archive lookup via KAAPPI_LIB_DIR). Run it once, with a
# target-arch zig on PATH, on the program that was the kaappi#1656 repro.
if [[ -n "$TARGET_ZIG" ]]; then
    echo ""
    echo "=== On-target kaappi compile smoke ($TARGET) ==="
    smoke_src="$SCRIPT_DIR/programs/tak.scm"
    smoke_bin="$WORK/tak-on-target"
    zig_dir="$(cd "$(dirname "$TARGET_ZIG")" && pwd)"
    expected_status=0
    expected=$($EMU "$KAAPPI" "$smoke_src" 2>&1) || expected_status=$?
    if compile_output=$($EMU env PATH="$zig_dir:$PATH" KAAPPI_LIB_DIR="$LIBDIR" \
        "$KAAPPI" compile "$smoke_src" -o "$smoke_bin" 2>&1); then
        actual_status=0
        actual=$($EMU "$smoke_bin" 2>&1) || actual_status=$?
        if [[ "$actual" == "$expected" && "$actual_status" == "$expected_status" ]]; then
            echo "PASS: on-target kaappi compile"
            PASS=$((PASS + 1))
        else
            echo "FAIL: on-target kaappi compile — output mismatch"
            echo "  expected (exit $expected_status): $expected"
            echo "  actual   (exit $actual_status): $actual"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  compile: $compile_output"
        echo "FAIL: on-target kaappi compile — compile failed"
        FAIL=$((FAIL + 1))
    fi
fi

echo ""
TOTAL=$((PASS + FAIL))
echo "=== Cross E2E Summary ($TARGET): $PASS/$TOTAL passed ==="
if [[ $FAIL -gt 0 ]]; then
    echo "$FAIL FAILED"
    exit 1
fi
