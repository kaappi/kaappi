#!/usr/bin/env bash
set -euo pipefail

payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')

[[ -z "$path" || "$path" != *.zig ]] && exit 0

if ! zig fmt "$path" >/dev/null 2>&1; then
  fmt_err=$(zig fmt "$path" 2>&1 || true)
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"zig fmt failed on %s:\\n%s"}}\n' "$path" "$fmt_err"
fi
