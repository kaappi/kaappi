#!/bin/bash
# Regression test for #2515: `zig build` with no -Dtarget tunes for the build
# host's exact CPU model, so a standalone binary built that way — the
# documented way to ship a Kaappi program — could SIGILL on another machine
# of the same architecture. The fix: -Dbundle/-Dbundle-src builds resolve the
# portable baseline CPU model by default; -Dcpu=native (Zig's own spelling —
# bit for bit the pre-fix tuning, and unlike a skip-the-pin flag it also
# delivers host tuning under an explicit -Dtarget) opts back into host tuning
# for a binary that really will only run here; any other explicit
# -Dcpu=<model> is always respected.
#
# Build-system defaults have no Scheme-visible surface and the binary carries
# no CPU-model tag (the bytecode compiler key hashes arch/os/abi only), so the
# observable is differential: Zig builds are reproducible, so the default
# bundle build must be byte-identical to an explicit -Dcpu=baseline one. That
# assertion fails without the fix on every host whose CPU model differs from
# the baseline (CI's x86_64 legs, Apple Silicon above M1) and passes trivially
# where host == baseline, because the bug cannot manifest there. The opt-out
# is checked the same way: when host != baseline, the -Dcpu=native build must
# differ from the default. A tiny zig probe — the technique from
# the issue itself — names the two models so the script knows which world it
# is in instead of guessing.
#
# Build discipline follows bundle_fixture_binary (kaappi#1930/#1926): the
# .sbc comes from the shared plain interpreter (host-tuned is fine — the CPU
# model is not part of the compiler hash, which is exactly why a baseline
# bundler may embed a host-tuned compiler's .sbc), and the default bundle
# build is the shared one, so only the -Dcpu=baseline twin (a cache hit under
# the fix) and the -Dcpu=native variant (one cold build) are new.
#
# Usage: bash tests/scheme/compile/bundle-cpu-baseline-2515.sh [path-to-kaappi]
# (the kaappi path is accepted for suite uniformity and unused: every binary
# here is built from current source, like every -Dbundle test.)

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"
skip_without_zig "rebuilds the interpreter with -Dbundle on this machine"

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$REPO_DIR/.zig-cache/kaappi-test-fixtures"
SBC="$OUT/bundle-replay.sbc"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# The binary under test: default flags, i.e. what a downstream user typing
# `zig build -Dbundle=program.sbc` gets. bundle_fixture_binary compiles the
# .sbc with the shared plain interpreter and builds the default bundle.
DEFAULT_BIN="$DIR/default-kaappi"
bundle_fixture_binary "$REPO_DIR" "$DEFAULT_BIN"

# --- probe: name the host and baseline CPU models (the issue's technique) --
# A three-line native zig program prints what the two CPU selections resolve
# to on this machine (e.g. host=apple_m3 baseline=apple_m1 on an M3 Mac).
cat > "$DIR/cpu-probe.zig" <<'EOF'
const std = @import("std");
const builtin = @import("builtin");
pub fn main() !void {
    const baseline = std.Target.Cpu.baseline(builtin.cpu.arch, builtin.os);
    std.debug.print("host={s}\nbaseline={s}\n", .{ builtin.cpu.model.name, baseline.model.name });
}
EOF
PROBE_LOG="$DIR/probe.log"
if ! (cd "$DIR" && zig build-exe cpu-probe.zig) > "$PROBE_LOG" 2>&1; then
    echo "FAIL: could not build the CPU-model probe" >&2
    cat "$PROBE_LOG" >&2
    exit 1
fi
# std.debug.print writes to stderr, so fold it into the capture.
PROBE_OUT="$(cd "$DIR" && ./cpu-probe 2>&1)"
HOST_MODEL="$(sed -n 's/^host=//p' <<< "$PROBE_OUT")"
BASE_MODEL="$(sed -n 's/^baseline=//p' <<< "$PROBE_OUT")"
if [ -z "$HOST_MODEL" ] || [ -z "$BASE_MODEL" ]; then
    echo "FAIL: CPU-model probe printed no models:" >&2
    printf '%s\n' "$PROBE_OUT" >&2
    exit 1
fi

# --- the two bundle variants the assertions need --------------------------
# Same .sbc, same -Doptimize, one flag apart. Under the fix the baseline twin
# is a Zig cache hit of the default build (identical resolved target), so it
# costs nothing; the native variant is the one cold build this script adds.
build_variant() { # <name> <extra zig build flags...>
    local name="$1"
    shift
    local log rc
    log=$(mktemp)
    build_lock "$REPO_DIR" bundle-cpu-2515
    rc=0
    (
        cd "$REPO_DIR" &&
            zig build -Dbundle="$SBC" -Doptimize=ReleaseSafe "$@" \
                --prefix "$DIR/prefix-$name" &&
            cp "$DIR/prefix-$name/bin/kaappi" "$DIR/$name-kaappi"
    ) > "$log" 2>&1 || rc=$?
    build_unlock "$REPO_DIR" bundle-cpu-2515
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: could not build the '$name' bundle variant" >&2
        cat "$log" >&2
    fi
    rm -f "$log"
    return "$rc"
}
build_variant baseline -Dcpu=baseline
build_variant native -Dcpu=native

# --- assertion 1: the default IS the baseline build ------------------------
# Without the fix (host-tuned default) these differ wherever host != baseline.
if ! cmp -s "$DEFAULT_BIN" "$DIR/baseline-kaappi"; then
    echo "FAIL: default -Dbundle build is not the -Dcpu=baseline build —" >&2
    echo "      the portable-baseline default (#2515) regressed" >&2
    exit 1
fi

# --- assertion 2: the opt-out restores host tuning -------------------------
# Only meaningful where the two tunings differ; where host == baseline the
# comparison is vacuous and the bug this guards cannot manifest.
if [ "$HOST_MODEL" != "$BASE_MODEL" ]; then
    if cmp -s "$DEFAULT_BIN" "$DIR/native-kaappi"; then
        echo "FAIL: -Dcpu=native did not restore host CPU tuning" >&2
        echo "      (host=$HOST_MODEL baseline=$BASE_MODEL, builds identical)" >&2
        exit 1
    fi
else
    echo "note: host CPU model == baseline ($HOST_MODEL); the opt-out comparison is vacuous here" >&2
fi

# --- assertion 3: the baseline binary still runs ---------------------------
# Baseline is a subset of the host's features, so the shipped default must
# execute right where it was built — and the .sbc inside it came from a
# host-tuned compiler, which the compiler key permits (see cache.md).
OUTPUT="$("$DEFAULT_BIN" 2>&1)" || true
if ! grep -q '^703: Hello, world! #t$' <<< "$OUTPUT"; then
    echo "FAIL: default (baseline) bundled binary does not run its program" >&2
    echo "full output: $OUTPUT" >&2
    exit 1
fi

echo "PASS: -Dbundle defaults to the baseline CPU ($BASE_MODEL; host is $HOST_MODEL); -Dcpu=native restores host tuning"
