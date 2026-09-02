# GitHub Issues

How the issue tracker is labeled and triaged. Two neighbouring documents own
the rest: [`CONTRIBUTING.md`](../../CONTRIBUTING.md) covers *who* may file
(org members) and the PR path, and `.github/ISSUE_TEMPLATE/` covers *what* a
report must contain. This document covers the label taxonomy, the priority
rubric, and the triage invariant — the parts a maintainer has to apply by
judgement rather than by template.

## The four label axes

Labels fall on four independent axes. An issue carries at most one label from
the priority axis and any number from the others.

### Priority — when

Exactly one on every open issue. Rubric below.

| Label | GitHub description |
|-------|-------------------|
| `priority: critical` | Must fix ASAP — blocks users or breaks core functionality |
| `priority: high` | Important — fix before next release |
| `priority: medium` | Should fix — plan for upcoming work |
| `priority: low` | Nice to have — fix when convenient |

### Kind — what sort of change

| Label | Meaning |
|-------|---------|
| `bug` | Something isn't working |
| `enhancement` | New feature or request |
| `refactor` | Code health / restructuring, no behavior change intended |
| `documentation` | Improvements or additions to documentation |
| `doc-truth` | Docs describe behavior that no longer exists |
| `r7rs-conformance` | R7RS-small spec conformance issue |
| `srfi` | SRFI implementation issue |
| `breaking` | Breaking change |
| `performance` | Throughput, latency, or memory cost |
| `question`, `duplicate`, `invalid`, `wontfix` | Standard GitHub triage set |

### Subsystem — where

`gc`, `macros`, `continuations`, `numeric-tower`, `concurrency`, `ffi`,
`lsp`, `native-backend`, `reader-change`, `engine-change`, `portable`,
`tooling`, `ci`, `legibility`, `tier-divergence`.

Three of these are load-bearing beyond navigation, because they predict the
*shape* of the fix:

- `portable` — pure Scheme `.sld`, no engine changes needed.
- `engine-change` — needs VM, compiler, GC, or runtime changes.
- `reader-change` — needs reader/lexer modifications.

### Process — how it arrived, how it's handled

| Label | Meaning |
|-------|---------|
| `audit` | Found during systematic audit (see [`../audit-strategy.md`](../audit-strategy.md)) |
| `fuzz-finding` | Automated report from the scheduled Fuzz workflow |
| `epic` | Umbrella tracking issue; children are separate issues |
| `blocked-upstream` | Blocked on an upstream dependency fix |
| `good first issue`, `help wanted` | Contributor onboarding |

## The priority rubric

The four descriptions above are too coarse to settle real triage. Every
level has a load-bearing question behind it.

| Level | The question it answers |
|-------|------------------------|
| critical | Does this compromise the process — memory unsafety, or an abort reachable from an ordinary program? |
| high | Does a legal program get a silently wrong answer, hang, or lose data in a path users actually reach? |
| medium | Is behaviour wrong against a spec or a documented guarantee, but loud, narrow, or recoverable? |
| low | Is the behaviour right and only its *description* or *diagnostic* wrong? |

### critical is reserved for process-level unsafety

Adopted 2026-08-01. A correctness bug does not earn `critical` no matter how
broad or how silent — it tops out at `high`.

Two classes qualify, and nothing else does:

- **Memory unsafety** — use-after-free, double free, a missing GC write
  barrier, cross-heap aliasing or mutation, stale registers, type confusion.
  The defect need not have been observed corrupting anything; the unsafety is
  the finding.
- **A process abort reachable from an ordinary program** — a panic, an
  uncatchable exhaustion, a module trap. What makes it process-level is that
  no `guard` can intercept it and the program cannot continue.

A *hang* is neither. It is a liveness failure, and it stays at `high` however
reliably it reproduces. Likewise a wrong answer, however silent and however
wide its blast radius: silence and breadth are arguments about where an issue
sits within `high`, not arguments for promoting it out of it.

### Reachability separates critical from high

Two issues can share an abort class and still land a level apart, because
"aborts the process" is not the whole question — *from what program* is.

An abort reachable from a handful of lines of ordinary code is `critical`. The
same abort class reached only by an extreme input — hundreds of thousands of
nesting levels, thousands of concurrent tasks, an allocation large enough to
recurse a stack to exhaustion — is `high`. The defect is equally real; the
program that provokes it sits far outside the envelope the implementation
intends to support.

The sharpest form of the test compares the triggering input against whatever
limit the implementation documents for that path:

- A program **inside** the documented envelope that aborts anyway is
  `critical` — the guard that should have caught it is out of reach, and a
  user obeying the documented limit still loses the process.
- A program that only aborts far **past** the documented cap is `high` — the
  guard works, and the input is not one anybody writes.

Tier is not part of the rule and does not discount an entry. An abort a
`guard` cannot intercept is process-level whichever target it happens on, and
a non-primary target may still back something users touch directly. Ask
whether the abort is reachable, not where.

### Silence is an aggravator, not a level

A loud failure is strictly safer than a quiet one: the user sees it, and it
cannot corrupt downstream output. So silence pushes an issue *up* within its
level, and a loud failure pulls it down. It never moves one across a level
boundary — that is what the rubric questions decide.

Two functional gaps of identical scope in the same procedure can still split,
on nothing but how they announce themselves:

