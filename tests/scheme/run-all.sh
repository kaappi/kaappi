#!/bin/bash
# Run all Kaappi Scheme test suites.
# Usage: bash tests/scheme/run-all.sh

set -e
KAAPPI="zig build run --"
PASS=0
FAIL=0
ERRORS=0

echo "=== Smoke tests ==="
for f in tests/scheme/smoke/*.scm; do
    if $KAAPPI "$f" > /dev/null 2>&1; then
        echo "  PASS  $f"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $f"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Compliance tests ==="
for f in tests/scheme/compliance/*.scm; do
    if $KAAPPI "$f" > /dev/null 2>&1; then
        echo "  PASS  $f"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $f"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Continuation tests ==="
for f in tests/scheme/continuations/*.scm; do
    if $KAAPPI "$f" > /dev/null 2>&1; then
        echo "  PASS  $f"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $f"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Hygiene tests ==="
for f in tests/scheme/hygiene/*.scm; do
    if $KAAPPI "$f" > /dev/null 2>&1; then
        echo "  PASS  $f"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $f"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== SRFI tests ==="
for f in tests/scheme/srfi/*.scm; do
    if $KAAPPI "$f" > /dev/null 2>&1; then
        echo "  PASS  $f"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $f"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== R7RS test suite (1,380 tests) ==="
R7RS_OUTPUT=$($KAAPPI tests/scheme/r7rs/r7rs-tests.scm 2>&1)
R7RS_PASS=$(echo "$R7RS_OUTPUT" | grep -oE '[0-9]+ pass' | awk '{s+=$1} END {print s+0}')
R7RS_FAIL=$(echo "$R7RS_OUTPUT" | grep -oE '[0-9]+ fail' | awk '{s+=$1} END {print s+0}')
echo "  $R7RS_PASS pass, $R7RS_FAIL fail"

echo ""
echo "=== Summary ==="
echo "  Scheme files: $PASS pass, $FAIL fail"
echo "  R7RS suite:   $R7RS_PASS pass, $R7RS_FAIL fail"
echo "  Total:        $((PASS + R7RS_PASS)) pass, $((FAIL + R7RS_FAIL)) fail"
