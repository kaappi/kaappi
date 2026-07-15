#!/usr/bin/env bash
# One-shot P1 access-semantics campaign: record environment, build via Kaappi's
# pipeline, collect vectorization evidence, then run the full Kalibera-Jones
# timing matrix. Produces results/<machine>-*.{csv,txt} for the report.
#
# Usage: run-all.sh <machine-label> [mode] [extra run-access.py args...]
#   mode = pilot | full   (default full)
set -euo pipefail
cd "$(dirname "$0")"

MACHINE="${1:?usage: run-all.sh <machine-label> [pilot|full] [extra args]}"
MODE="${2:-full}"
shift || true; shift || true

mkdir -p results
META="results/${MACHINE}-metadata.txt"
{
  echo "# P1 access-semantics campaign metadata"
  echo "machine_label: ${MACHINE}"
  echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "uname: $(uname -a)"
  echo "arch: $(uname -m)"
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "cpu: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
    echo "cores_physical: $(sysctl -n hw.physicalcpu 2>/dev/null || true)"
    echo "cores_logical: $(sysctl -n hw.logicalcpu 2>/dev/null || true)"
    echo "l1d_bytes: $(sysctl -n hw.l1dcachesize 2>/dev/null || true)"
    echo "l2_bytes: $(sysctl -n hw.l2cachesize 2>/dev/null || true)"
    echo "mem_bytes: $(sysctl -n hw.memsize 2>/dev/null || true)"
  else
    echo "cpu: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || true)"
    echo "cores_logical: $(nproc 2>/dev/null || true)"
    command -v lscpu >/dev/null 2>&1 && lscpu 2>/dev/null | grep -iE 'cache|model name|socket|core' | sed 's/^/lscpu: /' || true
    echo "mem_kb: $(grep -m1 MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || true)"
  fi
  echo "compiler: ${CC:-zig cc}"
  ( ${CC:-zig cc} --version 2>/dev/null | head -2 | sed 's/^/compiler_version: /' ) || true
  echo "zig_version: $(zig version 2>/dev/null || echo n/a)"
  echo "git_commit: $(git rev-parse HEAD 2>/dev/null || echo n/a)"
  echo "pipeline_flags: -w -O2   (src/native_compiler.zig tryLink)"
} | tee "$META"
echo

echo "== build =="
bash build.sh
echo
echo "== vectorization evidence =="
bash evidence.sh results
echo
echo "== timing matrix (mode=$MODE) =="
python3 run-access.py --mode "$MODE" --machine "$MACHINE" \
  --out "results/${MACHINE}-access.csv" "$@" | tee "results/${MACHINE}-table.txt"
echo
echo "artifacts in results/ for machine=${MACHINE}"
