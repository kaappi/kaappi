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
)

run_bench() {
    local name="$1" scm="$2" input="$3"
    local output
    output=$("$KAAPPI" --gc-stats "$scm" < "$input" 2>&1 || true)
    # Extract timing from output like "fib(35): 1.234s [OK]"
    local time_str
    time_str=$(echo "$output" | grep -oE '[0-9]+\.[0-9]+s' | head -1 || true)
    local status
    if echo "$output" | grep -q '\[OK\]'; then
        status="ok"
    else
        status="fail"
    fi
    local seconds="${time_str%s}"
    # Extract GC metrics
    local gc_collections gc_live gc_heap
    gc_collections=$(echo "$output" | grep "Collections:" | grep -oE '[0-9]+' | head -1 || echo "0")
    gc_live=$(echo "$output" | grep "Live objects:" | grep -oE '[0-9]+' | head -1 || echo "0")
    gc_heap=$(echo "$output" | grep "Heap size:" | grep -oE '[0-9]+' | head -1 || echo "0")
    echo "$name $seconds $status $gc_collections $gc_live $gc_heap"
}

# Run zig build bench (call/cc micro-benchmark)
run_callcc_bench() {
    local output
    output=$(zig build bench 2>&1 || true)
    # Extract timing from bench output
    local callcc_time callec_time
    callcc_time=$(echo "$output" | grep "call/cc" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")
    callec_time=$(echo "$output" | grep "call/ec" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")
    echo "call_cc $callcc_time ok"
    echo "call_ec $callec_time ok"
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
        read -r name seconds status gc_coll gc_live gc_heap <<< "$r"
        if $first; then first=false; else echo ","; fi
        # Ensure seconds is a valid number
        if ! [[ "${seconds:-0}" =~ ^[0-9]*\.?[0-9]+$ ]]; then seconds="0"; fi
        printf '  {"name": "%s", "seconds": %s, "status": "%s", "gc_collections": %s, "gc_live_objects": %s, "gc_heap_bytes": %s}' \
            "$name" "${seconds:-0}" "${status:-fail}" "${gc_coll:-0}" "${gc_live:-0}" "${gc_heap:-0}"
    done
    echo
    echo "]"
else
    printf "%-12s %10s  %-4s  %5s  %6s  %10s\n" "Benchmark" "Time" "OK?" "GC#" "Live" "Heap"
    printf "%-12s %10s  %-4s  %5s  %6s  %10s\n" "---------" "----" "---" "---" "----" "----"
    for r in "${results[@]}"; do
        read -r name seconds status gc_coll gc_live gc_heap <<< "$r"
        printf "%-12s %9ss  %-4s  %5s  %6s  %10s\n" "$name" "${seconds:-?}" "${status:-?}" "${gc_coll:--}" "${gc_live:--}" "${gc_heap:--}"
    done
fi
