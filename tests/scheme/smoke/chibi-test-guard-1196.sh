#!/usr/bin/env bash
# Regression test for issue #1196:
# (chibi test) macro must catch exceptions from the test expression,
# count them as failures, and continue executing subsequent tests.
set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

output=$("$KAAPPI" /dev/stdin <<'EOF'
(import (scheme base) (chibi test))
(test-begin "exception-guard")
(test 1 (car '()))   ;; should count as failure, not crash
(test 2 (+ 1 1))
(test 3 (+ 1 2))
(test-end "exception-guard")
EOF
)

# Should report exactly 2 pass and 1 fail
if echo "$output" | grep -q "2 pass, 1 fail"; then
  echo "PASS: exception in test expression counted as failure"
else
  echo "FAIL: unexpected output:"
  echo "$output"
  exit 1
fi
