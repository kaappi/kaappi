#!/bin/bash
# Verify --version outputs the version from build.zig.zon

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
expected=$(grep '\.version' build.zig.zon | sed 's/.*"\(.*\)".*/\1/')
output=$("$KAAPPI" --version 2>&1)

if echo "$output" | grep -qF "$expected"; then
    echo "PASS: --version contains $expected"
else
    echo "FAIL: expected '$expected' in output: $output"
    exit 1
fi
