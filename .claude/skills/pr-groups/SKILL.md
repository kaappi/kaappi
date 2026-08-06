---
name: pr-groups
description: Group open GitHub issues into cohesive sets, each landable as a single PR, with a merge order and a parallelism verdict. Use when the user asks which issues can be fixed in one PR, how to batch a milestone into PRs, how to plan the work for a release, or how to split a set of issues across sessions. Accepts a milestone title, a label, or a comma-separated list of issue numbers.
argument-hint: "[milestone-title | label:<name> | NNN,NNN,...]"
---

# PR Groups

Arguments: `$ARGUMENTS`

Turn a set of open issues into **groups, each of which one PR can close**, plus
the order to land them in.

This is the opposite of maximizing parallelism. Two issues in the same function
belong in one PR even though that serializes them — splitting them means two
reviews of the same code and a merge conflict between your own branches.

## 1. Scope the set

Interpret the argument:

| Argument shape | Query |
|---|---|
| empty | `gh issue list --state open --limit 500 --json number,title,labels,assignees` |
| a milestone title (e.g. `0.22.2`) | add `--milestone "<title>"` |
| `label:<name>` | add `--label "<name>"` (repeat per comma-separated label; they AND) |
| comma-separated numbers | fetch exactly those with `gh issue view` |

If a filter returns nothing, say so and stop. Never silently widen to the whole
tracker. If the returned count equals the limit, raise the limit and rerun.

Drop from consideration, and say which you dropped and why: epics and tracking
issues, issues already assigned, issues with an open linked PR, and anything
labelled blocked / blocked-upstream / wontfix / duplicate.

## 2. Read the bodies

Titles almost never name files; bodies usually do, often with line numbers.
Every rule below depends on knowing which code an issue touches, so fetch
bodies:

```bash
gh issue list --state open --limit 500 --milestone "<title>" --json number,title,labels,body
```

For a large set, write the bodies to a scratch file and read that rather than
paging them through several tool calls.

## 3. Verify each issue still reproduces

**Do this before grouping, not after.** An issue can have been fixed by a PR
that closed its siblings and never got closed itself — scheduling it wastes a
slot in the plan and, worse, makes the whole plan look untrustworthy when
someone discovers it.

For each issue carrying a runnable reproduction, run it against a current
build. Cheapest first — one-liners and single-file scripts are worth doing for
the whole set; skip anything needing a special build or hardware unless the
grouping hinges on it.

Report anything that no longer reproduces as **verify-and-close**, with the
observed output next to the issue's own "Expected" block, and leave it out of
the groups. Do not close it yourself unless the user asks.

Also check whether a merged PR already claims the area: if several sibling
issues were closed together, ask whether this one was simply missed.

## 4. Ground the file claims in the source

An issue's diagnosis is a hypothesis, and hypotheses in this tracker have been
wrong often enough to be worth a minute of checking. Before grouping on a
claim, confirm it:

```bash
grep -n '<symbol>' src/<file>.zig          # do the named sites exist?
wc -l src/<file>.zig                       # how big is the file already?
```

What you are looking for is cheap and specific:

- Do the two issues you want to pair really sit in the same function, or just
  the same file?
- Is the "one-line fix" one line?
- Has the surrounding code moved since the issue was filed?

A grouping built on a stale line number falls apart on contact.

## 5. Group by cohesion

Strongest signal first — pair on the highest one that applies:

1. **Same function, or adjacent arms of one switch.** One diff, one review.
2. **Same file.** One reviewer context, one file-level test update.
3. **Same root cause across different files.** State the shared cause in one
   sentence; if you cannot, it is not a group. ("Heap data reachable only from
   memory the collector cannot see" grouped a Zig slice bug with a HashMap key
   bug in unrelated files.)
4. **Same verification harness.** Fixes proven by one stress run, one test
   directory, or one platform leg batch well even when otherwise unrelated.
5. **Same zero-risk class.** Pure-data or pure-library fixes touching no engine
   code (e.g. several independent `.sld` bugs) batch broadly, because the review
   risk of adding one more is near zero. Say they are trivially splittable.

Do **not** group:

- A fix needing a design decision with one that doesn't. The design discussion
  will hold the whole PR hostage.
- An engine or model change with local fixes, for the same reason.
- Issues whose only link is a shared label or milestone.

Keep a group to what one reviewer can hold at once. Beyond roughly four issues,
split unless they are the zero-risk class.

## 6. Check what the grouped edits would blow

A group is a plan to make several edits to the same place, so check the
constraints that only bite in aggregate:

- **File size.** This repo keeps source files under 1500 lines
  (`CLAUDE.md`, "File size policy"). Run `wc -l` on every file a group touches
  and flag any that a multi-issue group would push over — the PR needs to plan
  its split, or the group needs to become two PRs. Name the natural seam.
- **Any single-entry table or generated list** several issues in the group each
  need to extend.

## 7. Order the groups

Two categories land first, and both were load-bearing in practice:

- **Instrument before subject.** If one issue is a broken detector, test, or
  assertion for the bug class the others are in, it goes first — otherwise the
  other fixes cannot be verified, and a green run proves nothing.
- **Signal before work.** If one issue makes CI produce false reds, it goes
  first — otherwise every later PR's CI is untrustworthy, and someone burns
  time disproving a failure they did not cause.

Then: groups touching disjoint files run **in parallel**. Groups needing a
design decision go last, on their own.

Apply any dependency stated in a body ("depends on", "blocked by", "after #NNN
lands") as a hard edge; a satisfied edge (target already closed) is not an edge.

## 8. Name the long pole

Say explicitly which group gates the release, and whether the remaining groups
are shippable without it. If they are, say so in one sentence — it is the most
actionable thing in the whole plan, because it converts a blocked release into
a scoping decision the user can make.

## Output format

For each group: a letter, the issue numbers, the files, and one sentence on why
they are one PR. Then the order, then the caveats.

```text
A — #NNN + #NNN · <shared cause in a few words>   (land first: <instrument|signal>)
    files: src/foo.zig:120, src/foo.zig:143
    <one sentence: why one PR>

B — #NNN · <what it is>
    files: lib/srfi/42.sld
```

Follow with the order as a short diagram:

```text
A  →  B, C, D  (parallel, disjoint files)  →  E  (design-first)
```

Close with: anything that no longer reproduces (from step 3), any repo
constraint a group would blow (step 6), and the long-pole sentence (step 8).

If the user wants to launch concurrent sessions rather than review a plan, also
emit the group leaders as bare paste-able lines, one wave per line, containing
nothing else:

```text
Wave 1: NNN, NNN
Wave 2: NNN, NNN, NNN
```

Waves come from the order in step 7 — every group in a wave touches files no
other group in that wave touches, so their PRs can merge in any order.
