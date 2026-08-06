#!/bin/bash
# Regression test for #703: handleDefineLibrary continues past import CompileError.
# A library whose import clause produces a CompileError (from a partially failing
# multi-import) should still execute its begin block and register exports.
#
# Without the fix, handleDefineLibrary returns immediately on CompileError,
# skipping the begin block (so module state is UNDEFINED) and library registration.
#
# The project lives in fixtures/bundle-replay/ and is shared with
# compile-preamble-gc-700.sh, which needs a bundled binary for its own reason:
# building one recompiles the whole interpreter, so one fixture means one
# rebuild rather than two (kaappi#1926). Each script asserts only its own line.
#
# Usage: bash tests/scheme/compile/compile-import-error-703.sh [path-to-kaappi]

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

EXPECTED="703: Hello, world! #t"

# The interpreter is the oracle; the golden string documents intent and still
# catches a value both tiers get wrong. See the "interpreter as the native
# tier's oracle" block in ../shell-common.sh.
OUTPUT=$("$KAAPPI" --lib-path "$FIXTURE/lib" "$FIXTURE/main.scm" 2>/dev/null)
INTERP_LINE=$(printf '%s\n' "$OUTPUT" | grep '^703: ' || true)
if [[ "$INTERP_LINE" != "$EXPECTED" ]]; then
    echo "FAIL: interpreter mode — expected '$EXPECTED', got '$INTERP_LINE'" >&2
    echo "full output: $OUTPUT" >&2
    exit 1
fi

# Same program as a bundled binary, where the define-library forms are reached
# through the preamble replay rather than a plain top-level load.
BUNDLE_BIN="$DIR/main-standalone"
bundle_fixture_binary "$REPO_DIR" "$BUNDLE_BIN"

OUTPUT=$("$BUNDLE_BIN" 2>/dev/null)
LINE=$(printf '%s\n' "$OUTPUT" | grep '^703: ' || true)
if [[ "$LINE" != "$INTERP_LINE" ]]; then
    echo "FAIL: standalone '$LINE' != interpreter '$INTERP_LINE'" >&2
    echo "full output: $OUTPUT" >&2
    exit 1
fi
