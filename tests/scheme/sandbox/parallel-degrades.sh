#!/bin/bash
# KEP-0002 Phase 5 (#1470): (kaappi parallel) degradation tests.
#
# --sandbox blocks real OS threads (srfi_18.sandboxAllowed() is false), and
# blocks every file-backed library load outright (vm_library.zig's
# tryLoadLibraryFromFile) -- a plain portable .sld would be unimportable
# there at all. (kaappi parallel) stays importable because its source is
# also embedded directly into the binary (vm_library.zig's
# embedded_libraries table); once imported, its own
# (cond-expand ((library (srfi 18)) ...) (else ...)) sees srfi 18
# unavailable under sandbox and takes the fiber-degraded make-pool branch --
# the same branch WASM takes, for the same reason. This script is the
# practical way to exercise that branch on this machine: native default
# builds always have real threads, and there's no wasm32-wasi runtime here.
#
# Exit 0 = pools degrade correctly under --sandbox. Any failure = exit 1.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

assert_output() {
    local label="$1"
    local expr="$2"
    local expected="$3"
    local output
    output=$(echo "$expr" | "$KAAPPI" --sandbox 2>&1 || true)
    if [ "$output" = "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected', got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_blocked() {
    local label="$1"
    local expr="$2"
    local output
    output=$(echo "$expr" | "$KAAPPI" --sandbox 2>&1 || true)
    if echo "$output" | grep -qi "error"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — no error produced, output: $output"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== (kaappi parallel) sandbox degradation tests ==="
echo

assert_output "processor-count is 1 under --sandbox" \
    '(display (processor-count))' \
    "1"

assert_output "(kaappi parallel) imports under --sandbox" \
    '(import (kaappi parallel)) (display (procedure? make-pool))' \
    "#t"

assert_output "make-pool/pool-submit/task-wait round trip over fiber workers" \
    '(import (scheme base) (kaappi parallel))
     (define pool (make-pool 3))
     (define reply (pool-submit pool (lambda () (* 6 7))))
     (display (task-wait reply))
     (pool-shutdown! pool)' \
    "42"

assert_output "parallel-map over fiber workers preserves order" \
    '(import (scheme base) (kaappi parallel))
     (display (parallel-map (lambda (x) (* x x)) (list 1 2 3 4 5)))' \
    "(1 4 9 16 25)"

assert_blocked "a task exception still propagates through task-wait" \
    '(import (scheme base) (kaappi parallel))
     (define pool (make-pool 2))
     (define reply (pool-submit pool (lambda () (error "boom"))))
     (task-wait reply)
     (pool-shutdown! pool)'

assert_blocked "pool-submit after shutdown still raises" \
    '(import (scheme base) (kaappi parallel))
     (define pool (make-pool 1))
     (pool-shutdown! pool)
     (pool-submit pool (lambda () 1))'

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "PARALLEL POOL SANDBOX DEGRADATION FAILED"
    exit 1
fi

echo "(kaappi parallel) degrades correctly under --sandbox."
exit 0
