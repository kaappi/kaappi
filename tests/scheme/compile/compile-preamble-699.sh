#!/bin/bash
# Regression test for #699: compileFile GC safety and preamble recording.
# Exercises the --compile path (compileFile), which roots expr before
# handleTopLevelForm and always appends to preamble, then re-runs the .scm to
# confirm the program still evaluates correctly.
#
# Note (kaappi#1516): the run-cache moved to ~/.kaappi/cache and is skipped for
# programs that import, so the re-run below is a fresh compile — it no longer
# loads the co-located test.sbc. Preamble *replay from a .sbc* is covered by
# the bundle tests (compile-preamble-gc-700.sh, compile-import-error-703.sh),
# which embed the .sbc and replay its preamble via readFromBuffer.
#
# This is one of the compile suite's genuine exceptions to the
# interpreter-oracle rule (kaappi#2110): the tier under test is a NAMED .sbc,
# and nothing can execute one. `kaappi out.sbc` reads it as source and dies at
# the `KPBC` magic; the only executor is `zig build -Dbundle`, a ~180s whole-
# interpreter rebuild that 700/703 already pay for once, via a shared fixture
# with a different program. So the assertion below is a golden value, and the
# comparison it is standing in for is made by those two scripts instead. What
# this script can still check, and now does, is that `--compile` produced a
# non-empty artifact rather than claiming success and writing nothing.
#
# Usage: bash tests/scheme/compile/compile-preamble-699.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

KAAPPI="${1:-zig-out/bin/kaappi}"

COMPILE_DIR=$(mktemp -d)
trap 'rm -rf "$COMPILE_DIR"' EXIT

cat > "$COMPILE_DIR/test.scm" << 'SCHEME'
(import (scheme base) (scheme write) (scheme char) (scheme cxr))
(display (string-upcase "hello"))
(display " ")
(display (car (cons 42 '())))
(newline)
SCHEME

"$KAAPPI" --compile -o "$COMPILE_DIR/test.sbc" "$COMPILE_DIR/test.scm" > /dev/null 2>&1

if [[ ! -s "$COMPILE_DIR/test.sbc" ]]; then
    echo "FAIL: --compile exited 0 but wrote no (or an empty) .sbc" >&2
    exit 1
fi

REPLAY_OUTPUT=$("$KAAPPI" "$COMPILE_DIR/test.scm" 2>/dev/null)
if [[ "$REPLAY_OUTPUT" != "HELLO 42" ]]; then
    echo "FAIL: expected 'HELLO 42', got '$REPLAY_OUTPUT'" >&2
    exit 1
fi
