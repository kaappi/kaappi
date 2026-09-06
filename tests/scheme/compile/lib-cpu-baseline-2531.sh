#!/bin/bash
# Regression test for kaappi#2531: `zig build` with no -Dtarget tunes for the
# build host's exact CPU model, and the `lib` step used to build
# libkaappi_rt.a from that same host-tuned target — so every executable a
# source-built `kaappi compile` emitted carried a host-tuned VM/GC and could
# SIGILL on another machine of the same architecture (#2515's misdiagnosis
# cost: it reads as a VM bug, not a build-flags bug). The fix, completing
# #2529's bundle-path pin: the runtime archive resolves the portable baseline
# CPU model by default; -Dcpu=native (Zig's own spelling — bit for bit the
# pre-fix tuning) opts back into host tuning; any other explicit -Dcpu=<model>
# is always respected. The dev binary from the same `zig build` configure
# stays host-tuned — only the artifact that ships inside kaappi-compile
# output is pinned.
#
# Build-system defaults have no Scheme-visible surface and the archive
# carries no CPU-model tag, so the observable is differential, exactly as in
# bundle-cpu-baseline-2515.sh: Zig builds are reproducible, so the default
# `zig build lib` archive must be byte-identical to an explicit
# `-Dcpu=baseline` one. That assertion fails without the fix on every host
# whose CPU model differs from the baseline (CI's x86_64 legs, Apple Silicon
# above M1) and passes trivially where host == baseline, because the bug
# cannot manifest there. The opt-out is checked the same way: when
# host != baseline, the -Dcpu=native archive must differ from the default.
# A tiny zig probe — the technique from the #2515 issue itself — names the
# two models so the script knows which world it is in instead of guessing.
#
# Build discipline (kaappi#1926/#1930): the default archive build shares
# run-all.sh's own up-front `zig build lib` cache key exactly (same default
# flags, and baseline == baseline under the fix), the -Dcpu=baseline twin is
# a cache hit of it, and only the -Dcpu=native variant is one cold build.
# The end-to-end link check compiles with the shared fixture interpreter
# (host-tuned is fine — the interpreter only drives emission and linking)
# against the default archive via KAAPPI_LIB_DIR, never zig-out's, so the
# assertion is about THIS tree's default flags and not whatever archive
# another script left installed. The archive is only half of what
# `kaappi compile` ships: on the preferred zig-cc link route the emitted IR
# must be pinned with -mcpu=baseline too (`zig cc` with no -mcpu resolves
# the host CPU, unlike clang/gcc's generic triple default), so a logging
# `zig` shim placed first on PATH captures the exact argv the link step
# handed the compiler — an externally observable assertion that runs on
# every host, baseline or not.
#
# Usage: bash tests/scheme/compile/lib-cpu-baseline-2531.sh [path-to-kaappi]
# (the kaappi path is accepted for suite uniformity and unused: the archive
# under test is built from current source, like every compile-suite script.)

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"
skip_without_zig "rebuilds libkaappi_rt.a with zig build lib on this machine"

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
RT_LIB="$(rt_lib_name)"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# --- probe: name the host and baseline CPU models (#2515's technique) ------
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

# --- the three archive variants the assertions need ------------------------
# Same -Doptimize, one flag apart. Under the fix the baseline twin resolves
# to the same target as the default build (a Zig cache hit), so it costs
# nothing; the native variant is the one cold build this script adds.
build_variant() { # <name> <extra zig build flags...>
    local name="$1"
    shift
    local log rc
    log=$(mktemp)
    build_lock "$REPO_DIR" lib-cpu-2531
    rc=0
    (
        cd "$REPO_DIR" &&
            zig build lib -Doptimize=ReleaseSafe "$@" \
                --prefix "$DIR/prefix-$name" &&
            cp "$DIR/prefix-$name/lib/$RT_LIB" "$DIR/$name-$RT_LIB"
    ) > "$log" 2>&1 || rc=$?
    build_unlock "$REPO_DIR" lib-cpu-2531
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: could not build the '$name' runtime-archive variant" >&2
        cat "$log" >&2
    fi
    rm -f "$log"
    return "$rc"
}
build_variant default
build_variant baseline -Dcpu=baseline
build_variant native -Dcpu=native

