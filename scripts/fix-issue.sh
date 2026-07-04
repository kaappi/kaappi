#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <issue-number>" >&2
    exit 1
fi

issue="$1"
branch="fix/$issue"
worktree=".claude/worktrees/fix-$issue"

if [ -d "$worktree" ]; then
    echo "Reusing existing worktree at $worktree"
else
    git worktree add "$worktree" -b "$branch" main 2>/dev/null \
        || git worktree add "$worktree" "$branch"
fi
cd "$worktree"
exec claude --permission-mode bypassPermissions --effort max "Work on GitHub issue #$issue"
