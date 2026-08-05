#!/bin/bash
# Regression test for #2010: a -Dbundle standalone binary IS the bundled
# program, so its whole argv belongs to that program's (command-line). A first
# argument that happens to spell a kaappi subcommand must neither be swallowed
# ("check", "fmt", "ast", "compile" silently vanished from the bundled
# program's argv) nor run instead of the bundled program ("explain", "doctor",
# "test", ...).
#
# Shares the bundle-replay fixture with compile-preamble-gc-700.sh and
# compile-import-error-703.sh, so the `zig build -Dbundle` here is a cache
# hit, not a third full rebuild (kaappi#1926). The fixture prints
# `cmdline: (<command-line>)` whenever it is given arguments (see main.scm).
#
# Usage: bash tests/scheme/compile/bundle-args-2010.sh [path-to-kaappi]

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

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

BUNDLE_BIN="$DIR/main-standalone"
bundle_fixture_binary "$REPO_DIR" "$BUNDLE_BIN"

FAIL=0

# Every kaappi inline subcommand plus the pre-VM dispatch words: the bundled
# binary must treat each as an ordinary first argument of its own program.
# `eval` and `repl` already passed through before #2010; the rest did not.
for arg in check fmt ast compile expand ir eval repl explain doctor test cache features; do
    OUTPUT=$("$BUNDLE_BIN" "$arg" z.scm 2>&1) || true
    CMDLINE=$(printf '%s\n' "$OUTPUT" | grep '^cmdline: ' || true)
    EXPECTED="cmdline: (\"$arg\" \"z.scm\")"
    if [[ "$CMDLINE" != "$EXPECTED" ]]; then
        echo "FAIL: bundled (command-line) for first arg '$arg' — expected '$EXPECTED', got '$CMDLINE'" >&2
        echo "full output: $OUTPUT" >&2
        FAIL=1
    fi
    # The bundled program must still have run its own code (not a kaappi
    # subcommand) when the first argument collides with one.
    if ! grep -q '^703: Hello, world! #t$' <<< "$OUTPUT"; then
        echo "FAIL: bundled program did not run with first arg '$arg' — kaappi subcommand intercepted?" >&2
        echo "full output: $OUTPUT" >&2
        FAIL=1
    fi
done

# A --flag spelling must reach the program too, not be parsed as kaappi's.
OUTPUT=$("$BUNDLE_BIN" --gc-stats z.scm 2>&1) || true
if ! grep -q '^cmdline: ("--gc-stats" "z.scm")$' <<< "$OUTPUT"; then
    echo "FAIL: '--gc-stats' was not passed through to (command-line)" >&2
    echo "full output: $OUTPUT" >&2
    FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
    exit 1
fi
echo "PASS: bundled binary passes every argv element through to (command-line)"
