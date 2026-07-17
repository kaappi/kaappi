---
name: parallel-issues
description: Group open GitHub issues into parallel sets for concurrent Claude Code sessions. Use when the user asks to batch issues, plan parallel work, triage open issues for parallel fixing, or create issue sets. Accepts an optional label (or multiple comma-separated labels) to restrict which issues are considered, and an optional second argument of comma-separated issue numbers to skip.
argument-hint: "[label[,label,...]] [skip-number[,skip-number,...]]"
---

# Parallel Issue Sets

Arguments: `$ARGUMENTS`

The first argument (if present) is a comma-separated list of labels to filter by.
The second argument (if present) is a comma-separated list of issue numbers to
skip entirely — they won't appear in any set and won't be fetched or analyzed.
Parse the skip list before querying GitHub and exclude those numbers from all
subsequent steps.

Look up open GitHub issues with:

```bash
gh issue list --state open --limit 500 --json number,title,labels,assignees,body
```

If labels were provided, split them on commas (trimming whitespace) and add a
separate `--label "<label>"` flag for each one (quoted — labels may contain
spaces). Multiple `--label` flags AND-filter: an issue must carry all of them.
If the filtered list comes back empty, say so and stop; don't fall back to
all open issues or fewer labels.

If the returned count equals the limit, raise the limit and rerun — a silently
truncated list would drop issues from the plan.

Titles rarely say which files an issue touches; bodies usually do, and the
grouping rules below depend on knowing that. Read the bodies. If the tracker
is too large to fetch every body, fetch `number,title,labels,assignees` first,
triage from titles, and `gh issue view <n>` the issues whose subsystem is
unclear.

## Which issues qualify

Skip issues that can't be handed to an independent fix session:

- **Epics, tracking, and meta issues** — title prefixes like "Epic:",
  "Tracking:", "Meta:", or labels to that effect. They span many subsystems
  and aren't one-PR-sized.
- **Assigned issues** — someone (or another session) is already on them.
- **Issues with an open linked PR** — a fix is already in flight; a second
  session would duplicate it. Add `--search "-linked:pr"` to filter these
  server-side when in doubt.
- **Not-actionable issues** — labels like blocked, question, discussion,
  wontfix, duplicate.

## Dependency analysis

Before grouping, determine which issues depend on which others:

- While reading each body (see above — you're already reading them for
  subsystem/file info), scan for dependency language referencing another
  issue number: "depends on #NNN", "blocked by #NNN", "requires #NNN",
  "needs #NNN first", "after #NNN lands/merges", "builds on #NNN". Treat
  these as directed edges (issue → the issue it depends on).
- Also check GitHub's native issue relationships when the body doesn't
  spell it out: `gh issue view <n>` renders a "Development"/linked-issues
  section in its output for issues with tracked relationships — read it
  alongside the body.
- If the dependency target is already closed, the edge is satisfied —
  ignore it.
- If the dependency target is open and qualifies for batching (see "Which
  issues qualify" above), the dependent issue must land in a **strictly
  later set** than the one containing its dependency — never the same set,
  never an earlier one.
- If the dependency target is open but doesn't qualify (e.g. it's an epic,
  it's assigned, it's blocked itself), the dependent issue isn't
  independently actionable yet — exclude it from all sets and say so,
  rather than guessing a set for it.
- Transitive chains (A ← B ← C) carry through: C's set must come after B's,
  which must come after A's.

## Grouping rules

- Every issue in a set must touch different source files/subsystems. The sets
  are worked by concurrent sessions and auto-merge lands their PRs in any
  order, so any file overlap means merge conflicts.
- Don't pair closely related issues (same feature area) even when the files
  differ — the fixes may interact.
- Prefer larger sets (more parallelism), but cap a set at ~8 issues unless
  the user asks for more — a set larger than the user can launch and monitor
  at once adds no real throughput.
- Order sets by dependency: apply the edges found above first (a dependency
  must precede its dependents' set), then place remaining foundational
  fixes in earlier sets and work that builds on them later.

## Output format

For each set, output only the issue numbers as a comma-separated list on one
line:

```
Set 1: NNN, NNN, NNN, ...
Set 2: NNN, NNN, ...
```

No commands, no cleanup, no explanations — these lines get pasted straight
into a session launcher, so anything else mixed in breaks the paste. (Context,
not output: the user waits for all PRs in a set to merge before launching the
next set — that's why the cross-set dependency ordering above matters.)
