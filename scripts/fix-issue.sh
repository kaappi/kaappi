#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <issue-number>" >&2
    exit 1
fi

issue="$1"
branch="fix/$issue"
worktree=".claude/worktrees/fix-$issue"

git worktree add "$worktree" -b "$branch" main
cd "$worktree"
exec claude --permission-mode bypassPermissions --effort max "Work on GitHub issue #$issue"
