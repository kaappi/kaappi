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
#   KAAPPI_EMU   command prefix that runs a target binary (default: empty,
#                i.e. binfmt_misc runs it transparently, as CI's
#                docker/setup-qemu-action arranges). Locally on macOS,
#                something like:
#                  KAAPPI_EMU="podman run --rm --platform linux/riscv64 \
#                    -v $PWD:$PWD -v /private/tmp:/private/tmp -w $PWD \
#                    kaappi-builder-riscv64"
#                — the repo and $TMPDIR must be visible at the same paths
#                inside the container.
#   TMPDIR       scratch root (default /tmp).
#
# Exit status is nonzero on any failure; the summary line names the count.

set -euo pipefail

TARGET="${1:?usage: run-e2e-cross.sh <zig-target> [target-zig-binary]}"
TARGET_ZIG="${2:-}"
EMU="${KAAPPI_EMU:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO_DIR/zig-out-cross-$TARGET"
WORK="${TMPDIR:-/tmp}/kaappi-e2e-cross-$$"
PASS=0
FAIL=0

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK"

cd "$REPO_DIR"

echo "=== Cross-building kaappi and libkaappi_rt.a for $TARGET ==="
zig build -Dtarget="$TARGET" --prefix "$OUT_DIR"
zig build lib -Dtarget="$TARGET" --prefix "$OUT_DIR"

KAAPPI="$OUT_DIR/bin/kaappi"
LIBDIR="$OUT_DIR/lib"

# The emulated interpreter must at least start; a wrong KAAPPI_EMU or a
# missing binfmt registration fails here, loudly, not as 38 parity FAILs.
echo "target kaappi: $($EMU "$KAAPPI" --version)"

# Cross-link one .ll against the target archive. -O2 and no -w, as run-e2e.sh
# does: any diagnostic the emitted IR provokes on this target is visible.
# No -mcpu: for a non-native -target, zig cc already defaults to the
# target's baseline model, the same model `zig build lib` pinned the
# archive to (kaappi#2531).
cross_link() {
    zig cc -target "$TARGET" -O2 "$1" -o "$2" -L"$LIBDIR" -lkaappi_rt -lc -lm -lpthread
}

assert_native_parity() {
    local label="$1"
    local program="$2"

    local expected
    expected=$($EMU "$KAAPPI" "$program" 2>&1) || true

    local ll_file="$WORK/$label.ll"
    local native_bin="$WORK/$label"

    local emit_output
    if ! emit_output=$($EMU "$KAAPPI" --emit-llvm -o "$ll_file" "$program" 2>&1); then
        echo "  emit: $emit_output"
        echo "FAIL: $label — emit-llvm failed"
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

    local actual
    actual=$($EMU "$native_bin" 2>&1) || true

    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== Native compilation parity tests ($TARGET) ==="
for program in "$SCRIPT_DIR"/programs/*.scm; do
    assert_native_parity "$(basename "$program" .scm)" "$program"
done

# Command-line passthrough (kaappi#1744), as in run-e2e.sh Phase 3.
echo ""
echo "=== Command-line argument passthrough ($TARGET) ==="
argv_ll="$WORK/test-argv.ll"
argv_bin="$WORK/test-argv"
if $EMU "$KAAPPI" --emit-llvm -o "$argv_ll" "$SCRIPT_DIR/test-argv.scm" 2>/dev/null &&
    cross_link "$argv_ll" "$argv_bin" 2>/dev/null; then
    actual=$($EMU "$argv_bin" a b c 2>&1) || true
    expected='("a" "b" "c")'
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: command-line argument passthrough"
        PASS=$((PASS + 1))
    else
        echo "FAIL: command-line argument passthrough"
        echo "  expected: $expected"
        echo "  actual:   $actual"
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
    expected=$($EMU "$KAAPPI" "$smoke_src" 2>&1) || true
    if compile_output=$($EMU env PATH="$zig_dir:$PATH" KAAPPI_LIB_DIR="$LIBDIR" \
        "$KAAPPI" compile "$smoke_src" -o "$smoke_bin" 2>&1); then
        actual=$($EMU "$smoke_bin" 2>&1) || true
        if [[ "$actual" == "$expected" ]]; then
            echo "PASS: on-target kaappi compile"
            PASS=$((PASS + 1))
        else
            echo "FAIL: on-target kaappi compile — output mismatch"
            echo "  expected: $expected"
            echo "  actual:   $actual"
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
