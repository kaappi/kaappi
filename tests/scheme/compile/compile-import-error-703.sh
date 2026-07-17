#!/bin/bash
# Regression test for #703: handleDefineLibrary continues past import CompileError.
# A library whose import clause produces a CompileError (from a partially failing
# multi-import) should still execute its begin block and register exports.
#
# Without the fix, handleDefineLibrary returns immediately on CompileError,
# skipping the begin block (so module state is UNDEFINED) and library registration.
#
# Usage: bash tests/scheme/compile/compile-import-error-703.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

KAAPPI="${1:-zig-out/bin/kaappi}"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

mkdir -p "$DIR/lib/myapp"

# Library A: simple leaf
cat > "$DIR/lib/myapp/util.sld" << 'SCHEME'
(define-library (myapp util)
  (import (scheme base))
  (export greet)
  (begin
    (define (greet name) (string-append "Hello, " name "!"))))
SCHEME

# Library B: depends on A, defines module-level state in begin block
cat > "$DIR/lib/myapp/app.sld" << 'SCHEME'
(define-library (myapp app)
  (import (scheme base) (srfi 69) (myapp util))
  (export app-greet lookup register!)
  (begin
    (define registry (make-hash-table string=? string-hash))
    (define (register! key val) (hash-table-set! registry key val))
    (define (lookup key) (hash-table-ref/default registry key #f))
    (define (app-greet name)
      (register! name #t)
      (greet name))))
SCHEME

# Main program
cat > "$DIR/main.scm" << 'SCHEME'
(import (scheme base) (scheme write) (myapp app))
(display (app-greet "world"))
(newline)
(display (lookup "world"))
(newline)
SCHEME

# Run in interpreter mode — must succeed
OUTPUT=$("$KAAPPI" --lib-path "$DIR/lib" "$DIR/main.scm" 2>/dev/null)
if [[ "$OUTPUT" != "Hello, world!"$'\n'"#t" ]]; then
    echo "FAIL: interpreter mode — expected 'Hello, world!' + '#t', got '$OUTPUT'" >&2
    exit 1
fi

# Compile to .sbc
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
(cd "$DIR" && "$KAAPPI_ABS" --lib-path lib --compile -o main.sbc main.scm > /dev/null 2>&1)

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

# Run bundled binary — the begin block must have executed (hash table initialized)
OUTPUT=$("$BUNDLE_BIN" 2>/dev/null)
if [[ "$OUTPUT" != "Hello, world!"$'\n'"#t" ]]; then
    echo "FAIL: standalone mode — expected 'Hello, world!' + '#t', got '$OUTPUT'" >&2
    exit 1
fi
