#!/usr/bin/env bash
# Interpreter-tier control (memo §9.4): build the dispatch-model primitives via
# Kaappi's pipeline, show plain and unordered scalar access are the same
# instruction, time the plain-vs-unordered dispatch-model delta, and (if a
# kaappi binary is given) report the real bytevector-u8-ref/-set! dispatch cost.
#
# Usage: run-interp.sh [kaappi-binary]
set -euo pipefail
cd "$(dirname "$0")"
CC="${CC:-zig cc}"

OD=""
for cand in llvm-objdump /opt/homebrew/opt/llvm/bin/llvm-objdump objdump; do
  command -v "$cand" >/dev/null 2>&1 && { OD="$cand"; break; }
done

echo "== build dispatch-model (zig cc -w -O2, no LTO) =="
$CC -w -O2 -c dispatch_bench.c -o dispatch_bench.o
for enc in plain unordered; do
  $CC -w -O2 -c "prim_${enc}.ll" -o "prim_${enc}.o"
  $CC -w -O2 dispatch_bench.o "prim_${enc}.o" -o "dispatch_${enc}"
done

echo
echo "== instruction-level evidence: prim_ref / prim_set access =="
echo "-- PLAIN --";     [ -n "$OD" ] && $OD -d prim_plain.o     | grep -iE 'ldr|str|ldrb|strb|ret|b\.' | head -20
echo "-- UNORDERED --"; [ -n "$OD" ] && $OD -d prim_unordered.o | grep -iE 'ldr|str|ldrb|strb|ret|b\.' | head -20

echo
echo "== dispatch-model timing (plain vs unordered) =="
python3 run-interp.py

if [ "${1:-}" != "" ] && [ -x "${1:-}" ]; then
  echo
  echo "== real kaappi primitive throughput =="
  "$1" kaappi_prim.scm || echo "(kaappi run failed; skipping)"
fi
