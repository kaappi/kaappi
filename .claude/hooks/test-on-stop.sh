#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

modified=$(git diff --name-only HEAD 2>/dev/null | grep '\.zig$' || true)
staged=$(git diff --cached --name-only 2>/dev/null | grep '\.zig$' || true)

if [[ -z "$modified" && -z "$staged" ]]; then
  exit 0
fi

if output=$(timeout 120 zig build test 2>&1); then
  exit 0
else
  tail_output=$(printf '%s' "$output" | tail -30)
  printf '{"decision":"block","reason":"Unit tests failed:\\n%s"}\n' "$tail_output"
fi
