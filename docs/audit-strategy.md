# Systematic Correctness Audit Strategy (v2)

**Status:** **COMPLETE** — 51 of 53 units, plus 2 closed as subsumed (53/53). **188 issues filed** (186 carry the campaign footer; #2129, #1870 and #1920 are recoverable only by label or by the `;; FAIL:` markers), grouped into 35 root causes; see [Findings](#findings) · **Last updated:** 2026-08-02 · **Tracking issue:** [#1890](https://github.com/kaappi/kaappi/issues/1890)
· **Supersedes:** the v1 campaign (issue [#1137](https://github.com/kaappi/kaappi/issues/1137), closed 2026-07-05, 87 findings, all fixed)

## Why a second campaign

The v1 campaign audited a ~39k-line interpreter with 578 procedures, 21
primitives files, and 72 SRFIs. It closed cleanly: `grep -rn ';; FAIL:' tests/`
returns **0** — every disabled regression test it left behind has been
re-enabled.

The codebase it audited no longer exists. Since the v1 base commit
(`f13e806`, 2026-07-06): **417 commits, +66,978/−8,347 lines across 192 source
files, and 60+ entirely new `src/` files.**

| | v1 (2026-07-05) | now (2026-07-31) | growth |
|---|---:|---:|---|
| `src/*.zig` lines | ~39,000 | 116,415 | 3.0× |
| Registered procedures | 578 | 687 | 1.2× |
| `primitives_*.zig` files | 21 | 31 | +10, **none audited** |
| SRFIs | 72 | 178 | 2.5× |
| `lib/srfi/*.sld` | 64 | 162 | 132 postdate v1 |
| Scheme test files | ~380 | ~660 | 166 of 200 SRFI tests postdate v1 |
| Zig unit tests | 473 | 1,114 | 2.4× |
| R7RS suite assertions | 988 | 1,395 | — |
| Open issues | 2 | 3 | — |

**The suite is green.** A full `run-all.sh` on 2026-07-31 at `261fde5f`:

```text
Scheme files: 624 pass, 0 fail, 0 timeout, 0 skipped
R7RS suite:   1395 pass, 0 fail
Total:        2019 pass, 0 fail
```

The reconnaissance pass below found **13 reproduced bugs anyway** — including an
exactness prefix that returns `+inf.0`, a formatter that silently rewrites every
line ending in a file, and a character-set library that is a multiset. That gap
between "2,019 assertions pass" and "13 bugs in an afternoon" is the entire case
for this campaign: the suite is green because it does not ask these questions,
not because the answers are right.

**The v1 campaign covered roughly a fifth of today's surface.** For most of
this codebase, v2 is a *first* audit, not a re-audit.

Whole subsystems postdate v1 entirely: the LLVM native backend (split across 6
`llvm_emit_*` files), the fiber I/O reactor (KEP-0001) and cross-thread
channels (KEP-0002), the Windows/FreeBSD/OpenBSD/NetBSD/s390x/ppc64le ports,
the WASM target, the `.sbc` bytecode cache, the entire "machine legibility"
CLI epic (#1503 — `check`, `fmt`, `doctor`, `cache`, `test`, `features`,
`explain`, pipeline dumps, `--timings`, `--diagnostics=json`), procedural
macros (SRFI 147/148/211/213), and 10 new `primitives_srfi*.zig` files.

## What this campaign is for — and what it is not

**This is the part that changed most since v1.** The project now runs nightly
coverage-guided fuzzing (`.github/workflows/fuzz.yml`, `src/tests_fuzz.zig`,
`tests/fuzz/*.sh`) with seven targets including three differential oracles:
IR-opt vs no-opt (#1394), bytecode VM vs LLVM native (#1395), and Kaappi vs
Chibi (#1396). v1 had none of this.

Do not rebuild what the fuzzers already do. Divide the work by what each is
structurally capable of finding:

| | Fuzzers own | This audit owns |
|---|---|---|
| **Finds** | crashes, panics, leaks, sanitizer hits, tier divergence | wrong-but-stable answers, missing procedures, spec deviations, stale docs |
| **Over** | a *generated subset* — `fuzz_gen*.zig` never emits filesystem, FFI, network, thread, or most SRFI forms | the full breadth: 178 SRFIs, 687 procedures, the CLI, the library loader |
| **Oracle** | self-consistency across tiers, or Chibi | the R7RS text and each SRFI's own spec |
| **Blind to** | anything all tiers get equally wrong; anything outside the grammar | anything needing millions of random inputs |

A concrete illustration from the reconnaissance below: **SRFI 14 is a multiset
that claims to be a character set, exports 23 of ~60 names, and is ASCII-only
while `(cond-expand (srfi-14 ...))` answers yes.** No fuzzer will ever find
that — every tier agrees, nothing crashes, and the generator does not emit
`char-set` forms. Conversely, no auditor would have found the divergences the
nightly oracles catch. The two programs are complements.

**Corollary for prioritisation:** prefer units where the oracle is a *document*
(a spec section, a SRFI page, a `docs/dev/*.md` guarantee) over units where the
oracle is *the implementation's own other half*. The latter is the fuzzers' job.

---

## Findings

Phase 8's synthesis, 2026-08-02. The campaign filed **188 issues** across 53
units; **170 are open**, 18 were fixed while it ran. A pile that size is raw
material, not a result — this section is the map.

### The shape of it

| | |
|---|---:|
| Issues filed carrying the campaign footer | 186 |
| Open campaign issues (footer ∪ `audit` label ∪ `;; FAIL:`-cited) | **170** |
| Closed during the campaign | 18 |
| Distinct root-cause groups the 170 fall into | **35** |
| Groups where one fix closes ≥ 2 issues | 24 |
| Issues where **the process dies or wedges** on ordinary input | **19** |
| Disabled assertions (`;;`- and `;;;`-style markers, 36 files) | 434 |

Neither tracking query alone finds every campaign issue. **2129** carries the
`audit` label but not the footer; **1870** carries the footer but not the
label; and **1920** carries **neither** — it is recoverable only from the
`;; FAIL:` markers, which is an argument for keeping that inventory as a
tracking artefact rather than only a test-hygiene one.

### The ten groups that matter

Full assignment of all 170 lives in the tracking issue's synthesis comment.
These are the ones where the grouping changes what a maintainer should do.

| Group | n | Root cause | The fix that closes the group |
|---|--:|---|---|
| **R1** cross-heap ownership | 13 | `Object.owner` enforcement is opt-**in** and exists for exactly **2 of 36 heap types** — channels and thread handles. `gc_deep_copy.zig:526` says so in a comment | Make the owner check a shared, opt-*out* helper at every primitive that dereferences a heap object it did not allocate |
| **R16** error taxonomy | 10 | Shared helpers cannot name their caller; the type branch and the range branch share one message | Thread the caller's name; split the two branches |
| **R19** thottam | 11 | Hand-rolled permissive version parsing (3), and the lockfile treated as the source of truth instead of the installation (5) | Two patches, one per sub-root |
| **R10** green-but-testing-nothing | 8 | Five separate mechanisms, one consequence: a check reports success having asserted nothing | Make failure detectable *first* — see "What to do first" |
| **R15** macro hygiene | 7 | Hygiene is renaming-**by-spelling**, so a template's free reference is resolved at the use site by name | Resolve template free references at definition site |
| **R3** reader exactness | 6 | `applyExactness` exists **twice** with different strategies (`reader_tokens.zig:393` un-rounds an f64; `primitives_numeric.zig:979` rebuilds from digits) | Delete the reader's copy and call the other |
| **R7** `.sbc` cache | 6 | A HIT round-trips *values* but not the *properties attached to them* — immutability, sharing, the macro table, source lines | Serialise the properties; add the target to the key |
| **R4** reader refill | 4 | The tokenizer does not preserve a partial token across the 4096-byte chunk boundary | One fix; **merge the four into one issue** |
| **R2** unvalidated → abort | 4 | An unvalidated value reaches a Zig `@intCast`/`@intFromFloat`/size computation and the process **panics** | Validate or widen at four sites |
| **R8** top-level dispatch | 2 | `handleTopLevelForm` both *recognises* a top-level head and *evaluates* it, so every caller gets evaluation as a side effect of asking | Split into `classify` + `run` |

### What to do first

Ranked by reachability × blast radius ÷ cost, not by severity label.

1. ~~**R10 — make failure detectable, before fixing anything else.**~~ **DONE**
   (2026-08-03, [#2116](https://github.com/kaappi/kaappi/issues/2116),
   [#2157](https://github.com/kaappi/kaappi/issues/2157),
   [#2162](https://github.com/kaappi/kaappi/issues/2162),
   [#2163](https://github.com/kaappi/kaappi/issues/2163)). Until this landed,
   every fix's regression test was of unknown value. Verified: the
   `(chibi test)` shim prints `1 fail` and **exits 0**, and five `ci.yml` steps
   ran `r7rs-tests.scm` bare — 1,395 assertions gated nothing on those legs;
   `run-all.sh`'s net required a failure *count*, so it matched neither
   `#f` nor a bare `FAIL:`, leaving 54 files unable to fail. This was the
   campaign's most-repeated finding and its only *meta* one.

   What shipped: all 56 verdictless files given a verdict — 52 converted to
   the SRFI-64 exit-on-fail shape and 4 kept on a hand-rolled `(exit 1)` for
   tier reasons (55 of the 56 came from the issue's own enumeration; the 56th,
   `deep-nesting-print-tier-margin.scm`, was missed by that enumeration's
   predicate because the word "assert" appears in one of its comments), plus
   `fiber-error-handling.scm` converted as a 53rd; a
   **verdict-channel check** in `run-all.sh` so the count cannot grow back
   from zero; the stdout net widened to a bare `FAIL` token; one shared
   `tools/run-r7rs-suite.sh` behind all seven R7RS callers; and `run-all.sh`
   made to refuse rather than silently build a default binary, printing the
   binary's `features --json` configuration in its header.

   **The predicted second finding appeared immediately**, as the ordering
   hazard in #2157 warned it would: the widened net caught
   `smoke/fiber-error-handling.scm` asserting the #551 behaviour that
   kaappi#1155 deliberately **reversed** — printing `FAIL - should have
   raised` and exiting 0 ever since #1155 merged. That is the clearest
   possible evidence the coverage did not previously exist.
2. **R2 — four ways ordinary Scheme kills the process.** Reproduced two:
   a 27-field record (plain R7RS `define-record-type`) panics with an integer
   overflow in `allocRecordInstance`, and `#e` on a decimal near 2^63 panics
   **inside `kaappi check` and `kaappi fmt`**, which execute nothing — so an
   editor opening an untrusted file is enough. Four sites, one fix pattern.
3. **R1 — the thread model's ownership hole.** Four of the ten `critical`
   issues live here, and the failure mode is the worst available: silent abort
   with empty stdout *and* stderr. One structural change retires the
   missing-owner-check half outright.
4. **R8 + R9 — split the dispatcher.** Reproduced both: `kaappi --compile`
   *executes* top-level `begin`/`cond-expand`/`define-values` bodies, and all
   eight uncacheable heads report `not cached: imports`. The same split also
   deletes `vm_eval.zig:135`'s `isSpecialTopLevelForm`, a hand-maintained
   mirror whose own comment says "Keep this list in sync" — **unfiled**, and a
   fourth instance of R9's pattern.
5. **R3 — delete the reader's second `applyExactness`.** Six issues, one
   deletion; 1911 is already written as the umbrella and 1907 (item 2) is the
   same code.

**Deliberately not first**, with reasons — severity alone would have ranked
these higher:

- **SRFI 166 (R25, 8 issues** — Phase 3.5 filed **11**; #2062 and #2066 regroup into R21 *byte vs codepoint vs column* and #2067 into R11, which is the regrouping doing its job**)** is the largest single count in the campaign and
  the *lowest* leverage per issue. The tracker's "close to one root cause"
  claim is **false**: re-verified in Phase 8 by routing the three issues it
  names as derived through the working procedural mechanism, which still gives
  the wrong answer — the failures are on the *consumer* side. These are 11
  separate procedures to write. Treat SRFI 166 as unimplemented rather than
  buggy, and let R11 make `cond-expand` stop claiming it.
- **thottam (R19, 11)** — low reachability, and no defect corrupts a running
  program.
- **Error taxonomy (R16, 10)** — nothing computes a wrong answer.

### Deduplication

Recommended closes, each verified:

- **1892 → close, superseded by 1929.** 1929 is the real defect: the guard has
  never executed since it was written.
- **1902 → close, decomposed** by Phase 1D into 1953 / 1954 / 1955 — three
  mechanisms with three distinct cliffs.
- **1900 → close, already fixed.** `tests/scheme/srfi/slow/` no longer exists
  (deleted in `e699b451`, PR 2071) and `run-all.sh:432` now carries the
  `test-begin` gate. Stale-open.
- **1893 / 1940 / 1945 / 1920 → merge into one.** One defect, four symptoms.
- **1911 stays** as the umbrella; its five members close with it.

Checked and **not** duplicates, so nobody re-tests them:

- **2003 vs 2074** — Phase 3.7 already recorded the negative result: a
  template's `car` is hijacked in argument position too, so the mechanisms
  differ.
- **1949 vs 2084** — the same missing precondition in two independently written
  files, and 2084 carries a second, unrelated defect (non-tail recursion).
- **2034 vs 1999** — same bug *class*, no shared code: `callHandler`/`callThunk`
  (`vm_calls.zig`) and `spawnFiber` (`fiber.zig:386`) each hand-roll frame setup
  instead of routing through `callClosure`, and each inherits none of its
  validation. Two patches, one narrative.

### The `;; FAIL:` inventory

**434** marker lines in **36** files citing **101 distinct numbers** — counting
both spellings, `;;` (431) and `;;;` (3). Result:

- **No marker cites a closed issue.** Nothing is sitting disabled behind a fix
  that already landed — the convention held for the whole campaign.
- **One marker cites a merged PR, not an issue.**
  `tests/scheme/compliance/reader-exactness-gaps.scm:381` reads `;; FAIL: #1919`;
  1919 is the *pull request* "Stop a VM limit from arriving as a catchable
  condition". Its text matches issue **1921** exactly. Because a PR reports as
  `MERGED`, any mechanical audit of marker states reads this one as done.
- **Three markers use `;;;`, not the documented `;;`**
  (`tests/scheme/audit/primitives_srfi160-audit.scm:265,711,757`). A grep for
  the convention misses them — which is R9's pattern inside the convention
  meant to guard against it.

### Two new findings the synthesis produced

- **The `segment`-at-`n=0` class has four members, not two.** 1949 and 2084 are
  filed; `string-segment` (`lib/srfi/152.sld:202`) and `range-segment`
  (`lib/srfi/196.sld:105`) are **unfiled** and hang identically — verified, with
  `n=1` as the control. `tsegment` (`lib/srfi/171-impl.scm:327`) raises
  `"argument to tsegment must be a positive integer"`, which is the
  discriminating control: this is a missing precondition, not an inherent shape.
- **`isSpecialTopLevelForm` is a fourth hand-maintained parallel list**
  (`vm_eval.zig:135`), unfiled, and it disappears if R8's split is done.

---

## Reconnaissance findings (2026-07-31)

A seven-agent reconnaissance pass ran before this document was written. It
produced **13 reproduced findings**, listed here so Phase 0 can file them
immediately rather than rediscovering them. Every row marked **[R]** was
reproduced a second time by the orchestrating session against
`zig-out/bin/kaappi` v0.22.1 (build `261fde5f`, macOS aarch64, ReleaseSafe);
rows marked **[A]** were single-source agent reports at the time of writing.

**All 13 are now filed** (Phase 0A, 2026-07-31) as
[#1891](https://github.com/kaappi/kaappi/issues/1891)–[#1903](https://github.com/kaappi/kaappi/issues/1903),
tracked from [#1890](https://github.com/kaappi/kaappi/issues/1890). Twelve
issues rather than thirteen: F1 and F2 share one root cause, and this document
mandates one issue per root cause. Both `[A]` rows were reproduced before
filing, and reproducing F12 corrected it — a *flat* cdr-cycle prints its label
correctly; only a **car-nested** cycle past the depth limit loses it. Keep the
table below for the repro recipes and controls; the issues carry the fixes.

| # | Finding | Repro | Severity |
|--:|---|---|---|
| F1 **[R]** | `#e1e19` reads as **inexact** `1e19`; `#e1e18` is correctly exact. R7RS §7.1.1 requires `#e` to yield an exact number. Cliff is exactly the i64 range — the overflow path in `reader_tokens.zig` falls back to `parseFloat` and drops the prefix. | `(exact? #e1e19)` ⟹ `#f` | wrong-result |
| F2 **[R]** | `#e1e400` ⟹ **`+inf.0`** — an exactness prefix producing an infinity. Same root cause as F1; should be a bignum. | `#e1e400` ⟹ `+inf.0` | wrong-result |
| F3 **[R]** | Radix-prefixed integers have **no trailing-delimiter check**, so one token silently reads as two datums. The `#t`/`#f` path does check. | `'(#b1p4)` ⟹ `(1 p4)`; `'(#o1e3)` ⟹ `(1 e3)` | wrong-result |
| F4 **[R]** | **The 4 KB reader bug is still live** (first seen 2026-07-19, never filed). A string literal straddling the port read-buffer refill boundary raises a spurious `KP3000: read error`. Discriminating control: an otherwise byte-identical file with a bare symbol in place of the string reads all 1024 datums. Needs `(read p)` on an `open-input-file` port — string ports and whole-file loading read into memory first and cannot hit it. | see `docs/dev/` note added in Phase 0 | wrong-result |
| F5 **[R]** | `kaappi expand` **violates the round-trip guarantee** documented at `docs/dev/observing-the-pipeline.md:90`. A `let-syntax` body is expanded with the *outer* macro, then the unapplied inner binding is re-emitted. 10 corpus files affected. | direct run `99`; expand→rerun `42` (4-line repro) | wrong-result |
| F6 **[R]** | **SRFI 14 is not a set.** `(char-set #\a #\a #\b)` ⟹ `(#\a #\a #\b)`; `char-set:letter` and even `char-set:full` are ASCII-only (`#\λ` ∉ `char-set:full`); 23 of ~60 spec names exported. `(cond-expand (srfi-14 ...))` answers yes, so portable code trusts it. | `(char-set-contains? char-set:full #\λ)` ⟹ `#f` | missing-feature + wrong-result |
| F7 **[R]** | `isRejectedFormHead` (`llvm_emit_forms.zig:400`) is a **hand-maintained 32-name list** parallel to the comptime-derived `ir.eval_fallback_form_names`, and is missing **`define-property`**. CLAUDE.md's stated hazard has *moved*, not closed: the derived list is complete and self-maintaining; this one is neither. | list diff; `--emit-llvm` defers the form to runtime | latent miscompilation |
| F8 **[R]** | `kaappi fmt` **silently converts CRLF→LF**, and `fmt --check` exits 1 on a canonical CRLF file. Windows is a supported platform; `docs/dev/fmt.md` never mentions line endings. The `equal?` round-trip safety net cannot see it. | 28-byte CRLF file → 26 bytes | data-modifying |
| F9 **[R]** | **`-Dgc-stress=true` never runs on a PR.** It appears 0 times in `ci.yml` and 13 times in the scheduled `fuzz.yml`. Neither TSan nor valgrind appears anywhere. | `grep -c gc-stress .github/workflows/ci.yml` ⟹ 0 | process gap |
| F10 **[R]** | Type errors **drop the value's identity** for heap types: a fixnum renders as `42`, a symbol as `#<symbol>`. Affects ~700 error sites via `safeValueDescription`. | `(vector-ref (vector 1 2) 'x)` ⟹ `got #<symbol>` | diagnostic quality |
| F11 **[R]** | `run-all.sh`'s globs are **non-recursive**, so `tests/scheme/srfi/slow/` (2 files, the full SRFI 257 + 257-rx reference suites) is referenced by nothing and never runs. `kaappi test` does pick them up. | `ls tests/scheme/srfi/slow/` | coverage gap |
| F12 **[A]** | `printer.zig`'s fixed 1024-entry `MAX_SHARED`/`MAX_PRINT_DEPTH` arrays **silently truncate**: `write` of a 1100-deep nest emits unreadable output with no error, and `write-shared` drops *all* labels past ~1000 shared cells, silently losing sharing. | agent-reported | wrong-result |
| F13 **[A]** | `kaappi test` and `run-all.sh` **disagree** on `tests/scheme/srfi/srfi150.scm` (exit 1 vs 0), with a self-contradictory summary (`21 passed, 0 failed, 4 expected-fail` beside `1 errored`). Blocks `kaappi test` from replacing the legacy runner. | agent-reported | tooling correctness |

### Documentation-truth findings

Five separately-verified claims that **CLAUDE.md and `docs/dev/` describe a
codebase that no longer exists**. An auditor trusting them wastes sessions
chasing fixed bugs — which makes Phase 0's truth pass the highest-leverage
half-hour in the campaign.

| Claim in the docs | Reality |
|---|---|
| Expander limitations #1800, #1801, #1791, the `(let-syntax … (define-syntax …))` failure, and the library-body `define-record-type` shadowing gap are open | **All five are fixed and do not reproduce.** Only #1832 (SRFI 150's 4 expected failures) is genuinely live — and its cited issue is *closed*, so either the fix is incomplete or the annotation is stale |
| SRFI 148: "134 pass, 8 `test-expect-fail` citing #1800/#1801" | **142 pass, zero `test-expect-fail`**; the header's issue citations are dead comments |
| A keyword missing from `eval_fallback_form_names` is a silent miscompilation | That list is now **comptime-derived and self-maintaining**. The hazard lives in `isRejectedFormHead` — see F7 |
| SRFI 120 timers cause nondeterministic **memory corruption** from a second thread ("not root-caused", the most alarming open bug in the tree) | **Did not reproduce.** Both documented entry paths now fail cleanly with precise errors, and the named mechanism (multi-hop nested-channel promotion) survived ~4,000 round trips and 20 soak processes. `<timer>` holds a Fiber, which `gc_deep_copy` rejects as structurally uncopyable — the constraint is now *engine-enforced*. Scope this as **validate-or-retire**, not root-cause |
| `docs/dev/srfi-exclusions.md` excludes SRFI 58 and 163 partly because "SRFI 160 has no implementation at all" / "SRFI 4 is a purely portable wrapper" | **Both statements are now false.** Only the reader `#N=` datum-label ambiguity still stands; 58 and 163 become genuinely re-considerable |

---

## Key principles

- **Prefer a documentary oracle.** Audit against a spec sentence, a SRFI page,
  or a `docs/dev/*.md` guarantee you can quote. Where the only oracle is the
  implementation's other half, that is fuzzer territory — see the table above.
- **Reproduce before filing.** The reconnaissance pass produced two
  false negatives (the 4 KB bug reported fixed when it is live; the SRFI 120
  corruption reported live when it is not) and several false positives from
  harness artefacts. Both directions cost real time. One independent re-run,
  with a *discriminating control*, is the cheapest insurance in this document.
- **Separate discovery from fixing.** File issues; do not fix. This overrides
  Step 4 of the `/audit-primitives` skill for the duration of the campaign.
- **Divide by domain, not by file count** — spec section + implementation +
  tests in one agent's context.
- **Test-first discovery** — run the existing tests for your domain before
  reading any source. Failures found there are free.
- **A stale doc is a finding.** Five of the six documented expander
  limitations were fixed without the docs being updated. File those too.
- **Each session is self-contained** — one domain, one report, one set of
  issues, one PR.

---

## Session protocol

Read this before every session. The phase sections say *what*; this says *how*.

1. **Worktree.** `git worktree add ../kaappi-audit-<unit> main`. Concurrent
   `zig build` in one checkout races on `zig-out/`. (This is now mandatory,
   not advisory — the reconnaissance pass hit it.)
2. **Rebuild.** `zig build`. Never trust an existing binary. If behaviour looks
   globally insane, check `zig-out/bin/kaappi --version` first.
3. **Clear the bytecode cache after every rebuild you intend to A/B against.**

   ```bash
   kaappi cache clear
   ```

   The cache key folds in the git build id, which for uncommitted work is the
   commit hash plus a bare `-dirty` flag — **not** a hash of the changes. Two
   different uncommitted edits at the same base commit alias to the same id and
   share entries. This has cost multiple sessions, presenting as nondeterminism.
   See `docs/dev/cache.md`.
4. **Run the existing tests for your domain first.**

   ```bash
   kaappi test tests/scheme/srfi          # SRFI-64 suites, aggregated
   kaappi test --json tests/scheme/audit  # machine-readable
   bash tests/scheme/run-all.sh           # everything, incl. shell suites
   ```

   `kaappi test` is the first-class runner (`docs/dev/test-runner.md`) and is
   what v2 uses by default; `run-all.sh` remains the only thing that drives the
   chibi-test R7RS suite and the shell suites. **They currently disagree on at
   least one file (F13)** — if your domain's counts differ between them, that is
   itself a finding.
5. **Write new tests** per your phase, as `(srfi 64)` with the exit-on-fail
   epilogue (grab the runner *before* `test-end`). See `tests/scheme/CLAUDE.md`
   — but note its directory table is stale (Phase 0 fixes it).
6. **Verify each failure before filing:**
   - Reproduce on the fresh build from step 2, with the cache cleared.
   - Re-read the exact spec text and quote it. Do not trust memory of what
     R7RS or a SRFI requires.
   - **Construct a discriminating control** — a near-identical input that
     *should* behave differently. F4's symbol-vs-string control is the model:
     it converts "this errors" into "this errors *because of the string path*".
   - Check `README.md § Known limitations` and `CONFORMANCE.md` — documented
     deviations (SRFI 248 handler timing, continuations under native drivers,
     fibers in native-driver callbacks) are not bugs.
   - Check whether the docs merely *claim* it is broken. Five such claims were
     stale as of 2026-07-31.
   - For crashes or nondeterminism, retry under `zig build -Dgc-stress=true`
     and say whether behaviour changes — it localises GC bugs.
   - Dedup: `gh issue list --state all --search "<proc-name>"`.
7. **Commit tests so the suite stays green.** Passing tests: enabled. Failing
   tests: comment out with a marker directly above —

   ```scheme
   ;; FAIL: #1234 (#e1e19 reads as inexact)
   ;; (test-assert (exact? #e1e19))
   ```

   The fix PR re-enables it. **Prefer this to `test-expect-fail`** when the
   failure is a raise rather than a wrong value: an expected-fail case that
   never *returns* wedges the suite (`compliance/printer-gaps.scm` documents
   that shape). The rule stands, but its original justification does not —
   it cited the F13 divergence, and Phase 6B ([#2081](https://github.com/kaappi/kaappi/pull/2081))
   showed that was never about `test-expect-fail` at all, and fixed it.
8. **Open a PR**, tick your box in the tracker, post one line on the tracking
   issue.

### Footguns

- **`timeout` does not exist on stock macOS.** Use the `run_timeout` helper in
  `tools/audit-baseline.sh` (tries `timeout`, then `gtimeout`, then
  `perl -e 'alarm shift; exec @ARGV' 30 <cmd>`). A hang is a finding.
- **Run expanded/reformatted files in the original's directory.** A
  round-trip harness that runs the output from a different cwd breaks relative
  `include` and `--lib-path` resolution and produces pure false positives —
  6 of 8 in the reconnaissance sweep.
- **`(chibi test)` never exits non-zero.** Only `r7rs-tests.scm` still uses the
  shim; `run-all.sh` parses its counts specially.
- **Stay on ReleaseSafe.** Debug is ~500× slower on allocation-heavy tests.
- **PDF reading:** `docs/errata-corrected-r7rs.pdf` is ~88 pages; the Read tool
  takes ≤20 pages per request. Read the table of contents, then only your
  domain's pages. Never the whole spec.
- **Do not run `kaappi cache clear` against your real `$KAAPPI_HOME`** when
  probing cache behaviour — export an isolated one, as `run-all.sh` does.
- **Name every assertion.** `(test-equal "what it checks" expected actual)`,
  never the two-argument form. SRFI-64's runner prints the failed assertion's
  *value*, not its source, so an unnamed failure on a remote CI leg is literally
  `#f` / `FAIL` with nothing to identify which of 400 assertions broke. SRFI-64
  has a `source-line` field and nothing populates it — portable `syntax-rules`
  cannot capture source location, so the name is the only channel. Phase 2.12
  burned two CI rounds on this before the names went in; the round after, the
  log said `FAIL (memv (file-info:rdev fi) '(0 -1))` and named the defect
  outright. Deriving names mechanically from the expression under test is fine —
  but **truncate the label before escaping backslashes**, or a cut lands between
  `\` and the character it escapes (slicing `#\z` to `#\`) and the file no longer
  reads.
- **Never assert that a bug is still present.** Pin the *specified* property,
  not the current symptom. Three such pins were written in this campaign after
  a real bug was found — it feels like the responsible thing to do — and all
  three failed on a platform other than their author's, because the symptom
  depended on the allocator rather than on the code: #2023's miss count held on
  ReleaseSafe and failed on the Debug leg (94 of 200 deep keys found under
  Debug, 6 of 200 under ReleaseSafe); #2027's "the aliased handle arrives
  unusable" held on macOS and failed on FreeBSD, **after** the PR had merged on
  stale green, leaving `main` red on five legs. Where a bug-adjacent tripwire is
  genuinely wanted, assert the classification instead: "the join does not refuse
  this tag" flips when the aliasing is fixed, and does not depend on how a freed
  pointer happens to behave.
- **A rebase followed quickly by a merge can land on stale green.** The checks
  showing green may belong to the *previous* push while the rebase-triggered run
  is still queued. #2030 merged at 14:41 on checks green for an earlier head; the
  new run finished 15:03–15:45 and failed. Re-check that the run whose checks you
  are reading actually points at the current head before merging.
- **Never assert a value the spec or the platform leaves unspecified** — assert
  the type, or the property the spec actually states. POSIX defines `st_rdev`
  only for character- and block-special files, so two successive guesses at
  `file-info:rdev` on a regular file both failed on CI (first `0` for
  macOS/Linux, then `{0, -1}` adding FreeBSD's `NODEV`); FreeBSD 14.3 duly failed
  for a regular file while *passing* for a fifo in the same run. Same rule:
  `@intFromFloat` on NaN is UB, so assert "does not abort", not the value
  (Phase 5D, caught only on NetBSD); and never assert wall-clock timing on the
  emulated legs — assert relative ordering.
- **A test's side effects must not be platform-scaled either, and
  `( ulimit -n 256; … )` is the cheapest BSD-leg simulator you have.** Phase
  2.12 opened 3000 directory streams without closing them; that passed on macOS
  and Linux (`ulimit -n` 1048576) and exhausted the descriptor table on
  `openbsd-test`/`netbsd-test`, taking down the *next* block — so the visible
  error named a file the failing test never mentions. One subshell turned an
  unreproducible remote failure into a deterministic local one, and produced the
  finding underneath it ([#1993](https://github.com/kaappi/kaappi/issues/1993)).

---

## Progress tracker

Tick when the PR is open and issues are filed; add date and issue numbers.

**Phase 0 — Baseline and documentation truth**

- [x] 0A: Baseline run, tracking issue, labels, file F1–F13 (2026-07-31, [#1890](https://github.com/kaappi/kaappi/issues/1890) tracking; baseline fully green at `261fde5f` — 624/624 Scheme files, 1395/1395 R7RS assertions, 0 fail; all 13 reconnaissance findings filed as 12 issues [#1891](https://github.com/kaappi/kaappi/issues/1891)–[#1903](https://github.com/kaappi/kaappi/issues/1903) — `#e1e19`/`#e1e400` merged as one root cause; labels `tier-divergence`, `tooling`, `doc-truth` created)
- [x] 0B: Documentation-truth pass (2026-07-31, [#1901](https://github.com/kaappi/kaappi/issues/1901); all 6 items corrected — every claim re-verified against v0.22.1 first, which corrected two of the reconnaissance findings in turn: `srfi148.scm`'s header is accurate rather than stale, and there are 6 `test-expect-fail` calls repo-wide (4 in `srfi150.scm`), not 7/6)

**Phase 1 — Reader, printer, numeric tower** (independent)

- [x] 1A: `#e`/`#i` exactness over the i64 boundary (F1, F2) + `string->number` parity (2026-07-31, [#1917](https://github.com/kaappi/kaappi/pull/1917); 128 assertions, 39 disabled — filed [#1907](https://github.com/kaappi/kaappi/issues/1907) reader **panics** on `#e` at 2^63 and aborts `check`/`fmt`/`ast`, [#1908](https://github.com/kaappi/kaappi/issues/1908) `#i` on a radix bignum reads digits as decimal, [#1909](https://github.com/kaappi/kaappi/issues/1909) `#e` below 1e-15 collapses to 0, [#1910](https://github.com/kaappi/kaappi/issues/1910) no Complex arm, [#1911](https://github.com/kaappi/kaappi/issues/1911) umbrella: **two divergent `applyExactness` implementations**, [#1921](https://github.com/kaappi/kaappi/issues/1921) unprefixed 2^63 decimal; reopened #751)
- [x] 1B: Radix-prefix delimiter checking (F3), all radices × invalid trailing chars, without breaking SRFI 169 separators or SRFI 270 hex floats (2026-07-31, [#1931](https://github.com/kaappi/kaappi/pull/1931); 148 assertions, 58 disabled — 494-cell sweep, 382 split; filed [#1929](https://github.com/kaappi/kaappi/issues/1929), which supersedes #1892: **`Reader.readIntegerWithRadix` has never executed** since the commit that added its guard)
- [x] 1C: Port read-buffer refill (F4) — string, symbol, char, block-comment, and raw-string tokens across the 4096/8192 boundaries (2026-07-31, [#1946](https://github.com/kaappi/kaappi/pull/1946); 23 assertions, 23 disabled — 1714 configurations; filed [#1940](https://github.com/kaappi/kaappi/issues/1940) silent splits incl. **a line comment's tail becoming program data**, [#1945](https://github.com/kaappi/kaappi/issues/1945) UTF-8 codepoint split; corrected #1893's own control, which was unsound)
- [x] 1D: Printer limits (F12) — `MAX_SHARED`/`MAX_PRINT_DEPTH` cliffs at n=1023/1024/1025, 2000-deep cycles, `write-shared` label exhaustion (2026-07-31, [#1956](https://github.com/kaappi/kaappi/pull/1956); 79 assertions, 16 disabled — filed [#1953](https://github.com/kaappi/kaappi/issues/1953) a leaf at depth **1023** renders as `.../...`, a legal datum with the wrong value (1024 errors loudly), [#1954](https://github.com/kaappi/kaappi/issues/1954) four container arms hang on cycles incl. `display`, [#1955](https://github.com/kaappi/kaappi/issues/1955) `write-simple` emits labels. #1902 decomposed into three mechanisms with three cliffs; a claim that #859 still reproduced was **dropped** after a discriminating pty test showed it does not)

**Phase 2 — Primitives** (independent; order = risk)

- [x] 2.1: The `%`-prefixed internal-primitive surface (~53 procedures reachable from user code, zero test mention) — see dimension D1 (2026-07-31, [#1918](https://github.com/kaappi/kaappi/pull/1918); 239 assertions — 51 of 66 `%` procedures callable with no import; filed [#1912](https://github.com/kaappi/kaappi/issues/1912) **wasm32 truncates indices to u32**, silent wrong reads *and writes* on plain `vector-set!`, [#1913](https://github.com/kaappi/kaappi/issues/1913)–[#1916](https://github.com/kaappi/kaappi/issues/1916); **zero panics** across ~180 adversarial calls)
- [x] 2.2: `primitives_io.zig` (+1108 lines against a 112-line audit test; custom-port and transcode branches are new) (2026-07-31, [#1947](https://github.com/kaappi/kaappi/pull/1947); 49 → 197 assertions, all 45 specs covered; filed [#1939](https://github.com/kaappi/kaappi/issues/1939) re-entrant custom-port read **aborts the process**, [#1941](https://github.com/kaappi/kaappi/issues/1941)–[#1944](https://github.com/kaappi/kaappi/issues/1944))
- [x] 2.3: `primitives_srfi181.zig` (new, no test) — custom-port callback re-entrancy and the blocking rejection (2026-08-01, [#2015](https://github.com/kaappi/kaappi/pull/2015); 196 assertions, 17 disabled — filed [#1995](https://github.com/kaappi/kaappi/issues/1995) **`read` returns `#<eof>` on every custom and transcoded port** (`readDatumFn` is the one primitive that goes around `readOneByte`), [#1996](https://github.com/kaappi/kaappi/issues/1996) `port-position` ignores the port's own read-ahead, [#1997](https://github.com/kaappi/kaappi/issues/1997) transcoded *output* ignores `#\return` as a line ending so a `crlf` round trip doubles every line break, [#1998](https://github.com/kaappi/kaappi/issues/1998) `close-input-port` closes the output side too, and — found while writing the suite, not SRFI-181-specific — [#2012](https://github.com/kaappi/kaappi/issues/2012) the first `(environment '(srfi N))` on a **file-backed** `.sld` silently abandons the rest of the enclosing top-level form. The blocking-callback guard is **correct at all six callback sites** and every rejection stays catchable; the eol-style *decode* matrix is correct in all 9 cells including the previously untested `lf`-on-input; deep copy refuses custom and transcoded ports cleanly at both SRFI-18 boundaries)
- [x] 2.4: `primitives_srfi160.zig` (new, no test) — 11-way element-kind dispatch over raw bytes, c64/c128 packing (2026-07-31, [#1952](https://github.com/kaappi/kaappi/pull/1952); 1066 assertions — filed [#1949](https://github.com/kaappi/kaappi/issues/1949) `Uvector-segment` with `n=0` **hangs**, [#1950](https://github.com/kaappi/kaappi/issues/1950)/[#1951](https://github.com/kaappi/kaappi/issues/1951) c64/c128 elements are always Complex. The 12-kind × boundary matrix and both seams are **correct**; the two range rules agree across 276 cells)
- [x] 2.5: `primitives_srfi237.zig` (new, no test) — sealed/opaque/uid, multi-level inheritance (2026-08-01, [#1975](https://github.com/kaappi/kaappi/pull/1975); 186 assertions, 26 disabled — filed [#1973](https://github.com/kaappi/kaappi/issues/1973) a **27-field record aborts the process** via u8 size arithmetic, reachable from plain R7RS `define-record-type`, and [#1974](https://github.com/kaappi/kaappi/issues/1974) four R6RS defects — **#1974 is fixed** ([#1989](https://github.com/kaappi/kaappi/pull/1989)), which enabled its 10 disabled assertions and re-pinned the 20 that documented the defects, taking the file to 209. Protocol composition is exact at 16/16 masks; the **nongenerative** cross-thread path is pinned enabled so #1932's fix flips a test)
- [x] 2.6: `primitives_fiber.zig` (+1241 lines against a 135-line audit test) (2026-08-01, [#2004](https://github.com/kaappi/kaappi/pull/2004); 32 → 111 assertions, 9 disabled — all 11 specs, KEP-0002 §6 (capacity/rendezvous/close/timeouts), the KEP-0001 park-vs-drive protocol, and **both directions** of the cross-thread sharing model. Filed [#2000](https://github.com/kaappi/kaappi/issues/2000) a blocking channel/fiber call inside a SRFI-181 custom-port callback **bypasses `in_custom_port_callback` and aborts the process** (SIGBUS, 5/5 at n=3000, clean at 2400; the `thread-sleep!` control is rejected at every depth), [#1999](https://github.com/kaappi/kaappi/issues/1999) `spawn` never binds the thunk's parameters so a non-thunk runs anyway with `#<undefined>` and the fiber's own closure as arguments, [#2001](https://github.com/kaappi/kaappi/issues/2001) `fiber-join` has **no `Object.owner` check** — a child thread joins a parent-heap fiber and a cross-thread `set-car!` is observed by the parent, [#2002](https://github.com/kaappi/kaappi/issues/2002) argument diagnostics. The channel owner check, deep-copy closure, delivery-wins and rendezvous accounting are **correct** on every route probed; surplus-argument tolerance is the codebase-wide convention, so it is pinned rather than reported. WASM was reasoned from the registration tables, not executed)
- [x] 2.7: `primitives_srfi18.zig` (+793/−352) — deep-copy round-trip for every new heap type (2026-08-01, [#2030](https://github.com/kaappi/kaappi/pull/2030); 122 assertions, 5 disabled, green in both ReleaseSafe and `-Dgc-stress=true` — the **full 41-tag × 3-boundary matrix**, the first enumeration of it. Filed [#2027](https://github.com/kaappi/kaappi/issues/2027) `gc_deep_copy` **aliases FFI handles across heaps**: a child-created `ffi-fn`/`ffi-library` is reclaimed by the child's own collector while the receiver holds it, arriving type-confused as `(0.0 . 0.0)` — 3/3 at *all three* copy boundaries incl. `channel-send` with the child still alive, so the source comment's "dangles once the child heap is freed" understates it; the A/B/C control isolates the cliff to **which heap allocates**, and gc-stress is unchanged. [#2028](https://github.com/kaappi/kaappi/issues/2028) doc-truth: `thread-value-sharing.md` has no *aliased* class, so the one unsound alias is invisible in the table built to answer exactly that question; `ffi-callback` is no longer "not probed" (globals **works**, both copy boundaries refuse). **All 22 reachable copied arms are correct** (of 24 — `flonum` and `native_closure` aren't constructible from interpreted Scheme): content fidelity holds for hash-table comparison mode, parameter converters, forced/unforced promise state, error message+irritants, bignum/rational/complex exactness, uninterned-ness, and internal *sharing* — and the 13 reachable refusals are clean, with a previously unpinned uniform asymmetry: IN refusals arrive **wrapped** in `uncaught-exception?`, OUT refusals **direct**. Extended [#1932](https://github.com/kaappi/kaappi/issues/1932) to the raise path (a third direction its repro did not cover) with the `nongenerative` control passing in all three. `flonum` and `native_closure` confirmed unreachable from interpreted Scheme; `multiple_values` never survives to a boundary)
- [x] 2.8: `primitives_hashtable.zig` (+403, 8 callback sites) (2026-08-01, [#2031](https://github.com/kaappi/kaappi/pull/2031); 77 → 201 assertions, 8 disabled — filed [#2023](https://github.com/kaappi/kaappi/issues/2023) an `equal?` table **cannot find any key nested deeper than 8**, because `valueHashDepth`'s cutoff hashes a pointer: this is the explicitly-named-but-unimplemented half of closed [#1180](https://github.com/kaappi/kaappi/issues/1180), and it reaches `(srfi 126)` 88/100 and `(srfi 146 hash)` 90/100; [#2024](https://github.com/kaappi/kaappi/issues/2024) a custom hash procedure that inserts into **its own** table makes `rehash` iterate a freed array — exit 133/134 with empty stdout *and* stderr, 12 of 16 sweep cells, same silent-loss shape in `hash-table-merge!`; [#2025](https://github.com/kaappi/kaappi/issues/2025) all four hash procedures return **negative** integers in the unbounded arm (62-bit mask through a 48-bit `makeFixnum`), which `(srfi 126)`'s `equal-hash` inherits. All **8 callback sites** were probed under mutation / raise / re-entry / blocking: only the custom-hash site is unsafe. `hash-table-walk` and `hash-table-fold` are **correct** on every route — insert-during-walk, delete-during-walk, forced rehash, raise, `call/cc` escape, nested re-entry, and #1181's rooted snapshot — and resuming a walk continuation after the native call returned fails cleanly. There is **no blocking guard on this path and none is needed**: channel and `thread-sleep!` calls work inside every callback, including 6000 native frames deep, where #2000's custom-port path aborts at 3000. D2 taxonomy is already covered by [#2021](https://github.com/kaappi/kaappi/issues/2021), which names this file's six sites; D4 arity table is clean; D6 round-trips both SRFI-18 boundaries with custom procs intact and refuses an uncopyable value cleanly)
- [x] 2.9: `primitives_control.zig` (14 callback sites; SRFI 248 sticky handlers are new) (2026-08-01, [#2039](https://github.com/kaappi/kaappi/pull/2039); 35 → 171 assertions, 15 disabled, green in ReleaseSafe, Debug *and* `-Dgc-stress=true` — filed [#2034](https://github.com/kaappi/kaappi/issues/2034) **`callHandler`/`callThunk` never check arity**, so a wrong-arity exception handler, `with-exception-handler` thunk, `call-with-values` producer or `call/cc`/`call/ec` receiver runs anyway with surplus parameters bound to leftover register contents — a 3-argument handler receives `#<builtin list>` from the *caller's* frame; [#2033](https://github.com/kaappi/kaappi/issues/2033) a top-level redefinition of `call/cc`/`call-with-current-continuation`/`apply`/`eval`/`call-with-values` is **ignored in tail position only**, because the superinstruction guard consults `resolveLocal`/`resolveUpvalue` and never globals; [#2035](https://github.com/kaappi/kaappi/issues/2035) 819 nested `dynamic-wind` extents abort with **KP9001 "internal error"** — the register file stops growing at 4096 of a documented 65536, `-Dmax-registers=65536` makes depth 5000 work, and unlike every other VM limit the failure is *catchable*, arriving as an error object whose message is the bare string `"error"`; [#2036](https://github.com/kaappi/kaappi/issues/2036) three diverging diagnostic paths; [#2037](https://github.com/kaappi/kaappi/issues/2037) `%unwind-to-escape` is missing from `internal_helpers`, so user code can pop the wind stack; [#2038](https://github.com/kaappi/kaappi/issues/2038) doc-truth — README and CONFORMANCE both say SRFI 248 has exactly *two* caveats, and the third makes a loop run 2ⁿ−1 times and then exit 0 with no output at all. **Confirmed correct:** all three R7RS §6.10 `dynamic-wind` ordering rules including rule 3, traced against chibi; both §6.11 and both §4.2.7 worked examples; the handler stack over 5000 declining `guard`s and 5000 escapes-from-a-handler; `call/ec` extent expiry both ways; the SRFI 248 sticky mechanism (resume re-enters the guarded body's wind extent, an enclosing `dynamic-wind` is untouched, `empty-continuation?` right in all six shapes); and **D5 — all 10 control callback sites park a fiber**)
- [x] 2.10: `primitives_srfi254.zig` (new, no test) — GC-integrated; guardians are callable (2026-08-01, [#2013](https://github.com/kaappi/kaappi/pull/2013); 178 assertions, 5 disabled, green in both ReleaseSafe and `-Dgc-stress=true` — filed [#2008](https://github.com/kaappi/kaappi/issues/2008) `invokeGuardian` has **no owner check**, so a guardian shared through a global aborts the process **silently** (exit 133/134, empty stdout *and* stderr, 5/5) under concurrent registration and hands back a type-confused live object after a join; [#2006](https://github.com/kaappi/kaappi/issues/2006) transport cell keys are held **strongly**, so cells never break and every registration is permanent; [#2011](https://github.com/kaappi/kaappi/issues/2011) a second guardian watching the same object **never** resurrects it. The ephemeron fixpoint itself is **correct** — two-link chains resolve consistently in both directions, key-references-value and key-is-value both break — and all 16 error paths carry the right KP code.)
- [x] 2.11: Batch — `parallel`, `sysinfo`, `random_port`, `srfi258`, `srfi260`, `srfi211` (~570 lines, 27 specs, none audited) (2026-08-01, [#2014](https://github.com/kaappi/kaappi/pull/2014); 230 assertions + a 17-assertion D7 sandbox suite, 7 disabled — **the six files themselves are clean**: all 27 specs correct, zero panics across ~120 adversarial calls, D1 all-reachable, D7 gate exactly as documented, and SRFI 258's uninterned-ness survives both deep-copy directions *with sharing preserved*. Every finding is in the surrounding engine: [#2003](https://github.com/kaappi/kaappi/issues/2003) a use-site `let` **captures a macro template's free reference to any global procedure**, so `(let ((car …)) …)` hijacks `car` inside any macro — the local-scope half of closed #1812, confirmed wrong against Chibi and Guile, with the def-site-local and global-non-procedure cases passing as controls; [#2005](https://github.com/kaappi/kaappi/issues/2005) `load` of a file containing `import` fails and blames the *loader's* line 1; [#2007](https://github.com/kaappi/kaappi/issues/2007) `kaappi check` calls two valid SRFI 211 transformer-specs invalid syntax; [#2009](https://github.com/kaappi/kaappi/issues/2009) doc-truth. Extended [#1913](https://github.com/kaappi/kaappi/issues/1913): the all-zero-seed port's own state fails `random-port-state?`, so it cannot be rebuilt from itself)
- [x] 2.12: `primitives_filesystem.zig` — 69 specs and 102 syscalls against a 177-line test (2026-08-01, [#1985](https://github.com/kaappi/kaappi/pull/1985); 69 → 427 assertions, 18 disabled — all 68 specs now touched, 10 of which the old test never mentioned. Filed [#1976](https://github.com/kaappi/kaappi/issues/1976) `file-info` **aborts uncatchably on any devfs path** (a signed `dev_t` narrowed to `u64`; `/dev/fd` is a *directory* with `st_rdev = 0` and still aborts, isolating `st_dev`), [#1977](https://github.com/kaappi/kaappi/issues/1977) silently discarded arguments — `(nice "x")` renices the process and returns 1 — and [#1978](https://github.com/kaappi/kaappi/issues/1978) errno discarded at ~102 sites. The NUL guard is uniform across all 24 path-taking procedures and `--sandbox` gating is fully coherent at 70/70 probes. **Two more findings came from CI, not the audit**, both in an area the unit had reported clean: [#1993](https://github.com/kaappi/kaappi/issues/1993) an fd-holding object is reclaimed only when the GC's *object*-count threshold trips, never on descriptor pressure — at `ulimit -n 256`, `Collections: 0` and exactly 253 opens succeed, while the sweep arm itself is correct — and [#1994](https://github.com/kaappi/kaappi/issues/1994) script execution echoes non-void top-level values, documented only in a fuzzing doc. The unit's own "3000 unclosed streams do not exhaust the fd table" was a **false clean** from macOS's 1048576 limit; see the last three footguns, which this unit paid for)
- [x] 2.13: Error-taxonomy sweep (D2) + diagnostic fidelity (F10, D3) (2026-08-01, [#2029](https://github.com/kaappi/kaappi/pull/2029); 98 assertions, 64 disabled — cross-cutting over all 31 `primitives_*.zig` plus `src/ffi.zig`, against the codebase's own contract in `docs/dev/adding-features.md` and the text `kaappi explain` prints. Filed [#2020](https://github.com/kaappi/kaappi/issues/2020) **33 bounds failures report KP3002 not KP3006** — `parseOptionalRange` alone covers 20 procedures, and R7RS defines `substring` *as* `string-copy` yet they return different codes; [#2021](https://github.com/kaappi/kaappi/issues/2021) 72 sites reject a correctly-typed value as KP3002 because the type branch and the range branch share one message, so `(bytevector 'x)` and `(bytevector 256)` are indistinguishable; [#2022](https://github.com/kaappi/kaappi/issues/2022) **31 procedures misreport which procedure failed** — shared helpers hardcode `'string'` (a real, working procedure), `'arithmetic'` (11 procedures incl. `+`, while its neighbour `/` is correct), and `'string operation'`; [#2026](https://github.com/kaappi/kaappi/issues/2026) CI's bare-TypeError gate misses `src/ffi.zig` on **both** axes at once — wrong path glob and wrong spelling — hiding 27 bare returns, 18 of them range checks whose message says "out of range" under KP3002. Extended [#1899](https://github.com/kaappi/kaappi/issues/1899) rather than re-filing F10: its documented rationale does not hold, because `mapNativeError` runs the **full allocating printer** on the same error path — `(sqrt 'the-key)` names the symbol while `(magnitude 'the-key)` reports `#<symbol>`, so the bare-return path CI forbids is *more* informative than the helper it enforces; also confirmed `#\a` renders as `#<char>` despite being an immediate (#1899 could not reproduce it), and that a bignum index reports "expected exact integer, got `#<bignum>`" — #1916's self-contradiction, still live one type over. **13 of 31 primitives files are clean on both axes** and asserted so, `primitives_io.zig` included after #2016; KP3001/3003/3004/3005 all stay distinct from KP3002)

**Phase 3 — SRFI breadth** (independent)

- [x] 3.1: **SRFI 14 rewrite** (F6) — range/inversion-list rep over the existing Unicode tables, plus the ~37 missing names (2026-07-31, [#1928](https://github.com/kaappi/kaappi/pull/1928), closed #1895; inversion lists, all 64 spec names, 172-assertion suite — 17/147 against the old library; filed [#1924](https://github.com/kaappi/kaappi/issues/1924) **cross-thread use-after-free**, [#1925](https://github.com/kaappi/kaappi/issues/1925) `char-numeric?` BMP-only, [#1927](https://github.com/kaappi/kaappi/issues/1927) `--lib-path` cannot shadow a bundled SRFI)
- [x] ~~3.2: SRFI 160 sweep A~~ — **subsumed by 2.4**, which swept all 12 element kinds (8 integer kinds × {min, min±1, max, max±1} plus 9 rejection classes, every cell correct) and cross-checked the two independent range rules across 276 cells. The "87% `s8`" gap it was written against is closed.
- [x] ~~3.3: SRFI 160 sweep B~~ — **subsumed by 2.4**, which covered both seams (u8-as-bytevector in both directions; c64/c128 packing incl. per-component precision, ±inf/NaN, and a rejected `set!` leaving the slot untouched) and verified the per-type wrappers three ways — each `.sld` mentions only its own tag, tag-normalised the 12 files are byte-identical, and a 12×12 predicate matrix is true only on the diagonal.
- [x] 3.4: SRFI 146 (108 of 161 exports untested) (2026-08-01, [#2070](https://github.com/kaappi/kaappi/pull/2070); 53 → **161 of 161 exports**, 668 assertions, 33 disabled — the **ordered-vs-hash differential** over the 66 shared names disagreed in four places and **all four were real defects**, none a spec-sanctioned ordering difference. Filed [#2044](https://github.com/kaappi/kaappi/issues/2044) **`(srfi 146 hash)` never consults its comparator** — and stores it faithfully, returning it `eq?`-identical from `hashmap-key-comparator`, so every introspective check a user writes to confirm the map is configured correctly passes while the map uses `equal?` throughout — [#2045](https://github.com/kaappi/kaappi/issues/2045) duplicate keys keep the *last* where the spec says the first (both libraries), [#2046](https://github.com/kaappi/kaappi/issues/2046)–[#2050](https://github.com/kaappi/kaappi/issues/2050), [#2052](https://github.com/kaappi/kaappi/issues/2052), [#2053](https://github.com/kaappi/kaappi/issues/2053). Extended #2023 rather than re-filing: **no** `(srfi 146 hash)` comparator avoids the depth-8 cliff. Confirmed correct: all four `mapping-search` continuations on both libraries, purity of all eight pure/linear pairs, the whole ordered-only surface, 1500 interleaved insert/delete rounds against a red-black delete that reuses the *insertion* balance routine. **Two non-defects avoided:** the reference suite predates a 2021 post-finalization note moving `comparator-register-default!` to the user — making those calls moved two assertions from fail to pass — and `mapping-catenate!`'s 4-argument signature is a spec typo the reference shares)
- [x] 3.5: SRFI 166 + `columnar`/`unicode`/`color`/`pretty` sub-libraries (52 of 89 untested) (2026-08-01, [#2069](https://github.com/kaappi/kaappi/pull/2069); **89 of 89 exports**, 244 assertions, 56 disabled — **the library is largely a stub**, and **CORRECTED by Phase 8:** the 11 issues do NOT share one root cause — that framing was the orchestrator's, and Phase 8 disproved it by experiment rather than argument, routing the supposedly-derived issues through the *working* procedural mechanism and still getting wrong answers. They are **11 distinct causes**; #2054 partially blocks exactly one sub-item each in #2065 and #2066. (Phase 8's R25 group holds **8** of these 11 — #2062 and #2066 belong to R21 *byte vs codepoint vs column* and #2067 to R11, so the two counts describe different populations rather than disagreeing.) The original (wrong) reading was: [#2054](https://github.com/kaappi/kaappi/issues/2054) `fn`/`with` are **procedures where the spec defines macros**, so every documented use raises `not a procedure` and the state variables are unreachable — which is *why* [#2064](https://github.com/kaappi/kaappi/issues/2064) `pretty` is byte-identical to `write` (verified: same length, zero newlines), [#2061](https://github.com/kaappi/kaappi/issues/2061) `numeric/comma` inserts no commas at all, [#2062](https://github.com/kaappi/kaappi/issues/2062) padding measures with `string-length`, and [#2066](https://github.com/kaappi/kaappi/issues/2066) `string-terminal-width` is `string-length` (CJK counts 3 where 6 is correct). Also [#2056](https://github.com/kaappi/kaappi/issues/2056)–[#2060](https://github.com/kaappi/kaappi/issues/2060), [#2063](https://github.com/kaappi/kaappi/issues/2063), [#2065](https://github.com/kaappi/kaappi/issues/2065), [#2067](https://github.com/kaappi/kaappi/issues/2067). **`(srfi 166 color)` has zero findings** across all 23 exports with exact SGR codes pinned — the control proving this is not an auditor calibrated to find fault everywhere. The "coloured strings break alignment" hypothesis was **correctly not filed**: the spec's own default `string-width` *is* `string-length`)
- [x] 3.6: SRFI 158 generators (43 of 55 untested) (2026-08-01, [#2068](https://github.com/kaappi/kaappi/pull/2068); **55 of 55 exports**, 349 assertions, 13 disabled — the ranked-highest risk came back **clean**: all 19 combinators consume exactly zero at construction, minimum-demand holds in all 13 probed cases, all 30 constructors/combinators keep returning eof once drained, and 37 infinite-generator compositions ran under `run_timeout` with no hangs. Filed [#2060](https://github.com/kaappi/kaappi/issues/2060) **SRFI 158's own `generator-unfold` example does not run** — SRFI 1's higher-order procedures and `hash-table-walk` are still native drivers, so a coroutine resume crosses a returned native frame. [#2055](https://github.com/kaappi/kaappi/issues/2055) and [#2057](https://github.com/kaappi/kaappi/issues/2057) are **reference-implementation defects chibi reproduces identically** — verified here and recorded on both issues, because fixing them makes Kaappi diverge from every implementation carrying the reference code. Two behaviours pinned rather than filed after chibi agreed. **Footgun found:** never write `(list (g) (g))` — chibi evaluates right-to-left, and a first draft "diverged" on three tests purely from argument order)
- [x] 3.7: NO-TEST batch — 2, 8, 11, 16, 28, 31, 34, 111, 145, 222, 229 (2026-08-01, [#2076](https://github.com/kaappi/kaappi/pull/2076); 271 assertions, 39 disabled, across three files — filed [#2074](https://github.com/kaappi/kaappi/issues/2074) **a use-site local named after a syntactic keyword captures it inside any macro template**, 15 of 17 keywords, chibi gets 16 of 17 right; [#2073](https://github.com/kaappi/kaappi/issues/2073) `(and-let* ((x 1)))` returns `#t` not the claw value, and **chibi does not reproduce**, so it is a Kaappi porting defect; [#2072](https://github.com/kaappi/kaappi/issues/2072) SRFI 222 implements **5 of the spec's 10 procedures**. Commented a **negative result** on #2003 rather than unifying: a template's `car` is hijacked in argument position too, so the two are genuinely different mechanisms. **Verification note:** a spot-check using `if`/`let` as the shadowed keywords reproduces nothing and matches chibi — those are among the 2 unaffected, so the "15 of 17" figure is load-bearing and a fix must be checked against all 17. Two things deliberately **not** filed after checking chibi: SRFI 28's format leniencies are byte-identical there, and `(procedure-tag car)` returning `key` is the reference implementation's own design)
- [x] 3.8: SMOKE-ONLY batch — 23, 46, 98, 112, 139, 149, 188, 190, 236, 244 (2026-08-01, [#2078](https://github.com/kaappi/kaappi/pull/2078); 67 → 264 assertions, 19/19 exports — **reopened two closed issues whose regression tests pinned only the valid case**: [#682](https://github.com/kaappi/kaappi/issues/682) (a pattern variable used at a lower ellipsis depth than it matched silently expands to `()`; the fix line was removed in #931 and `tests/scheme/smoke/ellipsis-depth-mismatch.scm` contains **no mismatch at all**, so it has printed PASS throughout) and [#550](https://github.com/kaappi/kaappi/issues/550) (checks added only inside the `isMultipleValues` arm, which `(values 1)` never reaches). New: [#2075](https://github.com/kaappi/kaappi/issues/2075) a `begin`-wrapped internal `define` in a `let` body escapes to the **global** environment when no enclosing procedure exists, and [#2082](https://github.com/kaappi/kaappi/issues/2082) `syntax-rules` accepts two ellipses in one list pattern. **Four of the ten were genuinely adequate** as smoke tests. Two footguns recorded: SRFI-64's `test-equal` evaluates inside a lambda, which supplies exactly the scope whose absence is #2075; and on SRFI 149 rule 4 it is **chibi that diverges**, with Guile agreeing with Kaappi)
- [x] 3.9: Large-and-thin batch — 113, 225, 178, 152, 240, 189, 35, 27 (2026-08-01, [#2095](https://github.com/kaappi/kaappi/pull/2095); 743 → **2,322 assertions**, 290 → **456 of 456 exports** across eight SRFIs, 32 disabled and each mutation-tested individually — filed [#2083](https://github.com/kaappi/kaappi/issues/2083) `bitvector-logical-shift` is **inverted on both branches**, failing SRFI 178's own test file; [#2084](https://github.com/kaappi/kaappi/issues/2084) `bitvector-segment` conses outside its recursive call, so a legal 200,000-bit vector dies of an *uncatchable* KP3008 and `n=0` recurses forever; [#2085](https://github.com/kaappi/kaappi/issues/2085) `bag-increment!` ignores "but not less than zero" and the negative multiplicity makes `bag->list` hang; [#2086](https://github.com/kaappi/kaappi/issues/2086), [#2087](https://github.com/kaappi/kaappi/issues/2087) SRFI 189 exports 24 of 82 names while `cond-expand` answers yes, [#2088](https://github.com/kaappi/kaappi/issues/2088). **The leverage:** SRFI 178's own reference implementation loads into this build as an alternate library, so all 107 exports were diffed against it over a **523,361-check** corpus — exactly three diverged, one a real bug and two a genuine spec ambiguity, **not filed**. 225 and 35 and 27 and 152 came back clean; the 152 seam is tighter than "agrees" — the `.sld` imports the 22 shared names straight from `(srfi 13)`, so they are the same binding, asserted by `eq?` identity)
- [x] 3.10: Un-quarantine `tests/scheme/srfi/slow/` (F11) and re-triage SRFI 150's expected failures against closed #1832 (2026-08-01, [#2071](https://github.com/kaappi/kaappi/pull/2071); **both premises were false.** The `slow/` files run in **0.39s and 0.44s**, not the 4½ and 1½ minutes their headers claim — true when they were quarantined 2026-07-20, false since 2026-07-28 when #1802/#1804 stopped ReleaseSafe memsetting the expander's 1MB buffers; nothing re-measured because nothing ever reported them missing. Moved up into `tests/scheme/srfi/` rather than adding a glob — preserving the "subdirectories hold fixtures" invariant and touching none of the 18 CI legs — after confirming the lean smokes are **not** superseded (18 of 34 and 8 of 25 assertions have no counterpart). Net **+131 assertions for ~0.8s**. The generalisable half: `run-all.sh` now **fails if any `.scm` under a suite subdirectory contains `test-begin`**, with no allowlist to maintain; **no other unreachable tests exist** — all 114 non-run-all files accounted for. SRFI 150's four failures are a **third defect**, [#2051](https://github.com/kaappi/kaappi/issues/2051) — not stale annotations and not an incomplete #1832, whose defining condition is *absent*. Verified and sharpened here: the rename-stripping is **spelling-based and hits symbols the user typed literally** — `(eq? '__hyg_2_a 'a)` is `#t` in kaappi and `#f` in chibi with no macro involved — making `__hyg_` a de-facto reserved namespace with no enforcement, the same shape as the v0.22.0 `%`-prefix incident)

**Phase 4 — Execution-tier divergence**

- [x] 4A: Derive `isRejectedFormHead` from the comptime set (F7) + a test asserting `derived ⊆ rejected ∪ documented-exclusions` (2026-08-01, [#2092](https://github.com/kaappi/kaappi/pull/2092), closes #1896; **the gap was LIVE, not latent** — the issue predicted latency, but the reachable half is the property expression's own *evaluation time*, observable with `display`: interpreter `PBC` vs native `BPC` for `cond` and `case`, and `do` **failed to compile at all** (KP9001), since `emitDo` installs loop-variable locals before the eval fallback can run. Exactly one name was missing — `define-property` — with 6 deliberate exclusions in the other direction, each carrying its reason in code. Discriminating control: the same forms *without* the cond/case/do wrapper agree between tiers before and after. The gate is now derived from `ir.eval_fallback_form_names` with a comptime block asserting `derived ⊆ rejected ∪ exclusions`, each `@compileError` branch triggered and confirmed. Filed [#2089](https://github.com/kaappi/kaappi/issues/2089) — a **third** hand-maintained keyword list with the identical drift and the identical missing name, `expander.well_known_forms`, so a template using `define-property` expands to `__hyg_N_define-property`; verified here, and the error blames the *first argument* with a spelling suggestion for an unrelated builtin, mentioning neither `define-property` nor hygiene)
- [x] 4B: Ship `tests/scheme/differential/run-differential.sh` — tiers (b) opt-off and (d) cold/warm cache first; both need no build and already run green (2026-07-31, [#1923](https://github.com/kaappi/kaappi/pull/1923); 557 files, 0 divergence, wired into run-all.sh; filed [#1922](https://github.com/kaappi/kaappi/issues/1922) cache HIT loses error source lines. Quantified the tier-(b) weakness: only **9 of 331** corpus files make the optimiser do anything. Debug reduces to `probes/` after CI timed out at 300s)
- [x] 4C: Convert `tests/scheme/compile/*.sh` from golden strings to an interpreter oracle (only 2 of 22 compare tiers today) (2026-08-02, [#2123](https://github.com/kaappi/kaappi/pull/2123); **the tracker was wrong on both numbers** — there are 23 scripts, not 22, and **8 already compared tiers, not 2**; the "2" predates five tier-comparing scripts written since #1799. 11 converted, 1 upgraded, 4 genuine exceptions (compilation-must-fail, emitted LLVM IR, a native diagnostic's text, and a named `.sbc` that nothing but `-Dbundle` can execute). Goldens kept everywhere as a *second* assertion, now checked against the interpreter. Four divergences filed from a throwaway sweep of 338 files (178 compile, 25 differ, most the documented top-level echo): [#2115](https://github.com/kaappi/kaappi/issues/2115) a `guard` does not catch an error raised inside a natively compiled callee — the program dies, and `llvm-backend.md` lists guard under "stress-tested"; [#2117](https://github.com/kaappi/kaappi/issues/2117) **#600 and #790 are live again in the LLVM emitter**; [#2118](https://github.com/kaappi/kaappi/issues/2118) **#788 likewise** — verified here, `(define (f quote) (quote 5))` with `(f -)` gives `-5` interpreted and `5` native, a *different value*, exit 0, no diagnostic; [#2119](https://github.com/kaappi/kaappi/issues/2119). **Mutation-tested both ways:** appending a bare top-level expression creates a real divergence that the converted script catches and the pre-conversion golden — set to exactly what native prints — is blind to. Also found `set-define-lexical-scope-819.sh`'s comment *claimed* it matched the interpreter and never ran it. **Verification note:** a spot-check using a keyword-named parameter as a *value* (`(+ if 1)`) agrees on both tiers; the bug needs it in **operator position**)
- [x] 4D: WASM cross-tier — diff the import-free corpus under wasmtime against the interpreter (today: 3 files, exit-code only) (2026-08-02, [#2122](https://github.com/kaappi/kaappi/pull/2122), **all 18 CI checks green**, CI reproducing the local numbers exactly on a different arch and wasmtime patch; wasmtime 46.0.0 was available, so nothing was deferred or inferred. Swept **591** files: 184 agree byte-for-byte, **401 excluded because no file-backed `.sld` loads on WASM at all**, 3 documented degradations, 4 diverge, **0 hangs**. **The tracker's "import-free corpus" was the wrong cut** — built-in registry libraries import fine; it is *file-backed* `.sld`s that never load, and that is a bug: [#2108](https://github.com/kaappi/kaappi/issues/2108), whose control is exact (`lib/srfi/2.sld` runs as a *script* but will not resolve as a *library*, same path, process and mount). [#2107](https://github.com/kaappi/kaappi/issues/2107) `write` of an 848-deep car nest **aborts the module and is uncatchable** — verified here, a `guard` with a `#t` clause never fires; `MAX_PRINT_DEPTH`'s 1024 guard is unreachable because `wasm_exe` is the one binary in `build.zig` with no `stack_size`, and the control is decisive (a **cdr**-nested list of 200,000 pairs, 236× more pairs, prints fine). [#2109](https://github.com/kaappi/kaappi/issues/2109) `(command-line)` is `'()`. **One hypothesis was checked and falsified rather than filed.** The harness prints the 401 unrunnable files explicitly, so a green run reads as covering **184 files, not 591**)
- [x] 4E: `.sbc` cache coverage — only 42 of 333 corpus files populate it; `sbc equiv:` covers 6 toy forms (2026-08-02, [#2121](https://github.com/kaappi/kaappi/pull/2121); **the population rule is eight top-level heads, not one** — `import`, `define-library`, `define-record-type`, `define-values`, `include`, `include-ci`, `begin`, `cond-expand`, any one of which anywhere at top level makes the whole file uncacheable, while the same constructs nested in a body leave caching alive. Measured with one isolated `KAAPPI_HOME` per file over 345 files: **40 cached, 305 not** (303 by `import`, 1 by `begin`, 1 by `define-values`), and **zero cached files contain any of the eight** — the no-false-positives check. `docs/dev/cache.md` documents only `import` and `--timings` blames `imports` for all eight → [#2114](https://github.com/kaappi/kaappi/issues/2114), verified here: four constructs that are not imports all report `not cached: imports`. **The codec is correct for every value it can represent** — every constant tag round-trips clean cold-vs-warm, including `-0.0`, ±inf, NaN, `#\x10FFFF`, `||`, multi-limb bignums — which makes the four divergences sharper, since all four are *metadata* a HIT drops rather than values it corrupts: [#2110](https://github.com/kaappi/kaappi/issues/2110) the immutable bit, so `set-car!` on a literal **raises cold and succeeds warm**, exit 1 → 0 (verified here); [#2111](https://github.com/kaappi/kaappi/issues/2111) no visited-set, so `eq?` flips, shared DAGs go exponential (**241 source bytes → 4.7 MB `.sbc`**) and cyclic literals never load; [#2112](https://github.com/kaappi/kaappi/issues/2112) the macro table is empty after a HIT; [#2113](https://github.com/kaappi/kaappi/issues/2113) the writer emits entries the reader always rejects, so the file recompiles forever while `cache status` calls it `current`. Corpus coverage 40 → 48, and a new gate **fails** the run if a file that wrote an entry does not HIT on re-run)

**Phase 5 — Concurrency**

- [x] 5A: **Validate-or-retire** the SRFI 120 corruption claim; deliver either a live repro or a PR rewriting the header plus tests pinning both rejections (2026-08-02, [#2140](https://github.com/kaappi/kaappi/pull/2140); **RETIRED, with tests that keep it retired.** All eight header claims given a verdict; the decisive one is that the reconnaissance credited the **wrong mechanism** — it said `gc_deep_copy`'s `.fiber` rejection closed both entry paths, but a top-level binding is *never deep-copied*, so that list has no bearing on it and the control channel's `Object.owner` check is what refuses there. Two independent guards, both now pinned by name (18 assertions, flake-checked 10/10). The "does not reproduce" is properly evidenced — **0 corruption in 125 runs** under gc-stress at load average ~18, and decisively *the same harness on the same machine catches #2129 at 13/15*, which is what separates a real negative from an idle-machine zero. Found three further refused entry paths and **a fourth that crashes**: [#2129](https://github.com/kaappi/kaappi/issues/2129) `thread-join!` frees the joined thread's GC/VM while a thread it spawned is still in its startup prologue — verified here at **18/20**, with both controls clean (join-the-grandchild-first 0/20, spawn-nothing 0/20). The repro imports only `(srfi 18)`; no timer, channel or uncopyable value is needed, and the 18/20 rate makes it the common case rather than a rare interleaving)
- [x] 5B: `waitForFd` park-vs-drive protocol — zero tests reference `waitForFd`, `driving_waits`, or `anyAncestorWaitResolved` (2026-08-01, [#1960](https://github.com/kaappi/kaappi/pull/1960); 26 tests, **no bugs in `waitForFd`**. Pinned the 2×2 selector and the unwind asymmetry, whose nine `false` rows had zero coverage. Filed [#1959](https://github.com/kaappi/kaappi/issues/1959) — the user-visible error names `dynamic-wind` as unparkable when it is not)
- [x] 5C: `gc_deep_copy` promoted-stub ownership skip — an already-promoted channel stub bypasses the owner check (2026-07-31, [#1938](https://github.com/kaappi/kaappi/pull/1938); 49 assertions, 24 disabled — CLAUDE.md's sharing model confirmed verbatim, 11 sound behaviours pinned; filed [#1933](https://github.com/kaappi/kaappi/issues/1933) **parent GC reclaims objects a live child references** (gc-stress: hard UAF panic), [#1932](https://github.com/kaappi/kaappi/issues/1932) a record loses its type across `thread-join!`, [#1934](https://github.com/kaappi/kaappi/issues/1934)–[#1937](https://github.com/kaappi/kaappi/issues/1937))
- [x] 5D: SRFI-18 re-audit (994 → 1435 lines since v1) (2026-08-01, [#1986](https://github.com/kaappi/kaappi/pull/1986); 77 → 274 assertions — filed [#1982](https://github.com/kaappi/kaappi/issues/1982) `thread-terminate!` **cannot interrupt a native wait**, a residual of closed #880 whose own verification used a `(thread-yield!)` loop — exactly the case its fix handles; [#1983](https://github.com/kaappi/kaappi/issues/1983) unguarded float→int aborts that reach `(kaappi fibers)` too; [#1984](https://github.com/kaappi/kaappi/issues/1984) four state-machine defects. **Portability lesson:** an assertion pinning `(seconds->time +nan.0)` ⟹ `0.0` failed only on CI's NetBSD — `@intFromFloat` on NaN is undefined, so never assert its *value*; assert that it does not abort, which is the real contrast with #1983's aborting cases.)
- [x] 5E: De-flake and arm the timing tests (76 wall-clock lines; `smoke/thread-sleep-876.scm` has no exit path at all) (2026-08-02, [#2120](https://github.com/kaappi/kaappi/pull/2120); **the tracker's "76 wall-clock lines" is not reproducible** — no definition yields 76 at HEAD or at the campaign baseline; the reproducible count is 216. Inventoried all 180 pre-existing lines into five classes (a fifth was added because folding "a time value used as data" into "genuinely needs wall-clock" would have overstated the risk by ~40 lines): **(c) races-its-own-setup 24 → 7, (d) cannot-fail 3 → 0**. **`srfi120.scm` had five racing blocks, not the two CI caught**, each reproduced *deterministically* by injecting a delay into the unmodified file — including #2076's and #2093's netbsd failures byte-for-byte — with a committed A/B fixture where the old shapes fail 6 of 10 and the new ones pass 12/12. Two fixes are structural rather than wider margins: the periodic task's ticks were **queuing in an unbounded channel**, so widening would have made it worse, and the no-handler block now schedules the erroring task **last**, leaving no deadline to lose at any speed. `thread-sleep-876.scm`'s "no exit path" claim is TRUE and worse — it is **1 of 54** files that cannot fail, because `run-all.sh`'s stdout net requires a failure *count* and so matches neither `#f` nor a bare `FAIL:` line ([#2116](https://github.com/kaappi/kaappi/issues/2116), verified here against the regex). [#2125](https://github.com/kaappi/kaappi/issues/2125) came from **declining** a review suggestion after probing: `(mutex-state m)` returns the child's *fiber*, not the owning thread, so the suggestion would have broken the test)
- [x] 5F: gc-stress × concurrency — needs `/do-stress-test` (Linux, hours) (2026-08-02, no PR — a droplet run, reported on [#1890](https://github.com/kaappi/kaappi/issues/1890); `c5-4vcpu-8gb` x86-64 Linux at `94ebd5a0`, destroyed after ~37 min for ~USD 0.09. **Clean on both halves**: the unit suite under `-Dgc-stress=true` is **1570 pass, 0 fail**, **CORRECTED 2026-08-02:** this entry originally also claimed the Scheme suite ran against that same binary (2061 pass, 0 fail). **It did not.** `zig build test -Dgc-stress=true` builds *test* binaries and never rebuilds `zig-out/bin/kaappi`, which `run-all.sh` uses — so that half ran against the plain binary from the earlier sanity build and proved nothing about gc-stress. Verified after the fact: the installed binary still reports `gc_stress = False` after a stress test run. Phase 7E caught it (#2163) by noticing the timings were arithmetically inconsistent with a stressed binary. The unit-suite result above stands; the Scheme half of 5F was **not** covered, and 7E's `gc-stress-scheme` CI job is what actually closes it — finding two real bugs on its first run (#2160, #2161). **The finding is the timing.** The run reported `EXIT:0` with a 7-byte results file after 8 minutes against a documented 1.5–3 hour budget, which is exactly what a silently-inapplicable build flag looks like; the control settled it — **50 s plain vs 5 m 07 s stressed**, with a different skip count (`1567 pass, 3 skip` vs `1570 pass`), so the flag is genuinely active and the estimate was ~30× stale, almost certainly since #1802/#1804 and #1809 stopped ReleaseSafe `0xAA`-filling `= undefined` buffers. `.claude/skills/do-stress-test/SKILL.md` is corrected here, including a note that `zig build test` prints nothing on success so a fast finish must be checked against the control rather than the clock)
- [x] 5G: Reactor backend parity — needs `/do-linux-test` (epoll) and `/vm-test` (kqueue) (2026-08-02, [#2158](https://github.com/kaappi/kaappi/pull/2158); **no droplet needed** — an already-running `podman machine` aarch64 Linux VM made the epoll half VERIFIED rather than inferred. **kqueue 1594 pass / 3 skip / 0 fail; epoll 1593 pass / 4 skip / 0 fail — no behavioural divergence across 1593 tests.** 15 new properties, each executed on *both* backends and each mutation-tested individually; the one mutation that survived was investigated rather than deleted (de-duplicating on the fd side is unobservable because the duplicate comes from the timer drain afterwards). Corrected the tracker's premise: parity *was* asserted for what the existing tests cover — the gap was the contracts `reactor.zig`'s own doc comments state. Filed [#2153](https://github.com/kaappi/kaappi/issues/2153) — `zig build test -Dtarget=wasm32-wasi` **does not compile** (23 errors, verified), so the WASI backend has no compile gate anywhere and `porting.md` Stage 3 names an acceptance criterion it cannot meet — and [#2154](https://github.com/kaappi/kaappi/issues/2154). Three hypotheses checked and deliberately not filed. **Trap worth knowing:** the same Linux binary run without the repo mounted fails 8 tests that read exactly like a backend divergence)

**Phase 6 — Tooling**

- [x] 6A: `fmt` line-ending policy (F8) — decide preserve-vs-normalise, implement, document, test CRLF/lone-CR/mixed (2026-08-01, [#2093](https://github.com/kaappi/kaappi/pull/2093); **F8 is narrower than filed** — two of the six cases were already correct, and `--check` and the rewrite provably **cannot** disagree, since `formatFile` computes the formatted text once and both paths compare it with the same `mem.eql`. The two genuinely broken cases are the two the finding did not name: a lone-CR file had `\r\r` counted as **zero** line endings so blank-line grouping was silently dropped, and a CRLF block comment kept its interior CRs, producing mixed-ending output from uniform input. Policy chosen: **normalize to LF**, rejecting rustfmt's preserve-dominant — `fmt.md` already promised layout depends only on content "not the input's own line breaks", `fmt` already canonicalises tabs, space runs, indentation and the trailing newline unconditionally, and preserve has no defined answer for a 50/50 mixed file. Line endings inside strings, raw strings, `|symbols|` and character literals are data and survive byte-for-byte. Filed [#2079](https://github.com/kaappi/kaappi/issues/2079) (a lone CR does not end a `;` comment — **chibi and Guile behave identically**, so it argues for documenting rather than conforming) and [#2080](https://github.com/kaappi/kaappi/issues/2080). `fmt.sh` 12 → 37 assertions; strict no-op verified on all 942 tracked `.scm`/`.sld`)
- [x] 6B: Reconcile `kaappi test` with `run-all.sh` (F13) (2026-08-01, [#2081](https://github.com/kaappi/kaappi/pull/2081), closes #1903; **the mechanism is not `test-expect-fail` at all** — `srfi150.scm` raises an uncaught top-level error and then calls `(exit 0)`, which `run-all.sh` reads from the process status as PASS while the `kaappi test` worker suppresses the exit, *records* it, and never consulted the record. **`run-all.sh` was right**: `tests/scheme/errors/exit-code.sh` already pins "explicit `(exit 0)` wins over an earlier uncaught error", and `emitResult`'s own doc comment claimed `errored` covered a nonzero exit, which the code never implemented. One `resolveVerdict` now weighs counters, recorded exit and top-level error together; an `(exit 0)` waives only the file's *own* error and can never bury a failing assertion. This also closed an **opposite-direction divergence nobody had noticed** — a file exiting nonzero with counters that do not explain it was FAIL under `run-all.sh` and silently PASS here. Per-file disagreements across all 352 SRFI-64 files: **1 → 0**, and `noted = 1` confirms no other file is in this state. The regression fixture rebuilds the shape from scratch, so the guarantee outlives #2051. Also filed [#2077](https://github.com/kaappi/kaappi/issues/2077) against Phase 2.12's own file)
- [x] 6C: Completions ↔ flag-table drift gate (`--no-ir-opt` is missing from all three scripts; `completions.zig` has zero tests) (2026-08-01, [#2099](https://github.com/kaappi/kaappi/pull/2099); the completions were a hand-maintained list parallel to the parser — **the same failure mode as 4A's `isRejectedFormHead` and the `%`-prefix reservation**, and the third instance of it found in this campaign. A new `src/cli_spec.zig` is the single authoritative table; the parser and all six generated scripts read from it, and a comptime check plus a soundness test (`no script offers a --flag no table declares` — the reverse direction, which is the easy one to forget) fail the build if they ever separate. 41 shell assertions, `docs/dev/cli-surface.md` added, wired into `run-all.sh`. Its `benchmark-pr` failure was **not attributable to the diff** and produced [#2101](https://github.com/kaappi/kaappi/issues/2101): `call_cc` and `call_ec` come from the *same* `zig build bench` invocation and `call_cc` was 1.00x, all 14 other benchmarks were 0.98–1.02x including one ten times smaller, and both are emitted `iterations 1` — the only unrepeated measurements in the table, held to the same 1.20x threshold as the medians)
- [x] 6D: LSP end-to-end — 942 lines, 6 inline tests, no integration test at all (2026-08-01, [#1987](https://github.com/kaappi/kaappi/pull/1987); 152 assertions, 5.2s — filed [#1979](https://github.com/kaappi/kaappi/issues/1979) a `define-syntax` **leaks across documents** and survives `didClose`, [#1981](https://github.com/kaappi/kaappi/issues/1981) four divergences from `kaappi check` incl. whole files going undiagnosed and `KP4xxx` never appearing, [#1980](https://github.com/kaappi/kaappi/issues/1980) six protocol defects incl. **no response at all** on bad `params`)
- [x] 6E: `thottam` — 932 lines, 3 tests; version-constraint parsing, `--locked`, lockfile provenance (2026-08-02, [#2146](https://github.com/kaappi/kaappi/pull/2146); 301 assertions and **10 issues** — and the security question answered **no**: `isValidPkgName` holds against every escape attempted, including a *transitive* dependency name, with the accepted byte set now pinned exhaustively over **0–255**. Made the offline testing work rather than skipping it — `KAAPPI_ORG` points at local **bare git repos**, so clone, tag resolution, checkout, lib copy and lockfile write all ran with no network. Filed [#2130](https://github.com/kaappi/kaappi/issues/2130) `Semver.parse` hands components to `std.fmt.parseInt`, so Zig's integer-literal grammar becomes the version grammar — verified: `1_0` → **10**, so a tag `v1_0.0.0` parses as 10.0.0 and **outranks a legitimate `v2.0.0`** under a constraint as ordinary as `>=1.0.0`; plus [#2131](https://github.com/kaappi/kaappi/issues/2131)–[#2138](https://github.com/kaappi/kaappi/issues/2138) and [#2144](https://github.com/kaappi/kaappi/issues/2144), the one real path asymmetry (`list`/`verify`/`update` build paths from state files unvalidated, while the destructive `remove` is safe *by placement rather than construction*). **The BSD legs then found a bigger bug than the audit did:** the new suite failed on all three, my first hypothesis (git cannot clone a local bare repo) was **disproved by its own probe passing**, and that falsification located [#2152](https://github.com/kaappi/kaappi/issues/2152) — `thottam` hardcodes `/usr/bin/git`, which exists on none of the BSDs, so the package manager is **non-functional on three platforms it ships for**. Compounded by `runGit` discarding git's stderr, which is why three CI runs contained no diagnostic at all)
- [x] 6F: `fmt` adversarial comment placement and a byte-level mutation fuzzer over the corpus (2026-08-02, [#2148](https://github.com/kaappi/kaappi/pull/2148); **~51,000 inputs, 3 root causes, 0 crashes, 0 hangs, 0 comment loss** — a genuine clean bill of health for the fuzzed surface, with all 3 byte-fuzzer guard trips and all 604 glued refusals sharing one cause. All 53 hand-written adversarial comment placements pass on all three oracles. Idempotence **holds** except one family ([#2142](https://github.com/kaappi/kaappi/issues/2142)): `hasBodyBlank` picks the first body item *by index* while the printer counts *non-comment* items — and `begin`/`case-lambda` are immune, being the two table entries with `n = 0`, which is the tell that confirms the diagnosis. [#2143](https://github.com/kaappi/kaappi/issues/2143) is the striking one and is verified here: `(display (list a#;(b) c))` runs and prints `(1 3)`, while `kaappi fmt --check` on the same file reports **`syntax error: unterminated list`** — the root defect being `fmt.zig:146`'s comment claiming its lexer "carves the same lexemes the real reader does", a stated invariant with nothing enforcing it. A spot-check with a *digit* rather than an identifier reproduces nothing, because there the reader also rejects. Also [#2141](https://github.com/kaappi/kaappi/issues/2141), [#2149](https://github.com/kaappi/kaappi/issues/2149), and a correction to #2093: `compile-import-error-703.sh` is not load-sensitive but deterministic build-id skew)

**Phase 7 — GC and portability**

- [x] 7A: Port-satellite tracing invariant — `Port.custom_backend`/`transcode` are hand-traced at 5 sites with no compiler enforcement; unify behind one helper + a mutation test (2026-08-01, [#2098](https://github.com/kaappi/kaappi/pull/2098); **the measurement came first and corrected the premise twice.** Three mutations, each traced nowhere: a new `Port` field and a new `CustomBacking` field were missed by **3 of 5** sites, not 5 — `objectSize` uses `@sizeOf` and `freeObject` uses `destroy`, so both stay correct automatically when a field is added inside an existing satellite; only a brand-new satellite pointer misses all five, and it leaks as well. And "compiles cleanly" is true of `zig build` but **false of `zig build test`** — unit 7B's `expectFields` pin (#1963) catches all three at test-compile time, so the hazard is not silent today, though the guard lives in a test file and the product build says nothing. Each mutation was confirmed to produce a real use-after-free (`referent was reclaimed while its container was reachable`), not a theoretical one. Fix: one `forEachValue` enumeration in `types_port.zig` with three caller-supplied actions, extending `tests_gc_tracing.zig` rather than inventing a parallel mechanism. Green under `zig build test` and `-Dgc-stress=true`)
- [x] 7B: `src/tests_gc_tracing.zig` — per-`ObjectTag` reachability under forced collection, the coverage exhaustive switches cannot provide (2026-08-01, [#1963](https://github.com/kaappi/kaappi/pull/1963); 62 tests, **1496/1496 under `-Dgc-stress=true`**, 8 mutations each with its kill set. **No arm misses a field.** Filed [#1961](https://github.com/kaappi/kaappi/issues/1961) — a minor collection performs a **full transitive mark**, so a forgotten `writeBarrier` is retention rather than a UAF *until* someone makes it generational — and [#1962](https://github.com/kaappi/kaappi/issues/1962) untraced raw env maps)
- [x] 7C: s390x endian gap — the big-endian canary runs only unit tests + `r7rs-tests.scm`; every endian-sensitive SRFI test (74, 160, 174) is excluded, and SRFI 74's own native-agreement assertion is tautological (2026-08-02, [#2145](https://github.com/kaappi/kaappi/pull/2145); **the only unit this campaign that confirmed both tracker claims rather than correcting one.** `s390x-test` runs exactly three steps and no `run-all.sh`, so **no `tests/scheme/**` file carrying an endian assertion had ever run big-endian** — including the SRFI 160 audit whose own header cites this gap. `ppc64le` is not a second canary (POWER is little-endian here). The SRFI 74 tautology is proved by **mutation on the oracle itself**: hardcoding the `endianness` native arm to `'big` leaves `srfi74.scm` at 30/30 pass, while the replacement suite reports 7 failures. Added `src/tests_endian.zig` (12 tests that run on s390x today with no CI change), 99 named Scheme assertions, and a one-command runner. Filed [#2139](https://github.com/kaappi/kaappi/issues/2139). **The trap it found is the campaign's sharpest:** `zig build test -Dtarget=s390x-linux` exits **0 with zero bytes of output having run no tests** (`skip_foreign_checks`; only `--summary all` reveals `skipped`), so the obvious local check for endian work certifies compilation while looking like a full green run. Everything about big-endian *behaviour* was correctly marked INFERRED)
- [x] 7D: Cross-endian `.sbc` round-trip in CI; decide whether the cache key should include the target triple (2026-08-02, [#2159](https://github.com/kaappi/kaappi/pull/2159); **no unconverted field exists** — every scalar routes through `nativeToLittle`/`littleToNative`, every `@bitCast` is paired, and bytecode operands are endian-neutral by construction, so the format was already portable and merely unverified. The deliverable is the instrument: **golden bytes**, asserted writer→bytes and bytes→reader *independently*, with a mutation table that is the unit's whole reason to exist — a **paired** `writeU32`+`readU32` flip **passes 10/10 round-trip tests** and fails both goldens; writer-only and reader-only flips each fail exactly one, proving the directions are genuinely independent. Same treatment for SRFI 271, whose three mutations each leave `srfi271.scm` at 35/35. Cache-key verdict: fold in the target — **with its own counterweight stated**, that `platform_features` is not arch-gated today so the realistic shared-`$KAAPPI_HOME` pairs cannot yet diverge; defense-in-depth now, a live wrong-answer the moment an arch-gated feature is added ([#2155](https://github.com/kaappi/kaappi/issues/2155)). Also [#2156](https://github.com/kaappi/kaappi/issues/2156), verified here: **`kaappi --compile` executes top-level form bodies** — `(begin (delete-file …))` and `(cond-expand (posix (delete-file …)))` both delete the file, while a bare `(delete-file …)` does not. Same dispatcher as #2114: that is the diagnostic half, this is the behavioural one)
- [x] 7E: Add `-Dgc-stress=true` to PR CI in some bounded form (F9) (2026-08-02, [#2165](https://github.com/kaappi/kaappi/pull/2165), 19/19 green; F9 closed. **5F's measurement changed the premise** — the 1.5–3 hour cost that kept gc-stress out of PR CI was ~30× stale — and 7E re-measured on the runner itself: **39 s plain vs 3 m stressed (4.6×)**, its own laptop figure of 1.75× being distorted by concurrent load. Two jobs added for **+58 s of critical path**, because `gc-stress-scheme` displaces the slower Debug leg. **The gate is proved to work:** removing a `pushRoot`/`popRoot` gives `3 crash, exit 1` under gc-stress and `3 skip, success` on plain CI — and its *first* mutation attempt was caught by neither, which taught the real rule (gc-stress detects a lost root when the object is later **marked**, not merely read). Three anti-decoration guards so the job cannot pass vacuously. **It found two real bugs on its first run** — [#2160](https://github.com/kaappi/kaappi/issues/2160), [#2161](https://github.com/kaappi/kaappi/issues/2161) — which is the clearest evidence the coverage did not previously exist. Also [#2157](https://github.com/kaappi/kaappi/issues/2157): five CI steps run `r7rs-tests.scm` bare and the `(chibi test)` shim exits 0 on failure, so **1,395 assertions gate nothing** on riscv64, s390x, ppc64le and both Windows legs; [#2162](https://github.com/kaappi/kaappi/issues/2162)–[#2164](https://github.com/kaappi/kaappi/issues/2164), including [#2163](https://github.com/kaappi/kaappi/issues/2163), which **caught the orchestrator's own false claim about 5F's Scheme half**. TSan verdict self-corrected from the PR's evidence: ruled out on memory, then found CI reports MaxRSS 95 M where macOS reported 8–9 GB — feasible after all)

**Phase 8 — Synthesis**

- [x] 8: Deduplicate, group by root cause, prioritise, update the tracking issue, inventory remaining `;; FAIL:` markers (2026-08-02, [#2171](https://github.com/kaappi/kaappi/pull/2171); **170 open issues → 35 root causes**, all assigned and none double-assigned, plus a `## Findings` section so the doc records what the campaign concluded and not only how it ran. **It refuted three of the five leads it was given** — the SRFI 166 single-cause framing (above), the arity cluster (four unrelated defects, though three sites hand-rolling frame setup instead of routing through `callClosure` is a real structural finding), and a mis-attributed issue number — which is the outcome that was asked for. Its priority argument is the campaign's central finding stated as an action: **fix the green-but-tests-nothing class first, because until failure is detectable every other fix's regression test is of unknown value.** Then the four uncatchable panics, where `#e` near 2^63 panics *inside* `check` and `fmt` — commands that execute nothing, so opening an untrusted file suffices. Found two previously-unfiled structural items: `isSpecialTopLevelForm` is a **fourth** hand-maintained parallel list, and the `segment`-at-`n=0` class has **four** members not two ([#2172](https://github.com/kaappi/kaappi/issues/2172), verified here — `string-segment` and `range-segment` hang, `n=1` clean, and SRFI 171's `tsegment` raises correctly, which proves a missing precondition rather than an inherent shape). Marker inventory: 101 distinct numbers, **none citing a closed issue** — the convention held for the whole campaign — but one cites a *merged PR* rather than an issue, which a mechanical state audit reads as done, and three use `;;;` so a grep for the documented convention misses them)

---

## New audit dimensions

The v1 skill checked six bug patterns (type-dispatch gaps, GC safety, UTF-8
indexing, callback error propagation, boundary conditions, ignored optional
arguments). All still apply. These seven are new since v1 and belong in every
Phase 2 session:

| | Dimension | Why it did not exist in v1 |
|---|---|---|
| D1 | **Internal-primitive direct-call surface** | The `%`-prefix convention and the `INTERNAL`/`INTERNAL_PUBLIC` split postdate v1 (#1856). ~53 procedures are callable from a plain script with no import and have zero test mention |
| D2 | **Error-taxonomy correctness** | `typeError`/`indexError`/`argError` now carry distinct codes (KP3002/3006/3007). `indexError` appears in 6 files, `argError` in 3 — bounds failures are likely still reported as type errors elsewhere |
| D3 | **Diagnostic fidelity** | F10's opaque rendering was fixed (#1899): `safeValueDescription` now names a symbol/string/char/rational/small-bignum value. The dimension stays live — the `else` arm still renders unlisted tags opaquely, and every new heap type must decide what its `got` field says |
| D4 | **Registration-table invariants** | `specs` arity vs. what the body indexes; `libs` tags vs. the SRFI's export list; the comptime `%`-vs-`scheme.*` check. Pure table-vs-body audit, no runtime needed |
| D5 | **Re-entrancy and parking discipline** | Fibers, the reactor, custom-port callbacks and guardian invocation are all post-v1. Which callbacks may block, and does the rejection stay catchable? |
| D6 | **Cross-heap deep-copy closure** | Every new heap type must round-trip both SRFI-18 boundaries or fail cleanly |
| D7 | **`--sandbox` / WASM degradation consistency** | A per-name gate that nobody has reviewed as a set — e.g. `%kaappi-lib-dir` is gated under `--sandbox` while `%os-name` is not |

---

## Phase details

### Phase 0 — Baseline and documentation truth (2 sessions)

**0A.** Run the baseline, create labels, open the tracking issue, and file
F1–F13 (reproducing the two `[A]` rows first).

```bash
zig build test
kaappi test tests
bash tests/scheme/run-all.sh
bash tools/audit-baseline.sh /tmp/audit-v2-baseline
```

The 2026-07-31 baseline (`261fde5f`, macOS aarch64, ReleaseSafe) was **624/624
Scheme files and 1395/1395 R7RS assertions, zero failures** — so unlike v1's
Phase 0, expect no free discoveries here. Its value is the "before" snapshot and
the confirmation that any red you see later is yours.

Note that a full `run-all.sh` now takes considerably longer than in v1 — over an
hour on a laptop with other work running, because the shell suites drive real
native compiles.

**0B.** The documentation-truth pass. Work through the table in
*Reconnaissance findings* above; for each claim, verify against the binary and
either delete, re-scope, or convert it into a filed issue. This is the highest
leverage half-hour in the campaign: it stops every later session from chasing
bugs that were fixed months ago.

Also refresh the two stale support artefacts:

- `tests/scheme/CLAUDE.md`'s directory table omits `fmt/`, `doctor/`, `cache/`,
  `pipeline/`, `timings/`, `test-runner/` and `acceptance/` — all of which exist
  and all of which `run-all.sh` runs.
- `.claude/skills/audit-primitives/SKILL.md` documents the old
  `try reg(vm, ...)` registration (it is now a `specs` table) and lists 18 of
  the 31 primitives files. Every Phase 2 session loads this skill.

### Phase 1 — Reader, printer, numeric tower (4 sessions)

The reader is where the reconnaissance found the highest density of real,
never-filed bugs (F1–F4), which is unsurprising: v1's Phase 1 audited the
*procedures* R7RS §6.2 defines, not the *lexical syntax* §7.1.1 defines.

Read §7.1.1 (external representations) and §6.2.5–6.2.7 (numeric I/O) from
`docs/errata-corrected-r7rs.pdf`, and use `/r7rs-reader` for the lexical
reference. Write tests to `tests/scheme/compliance/reader-<topic>-gaps.scm`.

The systematic invariant for 1A–1C is round-trip:
`(equal? x (read (open-input-string (write-to-string x))))` across every type,
plus the same via a *file* port for the buffer-boundary cases. Roughly 90 such
cases already pass; the failures are listed as F1–F4 and F12.

### Phase 2 — Primitives (13 units)

10 of 31 primitives files have **no audit test at all**, and every one of those
10 postdates v1. Six more have v1-era audit tests that are now badly
undersized relative to their file's growth.

Use `/audit-primitives`, with two overrides: do **not** fix (file instead), and
add dimensions D1–D7 to the skill's six patterns.

| File | Lines | Specs | Audit test | Churn since v1 |
|---|---:|---:|---|---|
| `primitives_io.zig` | 1941 | 45 | 112 lines | **+1108/−72** |
| `primitives_fiber.zig` | 1384 | 11 | 135 lines | **+1241/−110** |
| `primitives_srfi18.zig` | 1435 | 35 | 140 lines | **+793/−352** |
| `primitives_vector.zig` | 1215 | 42 | 314 lines | +419/−119 |
| `primitives_hashtable.zig` | 901 | 24 | 268 lines | +403/−55 |
| `primitives_srfi237.zig` | 457 | 18 | **none** | new |
| `primitives_srfi160.zig` | 280 | 6 | **none** | new |
| `primitives_srfi181.zig` | 234 | 10 | **none** | new |
| `primitives_srfi254.zig` | 159 | 16 | **none** | new |
| `primitives_random_port.zig` | 123 | 5 | **none** | new |
| `primitives_parallel.zig` | 122 | 9 | **none** | new |
| `primitives_sysinfo.zig` | 119 | 7 | **none** | new |
| `primitives_srfi260.zig` | 104 | 1 | **none** | new |
| `primitives_srfi258.zig` | 92 | 3 | **none** | new |
| `primitives_srfi211.zig` | 55 | 2 | **none** | new |
| `primitives_filesystem.zig` | 1123 | 69 | 177 lines | +162/−80 |

### Phase 3 — SRFI breadth (10 units)

**Coverage as measured 2026-07-31:** of 178 SRFIs, 12 have **no test file**
(2, 8, 11, 14, 16, 28, 31, 34, 111, 145, 222, 229) and ~15 are smoke-only
(≤12 assertions). More usefully, across the 79 SRFIs with ≥10 exports,
**1,293 of 3,993 exported names (32%) never appear in their own test file** —
a metric that survives helper-heavy suites where a raw assertion ratio does not.

The worst offenders by untested-export count: SRFI 14 (23/23, 100% — see F6),
160 (640/732), 158 (43/55), 146 (108/161), 166 (52/89), 64 (48/72),
257 (37/79), 113 (41/113), 178 (35/107), 225 (28/82).

Two caveats from the reconnaissance, both worth carrying:

- **SRFI 231 is well tested** (122 exports, 417 assertions, 1,040 lines, partly
  verbatim from the reference implementation). Do not audit it.
- **A high untested-export count is not itself evidence of bugs.** Spot probes
  of 11 untested SRFI 160 generics and 18 untested SRFI 158 generators all
  **passed**. Treat those units as closing a measurement gap, and rank
  bug-hunting effort toward per-kind range/exactness rejection and the seams
  (u8-as-bytevector, c64/c128 packing) rather than the generic bodies.

For each SRFI: read `lib/srfi/N.sld`, check
[srfi-explorations/srfi-test](https://github.com/srfi-explorations/srfi-test)
for an adaptable SRFI-64 suite before writing from scratch, then test the
spec's own documented examples plus edge cases.

### Phase 4 — Execution-tier divergence (5 units)

The interpreter has an oracle. **No other tier is checked against it.** Native
coverage is 112 LLVM-IR-*text* assertions plus 22 hand-written golden-value
shell scripts, only 2 of which compare tiers; WASM has 3 files and asserts only
an exit code.

The differential harness, `tests/scheme/differential/run-differential.sh`:

```text
for f in corpus:
  base = kaappi f                       # oracle
  cmp    kaappi --no-ir-opt f           # tier b — no build needed
  cmp    kaappi compile f -o x && ./x   # tier c — needs `zig build lib`
  cmp    cold vs warm $KAAPPI_HOME      # tier d — no build needed
compare (stdout, normalised stderr, exit code)
```

- **Corpus:** `tests/scheme/{smoke,compliance,audit}` (333 files); add
  `continuations/`, `hygiene/`, `srfi/` for tiers b and d. The native tier must
  skip anything importing a `.sld` (`kaappi compile` refuses those explicitly).
- **Exclusions:** gensym counters, `current-time`, hash iteration order,
  thread/fiber scheduling, `--timings`, absolute paths, `bench/`, `coverage/`.
- **Normalisation:** strip absolute temp paths and line numbers from stderr —
  a naive diff surfaces pure harness noise on every file.
- **Pass criterion:** byte-identical stdout and identical exit code; a mismatch
  names the tier.

Tiers (b) and (d) already run **green across 333 files** and need no build, so
land them first as a regression gate — any future diff is signal.

One caveat that shapes 4B: `kaappi ir` and `kaappi ir --no-opt` produce
**byte-identical output on 40 of 40 smoke files**, because every `define`/
`lambda` body lowers to an opaque `passthrough` node. The five IR optimisation
passes only reach top-level expression position, and only constant folding
visibly fired there. A differential that means anything must use
**top-level-expression-shaped generated probes**, not the existing corpora —
which is also why the 333-file green result is a weak negative, not a
clean bill of health.

### Phase 5 — Concurrency (7 units)

Constraint: **a flaky test is worse than no test.** Prefer deterministic
invariants and bounded-time assertions to wall-clock timing; put soak runs
behind a `KAAPPI_SOAK_N` flag defaulting to 1 in CI.

Current state: 138 Zig unit tests across fibers/scheduler/reactor/shared-channel
and ~60 Scheme files, but `waitForFd`, `driving_waits` and
`anyAncestorWaitResolved` have **zero direct test references** — the park-vs-drive
branch is only ever reached incidentally. #1625's unwind has exactly one test.
There is no deterministic scheduler seed, no soak harness, no TSan, no valgrind,
and no gc-stress on PRs (F9).

### Phase 6 — Tooling (6 units)

New since v1 and, apart from `compile`, thinly covered. The good news from
reconnaissance is substantial and worth not re-litigating:

- **`fmt` is genuinely robust.** Across an 847-file corpus it formatted clean,
  was 100% idempotent on a second pass, and lost no information across line,
  block and `#;` datum comments, raw strings, the `#\(`/`#\;`/`#\"`/space
  character literals,
  piped symbols containing parens, `#e#xFF`, custom ellipsis, and cyclic datum
  labels. Its one defect is line endings (F8).
- **The #1517 invariant holds exactly** — `features --json` matches runtime
  `(features)` element-for-element, and all 174 advertised `(import (srfi N))`
  succeed.
- **`explain` is complete** (29/29 codes) and **`check` is sound** on the
  probes tried (no false positive on a shadowed `car` or a forward reference).

So Phase 6 is mostly about the untested edges: the LSP (942 lines, no
integration test), `thottam` (932 lines, 3 tests), `completions.zig` (262
lines, 0 tests), and the two runner/formatter defects F8 and F13.

### Phase 7 — GC and portability (5 units)

All five exhaustive per-tag switches are genuinely exhaustive today — no
`else` arm in any of `markObjectContents`, `markValueInner`, `referencesYoung`,
`objectSize`, `freeObject` — and every recently-added Value-bearing field
(`RecordType.parent`, `Port.custom_backend`, `Port.transcode`,
`Transformer.proc`) is traced everywhere it must be.

The structural risk is that **exhaustiveness is compiler-enforced but the
inside of each arm is enforced by nothing.** `Port`'s satellites are hand-traced
at five sites, and `markValueInner` deliberately duplicates `markPortValues`
rather than calling it. A third Value-bearing `Port` field would compile
cleanly while being invisible to the GC in up to five places. 7A unifies this;
7B adds the per-tag reachability test that the switches cannot provide.

For portability: `.sbc` files *are* endian-portable (every scalar goes through
`nativeToLittle`/`littleToNative`), but **no test writes on one endianness and
reads on the other** — the s390x leg builds and runs on s390x only, so a paired
byte-swap bug would cancel out. Meanwhile the big-endian canary runs only unit
tests plus `r7rs-tests.scm`, so SRFI 74, 160 and 174 — the actual
byte-order-sensitive surfaces — never execute there, and SRFI 74's one
"native accessors agree" assertion is tautological (`blob-u32-native-set!` *is
defined as* `(blob-u32-set! (endianness native) …)`).

---

## Parallelization

```text
              Phase 0 (baseline + doc truth)
                        │
   ┌────────┬───────────┼───────────┬────────┬────────┐
   ▼        ▼           ▼           ▼        ▼        ▼
Phase 1  Phase 2    Phase 3    Phase 4   Phase 5  Phase 6/7
(reader) (prims)    (SRFI)     (tiers)  (concur)  (tools/GC)
4 units  13 units   10 units   5 units  7 units   11 units
   └────────┴───────────┴───────────┴────────┴────────┘
                        ▼
                    Phase 8 (synthesis)
```

Phase 0B should land before anything else — it prevents every later session
from chasing five already-fixed expander bugs.

Everything after that is independent. **3–4 concurrent sessions**, each in its
own worktree; beyond that, issue triage becomes the bottleneck and parallel
sessions file overlapping findings faster than the dedup search catches them.

Phases 5F, 5G and 7C need machines this laptop is not: `/do-stress-test`
(gc-stress on Linux, hours), `/do-linux-test` (epoll), `/vm-test` (kqueue on
the BSD VMs, and the s390x/ppc64le Alpine VMs for the endian work).

### Budget

| Phase | Units | Time each | Wall-clock (4-way) |
|---|---:|---:|---:|
| 0: Baseline + doc truth | 2 | 40 min | 40 min |
| 1: Reader/printer/numeric | 4 | 30 min | 30 min |
| 2: Primitives | 13 | 30 min | ~100 min |
| 3: SRFI breadth | 10 | 30 min | ~75 min |
| 4: Execution tiers | 5 | 40 min | ~50 min |
| 5: Concurrency | 7 | 40 min | ~70 min + machine time |
| 6: Tooling | 6 | 30 min | ~45 min |
| 7: GC/portability | 5 | 40 min | ~50 min |
| 8: Synthesis | 1 | 30 min | 30 min |
| **Total** | **53** | **~28 hr serial** | **~8 hr** |

---

## GitHub issue workflow

### Labels

The v1 labels (`r7rs-conformance`, `srfi`, `audit`, `numeric-tower`,
`continuations`, `macros`) already exist. Add:

```bash
gh label create "tier-divergence" --description "Interpreter vs native vs WASM vs cache" --color "0052CC"
gh label create "tooling" --description "CLI subcommands, fmt, check, LSP, thottam" --color "5319E7"
gh label create "doc-truth" --description "Docs describe behavior that no longer exists" --color "C2E0C6"
```

### Before filing — dedup (mandatory)

```bash
gh issue list --state all --search "<procedure-name>" --limit 10
```

### Title conventions

```text
[R7RS 7.1.1] #e1e19 reads as inexact — exactness prefix dropped on i64 overflow
[SRFI-14] char-set is a multiset, is ASCII-only, and exports 23 of ~60 names
[Native] isRejectedFormHead omits define-property — parallel to a derived list
[Tooling] kaappi fmt silently converts CRLF to LF
[Doc-truth] CLAUDE.md lists five expander limitations that are fixed
```

One issue per root cause: if five procedures share one missing dispatch branch,
file one issue listing all five.

### Body template

```markdown
**Category:** R7RS / SRFI / Native / Tooling / GC / Doc-truth
**Spec reference:** R7RS §7.1.1, page 62 — quote the exact sentence
**Severity:** crash / wrong-result / missing-feature / edge-case / doc-truth

**Minimal reproduction:**
\```scheme
(exact? #e1e19)   ;; expected: #t   actual: #f
\```

**Discriminating control:** `(exact? #e1e18)` ⟹ `#t` — the cliff is the i64 boundary

**Verified:** fresh ReleaseSafe build at <commit>, cache cleared; gc-stress unchanged/changed
**Source location:** src/reader_tokens.zig:447 (parseFloat fallback drops the prefix)
**Disabled test:** tests/scheme/compliance/<file>.scm (marked ;; FAIL: #this)

**Found by:** Systematic audit v2, Phase N
```

---

## Community resources

| Resource | URL | Purpose |
|---|---|---|
| Chibi R7RS tests | [ashinn/chibi-scheme](https://github.com/ashinn/chibi-scheme/blob/master/tests/r7rs-tests.scm) | De facto conformance suite; diffing against our adaptation is a cheap gap-finder. Also the pinned oracle for the nightly `Kaappi vs Chibi` fuzz job |
| r7rs-coverage | [ecraven.github.io/r7rs-coverage](https://ecraven.github.io/r7rs-coverage/) | Per-procedure coverage matrix across ~14 implementations |
| SRFI portable tests | [srfi-explorations/srfi-test](https://github.com/srfi-explorations/srfi-test) | Aggregated SRFI tests in SRFI-64 format |
| TaylanUB/scheme-srfis | [TaylanUB/scheme-srfis](https://github.com/TaylanUB/scheme-srfis) | R7RS SRFI implementations with SRFI-64 tests (SRFIs 0–123) |
| SRFI-64 | [srfi.schemers.org/srfi-64](https://srfi.schemers.org/srfi-64) | Test framework API |
