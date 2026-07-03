---
description: Group open GitHub issues into parallel sets for concurrent Claude Code sessions. Use when the user asks to batch issues, plan parallel work, triage open issues for parallel fixing, or create issue sets.
---

# Parallel Issue Sets

Look up all open GitHub issues with:

```bash
gh issue list --state open --limit 100 --json number,title,labels
```

Create numbered sets of issues that can be worked on by parallel Claude Code sessions. Auto-merge is enabled so PRs land independently in any order.

## Rules

- Every issue in a set MUST touch different source files/subsystems (no file overlap, no merge conflicts).
- No two issues in a set should be closely related (don't pair issues from the same feature area).
- Maximize set size (maximize parallelism).
- Pick issues in dependency order across sets (foundational fixes in earlier sets).
- Wait for all PRs in a set to merge before launching the next set.

## Output format

For each set, output only the issue numbers as a comma-separated list on one line:

```
Set 1: #NNN, #NNN, #NNN, ...
Set 2: #NNN, #NNN, ...
```

No commands, no cleanup, no explanations. Just the set number and issue numbers.
