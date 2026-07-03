#!/bin/bash
# Regression test for #783: --sandbox as a script argument must not activate
# sandboxing. The pre-scan must stop at the filename boundary.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# A script that uses sandboxed-out procedures (open-output-file, command-line)
cat > "$tmpdir/writer.scm" <<'SCM'
(import (scheme base) (scheme write) (scheme file) (scheme process-context))
(define args (command-line))
(display args)
(newline)
SCM

# 1) --sandbox AFTER the filename is a script argument — must NOT sandbox
output=$("$KAAPPI" "$tmpdir/writer.scm" --sandbox 2>&1)
if echo "$output" | grep -qF -- "--sandbox"; then
    echo "PASS: --sandbox after filename passed through as script arg"
    PASS=$((PASS + 1))
else
    echo "FAIL: --sandbox after filename was not in (command-line) — output: $output"
    FAIL=$((FAIL + 1))
fi

# 2) --sandbox BEFORE the filename is an interpreter flag — must sandbox
output=$("$KAAPPI" --sandbox "$tmpdir/writer.scm" 2>&1 || true)
if echo "$output" | grep -qi "error"; then
    echo "PASS: --sandbox before filename activates sandboxing"
    PASS=$((PASS + 1))
else
    echo "FAIL: --sandbox before filename did not sandbox — output: $output"
    FAIL=$((FAIL + 1))
fi

echo
echo "Passed: $PASS / $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
