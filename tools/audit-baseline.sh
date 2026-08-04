#!/bin/bash
# audit-baseline.sh — structured failure report (docs/audit-strategy.md).
#
# A developer report generator, not a test: it drives `zig build` and writes a
# directory of logs, so it needs a Zig toolchain and takes an *output
# directory* as $1 — the opposite of every driver under tests/scheme/, which
# takes the kaappi binary there and reports pass/fail through its exit status.
#
# It lives in tools/ for exactly that reason. While it sat at the top level of
# tests/scheme/ nothing in run-all.sh ran it (run_shell_suite globs a suite
# *directory*, and no call passed tests/scheme itself) — but any sweep of
# tests/scheme/**/*.sh picked it up, handed it the binary path, and got
# `mkdir -p zig-out/bin/kaappi.exe` followed by a summary grep against a
# path that is not a directory.
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
