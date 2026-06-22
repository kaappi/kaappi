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
)

run_bench() {
    local name="$1" scm="$2" input="$3"
    local output
    output=$("$KAAPPI" "$scm" < "$input" 2>/dev/null || true)
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
    echo "$name $seconds $status"
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
        read -r name seconds status <<< "$r"
        if $first; then first=false; else echo ","; fi
        # Ensure seconds is a valid number
        if ! [[ "${seconds:-0}" =~ ^[0-9]*\.?[0-9]+$ ]]; then seconds="0"; fi
        printf '  {"name": "%s", "seconds": %s, "status": "%s"}' "$name" "${seconds:-0}" "${status:-fail}"
    done
    echo
    echo "]"
else
    printf "%-12s %10s  %s\n" "Benchmark" "Time" "Status"
    printf "%-12s %10s  %s\n" "---------" "----" "------"
    for r in "${results[@]}"; do
        read -r name seconds status <<< "$r"
        printf "%-12s %9ss  %s\n" "$name" "${seconds:-?}" "$status"
    done
fi
