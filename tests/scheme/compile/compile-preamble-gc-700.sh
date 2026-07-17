#!/bin/bash
# Regression test for #700: preamble replay GC root and resilient imports.
# Creates a multi-library project where a bundled binary must replay preamble
# imports that trigger nested library loading (stressing GC). Without the
# expr root in the preamble replay loop, GC corrupts the import-set list.
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

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

mkdir -p "$DIR/lib/myapp"

# Leaf library with no dependencies
cat > "$DIR/lib/myapp/util.sld" << 'SCHEME'
(define-library (myapp util)
  (import (scheme base))
  (export double square)
  (begin
    (define (double x) (* x 2))
    (define (square x) (* x x))))
SCHEME

# Middle library depending on util
cat > "$DIR/lib/myapp/math.sld" << 'SCHEME'
(define-library (myapp math)
  (import (scheme base) (myapp util))
  (export quad)
  (begin
    (define (quad x) (double (double x)))))
SCHEME

# Top library depending on both
cat > "$DIR/lib/myapp/app.sld" << 'SCHEME'
(define-library (myapp app)
  (import (scheme base) (myapp util) (myapp math))
  (export run-app)
  (begin
    (define (run-app n) (+ (quad n) (square n)))))
SCHEME

# Main program importing all libraries in one form
cat > "$DIR/main.scm" << 'SCHEME'
(import (scheme base) (scheme write) (myapp app) (myapp util))
(display (run-app 3))
(display " ")
(display (double 5))
(newline)
SCHEME

# Compile to .sbc (from within temp dir so lib paths are relative)
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
(cd "$DIR" && "$KAAPPI_ABS" --lib-path lib --compile -o main.sbc main.scm > /dev/null 2>&1)

# Verify .sbc was created
if [[ ! -f "$DIR/main.sbc" ]]; then
    echo "FAIL: .sbc file not created" >&2
    exit 1
fi

# Build bundled binary
BUNDLE_BIN="$DIR/main-standalone"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
(cd "$REPO_DIR" && zig build -Dbundle="$DIR/main.sbc" -Doptimize=ReleaseSafe 2>/dev/null)
cp "$REPO_DIR/zig-out/bin/kaappi" "$BUNDLE_BIN"

# Rebuild regular binary
(cd "$REPO_DIR" && zig build 2>/dev/null)

# Run the bundled binary — must not crash or show preamble errors
OUTPUT=$("$BUNDLE_BIN" 2>&1)
if echo "$OUTPUT" | grep -q "preamble error"; then
    echo "FAIL: preamble error in bundled binary: $OUTPUT" >&2
    exit 1
fi
if [[ "$OUTPUT" != "21 10" ]]; then
    echo "FAIL: expected '21 10', got '$OUTPUT'" >&2
    exit 1
fi
