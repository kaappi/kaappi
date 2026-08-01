#!/bin/bash
# Regression test for #700: preamble replay GC root and resilient imports.
# A bundled binary must replay preamble imports that trigger nested library
# loading (stressing GC). Without the expr root in the preamble replay loop,
# GC corrupts the import-set list.
#
# The multi-library project lives in fixtures/bundle-replay/ and is shared with
# compile-import-error-703.sh, which needs a bundled binary for its own reason:
# building one recompiles the whole interpreter, so one fixture means one
# rebuild rather than two (kaappi#1926). Each script asserts only its own line.
#
# Usage: bash tests/scheme/compile/compile-preamble-gc-700.sh [path-to-kaappi]

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
FIXTURE="$REPO_DIR/tests/scheme/compile/fixtures/bundle-replay"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

EXPECTED="700: 21 10"

# The interpreter is the oracle: the bundled tier replays the preamble from an
# embedded .sbc, the interpreter loads the same libraries directly, and the two
# must agree. The golden string documents intent and still catches a value both
# tiers get wrong. See the "interpreter as the native tier's oracle" block in
# ../shell-common.sh.
INTERP_OUTPUT=$("$KAAPPI" --lib-path "$FIXTURE/lib" "$FIXTURE/main.scm" 2>/dev/null)
INTERP_LINE=$(printf '%s\n' "$INTERP_OUTPUT" | grep '^700: ' || true)
if [[ "$INTERP_LINE" != "$EXPECTED" ]]; then
    echo "FAIL: interpreter mode — expected '$EXPECTED', got '$INTERP_LINE'" >&2
    echo "full output: $INTERP_OUTPUT" >&2
    exit 1
fi

BUNDLE_BIN="$DIR/main-standalone"
bundle_fixture_binary "$REPO_DIR" "$KAAPPI" "$BUNDLE_BIN"

# Run the bundled binary — must not crash or show preamble errors
OUTPUT=$("$BUNDLE_BIN" 2>&1)
if grep -q "preamble error" <<< "$OUTPUT"; then
    echo "FAIL: preamble error in bundled binary: $OUTPUT" >&2
    exit 1
fi
LINE=$(printf '%s\n' "$OUTPUT" | grep '^700: ' || true)
if [[ "$LINE" != "$INTERP_LINE" ]]; then
    echo "FAIL: standalone '$LINE' != interpreter '$INTERP_LINE'" >&2
    echo "full output: $OUTPUT" >&2
    exit 1
fi
