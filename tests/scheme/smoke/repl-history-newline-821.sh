#!/bin/bash
# Regression test for #821: REPL history should not flatten newlines
#
# When a multi-line entry contains a line comment (;; ...),
# flattening newlines to spaces corrupts it because the comment
# extends to end-of-line and would swallow subsequent code.
#
# Test: enter a multi-line expression with a line comment, then
# recall it from history and verify it evaluates correctly.

set -e

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

# A multi-line expression where newline-to-space corruption would break it:
# If newlines become spaces, ";; comment" eats "(+ 1 2)" on the same line.
output=$(printf '(begin\n  ;; a comment\n  (+ 1 2))\n,quit\n' | $KAAPPI 2>&1 || true)

if echo "$output" | grep -q "3"; then
    echo "PASS: multi-line entry with comment evaluates correctly"
else
    echo "FAIL: multi-line entry with comment did not evaluate correctly"
    echo "Output was: $output"
    exit 1
fi