| Failure mode | Pull |
|--------------|------|
| Partial side effects retained, wrong answer propagates, exit 0 | up within the level |
| Raises immediately, discoverable on the first run, nothing downstream sees it | down within the level |

The question to ask is whether a user could ship on top of the defect without
noticing it. A silent failure earns its aggravation because the answer is that
they could.

### low means the behaviour is right

Reserve `low` for issues where the code does the correct thing and only its
*description* is wrong — `doc-truth`, diagnostic wording, error-taxonomy
tidying, `refactor`. Also `low`: a diagnostic that misattributes a real,
correctly-refused failure, where the tool declined to act and nothing was
corrupted.

An edge case whose behaviour is genuinely wrong is `medium` — unless the
issue itself argues for less and shows its work. A reporter who explains why
a defect is reachable through only one narrow constructor has made a case
worth honouring; the reasoning belongs on the issue, where the next
maintainer can weigh it.

## Severity is not priority

Audit issues carry a **severity** in their header, drawn from
[`../audit-strategy.md`](../audit-strategy.md)'s vocabulary: `wrong-result`,
`crash`, `missing-feature`, `diagnostic quality`, `coverage gap`,
`latent miscompilation`, `tooling correctness`, `doc-truth`, `edge-case`.

Severity describes **what the defect is**; priority describes **when we fix
it**. They do not map one-to-one, and the gap is entirely blast radius:

- `wrong-result` spans `high` down to `medium`. The defect is identically
  "wrong answer" at both ends; the reachable surface is not. A wrong answer on
  a path every program crosses and a wrong answer behind one option of one
  constructor share a severity and share nothing else.
- `crash` is usually `critical`, but see the reachability rule above. It is
  never lower than `high`: an unreachable-in-practice abort is still an abort.
- `doc-truth` and `diagnostic quality` are usually `low`, because the
  behaviour is normally correct and only its description is wrong. **Check
  that premise rather than assuming it.** An issue can be filed as `doc-truth`
  and ask only for a doc fix while the behaviour it conceals is a silent wrong
  result. A doc gap that hides one is not `low`.

Read the severity as an input to the priority decision, never as the answer.
The reporter chose it to describe the defect, usually before knowing how far
it reaches.

## Triage

**Invariant: every open issue carries exactly one priority label**, with one
exemption below. The invariant is not retroactive: issues closed before it was
adopted have no priority label, and backfilling them would be archaeology with
no consumer. That population is fixed — everything closed from here on was
labeled while it was open.

**Exempt: auto-filed `fuzz-finding` CI reports.** The Fuzz workflow opens a
`Fuzz CI: infrastructure or build failure` issue whenever a job dies without
a finding artifact. These are triage-and-close — the question is "what broke
the runner", not "when do we fix this" — so prioritizing them would be
ceremony. A fuzz report that turns out to be a real defect gets a normal
issue, which is labeled like any other.

It needs re-checking after any filing burst. An `audit` phase lands its
findings all at once, so the gap opens between one triage pass and the next
rather than drifting gradually. Re-run the sweep at the *end* of a pass as
well as the start: a burst can land while the pass is in progress, and the
first sweep is only a snapshot of the moment it ran.

Find every issue that violates the rule. "Exactly one" has two failure modes,
so this counts the priority labels and reports anything that is not 1 — a
missing label and a double label are equally worth knowing about, and only the
first is the common case:

```bash
gh issue list --repo kaappi/kaappi --state open --limit 400 \
  --json number,title,labels \
  --jq '.[] | ([.labels[].name | select(startswith("priority:"))] | length) as $n
            | select($n != 1)
            | select([.labels[].name] | index("fuzz-finding") | not)
        | "\(.number)\t\(.title)"'
```

Current distribution, and re-check it after a triage pass:

```bash
for p in critical high medium low; do
  printf 'priority: %-9s %s\n' "$p" \
    "$(gh issue list --repo kaappi/kaappi --state open --limit 400 \
        --label "priority: $p" --json number --jq 'length')"
done
```

Changing a level is a remove plus an add, so the invariant is never
transiently violated in the other direction:

```bash
gh issue edit <number> --repo kaappi/kaappi \
  --remove-label "priority: critical" --add-label "priority: high"
```

### Calibrate before labeling

This document deliberately holds no worked examples. The rubric is a summary
of decisions already made, and the decisions themselves live in the tracker,
where they stay current without anyone maintaining a second copy of them here.
So the tracker is the calibration source, and reading it is a step of the
triage, not an optional extra:

```bash
gh issue list --repo kaappi/kaappi --state all --limit 12 \
  --label "priority: high" --json number,title,labels \
  --jq '.[] | "\(.number)\t[\([.labels[].name] | join(", "))]\t\(.title[0:110])"'
```

Swap the label to bracket a candidate from both sides. Finding the nearest
`low` and the nearest `medium` for something you were about to call `medium`
is worth more than reading either level's description again.

An `audit` campaign files issues in bursts from one subsystem, which makes
the corpus lopsided by area but well-calibrated by level — the neighbours of
a new fibers issue are the other fibers issues, filed the same week against
the same rubric.

Two cautions on precedent. A neighbour can be mislabeled, so use the rubric
text as the authority and neighbours as a contradiction check: when several
comparable issues disagree with the criterion, the criterion wins and the
neighbours are the thing to fix. And match on *failure shape* rather than
subsystem — a tool that reports success while checking nothing has more in
common with another vacuous checker than with the rest of its own subsystem.
