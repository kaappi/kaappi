#!/bin/bash
# Run all Kaappi Scheme test suites.
# Usage: bash tests/scheme/run-all.sh

set -euo pipefail

KAAPPI=(zig build run --)
PASS=0
FAIL=0
R7RS_PASS=0
R7RS_FAIL=0
R7RS_STATUS_FAIL=0

run_file() {
    local file="$1"
    local output
    if output="$("${KAAPPI[@]}" "$file" 2>&1)"; then
        echo "  PASS  $file"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $file"
        echo "$output"
        FAIL=$((FAIL + 1))
    fi
}

run_suite() {
    local title="$1"
    shift
    local matched=0
    echo "=== $title ==="
    for pattern in "$@"; do
        for file in $pattern; do
            if [[ -e "$file" ]]; then
                matched=1
                run_file "$file"
            fi
        done
    done
    if [[ $matched -eq 0 ]]; then
        echo "  (no tests matched)"
    fi
    echo ""
}

run_suite "Smoke tests" tests/scheme/smoke/*.scm
run_suite "Compliance tests" tests/scheme/compliance/*.scm
run_suite "Continuation tests" tests/scheme/continuations/*.scm
run_suite "Hygiene tests" tests/scheme/hygiene/*.scm
run_suite "SRFI tests" tests/scheme/srfi/*.scm
run_suite "FFI tests" tests/scheme/ffi/*.scm

echo "=== R7RS test suite (1,380 tests) ==="
set +e
R7RS_OUTPUT="$("${KAAPPI[@]}" tests/scheme/r7rs/r7rs-tests.scm 2>&1)"
R7RS_STATUS=$?
set -e

R7RS_PASS=$(printf "%s\n" "$R7RS_OUTPUT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "pass") s += $i }} END {print s + 0}')
R7RS_FAIL=$(printf "%s\n" "$R7RS_OUTPUT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "fail") s += $i }} END {print s + 0}')
echo "  $R7RS_PASS pass, $R7RS_FAIL fail"
if [[ $R7RS_STATUS -ne 0 ]]; then
    echo "  FAIL  tests/scheme/r7rs/r7rs-tests.scm (non-zero exit)"
    R7RS_STATUS_FAIL=1
fi

echo ""
echo "=== Summary ==="
echo "  Scheme files: $PASS pass, $FAIL fail"
echo "  R7RS suite:   $R7RS_PASS pass, $R7RS_FAIL fail"
echo "  Total:        $((PASS + R7RS_PASS)) pass, $((FAIL + R7RS_FAIL + R7RS_STATUS_FAIL)) fail"

if [[ $FAIL -gt 0 || $R7RS_FAIL -gt 0 || $R7RS_STATUS_FAIL -gt 0 ]]; then
    exit 1
fi
