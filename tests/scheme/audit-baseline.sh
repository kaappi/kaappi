#!/bin/bash
# audit-baseline.sh — structured failure report
set -uo pipefail
OUT=${1:-/tmp/audit-baseline}
mkdir -p "$OUT"

# Portable timeout: GNU coreutils `timeout` is absent on stock macOS.
if command -v timeout >/dev/null 2>&1; then
  run_timeout() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then
  run_timeout() { gtimeout "$@"; }
else
  run_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }
fi

echo "=== Unit Tests ==="
zig build test 2>&1 | tee "$OUT/unit-tests.log"

echo "=== R7RS Suite ==="
zig build run -- tests/scheme/r7rs/r7rs-tests.scm 2>&1 | tee "$OUT/r7rs.log"

echo "=== Scheme Suites ==="
bash tests/scheme/run-all.sh 2>&1 | tee "$OUT/all-suites.log"

echo "=== SRFI Tests (individually, with fail counts) ==="
for f in tests/scheme/srfi/*.scm; do
  echo "--- $(basename "$f") ---"
  run_timeout 30 zig-out/bin/kaappi "$f" 2>&1 | tail -3
done | tee "$OUT/srfi-tests.log"

echo "=== Summary ==="
grep -E "(FAIL|ERROR|TIMEOUT)" "$OUT"/*.log | sort | uniq -c | sort -rn
