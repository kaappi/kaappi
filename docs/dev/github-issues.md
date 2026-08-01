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
| `no-changelog` | Not user-visible; exempt from the CHANGELOG check |
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

This is not an invented rule; it describes the existing corpus. All 13 issues
ever labeled `priority: critical` are memory unsafety or a process abort:

| Issue | Why critical |
|------:|--------------|
| [2027](https://github.com/kaappi/kaappi/issues/2027) | Deep copy aliases FFI handles across heaps; the freed slot reads back as a pair of flonums |
| [2024](https://github.com/kaappi/kaappi/issues/2024) | A custom hash inserting into its own table double-frees the entry array |
| [2008](https://github.com/kaappi/kaappi/issues/2008) | Cross-heap mutation of a raw `ArrayList`; silent abort or type-confused object |
| [1973](https://github.com/kaappi/kaappi/issues/1973) | A 27-field record aborts the process — `u8` overflow |
| [1939](https://github.com/kaappi/kaappi/issues/1939) | Re-entrant custom-port read aborts the process (exit 134) |
| [1933](https://github.com/kaappi/kaappi/issues/1933) | Parent collector reclaims objects a live child thread references |
| [1924](https://github.com/kaappi/kaappi/issues/1924) | Use-after-free: child-heap pointer dangles after join |
| [1907](https://github.com/kaappi/kaappi/issues/1907) | Reader panics (exit 134) on an `#e` literal |
| [1267](https://github.com/kaappi/kaappi/issues/1267) | Missing GC write barriers — old→young edges lost |
| [1256](https://github.com/kaappi/kaappi/issues/1256) | Stale registers in the tail-call window |
| [1245](https://github.com/kaappi/kaappi/issues/1245) | Epic: native VM re-entrancy, the class behind several of the above |
| [1191](https://github.com/kaappi/kaappi/issues/1191) | GC root stack overflow panics instead of raising |
| [1181](https://github.com/kaappi/kaappi/issues/1181) | Use-after-free when a hash-table callback deletes entries |

One issue was corrected to reach that state.
[1250](https://github.com/kaappi/kaappi/issues/1250) (macro-introduced `set!`
bypasses assignment conversion) had been critical since long before the rule.
Both of its reproductions *hang* — a liveness failure, not memory unsafety —
so it moved to `high` alongside its closest precedent,
[1954](https://github.com/kaappi/kaappi/issues/1954), where four output
procedures hang forever on a cycle. It is closed, so the change buys nothing
operationally; it is recorded here because a lone counter-example in the
corpus is exactly what a future maintainer would calibrate against.

### Reachability separates critical from high

Two issues can share an abort class and still land a level apart, because
"aborts the process" is not the whole question — *from what program* is.

[1939](https://github.com/kaappi/kaappi/issues/1939) aborts from a five-line
program: a custom-port `read!` callback that reads its own port. Critical.

[2000](https://github.com/kaappi/kaappi/issues/2000) is the same abort class
in the same subsystem — a missing `in_custom_port_callback` guard at three
`(kaappi fibers)` call sites — but the SIGBUS needs ~2500 concurrent fibers
(2400 is clean 3/3; 2500 aborts 5/5). Below that depth the bug is real but
non-crashing. High.

Every existing critical aborts from an ordinary program. That is the line.

### Silence is an aggravator, not a level

A loud failure is strictly safer than a quiet one: the user sees it, and it
cannot corrupt downstream output. So silence pushes an issue *up* within its
level, and a loud failure pulls it down.

| Issue | Failure mode | Level |
|------:|--------------|-------|
| [2012](https://github.com/kaappi/kaappi/issues/2012) | A top-level form is abandoned mid-way, keeping partial side effects, exit 0 | high |
| [2005](https://github.com/kaappi/kaappi/issues/2005) | `load` of a file with an `import` fails — loudly, with a wrong file attributed | medium |

Both are functional gaps in a core R7RS procedure. The first is silent and
order-dependent; the second raises immediately and is discoverable on the
first run.

### low means the behaviour is right

Reserve `low` for issues where the code does the correct thing and only its
*description* is wrong — `doc-truth`, diagnostic wording, error-taxonomy
tidying, `refactor`. An edge case whose behaviour is genuinely wrong is
`medium`, unless the issue itself argues for less: the reporter of
[1998](https://github.com/kaappi/kaappi/issues/1998) asked for low on the
grounds that a bidirectional port is reachable only through a single SRFI 181
constructor, and that reasoning is on the issue.

## Severity is not priority

Audit issues carry a **severity** in their header, drawn from
[`../audit-strategy.md`](../audit-strategy.md)'s vocabulary: `wrong-result`,
`crash`, `missing-feature`, `diagnostic quality`, `coverage gap`,
`latent miscompilation`, `tooling correctness`, `doc-truth`, `edge-case`.

Severity describes **what the defect is**; priority describes **when we fix
it**. They do not map one-to-one, and the gap is entirely blast radius:

- `wrong-result` spans high ([2012](https://github.com/kaappi/kaappi/issues/2012),
  a silently abandoned top-level form) down to medium
  ([1997](https://github.com/kaappi/kaappi/issues/1997), a `crlf` transcoder
  doubling line breaks) — the defect is identically "wrong answer"; the
  reachable surface is not.
- `crash` is usually critical, but see the reachability rule above.
- `doc-truth` and `diagnostic quality` are usually low, because the behaviour
  is normally correct and only its description is wrong. Check that premise
  rather than assuming it: [2038](https://github.com/kaappi/kaappi/issues/2038)
  is filed as doc-truth and asks for a doc fix, but the behaviour it conceals
  is a loop running 2ⁿ−1 times that past n≈20 prints nothing and exits 0. A
  doc gap that hides a silent wrong result is not low.

Read the severity as an input to the priority decision, never as the answer.

## Triage

**Invariant: every open issue carries exactly one priority label**, with one
exemption below. No issue in the tracker has ever carried two. The invariant
is not retroactive: 766 closed issues predate it and have no priority label —
backfilling them would be archaeology with no consumer, and the number is
stable because everything closed from here on was labeled while open.

**Exempt: auto-filed `fuzz-finding` CI reports.** The Fuzz workflow opens a
`Fuzz CI: infrastructure or build failure` issue whenever a job dies without
a finding artifact. These are triage-and-close — the question is "what broke
the runner", not "when do we fix this" — and all six filed so far have been
handled with no priority label. Prioritizing them would be ceremony. A fuzz
report that turns out to be a real defect gets a normal issue, which is
labeled like any other.

It needs re-checking after any filing burst. An `audit` phase lands its
findings all at once, so the gap opens between one triage pass and the next
rather than drifting gradually.

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
gh issue edit 2003 --repo kaappi/kaappi \
  --remove-label "priority: critical" --add-label "priority: high"
```

### Calibrate before labeling

The rubric above is a summary of decisions already made, so the fastest way
to label a new issue correctly is to read how comparable ones were labeled
rather than to reason from the four one-line descriptions:

```bash
gh issue list --repo kaappi/kaappi --state all --limit 12 \
  --label "priority: high" --json number,title,labels \
  --jq '.[] | "\(.number)\t[\([.labels[].name] | join(", "))]\t\(.title[0:110])"'
```

An `audit` campaign files issues in bursts from one subsystem, which makes
the corpus lopsided by area but well-calibrated by level — the neighbours of
a new fibers issue are the other fibers issues, filed the same week against
the same rubric.
