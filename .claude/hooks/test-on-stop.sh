#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

modified=$(git diff --name-only HEAD 2>/dev/null | grep '\.zig$' || true)
staged=$(git diff --cached --name-only 2>/dev/null | grep '\.zig$' || true)

if [[ -z "$modified" && -z "$staged" ]]; then
  exit 0
fi

if command -v timeout &>/dev/null; then
  test_cmd="timeout 120 zig build test"
elif command -v gtimeout &>/dev/null; then
  test_cmd="gtimeout 120 zig build test"
else
  test_cmd="zig build test"
fi

if output=$($test_cmd 2>&1); then
  exit 0
else
  tail_output=$(printf '%s' "$output" | tail -30)
  printf '{"decision":"block","reason":"Unit tests failed:\\n%s"}\n' "$tail_output"
fi
