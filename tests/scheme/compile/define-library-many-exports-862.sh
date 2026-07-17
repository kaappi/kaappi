#!/bin/bash
# Regression test for #862: define-library silently drops exports beyond 128
# Creates a library with 200 exports, verifies all are importable.

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"
KAAPPI="${1:-zig-out/bin/kaappi}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Generate a library with 200 exports
mkdir -p "$TMPDIR/bigexport"
{
  echo '(define-library (bigexport big)'
  echo '  (import (scheme base))'
  printf '  (export'
  for i in $(seq 0 199); do printf ' proc-%d' "$i"; done
  echo ')'
  echo '  (begin'
  for i in $(seq 0 199); do
    echo "    (define (proc-$i x) (+ x $i))"
  done
  echo '))'
} > "$TMPDIR/bigexport/big.sld"

# Write the test script
cat > "$TMPDIR/test.scm" << 'SCHEME'
(import (scheme base) (scheme write) (bigexport big))
(define pass 0)
(define fail 0)
(define (check desc val expected)
  (if (equal? val expected)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display desc)
      (display " got ") (write val)
      (display " expected ") (write expected) (newline))))
(check "proc-0"   (proc-0 0) 0)
(check "proc-127" (proc-127 0) 127)
(check "proc-128" (proc-128 0) 128)
(check "proc-129" (proc-129 0) 129)
(check "proc-150" (proc-150 0) 150)
(check "proc-199" (proc-199 0) 199)
(check "proc-128(10)" (proc-128 10) 138)
(check "proc-199(1)"  (proc-199 1) 200)
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
SCHEME

"$KAAPPI" --lib-path "$TMPDIR" "$TMPDIR/test.scm"
