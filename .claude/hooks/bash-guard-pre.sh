#!/usr/bin/env bash
set -euo pipefail

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')

block() {
  printf '{"decision":"block","reason":"%s"}\n' "$1"
  exit 0
}

printf '%s' "$cmd" | grep -Eq 'rm\s+-rf\s+/' && block "rm -rf with root path"
printf '%s' "$cmd" | grep -Eq '(^|\s|;|&&|\|\|)sudo\s' && block "sudo usage"
printf '%s' "$cmd" | grep -Eq 'git\s+push\s.*--force' && block "git push --force"
printf '%s' "$cmd" | grep -Eq 'git\s+tag\s+-d' && block "git tag deletion"
printf '%s' "$cmd" | grep -Eq 'git\s+reset\s+--hard' && block "git reset --hard"

exit 0
