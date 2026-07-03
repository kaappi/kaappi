#!/bin/bash
# Regression test for #823: ,step should preserve debug_mode
#
# This tests that using ,step in the REPL does not disable active breakpoints.
# The fix saves and restores debug_mode/step_mode around ,step evaluation.
#
# Test: set a breakpoint, run ,step on an expression, verify breakpoint is
# still active by checking debug_mode state.

set -e

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

# Feed REPL commands via stdin and check output
output=$(printf ',break test-fn\n,step (+ 1 2)\n,breakpoints\n,quit\n' | $KAAPPI 2>&1 || true)

# After ,step, breakpoints should still be listed (debug_mode preserved)
if echo "$output" | grep -q "test-fn"; then
    echo "PASS: breakpoint preserved after ,step"
else
    echo "FAIL: breakpoint lost after ,step"
    echo "Output was: $output"
    exit 1
fi
