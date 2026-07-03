#!/bin/bash
# Run all Kaappi Scheme test suites.
# Usage: bash tests/scheme/run-all.sh

set -euo pipefail

# Use pre-built binary if available, otherwise build once.
if [[ ! -x zig-out/bin/kaappi ]]; then
    zig build
fi
KAAPPI=zig-out/bin/kaappi

TIMEOUT=60
PASS=0
FAIL=0
TIMEDOUT=0
R7RS_PASS=0
R7RS_FAIL=0
R7RS_STATUS_FAIL=0

run_file() {
    local file="$1"
    local output pid status
    "$KAAPPI" "$file" > /tmp/kaappi-test-out 2>&1 &
    pid=$!
    if wait_with_timeout "$pid" "$TIMEOUT"; then
        status=0
        wait "$pid" || status=$?
    else
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        echo "  TIMEOUT  $file  (killed after ${TIMEOUT}s)"
        cat /tmp/kaappi-test-out
        TIMEDOUT=$((TIMEDOUT + 1))
        return
    fi
    if [[ $status -eq 0 ]]; then
        echo "  PASS  $file"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $file"
        cat /tmp/kaappi-test-out
        FAIL=$((FAIL + 1))
    fi
}

wait_with_timeout() {
    local pid=$1 secs=$2 elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [[ $elapsed -ge $secs ]]; then return 1; fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 0
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
run_suite "Audit tests" tests/scheme/audit/*.scm

echo "=== Compile tests ==="
for test_script in tests/scheme/compile/*.sh; do
    if [[ -x "$test_script" ]]; then
        set +e
        bash "$test_script" "$KAAPPI" > /tmp/kaappi-test-out 2>&1
        status=$?
        set -e
        if [[ $status -eq 0 ]]; then
            echo "  PASS  $test_script"
            PASS=$((PASS + 1))
        else
            echo "  FAIL  $test_script"
            cat /tmp/kaappi-test-out
            FAIL=$((FAIL + 1))
        fi
    fi
done
echo ""

echo "=== R7RS test suite ==="
set +e
# Capture stdout and stderr separately to preserve panic messages
"$KAAPPI" tests/scheme/r7rs/r7rs-tests.scm > /tmp/kaappi-r7rs-stdout 2> /tmp/kaappi-r7rs-stderr
R7RS_STATUS=$?
R7RS_OUTPUT="$(cat /tmp/kaappi-r7rs-stdout /tmp/kaappi-r7rs-stderr)"
set -e

R7RS_PASS=$(printf "%s\n" "$R7RS_OUTPUT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "pass") s += $i }} END {print s + 0}')
R7RS_FAIL=$(printf "%s\n" "$R7RS_OUTPUT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "fail") s += $i }} END {print s + 0}')
echo "  $R7RS_PASS pass, $R7RS_FAIL fail"
if [[ $R7RS_STATUS -ne 0 ]]; then
    echo "  FAIL  tests/scheme/r7rs/r7rs-tests.scm (exit $R7RS_STATUS)"
    echo "--- stderr output ---"
    cat /tmp/kaappi-r7rs-stderr 2>/dev/null || true
    echo "--- last 20 lines stdout ---"
    tail -20 /tmp/kaappi-r7rs-stdout 2>/dev/null || true
    echo "--- end crash context ---"
    # Retry without JIT to isolate JIT-related crashes
    echo "  Retrying with --no-jit..."
    set +e
    R7RS_NOJIT="$("$KAAPPI" --no-jit tests/scheme/r7rs/r7rs-tests.scm 2>&1)"
    R7RS_NOJIT_STATUS=$?
    set -e
    R7RS_NOJIT_PASS=$(printf "%s\n" "$R7RS_NOJIT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "pass") s += $i }} END {print s + 0}')
    echo "  --no-jit: $R7RS_NOJIT_PASS pass (exit $R7RS_NOJIT_STATUS)"
    if [[ $R7RS_NOJIT_STATUS -ne 0 ]]; then
        printf "%s\n" "$R7RS_NOJIT" | tail -40
    fi
    R7RS_STATUS_FAIL=1
fi

echo ""
echo "=== Summary ==="
echo "  Scheme files: $PASS pass, $FAIL fail, $TIMEDOUT timeout"
echo "  R7RS suite:   $R7RS_PASS pass, $R7RS_FAIL fail"
echo "  Total:        $((PASS + R7RS_PASS)) pass, $((FAIL + R7RS_FAIL + R7RS_STATUS_FAIL + TIMEDOUT)) fail ($TIMEDOUT from timeouts)"

if [[ $FAIL -gt 0 || $TIMEDOUT -gt 0 || $R7RS_FAIL -gt 0 || $R7RS_STATUS_FAIL -gt 0 ]]; then
    exit 1
fi
