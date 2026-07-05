# Systematic R7RS Conformance and SRFI Audit Strategy

**Status:** in progress · **Last updated:** 2026-07-05 · **Tracking issue:** [#1137](https://github.com/kaappi/kaappi/issues/1137)

## The Core Problem

Kaappi is a ~39k-line R7RS Scheme implementation with 578 built-in procedures,
21 primitives files, and 72 SRFIs. A naive "scan everything at once" approach
will either exhaust AI context windows or produce shallow, low-quality findings.
This strategy is **thorough**, **incremental**, and **agent-efficient** — and
designed for parallel execution across multiple Claude Code sessions.

Every unit of work below is sized for one focused session (or one parallel
subagent). Each session reads this document's **Session protocol**, does one
unit, and checks it off in the **Progress tracker**. The document is
self-maintaining: the tracker is the single source of truth for what's done.

## Key Principles

- **Divide by domain, not by file count** — group related files so each agent
  has coherent context (spec section + implementation + tests)
- **Test-first discovery** — run existing tests to find failures *before*
  reading source code; failures are free discoveries that need zero agent time
- **Separate discovery from fixing** — file GitHub issues now, fix later.
  This deliberately **overrides Step 4 of the `/audit-primitives` skill**
  (which says fix bugs in place); during this campaign, file instead of fix
- **Reuse existing infrastructure** — the project has `(chibi test)`,
  the `/audit-primitives` skill, coverage tests, and a bug report template
- **Each agent session is self-contained** — one domain, one report,
  one set of issues, one PR
- **Parallelize by independence** — phases 1–3 can run concurrently across
  sessions since they touch non-overlapping files

---

## Session Protocol (read this before every session)

Every audit session follows the same mechanical steps. The phase sections
below only specify *what* to audit; this section specifies *how*.

1. **Branch.** `git checkout -b audit/<unit-name>` from a fresh `main`.
   If other audit sessions are running concurrently in this checkout, use a
   git worktree instead (`git worktree add ../kaappi-audit-<unit> main`) —
   concurrent `zig build` runs in one directory race on `zig-out/`.
2. **Rebuild.** `zig build` — never trust an existing `zig-out/bin/kaappi`.
   A stale binary built with debug flags has produced phantom "regressions"
   before. If behavior looks globally insane (everything failing), check
   `zig-out/bin/kaappi --version` and rerun `--gc-stats` on a trivial program
   before believing any result.
3. **Run existing tests for the domain first.** Failures found here cost
   nothing — capture them before reading any source.
4. **Write new tests** per the phase's prompt. Follow existing conventions:
   `(chibi test)` for `tests/scheme/audit/` and `compliance/`; exit-code
   style or `(chibi test)` for `tests/scheme/srfi/` (naming: `srfiNNN.scm`,
   extensions as `srfiNNN-ext.scm`).
5. **Verify each failure before filing** (false-positive filter):
   - Reproduce on the fresh build from step 2.
   - Re-read the exact spec text; quote it in the issue. Do not trust memory
     of what R7RS or a SRFI requires.
   - Check `README.md § Known limitations` — e.g. continuations captured
     inside native higher-order calls (`map`, `for-each`, `dynamic-wind`)
     cannot be resumed after the native frame returns, and fibers can't park
     inside native callbacks. These are documented, not bugs.
   - For crashes or nondeterministic failures, retry with a
     `zig build -Dgc-stress=true` binary and note whether behavior changes
     (include this in the issue — it localizes GC bugs).
   - Search for duplicates: `gh issue list --state all --search "<proc-name>"`.
6. **File one issue per distinct bug** using the template in
   *GitHub Issue Workflow* below. Related failures with one obvious root
   cause (e.g. "bignum dispatch missing in 5 comparison procedures") get
   **one** issue listing all affected procedures.
7. **Commit tests so the suite stays green.** `run-all.sh` must pass on your
   branch. Tests that pass: commit enabled. Tests that fail (bug found):
   comment out the failing assertion with a marker line directly above it —

   ```scheme
   ;; FAIL: #1234 (exact->inexact truncates rationals)
   ;; (test 0.3333333333333333 (exact->inexact 1/3))
   ```

   The fix PR for #1234 re-enables the test — it's a ready-made regression test.
8. **Open a PR** with the new test files, update your checkbox in the
   Progress tracker below (include issue numbers), and post a one-line
   summary on the tracking issue.

### Footguns

- **`(chibi test)` never exits non-zero.** `run-all.sh` checks only exit
  codes, so a chibi-test file with 30 failing assertions still prints PASS.
  Always run audit files directly and read the printed `N pass, M fail`
  counts: `zig-out/bin/kaappi tests/scheme/audit/foo-audit.scm`.
- **Stale `.sbc` bytecode caches** are keyed on source hash only — a rebuilt
  *binary* does not invalidate them. Delete any `.sbc` next to a `.scm` you
  are re-running after an interpreter change (mainly a Phase 4 concern).
- **Stay on ReleaseSafe** (the default). Debug builds are ~500x slower on
  allocation-heavy tests and mask use-after-free differently.
- **Use timeouts** when running thread/fiber/continuation tests individually:
  `timeout 30 zig-out/bin/kaappi <file>`. A hang is a finding — file it.
  **Stock macOS has no `timeout`** — use the `run_timeout` helper pattern
  from `tests/scheme/audit-baseline.sh` (falls back to `gtimeout`, then
  `perl -e 'alarm shift; exec @ARGV' 30 <cmd>`).
- **PDF reading:** the R7RS spec (`docs/errata-corrected-r7rs.pdf`) is ~88
  pages; the Read tool takes page ranges (max 20/request). Read the table of
  contents first, then only your domain's pages. Never read the whole spec.

---

## Progress Tracker

Check off each unit when its PR is open and issues are filed. Add the date
and issue numbers, e.g. `[x] ... (2026-07-06, #1101–#1105)`.

**Phase 0 — Baseline**
- [x] 0: Baseline run, tracking issue, labels created, `audit-baseline.sh` committed (2026-07-05, #1137; baseline fully green at b2317e8 — 0 failures across all suites, no issues filed)

**Phase 1 — R7RS spec gap analysis** (independent; run in parallel)
- [x] 1A: Expressions & syntax (4.1–4.3) + Libraries (5.6–5.7) (2026-07-05, #1139–#1142; 34 new gap tests, 3 disabled pending fixes; libraries 5.6 fully green)
- [x] 1B: Equivalence, numbers, booleans, lists, symbols (6.1–6.5) (2026-07-05, no bugs found — 40 gap tests all pass, incl. circular equal? termination and numeric I/O round-trips)
- [x] 1C: Characters, strings, vectors, bytevectors (6.6–6.9) (2026-07-05, #1145; 43 gap tests, 4 disabled — char classification derives from case mappings; full string casing, UTF-8 slicing, overlap copies all conform)
- [x] 1D: Control, exceptions, eval, I/O, system (6.10–6.14) (2026-07-05, #1147; 30 gap tests, 2 disabled — immutable environments don't signal on define/set!; cyclic write, CRLF read-line, raise-continuable all conform)

**Phase 2 — Primitives audit** (independent; run in parallel; order = risk)
- [ ] 2.1: `primitives_srfi18.zig` (threads)
- [ ] 2.2: `primitives_string_ext.zig` (SRFI-13)
- [ ] 2.3: `primitives_char.zig` (Unicode)
- [ ] 2.4: `primitives_io.zig` (ports)
- [ ] 2.5: `primitives_filesystem.zig` (SRFI-170)
- [ ] 2.6: `primitives_srfi1.zig` (SRFI-1)
- [ ] 2.7: `primitives_control.zig` (call/cc, guard)
- [ ] 2.8: `primitives_vector.zig`
- [ ] 2.9: `primitives_list.zig`
- [ ] 2.10: `primitives_bytevector.zig`
- [ ] 2.11: `primitives_hashtable.zig` (SRFI-69)
- [ ] 2.12: `primitives_fiber.zig`
- [ ] 2.13: `primitives_ffi.zig`
- [ ] 2.14: `primitives_r7rs.zig`
- [ ] 2.15: `primitives_random.zig` (SRFI-27)
- [ ] 2.16: `primitives_lazy.zig`
- [ ] 2.17: `primitives_cxr.zig`
- [ ] 2.18: `primitives.zig` (core)

**Phase 3 — SRFI conformance**
- [ ] 3.0: Run all 35 existing SRFI test files, capture failures
- [ ] 3.1: Built-in SRFIs without adequate tests (9, 39, 170)
- [ ] 3a: SRFIs 0, 6, 17, 23, 26 (syntax extensions)
- [ ] 3b: SRFIs 37, 38, 43, 116, 117, 134 (records, arrays, immutable data)
- [ ] 3c: SRFIs 41, 42, 45, 143, 144 (lazy evaluation, math)
- [ ] 3d: SRFIs 60, 61, 78, 87, 197, 210, 227 (bitwise, testing, pipelines)
- [ ] 3e: SRFIs 4, 127, 130, 233, 235 (vectors, cursors, combinators)
- [ ] 3.4: Upgrade smoke-only SRFIs to behavioral tests (98, 125, 128, 132, 141, 151, 152, 174, 175, 195, 219, 232)

**Phase 4 — Compiler & VM edge cases**
- [ ] 4A: Tail positions in derived forms + thin-coverage forms
- [ ] 4B: Continuation interactions (dynamic-wind, guard, parameterize, values)
- [ ] 4C: Macro hygiene + define-library import sets

**Phase 5 — Synthesis**
- [ ] 5: Deduplicate, group by root cause, prioritize, update tracking issue

---

## Current State (verified 2026-07-05)

Before planning work, here is what actually exists:

### Test infrastructure

| Suite | Location | Count | Framework |
|-------|----------|------:|-----------|
| R7RS conformance | `tests/scheme/r7rs/r7rs-tests.scm` | 988 assertions | `(chibi test)` |
| Zig unit tests | `src/tests_*.zig` (21 files) | 473 tests | Zig `test` |
| Scheme smoke tests | `tests/scheme/smoke/` | 245 files | Exit code |
| Compliance tests | `tests/scheme/compliance/` | 35 files | Mixed |
| Continuation tests | `tests/scheme/continuations/` | 13 files | Exit code |
| Hygiene tests | `tests/scheme/hygiene/` | 12 files | Exit code |
| SRFI tests | `tests/scheme/srfi/` | 35 files | Exit code |
| FFI tests | `tests/scheme/ffi/` | 12 files | Exit code |
| Audit tests | `tests/scheme/audit/` | 3 files | `(chibi test)` |
| Compiler tests | `tests/scheme/compile/` | 8 shell scripts | Shell |
| Error tests | `tests/scheme/errors/` | 7 files | Shell |
| Coverage gap tests | `tests/scheme/coverage/` | 27 files | Exit code |
| Robustness | `tests/scheme/robustness/` | 1 file | Shell |
| Sandbox | `tests/scheme/sandbox/` | 1 file | Shell |

`run-all.sh` executes: smoke, compliance, continuations, hygiene, srfi, ffi,
audit, errors, compile, and r7rs. It **excludes** bench/ (performance),
coverage/ (gap-fillers), deferred/ (known-deferred .sbc files), phase1–5/
(.sbc bytecache tests), robustness/, and sandbox/.

Most Scheme test files use **no formal framework** — they succeed on exit
code 0 and fail on non-zero. Only audit tests and a few compliance files use
`(chibi test)`. One file uses `(srfi 64)`. Note: `run-all.sh` treats
chibi-test files as pass/fail **by exit code only** — it does not parse their
`N fail` output (except for the R7RS suite, which is parsed specially). See
Footguns above.

### Primitives audit status

3 of 21 primitives files have been audited:

| File | Status | Audit test |
|------|--------|-----------|
| `primitives_arithmetic.zig` | **Done** | `audit/primitives_arithmetic-audit.scm` |
| `primitives_numeric.zig` | **Done** | `audit/primitives_numeric-audit.scm` |
| `primitives_string.zig` | **Done** | `audit/primitives_string-audit.scm` |
| All other 18 files | Not audited | — |

### SRFI test coverage

| Coverage level | Count |
|----------------|------:|
| Conformance-level tests in `tests/scheme/srfi/` | 29 |
| Smoke-level only (loading + basic use, in `coverage/` or `compliance/`) | 13 |
| No test at all | 30 |

Note: `srfi_foundation.scm` tests 10 SRFIs in one file (2, 8, 11, 16, 28,
31, 34, 111, 145, 222). `srfi-loading-coverage.scm` smoke-tests 22 SRFIs
but only verifies they load and export, not behavioral correctness.

### GitHub state

The `audit`, `r7rs-conformance`, and `srfi` labels **do not exist yet** —
Phase 0 creates them. The issue tracker is nearly empty (2 open issues,
both refactoring epics), so duplicate risk is low but grows as parallel
sessions file findings — hence the mandatory dedup search in the protocol.

---

## Phase 0: Baseline (1 session, ~20 min)

**Goal:** Establish a known-good baseline of what currently passes/fails.

```bash
zig build test                                           # Zig unit tests (473 tests)
zig build run -- tests/scheme/r7rs/r7rs-tests.scm        # R7RS suite (988 assertions)
bash tests/scheme/run-all.sh                             # All Scheme suites
```

Save the R7RS test output — it reports pass/fail/error counts per section
(6.1 Equivalence, 6.2 Numbers, etc.). This becomes the "before" snapshot.
Any existing failures are **free bug discoveries** that need no agent time.

**Deliverables for this session:**

1. **Create the labels** (see GitHub Issue Workflow below for the full list).
2. **Create the tracking issue** and record its number at the top of this doc:

   ```bash
   gh issue create --title "Tracking: R7RS conformance and SRFI audit" \
     --label audit
   ```

   Include section-by-section R7RS pass/fail counts in the issue body, plus a
   checklist mirroring the Progress tracker above.
3. **Commit the baseline script** as `tests/scheme/audit-baseline.sh` so every
   later session can rerun it. _Done — see the committed script._ It runs
   unit tests, the R7RS suite, `run-all.sh`, and each SRFI file individually
   (with a portable timeout helper — see Footguns), teeing each stage to
   `$OUT/*.log` and ending with a grep summary of FAIL/ERROR/TIMEOUT lines.
   Usage: `bash tests/scheme/audit-baseline.sh [output-dir]` (default
   `/tmp/audit-baseline`).

4. **File issues for any existing failures** found by the baseline (following
   the Session protocol's verification steps).

Feed only the *failures* to later analysis. This eliminates "running tests"
time from all subsequent agent sessions.

---

## Phase 1: R7RS Spec-Driven Test Gap Analysis (4 sessions)

**Goal:** Find R7RS requirements NOT covered by the existing 988-assertion
test suite.

The existing `tests/scheme/r7rs/r7rs-tests.scm` is adapted from Chibi's suite.
It covers most of R7RS but has known gaps. The authoritative spec reference is
`docs/errata-corrected-r7rs.pdf`.

### Domain map

| Domain | R7RS Sections | Primitives Files | Existing Tests | Session |
|--------|--------------|-----------------|----------------|:-------:|
| Expressions & Syntax | 4.1–4.3 | `compiler*.zig`, `expander.zig` | `tests_macros.zig`, `tests_ir.zig`, smoke/macros.scm | 1A |
| Libraries | 5.6–5.7 | `vm_library.zig`, `library.zig` | smoke/libraries.scm, tests_libraries.zig | 1A |
| Equivalence | 6.1 | `primitives.zig` | r7rs-tests.scm §6.1 | 1B |
| Numbers | 6.2 | `primitives_arithmetic.zig`, `primitives_numeric.zig`, `bignum.zig` | r7rs-tests.scm §6.2, audit/*-audit.scm | 1B |
| Booleans | 6.3 | `primitives.zig` | r7rs-tests.scm §6.3 | 1B |
| Lists | 6.4 | `primitives.zig`, `primitives_list.zig` | r7rs-tests.scm §6.4 | 1B |
| Symbols | 6.5 | `primitives.zig` | r7rs-tests.scm §6.5 | 1B |
| Characters | 6.6 | `primitives_char.zig` | r7rs-tests.scm §6.6, compliance/chars.scm | 1C |
| Strings | 6.7 | `primitives_string.zig`, `primitives_string_ext.zig` | r7rs-tests.scm §6.7, compliance/strings.scm, audit/ | 1C |
| Vectors | 6.8 | `primitives_vector.zig` | r7rs-tests.scm §6.8 | 1C |
| Bytevectors | 6.9 | `primitives_bytevector.zig` | r7rs-tests.scm §6.9 | 1C |
| Control | 6.10 | `primitives_control.zig`, `vm_continuations.zig` | r7rs-tests.scm §6.10, continuations/ | 1D |
| Exceptions | 6.11 | `primitives_control.zig`, `vm.zig` | r7rs-tests.scm §6.11, errors/ | 1D |
| Environments & eval | 6.12 | `primitives_r7rs.zig` | r7rs-tests.scm §6.12 | 1D |
| I/O (Ports) | 6.13 | `primitives_io.zig` | r7rs-tests.scm §6.13 | 1D |
| System | 6.14 | `primitives_r7rs.zig`, `primitives_filesystem.zig` | r7rs-tests.scm §6.14 | 1D |

Sessions 1A–1D are independent — run them in parallel.

### Session prompt (Phase 1)

```
Read docs/audit-strategy.md — follow the Session protocol. Your unit is
Phase 1, session 1X (domains listed in the Domain map).

For each domain in your session:
1. Read the relevant R7RS section from docs/errata-corrected-r7rs.pdf
   (find pages via the PDF's table of contents; read only those pages).
2. Read the matching section of tests/scheme/r7rs/r7rs-tests.scm and the
   listed existing tests.
3. For each procedure/syntax in the spec section, ask:
   - Is it tested at all? (grep for its name across tests/)
   - Are edge cases tested? (empty inputs, type errors, boundary values,
     exact/inexact and fixnum/bignum boundaries where numeric)
   - Does the implementation match the spec text exactly?
4. Write new tests to tests/scheme/compliance/r7rs-<section>-gaps.scm
   using (chibi test). Run them directly and read the pass/fail counts.
5. Verify and file issues per the Session protocol; comment out failing
   assertions with ;; FAIL: #NNN markers.

Deliverables: PR with the gap-test files, issues filed, tracker updated.
```

**Why this is agent-efficient:** Each session reads ~3 files per domain
(spec pages + test section + primitives file), with full domain context.

---

## Phase 2: Primitives Audit (18 units, ~1 session each)

**Goal:** Audit every unaudited primitives file for correctness using the
`/audit-primitives` skill — **except its Step 4**: do not fix; file issues.

3 files are already audited (arithmetic, numeric, string). The remaining 18
are prioritized by a composite risk score: type-dispatch complexity × GC
allocation density × concurrency/Unicode surface area.

### Execution order (by risk, highest first)

| Priority | File | Lines | Procs | Risk factors |
|---------:|------|------:|------:|-------------|
| 1 | `primitives_srfi18.zig` | 994 | 35 | Thread safety, mutex/condition-var, deep-copy boundaries |
| 2 | `primitives_string_ext.zig` | 952 | 30 | SRFI-13, Unicode, 99 GC allocs, start/end indexing |
| 3 | `primitives_char.zig` | 622 | 22 | Unicode classification, case-folding tables |
| 4 | `primitives_io.zig` | 905 | 40 | Port encoding, GC allocs, 5 callback sites |
| 5 | `primitives_filesystem.zig` | 1041 | 69 | Largest proc count, OS syscall boundary |
| 6 | `primitives_srfi1.zig` | 1748 | 71 | 88 GC allocs, 254 error sites, fold/unfold/partition |
| 7 | `primitives_control.zig` | 348 | 16 | call/cc, dynamic-wind, guard interactions |
| 8 | `primitives_vector.zig` | 915 | 33 | GC allocs, vector-map/for-each callbacks |
| 9 | `primitives_list.zig` | 490 | 17 | Improper/circular lists, map/for-each callbacks |
| 10 | `primitives_bytevector.zig` | 405 | 21 | Endianness, binary I/O, UTF-8 encoding |
| 11 | `primitives_hashtable.zig` | 553 | 23 | SRFI-69, custom hash/equal callbacks |
| 12 | `primitives_fiber.zig` | 253 | 8 | Concurrency, fiber scheduling |
| 13 | `primitives_ffi.zig` | 293 | 7 | FFI boundary, pointer safety |
| 14 | `primitives_r7rs.zig` | 370 | 17 | values, call-with-values, eval, load |
| 15 | `primitives_random.zig` | 177 | 12 | SRFI-27, statistical properties |
| 16 | `primitives_lazy.zig` | 103 | 4 | delay/force re-entrancy |
| 17 | `primitives_cxr.zig` | 155 | 24 | Low risk: pure accessor combinators |
| 18 | `primitives.zig` (core) | 862 | 39 | Type predicates, cons/car/cdr, eq/eqv/equal, apply |

Small files can be batched: 2.15–2.17 (random, lazy, cxr) fit in one session.

### Session prompt (Phase 2)

```
Read docs/audit-strategy.md — follow the Session protocol. Your unit is
Phase 2.N: src/primitives_XXX.zig.

Follow the /audit-primitives skill workflow, with one override: do NOT fix
bugs (skip the skill's Step 4 fixing; this campaign separates discovery
from fixing). Instead:
1. Write the audit test file to tests/scheme/audit/primitives_XXX-audit.scm
   using (chibi test). Cover the skill's 6 bug patterns: type dispatch
   gaps, GC safety, UTF-8 indexing, error propagation in callbacks,
   boundary conditions, ignored optional arguments.
2. Run it DIRECTLY (zig-out/bin/kaappi <file>) and read the pass/fail
   counts — run-all.sh will not surface chibi-test failures.
3. Verify and file issues per the Session protocol; comment out failing
   assertions with ;; FAIL: #NNN markers so run-all.sh stays green.

Deliverables: PR with the audit test file, issues filed, tracker updated.
```

**Budget:** 15–30 min each. Files 1–6 are independent; run up to 4
concurrently (in separate worktrees).

---

## Phase 3: SRFI Conformance (8 units)

**Goal:** Verify all 72 SRFIs work correctly.

### Current coverage (from Current State above)

- **8 built-in SRFIs** (Zig primitives): 1, 9, 13, 18, 39, 69, 133, 170
- **64 portable SRFIs** (.sld files in `lib/srfi/`)
- **29 SRFIs** have conformance-level tests, **13** smoke-only, **30** none

**SRFIs with conformance tests** (29): 1, 2, 8, 11, 13, 14, 16, 18, 19, 27,
28, 31, 34, 35, 36, 48, 64, 69, 111, 113, 115, 133, 145, 146, 158, 166, 189,
196, 222

**Smoke-only** (13; loading + exports verified, behavior untested): 98, 125,
128, 132, 141, 151, 152, 170, 174, 175, 195, 219, 232

**No test at all** (30): built-in **9** (define-record-type) and **39**
(parameters) — highest risk since they're Zig code — plus portable 0, 4, 6,
17, 23, 26, 37, 38, 41, 42, 43, 45, 60, 61, 78, 87, 116, 117, 127, 130, 134,
143, 144, 197, 210, 227, 233, 235.

### Units

**3.0 — Validate existing tests** (1 session): run all 35 existing SRFI test
files individually with `timeout 30`, read fail counts, file issues. (Phase 0's
baseline script already does the run; this session analyzes and files.)

**3.1 — Built-in SRFIs without adequate tests** (1 session): SRFI-9 (records;
only indirectly tested via the R7RS suite), SRFI-39 (parameters; no dedicated
test), SRFI-170 (filesystem; smoke-only — coordinate with Phase 2.5, which
audits the same file; whichever runs first covers it, the other skips).

**3a–3e — Portable SRFIs with no test** (5 sessions, groups of 5–7 related
SRFIs — see Progress tracker for exact groupings). Adapt tests from
[srfi-explorations/srfi-test](https://github.com/srfi-explorations/srfi-test)
(SRFI-64 format) before writing from scratch.

**3.4 — Upgrade smoke-only SRFIs** (1 session): 98, 125, 128, 132, 141, 151,
152, 174, 175, 195, 219, 232 (170 handled by 3.1/2.5).

### Session prompt (Phase 3)

```
Read docs/audit-strategy.md — follow the Session protocol. Your unit is
Phase 3X: SRFIs N1, N2, ... (see the Progress tracker grouping).

For each SRFI:
1. Read lib/srfi/N.sld to understand the implementation.
2. Check tests/scheme/srfi/ for existing tests (naming: srfiNNN.scm).
3. Check github.com/srfi-explorations/srfi-test for an adaptable portable
   test before writing from scratch.
4. Read the SRFI spec at srfi.schemers.org/srfi-N — test the documented
   examples plus edge cases.
5. Write/extend tests as tests/scheme/srfi/srfiNNN.scm (or srfiNNN-ext.scm
   if srfiNNN.scm exists). Run each file directly with timeout 30.
6. Verify and file issues per the Session protocol (labels: bug, srfi,
   audit); comment out failing assertions with ;; FAIL: #NNN markers.

Deliverables: PR with test files, issues filed, tracker updated.
```

---

## Phase 4: Compiler & VM Edge Cases (3 sessions)

**Goal:** Test the tricky parts that are hard to catch with procedure-level
testing. Depends on Phase 1A (spec gap awareness for sections 4.x/5.x) but
not on Phases 2–3.

### 4A — Tail positions + thin-coverage forms

Proper tail recursion in all positions: `if`, `cond`, `case`, `let`, `begin`,
`when`, `unless`, `and`, `or`, `do`, `guard`, `case-lambda`, `let-values`,
`let*-values`. Existing: `tests/scheme/smoke/tail-calls.scm`,
`src/tests_tail_calls.zig` (12 tests). Known gaps: `do` loop tail positions,
`case-lambda` clause tails, `guard` handler tails, `let-values` body tails.
Test method: write loops that stack-overflow without TCO.

Thin-coverage compiler forms (each has ≤1 Zig test and ≤2 Scheme tests):

- `delay` / `delay-force` — missing iterative forcing chains (R7RS 4.2.5)
- `parameterize` — missing nested parameterize, interaction with dynamic-wind
- `define-values` — missing wrong-value-count errors and library-body uses
- `let*-values` — 1 Zig test, no Scheme test
- `letrec*` — missing ordering guarantees vs `letrec`
- `letrec-syntax` — missing recursive syntax definitions

### 4B — Continuation interactions

- call/cc + dynamic-wind (wind-in/wind-out ordering)
- call/cc + guard (re-raise semantics)
- call/cc + parameterize (parameter value capture)
- call/cc + multiple values; `values` with 0 arguments; values in non-tail
  position within `let-values`
- Multi-shot continuations with parameterize

Existing: `tests/scheme/continuations/` (13 files),
`src/tests_continuations.zig` (24 tests). **Check README known limitations
first** — continuations captured under native `map`/`for-each` cannot resume
after the native frame returns; that's documented, not a bug.

### 4C — Macro hygiene + define-library

- Deeply nested ellipsis patterns, macro-generating macros
- Shadowing: macro-introduced bindings vs user bindings
- Library-scoped transformers with `(export (rename ...))`
- `only`/`except` combined with `rename`/`prefix` import sets
- `cond-expand` in library declarations; `include` with relative paths
- Circular library dependencies (error reporting quality)

Existing: `tests/scheme/hygiene/` (12 files), `src/tests_macros.zig`
(31 tests), `src/tests_libraries.zig` (18 tests).

### Session prompt (Phase 4)

```
Read docs/audit-strategy.md — follow the Session protocol. Your unit is
Phase 4X (see the focus list for your unit).

Read R7RS sections 4.1–4.3 / 5.6–5.7 as relevant, the existing tests named
in your unit, and for 4A also src/compiler_ir.zig (compileFromNode) and
src/ir.zig (markTailPositions).

Write tests to tests/scheme/compliance/r7rs-<topic>-gaps.scm. TCO tests
must be structured to stack-overflow when the optimization is missing.
Delete stale .sbc files before re-running edited tests. Verify and file
issues per the Session protocol.

Deliverables: PR with test files, issues filed, tracker updated.
```

---

## Phase 5: Cross-Cutting Synthesis (1 session)

**Goal:** Review all issues filed, deduplicate, identify root causes,
prioritize. Runs after all other phases.

```
Read all open GitHub issues with labels "audit", "r7rs-conformance", or "srfi".
1. Group by root cause (e.g., "bignum dispatch missing in 5 procedures") —
   close duplicates, link related issues, create epics for systemic problems.
2. Prioritize: crashes > wrong results > missing features > edge cases.
3. Update the Phase 0 tracking issue with final counts and the priority order.
4. Count the ;; FAIL: markers across tests/ — each is a disabled regression
   test waiting on a fix; list them in the tracking issue.
```

**Optional hardening (recommended):** once every failing assertion is either
fixed or commented with a `;; FAIL: #NNN` marker, extend `run-all.sh` to parse
`N fail` counts from chibi-test output (as it already does for the R7RS suite)
so future chibi-test failures actually fail the run.

---

## Parallelization Plan

```
        Phase 0 (baseline)
              │
    ┌─────────┼─────────┐
    ▼         ▼         ▼
 Phase 1   Phase 2   Phase 3
 (spec     (prims    (SRFI
  gaps)     audit)    tests)
 4 units   18 units   8 units
    │         │         │
    └─────────┼─────────┘
              ▼
          Phase 4 (needs 1A only)
       (compiler/VM, 3 units)
              │
              ▼
          Phase 5
        (synthesis)
```

Within each phase, units are also independent. The only cross-phase overlap
to coordinate: Phase 2.5 and Phase 3.1 both touch SRFI-170/filesystem.

**Mechanics for concurrent sessions:** run each in its own git worktree
(`git worktree add ../kaappi-audit-<unit> main`) — parallel `zig build` in one
checkout races on `zig-out/`, and parallel edits to this tracker conflict.
Merge tracker updates promptly. The units work equally well as separate
interactive sessions or as parallel subagents launched from one orchestrating
session with worktree isolation.

**Practical recommendation:** 3–4 concurrent sessions. Beyond that, issue
triage (dedup, labeling) becomes the bottleneck, and parallel sessions start
filing overlapping findings faster than the dedup search catches them.

### Session budget estimate

| Phase | Units | Parallelizable | Time each | Wall-clock (4-way) |
|-------|------:|:--------------:|----------:|-----------:|
| 0: Baseline | 1 | — | 20 min | 20 min |
| 1: Spec gap analysis | 4 | 4 | 30 min | 30 min |
| 2: Primitives audit | 18 (≈16 sessions) | 4 | 20 min | ~80 min |
| 3: SRFI conformance | 8 | 4 | 25 min | ~50 min |
| 4: Compiler/VM edges | 3 | 3 | 30 min | 30 min |
| 5: Synthesis | 1 | — | 20 min | 20 min |
| **Total** | **~33 sessions** | | **~11 hr serial** | **~4 hr** |

---

## GitHub Issue Workflow

### Labels to create (Phase 0)

```bash
gh label create "r7rs-conformance" --description "R7RS-small spec conformance issue" --color "B60205"
gh label create "srfi" --description "SRFI implementation issue" --color "D93F0B"
gh label create "audit" --description "Found during systematic audit" --color "FBCA04"
gh label create "numeric-tower" --description "Fixnum/flonum/bignum/rational/complex" --color "0E8A16"
gh label create "continuations" --description "call/cc, dynamic-wind, guard" --color "1D76DB"
gh label create "macros" --description "syntax-rules, hygiene" --color "5319E7"
```

### Before filing — dedup check (mandatory)

```bash
gh issue list --state all --search "<procedure-name>" --limit 10
```

If a match exists, comment on it instead of filing a new issue.

### Issue title conventions

```
[R7RS 6.2] exact->inexact: returns wrong value for rationals
[SRFI-1] filter: does not preserve order for improper lists
[R7RS 4.2] named-let: not in tail position
[Compiler] case: missing tail position for last clause
```

One issue per root cause — if 5 procedures share one missing dispatch branch,
file one issue listing all 5.

### Issue body template

```markdown
**Category:** R7RS conformance / SRFI / Compiler / VM
**Spec reference:** R7RS section 6.2.6, page 38 — quote the exact sentence
**Severity:** crash / wrong-result / missing-feature / edge-case

**Minimal reproduction:**
\```scheme
(exact->inexact 1/3)  ;; expected: 0.3333... actual: 0
\```

**Expected:** 0.3333333333333333
**Actual:** 0

**Verified:** fresh ReleaseSafe build at <commit>; gc-stress unchanged/changed
**Source location:** src/primitives_numeric.zig (function name if known)
**Disabled test:** tests/scheme/audit/<file>.scm (marked ;; FAIL: #this)

**Found by:** Systematic audit, Phase N
```

---

## Community Resources

| Resource | URL | Purpose |
|----------|-----|---------|
| Chibi R7RS tests | [github.com/ashinn/chibi-scheme](https://github.com/ashinn/chibi-scheme/blob/master/tests/r7rs-tests.scm) | De facto R7RS conformance suite (1,225 assertions — ~240 more than our adaptation; diffing the two is a cheap gap-finder for Phase 1) |
| r7rs-coverage (ecraven) | [github.com/ecraven/r7rs-coverage](https://github.com/ecraven/r7rs-coverage) | Per-procedure coverage matrix across ~14 implementations |
| r7rs-coverage results | [ecraven.github.io/r7rs-coverage](https://ecraven.github.io/r7rs-coverage/) | Live conformance matrix (compare Kaappi against others) |
| SRFI portable tests | [github.com/srfi-explorations/srfi-test](https://github.com/srfi-explorations/srfi-test) | Aggregated SRFI tests in SRFI-64 format (dozens of SRFIs) |
| TaylanUB/scheme-srfis | [github.com/TaylanUB/scheme-srfis](https://github.com/TaylanUB/scheme-srfis) | R7RS SRFI implementations with SRFI-64 tests (SRFIs 0–123) |
| r7rs-tests (Retropikzel) | [gitea.scheme.org/Retropikzel/r7rs-tests](https://gitea.scheme.org/Retropikzel/r7rs-tests) | Cross-implementation R7RS test runner (low activity) |
| SRFI-64 | [srfi.schemers.org/srfi-64](https://srfi.schemers.org/srfi-64) | Standard Scheme test framework API |
