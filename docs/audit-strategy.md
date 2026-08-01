# Systematic Correctness Audit Strategy (v2)

**Status:** in progress (19 of 53 units — 2.12 still held by a FreeBSD divergence, see [#1985](https://github.com/kaappi/kaappi/pull/1985)) · **Last updated:** 2026-08-01 · **Tracking issue:** [#1890](https://github.com/kaappi/kaappi/issues/1890)
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
   failure is a raise rather than a wrong value: a top-level error inside an
   expected-fail case sets `error=true` in `kaappi test` even as the legacy
   runner reports the file green — exactly the F13 divergence.
8. **Open a PR**, tick your box in the tracker, post one line on the tracking
   issue.

### Footguns

- **`timeout` does not exist on stock macOS.** Use the `run_timeout` helper in
  `tests/scheme/audit-baseline.sh` (tries `timeout`, then `gtimeout`, then
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
- [ ] 2.3: `primitives_srfi181.zig` (new, no test) — custom-port callback re-entrancy and the blocking rejection
- [x] 2.4: `primitives_srfi160.zig` (new, no test) — 11-way element-kind dispatch over raw bytes, c64/c128 packing (2026-07-31, [#1952](https://github.com/kaappi/kaappi/pull/1952); 1066 assertions — filed [#1949](https://github.com/kaappi/kaappi/issues/1949) `Uvector-segment` with `n=0` **hangs**, [#1950](https://github.com/kaappi/kaappi/issues/1950)/[#1951](https://github.com/kaappi/kaappi/issues/1951) c64/c128 elements are always Complex. The 12-kind × boundary matrix and both seams are **correct**; the two range rules agree across 276 cells)
- [x] 2.5: `primitives_srfi237.zig` (new, no test) — sealed/opaque/uid, multi-level inheritance (2026-08-01, [#1975](https://github.com/kaappi/kaappi/pull/1975); 186 assertions, 26 disabled — filed [#1973](https://github.com/kaappi/kaappi/issues/1973) a **27-field record aborts the process** via u8 size arithmetic, reachable from plain R7RS `define-record-type`, and [#1974](https://github.com/kaappi/kaappi/issues/1974) four R6RS defects — **#1974 is fixed** ([#1989](https://github.com/kaappi/kaappi/pull/1989)), which enabled its 10 disabled assertions and re-pinned the 20 that documented the defects, taking the file to 209. Protocol composition is exact at 16/16 masks; the **nongenerative** cross-thread path is pinned enabled so #1932's fix flips a test)
- [ ] 2.6: `primitives_fiber.zig` (+1241 lines against a 135-line audit test)
- [ ] 2.7: `primitives_srfi18.zig` (+793/−352) — deep-copy round-trip for every new heap type
- [ ] 2.8: `primitives_hashtable.zig` (+403, 8 callback sites)
- [ ] 2.9: `primitives_control.zig` (14 callback sites; SRFI 248 sticky handlers are new)
- [ ] 2.10: `primitives_srfi254.zig` (new, no test) — GC-integrated; guardians are callable
- [x] 2.11: Batch — `parallel`, `sysinfo`, `random_port`, `srfi258`, `srfi260`, `srfi211` (~570 lines, 27 specs, none audited) (2026-08-01, [#2011](https://github.com/kaappi/kaappi/pull/2011); 230 assertions + a 17-assertion D7 sandbox suite, 7 disabled — **the six files themselves are clean**: all 27 specs correct, zero panics across ~120 adversarial calls, D1 all-reachable, D7 gate exactly as documented, and SRFI 258's uninterned-ness survives both deep-copy directions *with sharing preserved*. Every finding is in the surrounding engine: [#2003](https://github.com/kaappi/kaappi/issues/2003) a use-site `let` **captures a macro template's free reference to any global procedure**, so `(let ((car …)) …)` hijacks `car` inside any macro — the local-scope half of closed #1812, confirmed wrong against Chibi and Guile, with the def-site-local and global-non-procedure cases passing as controls; [#2005](https://github.com/kaappi/kaappi/issues/2005) `load` of a file containing `import` fails and blames the *loader's* line 1; [#2007](https://github.com/kaappi/kaappi/issues/2007) `kaappi check` calls two valid SRFI 211 transformer-specs invalid syntax; [#2009](https://github.com/kaappi/kaappi/issues/2009) doc-truth. Extended [#1913](https://github.com/kaappi/kaappi/issues/1913): the all-zero-seed port's own state fails `random-port-state?`, so it cannot be rebuilt from itself)
- [ ] 2.12: `primitives_filesystem.zig` — 69 specs and 102 syscalls against a 177-line test
- [ ] 2.13: Error-taxonomy sweep (D2) + diagnostic fidelity (F10, D3)

**Phase 3 — SRFI breadth** (independent)

- [x] 3.1: **SRFI 14 rewrite** (F6) — range/inversion-list rep over the existing Unicode tables, plus the ~37 missing names (2026-07-31, [#1928](https://github.com/kaappi/kaappi/pull/1928), closed #1895; inversion lists, all 64 spec names, 172-assertion suite — 17/147 against the old library; filed [#1924](https://github.com/kaappi/kaappi/issues/1924) **cross-thread use-after-free**, [#1925](https://github.com/kaappi/kaappi/issues/1925) `char-numeric?` BMP-only, [#1927](https://github.com/kaappi/kaappi/issues/1927) `--lib-path` cannot shadow a bundled SRFI)
- [x] ~~3.2: SRFI 160 sweep A~~ — **subsumed by 2.4**, which swept all 12 element kinds (8 integer kinds × {min, min±1, max, max±1} plus 9 rejection classes, every cell correct) and cross-checked the two independent range rules across 276 cells. The "87% `s8`" gap it was written against is closed.
- [x] ~~3.3: SRFI 160 sweep B~~ — **subsumed by 2.4**, which covered both seams (u8-as-bytevector in both directions; c64/c128 packing incl. per-component precision, ±inf/NaN, and a rejected `set!` leaving the slot untouched) and verified the per-type wrappers three ways — each `.sld` mentions only its own tag, tag-normalised the 12 files are byte-identical, and a 12×12 predicate matrix is true only on the diagonal.
- [ ] 3.4: SRFI 146 (108 of 161 exports untested)
- [ ] 3.5: SRFI 166 + `columnar`/`unicode`/`color`/`pretty` sub-libraries (52 of 89 untested)
- [ ] 3.6: SRFI 158 generators (43 of 55 untested)
- [ ] 3.7: NO-TEST batch — 2, 8, 11, 16, 28, 31, 34, 111, 145, 222, 229
- [ ] 3.8: SMOKE-ONLY batch — 23, 46, 98, 112, 139, 149, 188, 190, 236, 244
- [ ] 3.9: Large-and-thin batch — 113, 225, 178, 152, 240, 189, 35, 27
- [ ] 3.10: Un-quarantine `tests/scheme/srfi/slow/` (F11) and re-triage SRFI 150's expected failures against closed #1832

**Phase 4 — Execution-tier divergence**

- [ ] 4A: Derive `isRejectedFormHead` from the comptime set (F7) + a test asserting `derived ⊆ rejected ∪ documented-exclusions`
- [x] 4B: Ship `tests/scheme/differential/run-differential.sh` — tiers (b) opt-off and (d) cold/warm cache first; both need no build and already run green (2026-07-31, [#1923](https://github.com/kaappi/kaappi/pull/1923); 557 files, 0 divergence, wired into run-all.sh; filed [#1922](https://github.com/kaappi/kaappi/issues/1922) cache HIT loses error source lines. Quantified the tier-(b) weakness: only **9 of 331** corpus files make the optimiser do anything. Debug reduces to `probes/` after CI timed out at 300s)
- [ ] 4C: Convert `tests/scheme/compile/*.sh` from golden strings to an interpreter oracle (only 2 of 22 compare tiers today)
- [ ] 4D: WASM cross-tier — diff the import-free corpus under wasmtime against the interpreter (today: 3 files, exit-code only)
- [ ] 4E: `.sbc` cache coverage — only 42 of 333 corpus files populate it; `sbc equiv:` covers 6 toy forms

**Phase 5 — Concurrency**

- [ ] 5A: **Validate-or-retire** the SRFI 120 corruption claim; deliver either a live repro or a PR rewriting the header plus tests pinning both rejections
- [x] 5B: `waitForFd` park-vs-drive protocol — zero tests reference `waitForFd`, `driving_waits`, or `anyAncestorWaitResolved` (2026-08-01, [#1960](https://github.com/kaappi/kaappi/pull/1960); 26 tests, **no bugs in `waitForFd`**. Pinned the 2×2 selector and the unwind asymmetry, whose nine `false` rows had zero coverage. Filed [#1959](https://github.com/kaappi/kaappi/issues/1959) — the user-visible error names `dynamic-wind` as unparkable when it is not)
- [x] 5C: `gc_deep_copy` promoted-stub ownership skip — an already-promoted channel stub bypasses the owner check (2026-07-31, [#1938](https://github.com/kaappi/kaappi/pull/1938); 49 assertions, 24 disabled — CLAUDE.md's sharing model confirmed verbatim, 11 sound behaviours pinned; filed [#1933](https://github.com/kaappi/kaappi/issues/1933) **parent GC reclaims objects a live child references** (gc-stress: hard UAF panic), [#1932](https://github.com/kaappi/kaappi/issues/1932) a record loses its type across `thread-join!`, [#1934](https://github.com/kaappi/kaappi/issues/1934)–[#1937](https://github.com/kaappi/kaappi/issues/1937))
- [x] 5D: SRFI-18 re-audit (994 → 1435 lines since v1) (2026-08-01, [#1986](https://github.com/kaappi/kaappi/pull/1986); 77 → 274 assertions — filed [#1982](https://github.com/kaappi/kaappi/issues/1982) `thread-terminate!` **cannot interrupt a native wait**, a residual of closed #880 whose own verification used a `(thread-yield!)` loop — exactly the case its fix handles; [#1983](https://github.com/kaappi/kaappi/issues/1983) unguarded float→int aborts that reach `(kaappi fibers)` too; [#1984](https://github.com/kaappi/kaappi/issues/1984) four state-machine defects. **Portability lesson:** an assertion pinning `(seconds->time +nan.0)` ⟹ `0.0` failed only on CI's NetBSD — `@intFromFloat` on NaN is undefined, so never assert its *value*; assert that it does not abort, which is the real contrast with #1983's aborting cases.)
- [ ] 5E: De-flake and arm the timing tests (76 wall-clock lines; `smoke/thread-sleep-876.scm` has no exit path at all)
- [ ] 5F: gc-stress × concurrency — needs `/do-stress-test` (Linux, hours)
- [ ] 5G: Reactor backend parity — needs `/do-linux-test` (epoll) and `/vm-test` (kqueue)

**Phase 6 — Tooling**

- [ ] 6A: `fmt` line-ending policy (F8) — decide preserve-vs-normalise, implement, document, test CRLF/lone-CR/mixed
- [ ] 6B: Reconcile `kaappi test` with `run-all.sh` (F13)
- [ ] 6C: Completions ↔ flag-table drift gate (`--no-ir-opt` is missing from all three scripts; `completions.zig` has zero tests)
- [x] 6D: LSP end-to-end — 942 lines, 6 inline tests, no integration test at all (2026-08-01, [#1987](https://github.com/kaappi/kaappi/pull/1987); 152 assertions, 5.2s — filed [#1979](https://github.com/kaappi/kaappi/issues/1979) a `define-syntax` **leaks across documents** and survives `didClose`, [#1981](https://github.com/kaappi/kaappi/issues/1981) four divergences from `kaappi check` incl. whole files going undiagnosed and `KP4xxx` never appearing, [#1980](https://github.com/kaappi/kaappi/issues/1980) six protocol defects incl. **no response at all** on bad `params`)
- [ ] 6E: `thottam` — 932 lines, 3 tests; version-constraint parsing, `--locked`, lockfile provenance
- [ ] 6F: `fmt` adversarial comment placement and a byte-level mutation fuzzer over the corpus

**Phase 7 — GC and portability**

- [ ] 7A: Port-satellite tracing invariant — `Port.custom_backend`/`transcode` are hand-traced at 5 sites with no compiler enforcement; unify behind one helper + a mutation test
- [x] 7B: `src/tests_gc_tracing.zig` — per-`ObjectTag` reachability under forced collection, the coverage exhaustive switches cannot provide (2026-08-01, [#1963](https://github.com/kaappi/kaappi/pull/1963); 62 tests, **1496/1496 under `-Dgc-stress=true`**, 8 mutations each with its kill set. **No arm misses a field.** Filed [#1961](https://github.com/kaappi/kaappi/issues/1961) — a minor collection performs a **full transitive mark**, so a forgotten `writeBarrier` is retention rather than a UAF *until* someone makes it generational — and [#1962](https://github.com/kaappi/kaappi/issues/1962) untraced raw env maps)
- [ ] 7C: s390x endian gap — the big-endian canary runs only unit tests + `r7rs-tests.scm`; every endian-sensitive SRFI test (74, 160, 174) is excluded, and SRFI 74's own native-agreement assertion is tautological
- [ ] 7D: Cross-endian `.sbc` round-trip in CI; decide whether the cache key should include the target triple
- [ ] 7E: Add `-Dgc-stress=true` to PR CI in some bounded form (F9)

**Phase 8 — Synthesis**

- [ ] 8: Deduplicate, group by root cause, prioritise, update the tracking issue, inventory remaining `;; FAIL:` markers

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
| D3 | **Diagnostic fidelity** | `safeValueDescription` renders symbols, strings, vectors, bytevectors, rationals and bignums opaquely — see F10 |
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
bash tests/scheme/audit-baseline.sh /tmp/audit-v2-baseline
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
