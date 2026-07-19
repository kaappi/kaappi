---
description: Prediction-with-commitment comprehension quiz on a core Kaappi subsystem — writes questions from the current code, waits for committed answers, verifies against code and live runs, and logs results to a per-user ledger. Use when the user asks to be quizzed, to test or calibrate their understanding of a subsystem, or to measure comprehension coverage / pay down cognitive debt.
---

# Comprehension Quiz

Measures and repairs the gap between the code and the maintainer's mental
model of it. One principle governs everything here: **prediction with
commitment before revelation**. A committed wrong answer, corrected with
evidence, builds more model than any explainer (the hypercorrection
effect). This is a calibration instrument, not an exam.

The argument is a subsystem alias or a `src/` file. Aliases are the
canonical ledger keys, one per core-tier section of
`docs/dev/understanding-map.md`: `values` (§1), `gc` (§2), `ir` (§3),
`continuations` (§4), `hygiene` (§5), `fibers` (§6), `threads` (§7).
A `src/` file argument resolves to the core-tier section whose
**Where** line lists it and is quizzed under that section's alias; a
file listed by no core section is fenced-tier — quizzed only if
explicitly asked, with the file itself as the syllabus and its path as
the ledger key. Only core-tier subsystems are quizzed by default: not
knowing fenced-tier internals is the point of the fence. With no
argument: read the ledger, list the aliases least recently quizzed,
let the user pick.

## Workflow

### Step 1: Prepare (silently)

1. Read the resolved core-tier section in `docs/dev/understanding-map.md`
   — its "Theory" list is the syllabus. (For an explicitly requested
   fenced-tier file, the file itself is the syllabus.)
2. Read the actual sources. Questions and answers are grounded in the
   code as it is **today**, never in docs or your memory of them.
3. Read the relevant `docs/dev/` pages *last*, looking for drift: if doc
   and code disagree, that is a finding — and prime quiz material.
4. Check `~/.kaappi/quiz-ledger.md` for this subsystem's previous `Gaps:`
   lines — if any exist, re-test exactly one (spaced repetition).

Do not narrate this phase, and do not quote code that leaks answers.

### Step 2: Ask

Write 3–5 questions, numbered, all in one message. Mix these types:

- **Prediction** — "what happens if …" for a concrete input or sequence;
  must be demonstrable by running something.
- **Invariant** — "what must remain true across …, and what breaks when
  it doesn't?"
- **Design** — "why this way; what alternative was rejected, and why?"
- **Debugging** — "given this symptom, where do you look first, and why
  there?"

Then state the rules and **end the turn**:

> Commit answers to all questions before I reveal anything. Guessing is
> fine — a confident wrong answer is the most valuable outcome. One or
> two sentences each.

No hints, no code excerpts that give answers away, no continuing until
the user replies. Grade only what they commit; unanswered questions are
recorded as not attempted.

### Step 3: Verify with evidence

Ground truth comes **by demonstration, not recall**:

- Behavior questions: run it — a scratch `.scm` through
  `zig-out/bin/kaappi` (build first if needed), the REPL, `kaappi ir` /
  `kaappi expand`, `--disassemble`; `-Dgc-stress=true` for GC claims.
  Show the actual output.
- Invariant/design questions: cite the exact `file:line` and quote the
  decisive lines.
- If a question can't be demonstrated or cited, it was a bad question —
  void it and say so rather than grading from belief.

### Step 4: Grade

Per question: ✓ correct / ◐ partial / ✗ wrong — evidence first, then at
most one short paragraph of correction. A confident ✗ is the jackpot:
show the disproof cleanly and plainly; don't soften it, don't pile on.

Two special verdicts:

- **User right, code wrong** — their model beats the implementation.
  That's a bug finding: offer to file it.
- **User matches the docs, code disagrees** — doc drift: offer to fix the
  doc or file it.

### Step 5: Ledger

Append to `~/.kaappi/quiz-ledger.md` (create with a
`# Kaappi comprehension ledger` header if missing). It lives outside the
repo deliberately: it survives worktrees and stays out of the public
repo. Format:

```markdown
## 2026-07-19 — gc (3/5)
1. ✓ root-before-allocate across two allocations
2. ✗ write-barrier direction — answered young→old; it's old→young (memory.zig:NNN)
3. ◐ copy-before-collect — knew the rule, not why slices alias
4. ✓ vm_instance as root (#1401)
5. — survive-count promotion (not attempted)
Gaps: barrier direction; promotion rule.
Drift: none.
```

One `##` entry per quiz; a verdict plus a few-word gist per question; a
`Gaps:` line (it seeds the next quiz's re-test); a `Drift:` line.

### Step 6: Close the loop

- **≥80%** — model is healthy; note which subsystem the ledger says is
  most stale.
- **≤50% on a core subsystem** — suggest a retrieval session: the user
  writes the subsystem's theory from memory (ten lines), then you diff it
  against the code together.
- **Any confident ✗ on an invariant** — flag it in `Gaps:` so the next
  quiz re-tests it.
- Findings (bugs, drift) get filed or fixed, not just noted.

## Question quality bar

Good questions probe theory; bad ones probe text.

**Good** — "A primitive holds the Value returned by `allocPair` in a Zig
local, calls `allocVector`, then uses the local. What can happen, and
which build flag makes the failure deterministic?" (runnable, plausible
wrong answers, tests a load-bearing rule)

**Good** — "`close-port` on an fd with fibers parked on it: what happens
to those fibers, and why was 'leave them parked' not an option?"

**Bad** — "How many optimization passes does the IR run?" (grep-able
trivia — a number, not a model)

**Bad** — "Which file implements dynamic-wind transitions?" (naming;
knowing it's `vm_continuations.zig` is not knowing the wind invariant)

The test for keeping a question: could a wrong answer to it ever cause a
bad merge decision, a wrong review, or a misdiagnosis? If not, cut it.

## Anti-patterns

- Explaining anything before answers are committed — the commitment *is*
  the mechanism.
- Grading from docs or memory instead of demonstration.
- Padding to five questions with trivia — three sharp beat five soft.
- Turning the reveal into a lecture — evidence, one paragraph, move on.
- Quizzing fenced-tier internals unprompted.
