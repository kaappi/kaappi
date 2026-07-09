#!/bin/bash
# Run all Kaappi Scheme test suites.
# Usage: bash tests/scheme/run-all.sh

set -euo pipefail

# Use pre-built binary if available, otherwise build once.
if [[ ! -x zig-out/bin/kaappi ]]; then
    zig build
fi
KAAPPI=zig-out/bin/kaappi

TMPOUT=$(mktemp /tmp/kaappi-test-XXXXXX)
TMPSTDOUT=$(mktemp /tmp/kaappi-r7rs-stdout-XXXXXX)
TMPSTDERR=$(mktemp /tmp/kaappi-r7rs-stderr-XXXXXX)
trap 'rm -f "$TMPOUT" "$TMPSTDOUT" "$TMPSTDERR"' EXIT

TIMEOUT="${KAAPPI_TEST_TIMEOUT:-60}"
PASS=0
FAIL=0
TIMEDOUT=0
SKIPPED=0

# Space-separated basenames to skip (e.g. KAAPPI_TEST_SKIP="callcc-bench.scm foo.scm")
SKIP="${KAAPPI_TEST_SKIP:-}"

should_skip() {
    local base
    base=$(basename "$1")
    for s in $SKIP; do
        if [[ "$base" == "$s" ]]; then return 0; fi
    done
    return 1
}
R7RS_PASS=0
R7RS_FAIL=0
R7RS_STATUS_FAIL=0

run_file() {
    local file="$1"
    local output pid status
    "$KAAPPI" "$file" > "$TMPOUT" 2>&1 &
    pid=$!
    if wait_with_timeout "$pid" "$TIMEOUT"; then
        status=0
        wait "$pid" || status=$?
    else
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        echo "  TIMEOUT  $file  (killed after ${TIMEOUT}s)"
        cat "$TMPOUT"
        TIMEDOUT=$((TIMEDOUT + 1))
        return
    fi
    if [[ $status -eq 0 ]]; then
        # chibi-test files exit 0 even when assertions fail (the shim's
        # "N pass, M fail" summary is the only signal), and SRFI-64 files
        # rely on their own exit-on-fail epilogue. Trust the printed
        # counts, not just the exit code.
        if grep -Eq '(^|[^0-9])[1-9][0-9]* fail|unexpected (failures|errors) +[1-9]' "$TMPOUT"; then
            echo "  FAIL  $file  (failing assertions reported despite exit 0)"
            cat "$TMPOUT"
            FAIL=$((FAIL + 1))
        else
            echo "  PASS  $file"
            PASS=$((PASS + 1))
        fi
    else
        echo "  FAIL  $file"
        cat "$TMPOUT"
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
                if should_skip "$file"; then
                    echo "  SKIP  $file"
                    SKIPPED=$((SKIPPED + 1))
                    matched=1
                    continue
                fi
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

run_shell_suite() {
    local title="$1" dir="$2"
    local matched=0
    echo "=== $title ==="
    for test_script in "$dir"/*.sh; do
        [[ -e "$test_script" ]] || continue
        if [[ ! -x "$test_script" ]]; then
            echo "  FAIL  $test_script  (not executable)"
            FAIL=$((FAIL + 1))
            continue
        fi
        matched=1
        set +e
        KAAPPI="$KAAPPI" bash "$test_script" "$KAAPPI" > "$TMPOUT" 2>&1
        status=$?
        set -e
        if [[ $status -eq 0 ]]; then
            echo "  PASS  $test_script"
            PASS=$((PASS + 1))
        else
            echo "  FAIL  $test_script"
            cat "$TMPOUT"
            FAIL=$((FAIL + 1))
        fi
    done
    if [[ $matched -eq 0 ]]; then
        echo "  (no tests matched)"
    fi
    echo ""
}

run_suite "Smoke tests" tests/scheme/smoke/*.scm
run_shell_suite "Smoke shell tests" tests/scheme/smoke
run_suite "Compliance tests" tests/scheme/compliance/*.scm
run_suite "Continuation tests" tests/scheme/continuations/*.scm
run_suite "Hygiene tests" tests/scheme/hygiene/*.scm
run_suite "SRFI tests" tests/scheme/srfi/*.scm
run_suite "FFI tests" tests/scheme/ffi/*.scm
run_suite "Audit tests" tests/scheme/audit/*.scm
run_shell_suite "Error tests" tests/scheme/errors
run_shell_suite "Compile tests" tests/scheme/compile

echo "=== R7RS test suite ==="
set +e
"$KAAPPI" tests/scheme/r7rs/r7rs-tests.scm > "$TMPSTDOUT" 2> "$TMPSTDERR"
R7RS_STATUS=$?
R7RS_OUTPUT="$(cat "$TMPSTDOUT" "$TMPSTDERR")"
set -e

R7RS_PASS=$(printf "%s\n" "$R7RS_OUTPUT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "pass") s += $i }} END {print s + 0}')
R7RS_FAIL=$(printf "%s\n" "$R7RS_OUTPUT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "fail") s += $i }} END {print s + 0}')
echo "  $R7RS_PASS pass, $R7RS_FAIL fail"
if [[ $R7RS_STATUS -ne 0 ]]; then
    echo "  FAIL  tests/scheme/r7rs/r7rs-tests.scm (exit $R7RS_STATUS)"
    echo "--- stderr output ---"
    cat "$TMPSTDERR" 2>/dev/null || true
    echo "--- last 20 lines stdout ---"
    tail -20 "$TMPSTDOUT" 2>/dev/null || true
    echo "--- end crash context ---"
    R7RS_STATUS_FAIL=1
fi

echo ""
echo "=== Summary ==="
echo "  Scheme files: $PASS pass, $FAIL fail, $TIMEDOUT timeout, $SKIPPED skipped"
echo "  R7RS suite:   $R7RS_PASS pass, $R7RS_FAIL fail"
echo "  Total:        $((PASS + R7RS_PASS)) pass, $((FAIL + R7RS_FAIL + R7RS_STATUS_FAIL + TIMEDOUT)) fail ($TIMEDOUT from timeouts, $SKIPPED skipped)"

if [[ $FAIL -gt 0 || $TIMEDOUT -gt 0 || $R7RS_FAIL -gt 0 || $R7RS_STATUS_FAIL -gt 0 ]]; then
    exit 1
fi
