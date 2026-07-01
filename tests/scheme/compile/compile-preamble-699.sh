#!/bin/bash
# Regression test for #699: compileFile GC safety and preamble recording.
# Exercises the --compile path (compileFile), which roots expr before
# handleTopLevelForm and always appends to preamble. Compiles to .sbc,
# then re-runs the .scm (which loads the cached .sbc) to verify imports replay.
#
# Usage: bash tests/scheme/compile/compile-preamble-699.sh [path-to-kaappi]

set -euo pipefail

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

REPLAY_OUTPUT=$("$KAAPPI" "$COMPILE_DIR/test.scm" 2>/dev/null)
if [[ "$REPLAY_OUTPUT" != "HELLO 42" ]]; then
    echo "FAIL: expected 'HELLO 42', got '$REPLAY_OUTPUT'" >&2
    exit 1
fi
