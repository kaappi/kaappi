#!/bin/bash
# Kaappi benchmark runner
# Runs all benchmark programs and outputs results in machine-readable format.
#
# Usage: bash benchmarks/run-benchmarks.sh [--json]
#
# Without --json: human-readable table
# With --json: JSON array for CI consumption

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
JSON_MODE=false
TIMEOUT=120

# Use gtimeout on macOS (from coreutils), timeout on Linux, or skip
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout $TIMEOUT"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout $TIMEOUT"
else
    TIMEOUT_CMD=""
fi

if [ "${1:-}" = "--json" ]; then
    JSON_MODE=true
fi

BENCHMARKS=(
    "fib:benchmarks/fib.scm:benchmarks/fib.input"
    "nqueens:benchmarks/nqueens.scm:benchmarks/nqueens.input"
    "primes:benchmarks/primes.scm:benchmarks/primes.input"
    "tak:benchmarks/tak.scm:benchmarks/tak.input"
    "string:benchmarks/string.scm:benchmarks/string.input"
    "list:benchmarks/list.scm:benchmarks/list.input"
    "vector:benchmarks/vector.scm:benchmarks/vector.input"
    "hashtable:benchmarks/hashtable.scm:benchmarks/hashtable.input"
    "continuations:benchmarks/continuations.scm:benchmarks/continuations.input"
    "tailcall:benchmarks/tailcall.scm:benchmarks/tailcall.input"
    "closures:benchmarks/closures.scm:benchmarks/closures.input"
    "bignum:benchmarks/bignum.scm:benchmarks/bignum.input"
    "gc-pressure:benchmarks/gc-pressure.scm:benchmarks/gc-pressure.input"
)

extract_field() {
    local output="$1" field="$2"
    echo "$output" | sed -n "s/.*${field}: \([^ ,]*\).*/\1/p" | head -1
}

run_bench() {
    local name="$1" scm="$2" input="$3"
    local output
    output=$($TIMEOUT_CMD "$KAAPPI" --gc-stats "$scm" < "$input" 2>&1 || true)
    # Parse new common.scm output:
    # name: <name>, time: <median>, status: <ok|fail>, min: <min>, max: <max>, iterations: <n>
    local time_str status min_str max_str iterations
    time_str=$(extract_field "$output" "time")
    status=$(extract_field "$output" "status")
    min_str=$(extract_field "$output" "min")
    max_str=$(extract_field "$output" "max")
    iterations=$(extract_field "$output" "iterations")
    # Extract GC metrics from --gc-stats stderr output
    local gc_collections gc_live gc_heap
    gc_collections=$(echo "$output" | grep "Collections:" | grep -oE '[0-9]+' | head -1 || echo "0")
    gc_live=$(echo "$output" | grep "Live objects:" | grep -oE '[0-9]+' | head -1 || echo "0")
    gc_heap=$(echo "$output" | grep "Heap size:" | grep -oE '[0-9]+' | head -1 || echo "0")
    echo "$name ${time_str:-0} ${status:-fail} ${min_str:-0} ${max_str:-0} ${iterations:-0} ${gc_collections:-0} ${gc_live:-0} ${gc_heap:-0}"
}

# Run zig build bench (call/cc micro-benchmark)
run_callcc_bench() {
    local output
    output=$($TIMEOUT_CMD zig build bench 2>&1 || true)

    local cc_line ec_line
    cc_line=$(echo "$output" | grep "^name: call_cc," || true)
    ec_line=$(echo "$output" | grep "^name: call_ec," || true)

    local cc_time cc_status ec_time ec_status
    cc_time=$(extract_field "$cc_line" "time")
    cc_status=$(extract_field "$cc_line" "status")
    ec_time=$(extract_field "$ec_line" "time")
    ec_status=$(extract_field "$ec_line" "status")

    echo "call_cc ${cc_time:-0} ${cc_status:-fail} 0 0 1 0 0 0"
    echo "call_ec ${ec_time:-0} ${ec_status:-fail} 0 0 1 0 0 0"
}

# Collect results
results=()

for spec in "${BENCHMARKS[@]}"; do
    IFS=: read -r name scm input <<< "$spec"
    result=$(run_bench "$name" "$scm" "$input")
    results+=("$result")
done

# Add call/cc bench
while IFS= read -r line; do
    results+=("$line")
done < <(run_callcc_bench)

# Output
if $JSON_MODE; then
    echo "["
    first=true
    for r in "${results[@]}"; do
        read -r name value status mn mx iterations gc_coll gc_live gc_heap <<< "$r"
        if $first; then first=false; else echo ","; fi
        # Ensure value fields are valid numbers
        if ! [[ "${value:-0}" =~ ^[0-9]*\.?[0-9]+$ ]]; then value="0"; fi
        if ! [[ "${mn:-0}" =~ ^[0-9]*\.?[0-9]+$ ]]; then mn="0"; fi
        if ! [[ "${mx:-0}" =~ ^[0-9]*\.?[0-9]+$ ]]; then mx="0"; fi
        printf '  {"name": "%s", "unit": "seconds", "value": %s, "min": %s, "max": %s, "iterations": %s, "status": "%s", "gc_collections": %s, "gc_live_objects": %s, "gc_heap_bytes": %s}' \
            "$name" "${value:-0}" "${mn:-0}" "${mx:-0}" "${iterations:-0}" "${status:-fail}" "${gc_coll:-0}" "${gc_live:-0}" "${gc_heap:-0}"
    done
    echo
    echo "]"
else
    printf "%-12s %10s %10s %10s  %-4s  %5s  %6s  %10s\n" "Benchmark" "Median" "Min" "Max" "OK?" "GC#" "Live" "Heap"
    printf "%-12s %10s %10s %10s  %-4s  %5s  %6s  %10s\n" "---------" "------" "---" "---" "---" "---" "----" "----"
    for r in "${results[@]}"; do
        read -r name value status mn mx iterations gc_coll gc_live gc_heap <<< "$r"
        printf "%-12s %9ss %9ss %9ss  %-4s  %5s  %6s  %10s\n" "$name" "${value:-?}" "${mn:-?}" "${mx:-?}" "${status:-?}" "${gc_coll:--}" "${gc_live:--}" "${gc_heap:--}"
    done
fi

# Fail if any benchmark failed verification
if printf '%s\n' "${results[@]}" | grep -qw 'fail'; then
    echo "ERROR: One or more benchmarks failed verification:" >&2
    for r in "${results[@]}"; do
        read -r name value status _ <<< "$r"
        if [ "$status" = "fail" ]; then
            echo "  FAIL: $name (value=$value)" >&2
        fi
    done
    exit 1
fi