# --- assertion 1: the default IS the baseline archive ----------------------
# Without the fix (host-tuned default) these differ wherever host != baseline.
if ! cmp -s "$DIR/default-$RT_LIB" "$DIR/baseline-$RT_LIB"; then
    echo "FAIL: default zig build lib archive is not the -Dcpu=baseline one —" >&2
    echo "      the portable-baseline default (kaappi#2531) regressed" >&2
    exit 1
fi

# --- assertion 2: the opt-out restores host tuning -------------------------
# Only meaningful where the two tunings differ; where host == baseline the
# comparison is vacuous and the bug this guards cannot manifest.
if [ "$HOST_MODEL" != "$BASE_MODEL" ]; then
    if cmp -s "$DIR/default-$RT_LIB" "$DIR/native-$RT_LIB"; then
        echo "FAIL: -Dcpu=native did not restore host CPU tuning" >&2
        echo "      (host=$HOST_MODEL baseline=$BASE_MODEL, archives identical)" >&2
        exit 1
    fi
else
    echo "note: host CPU model == baseline ($HOST_MODEL); the opt-out comparison is vacuous here" >&2
fi

# --- assertion 3: kaappi-compile output linked against the default runs ----
# Baseline is a subset of the host's features, so a program linked against
# the default (baseline) archive must run right where it was built — and
# exit cleanly, since a teardown crash after the expected line printed is
# exactly what this assertion exists to catch. This is the issue's own
# scenario minus the second machine: the byte-identity assertions above
# stand in for "the tuning actually moved".
fixture_interpreter "$REPO_DIR" || {
    echo "FAIL: could not build the fixture interpreter" >&2
    exit 1
}
INTERP="$(fixture_interpreter_path "$REPO_DIR")"
cat > "$DIR/prog.scm" <<'EOF'
(display "2531: baseline archive links and runs") (newline)
EOF

# --- assertion 4: the zig-cc link route pins -mcpu=baseline ----------------
# A logging `zig` shim captures the exact argv `kaappi compile` hands the
# compiler. The shim is transparent (it execs the real zig), so the binary
# this one compile produces serves both this assertion and assertion 3.
# Pre-fix the captured line has no -mcpu and zig cc tunes for the host;
# unlike assertions 1/2 this check is meaningful on every host, because the
# flag is passed unconditionally.
REAL_ZIG="$(command -v zig)"
export REAL_ZIG
SHIM_LOG="$DIR/zig-argv.log"
export SHIM_LOG
mkdir -p "$DIR/shim-bin"
cat > "$DIR/shim-bin/zig" <<'SHIM'
#!/bin/bash
printf '%s\n' "$*" >> "$SHIM_LOG"
exec "${REAL_ZIG:?REAL_ZIG not set}" "$@"
SHIM
chmod +x "$DIR/shim-bin/zig"
: > "$SHIM_LOG"

COMPILE_LOG="$DIR/compile.log"
if ! (cd "$DIR" && PATH="$DIR/shim-bin:$PATH" KAAPPI_LIB_DIR="$DIR/prefix-default/lib" \
        "$INTERP" compile prog.scm -o prog) > "$COMPILE_LOG" 2>&1; then
    echo "FAIL: kaappi compile against the default (baseline) archive failed" >&2
    cat "$COMPILE_LOG" >&2
    exit 1
fi
if ! grep -q -- '-mcpu=baseline' "$SHIM_LOG"; then
    echo "FAIL: the zig-cc link route did not pin -mcpu=baseline —" >&2
    echo "      the program code kaappi compile ships stays host-tuned (kaappi#2531)" >&2
    echo "argv captured by the shim:" >&2
    cat "$SHIM_LOG" >&2
    exit 1
fi

if ! OUTPUT="$(cd "$DIR" && ./prog 2>&1)"; then
    echo "FAIL: program linked against the default (baseline) archive exited unsuccessfully" >&2
    echo "full output: $OUTPUT" >&2
    cat "$COMPILE_LOG" >&2
    exit 1
fi
if [ "$OUTPUT" != "2531: baseline archive links and runs" ]; then
    echo "FAIL: program linked against the default (baseline) archive did not run" >&2
    echo "full output: $OUTPUT" >&2
    cat "$COMPILE_LOG" >&2
    exit 1
fi

echo "PASS: zig build lib defaults to the baseline CPU ($BASE_MODEL; host is $HOST_MODEL); -Dcpu=native restores host tuning; the zig-cc link pins -mcpu=baseline"
