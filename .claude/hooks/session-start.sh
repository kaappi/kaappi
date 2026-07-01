#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

branch=$(git branch --show-current 2>/dev/null || echo "detached")
zig_ver=$(zig version 2>/dev/null || echo "not found")
printf 'Branch: %s | Zig: %s\n' "$branch" "$zig_ver"

if [ -d .claude/worktrees ]; then
  stale=$(find .claude/worktrees -maxdepth 1 -mindepth 1 -type d -mtime +7 2>/dev/null || true)
  if [ -n "$stale" ]; then
    count=$(echo "$stale" | wc -l | tr -d ' ')
    printf '⚠ %s stale worktree(s) (>7 days) in .claude/worktrees/\n' "$count"
  fi
fi

exit 0
