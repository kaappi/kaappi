#!/bin/bash
# Standalone-binary smoke for the SRFI 241/202 er-macro re-port (kaappi#2391).
#
# The re-port's SRFI-64 suites are interpreter-only evidence; per the
# LLVM-backend notes a compiled-artifact tier needs its own script here.
# `kaappi compile` refuses programs whose imports resolve from .sld files by
# design (kaappi#1743), so the compiled route for a library-importing program
# is the -Dbundle standalone binary: the .sbc pathway compiles the srfi
# libraries at build time and embeds them, and the resulting binary replays
# that bytecode with no library search path at all — exercising `match` and
# `and-let*` expansions through compile-serialize-replay instead of the
# interpreter's load path.
#
# The interpreter is the oracle (see the block in ../shell-common.sh): both
# tiers run the same fixture and their whole outputs must agree; the golden
# strings document intent and still catch an answer both tiers get wrong.
#
# Build discipline follows bundle_fixture_binary (kaappi#1930/#1926): the
# .sbc is produced by an interpreter built from the SAME source as the
# -Dbundle rebuild, into an isolated prefix, so the two share one build id;
# compiling from inside the fixture directory keeps the recorded paths
# relative and the .sbc bytes deterministic, making repeat -Dbundle builds
# content-cache hits. This fixture is separate from the shared bundle-replay
# one on purpose: srfi imports would make that fixture's .sbc bytes depend
# on the srfi library search path, and its three scripts share one binary.
# Every kaappi invocation gets a throwaway KAAPPI_HOME so an installed
# ~/.kaappi/lib (or its cache) can never shadow the tree's .sld files
# (kaappi#2352).
#
# Usage: bash tests/scheme/compile/srfi-241-202-bundle-2391.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"
skip_without_zig "rebuilds the interpreter with -Dbundle on this machine"

KAAPPI="${1:-zig-out/bin/kaappi}"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
FIXTURE="$REPO_DIR/tests/scheme/compile/fixtures/srfi-241-202"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

EXPECTED_A='2391-a: ((1 3 5) (2 4 6) end)'
EXPECTED_B='2391-b: (prefix 1 2 suffix 3)'
EXPECTED_C='2391-c: (9 4 2 1)'

# --- interpreter run (the oracle) ---------------------------------------
INTERP_OUTPUT=$(KAAPPI_HOME="$DIR/interp-home" "$KAAPPI" \
    --lib-path "$REPO_DIR/lib" "$FIXTURE/main.scm" 2>/dev/null)
for expected in "$EXPECTED_A" "$EXPECTED_B" "$EXPECTED_C"; do
    if ! grep -Fxq "$expected" <<< "$INTERP_OUTPUT"; then
        echo "FAIL: interpreter — expected line '$expected' missing" >&2
        echo "full output: $INTERP_OUTPUT" >&2
        exit 1
    fi
done

# --- standalone binary: interp prefix -> .sbc -> -Dbundle ----------------
OUT="$REPO_DIR/.zig-cache/kaappi-test-fixtures-2391"
SBC="$OUT/srfi-241-202.sbc"
INTERP="$OUT/interp/bin/kaappi"
BUNDLE_BIN="$DIR/main-standalone"
LOG=$(mktemp)

build_lock "$REPO_DIR" bundle-2391
rc=0
(
    mkdir -p "$OUT" &&
        cd "$REPO_DIR" &&
        zig build -Doptimize=ReleaseSafe --prefix "$OUT/interp" &&
        [ -x "$INTERP" ] &&
        cd "$FIXTURE" &&
        # Relative cwd => relative recorded paths => deterministic .sbc
        # bytes; srfi resolution comes from the isolated prefix's own
        # exe-relative lib (installed from this tree by the build above),
        # and the throwaway KAAPPI_HOME keeps a user install out of it.
        KAAPPI_HOME="$OUT/home" "$INTERP" --compile -o "$SBC" main.scm &&
        [ -f "$SBC" ] &&
        cd "$REPO_DIR" &&
        zig build -Dbundle="$SBC" -Doptimize=ReleaseSafe \
            --prefix "$OUT/prefix" &&
        cp "$OUT/prefix/bin/kaappi" "$BUNDLE_BIN"
) > "$LOG" 2>&1 || rc=$?
build_unlock "$REPO_DIR" bundle-2391

if [ "$rc" -ne 0 ]; then
    echo "FAIL: could not build the bundled srfi-241-202 binary" >&2
    cat "$LOG" >&2
    rm -f "$LOG"
    exit 1
fi
rm -f "$LOG"

# --- the two tiers must agree, line for line ----------------------------
BUNDLE_OUTPUT=$(KAAPPI_HOME="$DIR/bundle-home" "$BUNDLE_BIN" 2>&1)
if [[ "$BUNDLE_OUTPUT" != "$INTERP_OUTPUT" ]]; then
    echo "FAIL: standalone output diverges from the interpreter" >&2
    echo "--- interpreter:" >&2
    printf '%s\n' "$INTERP_OUTPUT" >&2
    echo "--- standalone:" >&2
    printf '%s\n' "$BUNDLE_OUTPUT" >&2
    exit 1
fi

echo "PASS: srfi-241-202 bundle smoke (3 lines, both tiers agree)"
