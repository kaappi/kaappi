#!/usr/bin/env bash
# Build the P1 access-semantics kernel binaries with Kaappi's exact native
# pipeline: `zig cc -w -O2` (the flags in src/native_compiler.zig:tryLink).
# One binary per (kernel, encoding) = driver.o + <kernel>_<encoding>.o, linked
# with no LTO so each kernel's -O2 codegen is preserved verbatim.
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-zig cc}"
CFLAGS="-w -O2"

echo "# pipeline: $CC $CFLAGS   (matches src/native_compiler.zig)"
$CC --version 2>/dev/null | head -1 || true

python3 gen_kernels.py

mkdir -p obj bin
# Common driver object, compiled once and shared across all links.
$CC $CFLAGS -c driver.c -o obj/driver.o

count=0
for ll in kernels/*.ll; do
  base="$(basename "$ll" .ll)"          # e.g. f64_map_unordered
  $CC $CFLAGS -c "$ll" -o "obj/${base}.o"
  $CC $CFLAGS obj/driver.o "obj/${base}.o" -o "bin/${base}"
  count=$((count + 1))
done
echo "built $count binaries into bin/"
