# `kaappi test` — first-class SRFI-64 runner

The suite standardises on [SRFI-64](https://srfi.schemers.org/srfi-64/) as its
test harness. `kaappi test` is the runner an agent or CI drives on top of it: it
discovers SRFI-64 suites, runs each one, and aggregates pass/fail/skip counts
**from the SRFI-64 runner's own counters** — never by scraping the
`# of expected passes` lines. It is part of the machine-legibility epic
(kaappi#1503, kaappi#1509); the guiding rule is that a caller can go from a
failing suite to a fix using documented, structured output alone.

```text
kaappi test [paths...]
```

- **Discovery.** With no paths, recurse `./tests` and keep files that use
  SRFI-64 (a source substring check on `srfi 64`, which skips benchmarks, the
  chibi-test R7RS suite, and coverage helpers). A named **file** is run as given
  (no filter — you asked for it by name); a named **directory** is recursed with
  the SRFI-64 filter. Discovered files run in sorted order.
- **`--json`.** Emit JSON Lines: one `{"type":"file", …}` object per file, then
  one `{"type":"summary", …}` object. See the schema below.
- **`--seed <n>`.** Seed SRFI-27's default random source deterministically
  (`random-source-pseudo-randomize! default-random-source 0 n`), so a run with
  the same seed reproduces the same `random-integer`/`random-real` draws. The
  effective seed — pinned or auto-chosen — is printed on **every** run (to
  stderr, so `--json` stdout stays pure), so any failure can be replayed with
  `--seed`.
- **`--lib-path <path>`.** Repeatable; forwarded to every test file. This is
  what makes the runner work unchanged on an ecosystem repo:
  `kaappi test --lib-path ./lib`.
- **`-j` / `--jobs <n>`.** Run up to `n` files concurrently (default: one per
  CPU; `--jobs 1` forces the old strictly-sequential behaviour). Because every
  file is already an isolated worker process, this changes scheduling only —
  verdicts, per-file output and its **ordering**, and the summary counts are
  identical at any job count. Durations are the one thing that legitimately
  moves, so `tests/scheme/test-runner/jobs.sh` normalises the `…ms` fields and
  then requires the whole transcript to match byte for byte. Windows always runs
  one job; see below.
- **Exit status** is nonzero iff a test failed, unexpectedly passed (`xpass`),
  or a file errored.

## How it works: one worker subprocess per file

`kaappi test` is an **orchestrator**. For each file it forks a **worker** — an
ordinary `kaappi <file>` invocation with `KAAPPI_TEST_EMIT` (and, when seeded,
`KAAPPI_TEST_SEED`) set in its environment. The worker's presence of
`KAAPPI_TEST_EMIT` is what puts it in worker mode; there is no user-facing worker
flag.

Subprocess isolation is deliberate. A test file may loop, segfault, leak an
SRFI-18 thread, open sockets, or call `(exit 1)` in its failure epilogue. In a
separate process, none of that can corrupt the run or bleed into another file's
results, and a hung file is a `kill` away — the same robustness the legacy
`tests/scheme/run-all.sh` gets from spawning per file, but with structured
results instead of scraped text. It is also what makes `--jobs` cheap: files are
already independent units, so running several at once needs no isolation work of
its own.

### How `--jobs` runs them

Worker threads claim file indices from one atomic counter and each performs the
whole blocking sequence for its file (spawn → drain the pipe → `waitpid` → read
the emitted JSON). The **main thread reports**, walking the completed prefix in
file order, so output streams in exactly the order a sequential run would print
it even though files finish out of order. Each outcome is freed as it is
reported, so peak retention is whatever finished ahead of the reporting cursor.

Two details are load-bearing:

- **The emit path travels in the child's own `envp`,** not in the parent's
  environment. `setenv` on the parent before each fork — what the sequential
  version did — is a single mutable global shared by every in-flight worker, so
  two concurrent spawns would send both children to the same emit path and lose
  a result.
- **Windows is pinned to one job** (`resolveJobs`). There `CreateProcessW`
  inherits the parent's environment block and this code builds no custom one, so
  the emit path is still set on the parent, which is only safe while spawns are
  serialised. Lifting this means threading an environment block through
  `platform.winSpawnCaptureMerged`.

Reporting stays single-threaded, so `Totals` and stdout need no locking.

Inside the worker (`src/main.zig` `runWorkerFile` → `src/test_runner.zig`):

1. **Install a collecting runner.** Before the file runs, the worker evaluates a
   prelude that sets `test-runner-factory` to a factory built on
   `test-runner-null` (so the SRFI-64 machinery prints nothing and writes no
   `.log` file). Its `on-test-end` hook reads `test-result-kind` and the
   result-alist and funnels every result into `%kt-*` accumulators; its
   `on-group-begin` hook captures the outermost suite name. Because
   `(import (srfi 64))` is idempotent, the file's own import doesn't reset the
   factory. Multiple `test-begin`/`test-end` groups in one file each get a fresh
   runner via the factory, and all funnel into the same accumulators.
2. **Suppress `(exit)`.** The worker sets `vm.suppress_exit`, so a file's
   `(exit 1)` failure epilogue becomes a *recorded* no-op (`vm.exit_requested`
   / `vm.exit_code`) instead of terminating the worker before it can emit its
   result. Because the call never happens, its *semantics* are reapplied when
   the verdict is resolved — see [Verdicts](#verdicts-and-what-errored-means)
   below.
3. **Run the file** via the normal `runFile` path (so the `.sbc` cache, imports,
   and error diagnostics all behave exactly as a plain run).
4. **Emit one JSON object** for the file to `KAAPPI_TEST_EMIT`, built by walking
   the `(%kt-collect)` vector. Writing to a file (not stdout) keeps it separate
   from the test file's own output, and is robust to the worker crashing.

The orchestrator reads that file back, parses it with a real JSON parser
(`std.json`), aggregates the counts, and — in `--json` mode — re-serializes each
object so it can enrich an errored file with the diagnostic it captured from the
worker's stdout/stderr (which the worker itself never sees, since that went to
the pipe the orchestrator owns). A worker that writes no result (a crash) is
reported as an errored file synthesised from the captured output.

## Verdicts, and what "errored" means

A **file-level error** (`"error": true`) is a failure of the *file*, as opposed
to a failure of a test. SRFI-64 catches ordinary test failures internally via
`guard`, so those never set it — they show up in the counts and `failures`.

Three inputs decide it (`resolveVerdict` in `src/test_runner.zig`): whether an
uncaught read/compile/runtime error was reported at top level, what the file's
suppressed `(exit)` asked for, and whether the SRFI-64 counters already show a
failure.

| The file… | `error` | Why |
|---|---|---|
| ran clean | `false` | — |
| hit an uncaught top-level error, never called `(exit)` | **`true`** | a plain run would exit 1 |
| hit an uncaught top-level error, then `(exit 0)` | `false` + a **note** | the file waived it; a plain run exits 0 |
| called `(exit N≠0)` with a failing count | `false` | redundant — the counts carry it, and `files_failed` already counts the file |
| called `(exit N≠0)` with nothing failing | **`true`** + a **note** | otherwise the file's own verdict is lost |

An `(exit 0)` waives only the file's *own* top-level error. It can never bury a
failing assertion: the counters stay authoritative, so a file that both errors
and fails is still reported as a failure.

**Why the exit status matters at all**, given the whole point of this runner is
to stop scraping: `tests/scheme/run-all.sh` runs the same file as a plain
`kaappi <file>` and reads exactly that status, and
`tests/scheme/errors/exit-code.sh` pins the rule it follows — *an explicit
`(exit N)` always wins over an already-reported top-level error*. A runner that
suppressed the call and then ignored what it asked for would reach a different
verdict than the legacy runner on the same file, which is what
[kaappi#1903](https://github.com/kaappi/kaappi/issues/1903) was: `srfi150.scm`
green under `run-all.sh` and `1 errored`, exit 1, under `kaappi test`.
`tests/scheme/test-runner/runner-agreement.sh` runs a fixture matrix through
*both* verdict rules and requires them to match.

A **note** is the channel for something a verdict deliberately tolerates. It
travels in `error_message` (with `"error": false`), prints under the file's
`PASS`/`FAIL` line in text mode along with whatever the worker wrote to
stdout/stderr, and is tallied as `noted` in the summary. So a waived top-level
error is visible without being fatal, rather than either failing the run or
disappearing from it.

## JSON schema

One object per line (JSON Lines). Prose fields (`error_message`, failure
`expected`/`actual`) are human-oriented and may be reworded; the structural
fields (counts, `kind`, `error`) are the stable contract.

Per-file object:

```json
{
  "type": "file",
  "file": "tests/scheme/smoke/numeric.scm",
  "suite": "numeric",
  "tests": 77,
  "pass": 77, "fail": 0, "xpass": 0, "xfail": 0, "skip": 0,
  "error": false,
  "error_message": null,
  "duration_ms": 203.4,
  "failures": [
    {
      "name": "wrong sum",
      "kind": "fail",
      "expected": "5",
      "actual": "4",
      "source_file": null,
      "source_line": null
    }
  ]
}
```

- `suite` — the outermost `test-begin` name, or `null`.
- `error_message` — the diagnostic for an errored file, **or** the note for a
  file whose verdict tolerated something (`"error": false` with a non-null
  message). Never assume `error_message != null` implies `error`.
- `tests` — `pass + fail + xpass + xfail + skip`.
- `kind` — `"fail"` (an expected pass that failed) or `"xpass"` (an
  expected-fail that unexpectedly passed). `xfail` (expected fail) and `skip`
  are counted but not listed as failures.
- `expected` — present for comparison forms (`test-equal`/`test-eqv`/`test-eq`);
  `null` for `test-assert`/`test-error`, which have no expected value. Rendered
  with `write`.
- `source_file`/`source_line` — populated when SRFI-64's result-alist carries
  them (a forward-compatible slot; Kaappi's SRFI-64 does not currently set
  them, so they are usually `null`).

Summary object (always last):

```json
{
  "type": "summary",
  "files": 108, "files_failed": 1, "errors": 0, "noted": 0,
  "tests": 1611, "pass": 1610, "fail": 1, "xpass": 0, "xfail": 0, "skip": 0,
  "seed": 543286,
  "duration_ms": 15825.0
}
```

- `noted` — files carrying a note (see [Verdicts](#verdicts-and-what-errored-means)).
  A note never fails the run, so `noted` is independent of `files_failed`.

## `--changed`: affected-test selection over the import graph

R7RS makes file-level dependency tracking unusually cheap: `define-library` and
`import` declare a file's dependencies explicitly, so a suite's dependency
closure is derivable by *reading library declarations* — no build-system
integration, no compiler instrumentation. `kaappi test` exploits this to run
only the suites a change actually touches (kaappi#1510).

```text
kaappi test --changed [--since <rev>]     # run only affected suites
kaappi test --list-affected [--since <rev>]  # print them, run nothing
```

- **`--changed`** runs only affected suites. An empty affected set is a clean
  exit (0) — "nothing changed" is success, not "no tests found".
- **`--list-affected`** prints the affected suites (one path per line to stdout)
  without running them, so the list pipes cleanly. With `--json` it prints one
  `{"type":"affected","since":…,"full_run":<bool>,"count":N,"files":[…]}` object.
- **`--since <rev>`** sets the git revision the change set is diffed against
  (default `HEAD`, i.e. working-tree changes since the last commit; use e.g.
  `--since main` for everything on the branch). Requires one of the two modes.

### How the closure is computed

The change set is `git diff --name-only <rev>` plus untracked files
(`git ls-files --others`), so a brand-new, uncommitted suite counts as changed.
For each discovered suite the runner computes the transitive closure of the
Scheme source it depends on and runs the suite iff its own file or anything in
that closure is in the change set:

- **imports** — each `(import <spec>…)` library name (unwrapping
  `only`/`except`/`prefix`/`rename`) is resolved to its `.sld` file with the
  same search path a real run uses (cwd, `lib/`, then each `--lib-path`), and
  followed recursively. A name with no `.sld` on disk is a built-in library
  (implemented in Zig) and contributes nothing to the *source* graph.
- **includes** — `include`, `include-ci`, and `include-library-declarations`
  files are resolved relative to the including file (exactly as the loader does)
  and followed.
- **containers** — `define-library`, `begin`, and `cond-expand` are walked for
  nested declarations; every `cond-expand` clause body is visited (running a
  suite a feature would have excluded is safe; skipping one is not).

Diamond dependencies (two libraries importing a common third) and cycles are
handled by a visited set, and each file is parsed once and memoised.

### What is and isn't tracked

The selection is **safe over precise**: a suite is skipped only when its whole
import closure is provably unchanged. Every "can't be sure" case runs *more*
tests, never fewer, and says why on stderr.

| Situation | Behaviour |
|-----------|-----------|
| A file in a suite's import closure changed | suite runs |
| The suite's own file changed / is untracked | suite runs |
| `(load <path>)` anywhere in the closure | that suite runs (the path may be computed — an **untrackable edge**), noted on stderr |
| A dependency can't be read or parsed | that suite runs (its worker surfaces the real error) |
| A native/FFI artifact changed (`csrc/…`, `*.dylib`/`*.so`/`*.dll`) | **all** suites run — `ffi-open` binds a shared library by name at runtime, invisible to the static import graph, so the package's tests are all treated as dirty |
| git is unavailable / not a repo / unknown `--since` revision | **all** suites run |
| Behaviour change in a built-in (Zig) library | **not tracked** — it lives in the binary, not a `.sld`; rebuild + full run |

The stderr note is always printed: either `N of M tests affected since <rev>`
(with the forced-because-incomplete suites listed), or the reason for a full-run
fallback. `--json` stdout stays pure — all of this goes to stderr.

## Relationship to `run-all.sh`

[`tests/scheme/run-all.sh`](../../tests/scheme/run-all.sh) is the **legacy**
runner and stays: it also drives the chibi-test R7RS suite and the shell-based
error/compile suites, which are outside `kaappi test`'s SRFI-64 scope, and it
runs `kaappi test`'s own acceptance shell tests
(`tests/scheme/test-runner/*.sh`). Over time SRFI-64 suites can delegate to
`kaappi test`; nothing forces the switch.

It runs its own `.scm` suites concurrently too, via `KAAPPI_TEST_JOBS`
(default: one per CPU, `KAAPPI_TEST_JOBS=1` to serialise), and its **shell**
suites at `KAAPPI_SHELL_TEST_JOBS` (default: the same). They get separate knobs
because a shell script can fork a whole compiler, so a box that wants the
`.scm` files N-wide does not necessarily want N concurrent `zig build`s.

Three things make that safe and worthwhile (kaappi#1926):

- **One archive, built once.** 18 scripts in `compile/` need
  `zig-out/lib/libkaappi_rt.a` and each ran `zig build lib` itself, racing
  over one install. `run-all.sh` now builds it up front and exports
  `KAAPPI_RT_LIB_READY`, which `ensure_runtime_lib` treats as "already
  fresh". The marker is advisory: a script run standalone — the Windows CI
  legs invoke each one directly — sees none and builds its own, as before.
- **A lock for the builds that remain.** `build_lock`/`build_unlock` in
  `shell-common.sh` serialise anything that installs into `zig-out/`, using a
  `mkdir` lock (atomic on POSIX and Git Bash alike; `flock` is Linux-only and
  macOS has none). A lock whose holder died — `run-all.sh` kills a script that
  overruns `SHELL_TIMEOUT` — is stolen by the next waiter via the recorded pid.
- **One interpreter rebuild, not two.** `zig build -Dbundle=…` recompiles the
  whole interpreter, because the embedded bytecode is part of the compiled
  module graph; at ~180s on a 4-core runner, the two scripts that needed one
  were 85% of the shell suites' entire wall time. They now share the fixture
  in `tests/scheme/compile/fixtures/bundle-replay/`, so the second build is a
  ~0.2s hit in Zig's own content-addressed cache. `bundle_fixture_binary`
  first builds the interpreter from current source into an isolated prefix
  and produces the `.sbc` with *that* binary, so the `.sbc` and the bundler
  always share one build id (kaappi#1930) — a `.sbc` made by whatever
  `zig-out/bin/kaappi` was lying around would go stale against the rebuilt
  bundler's build id and fail with `invalid embedded bytecode` whenever the
  tree moved (see [cache.md](cache.md)). Regenerating the `.sbc` on every
  call is what keeps it honest: identical sources give identical bytes and
  the hit, while an edit under `src/` changes them and forces exactly the
  rebuild it must.

Dispatch inside a suite is longest-first — scripts that shell out to a full
`zig build -D…` go first, found by grep rather than a hand-kept list of names.
Reporting still walks the glob-sorted order, so a transcript diff between two
runs stays meaningful at any job count.

## Tests

- `src/test_runner.zig` unit tests — JSON serialization round-trips, the
  SRFI-64 discovery gate, and the `suppress_exit` behaviour (the guard on the
  `exitFn` change in `src/primitives_r7rs.zig`).
- `src/test_selection.zig` unit tests — import-spec unwrapping, the
  native-artifact classifier, lexical path canonicalisation, and the closure
  BFS over synthetic graphs (diamond deps, incomplete edges, cycles).
- `tests/scheme/test-runner/json.sh` — the `--json` contract, validated with a
  real JSON parser (python3): per-file + summary objects, counts, failure
  detail, errored-file message, pure-JSON stdout, and exit status.
- `tests/scheme/test-runner/seed.sh` — `--seed` reproducibility (same seed →
  same draw, different seed → different draw, seed echoed on every run),
  observed through the JSON.
- `tests/scheme/test-runner/runner-agreement.sh` — the guarantee that this
  runner and `tests/scheme/run-all.sh` cannot reach different verdicts
  (kaappi#1903). Seven fixtures — top-level errors acknowledged and not,
  `(exit 0)` over a failing assertion, redundant and unexplained nonzero exits,
  a plain `test-expect-fail`, and a clean control — are each run through *both*
  verdict rules, which must agree *and* land on the expected verdict.

  It carries a **copy** of `run-all.sh`'s stdout net regex, which is how the two
  rules would drift while this script kept certifying agreement — so it also
  greps `run-all.sh` for that pattern verbatim and fails if it is not there.

  One deliberate asymmetry survives, and is not a fixture because no legitimate
  file can produce it: since kaappi#2116 the net also matches a bare `FAIL`
  token, so a file printing `FAIL` while exiting 0 with zero SRFI-64 failures
  is red under `run-all.sh` and green under `kaappi test`. That shape *is* the
  bug class #2116 exists to forbid, and every file in the corpus that can print
  `FAIL` also exits nonzero when it does — which is why all ten fixtures still
  agree. If `kaappi test` ever grows the same net, the asymmetry closes.
- `tests/scheme/test-runner/changed.sh` — `--changed`/`--list-affected` over a
  throwaway git repo with a known dependency shape: diamond import, `include`,
  a `(load …)` escape hatch, native-artifact and unknown-revision full-run
  fallbacks, untracked-suite detection, and the `--since` usage guard.

The shell tests generate their fixtures in a temp dir (a throwaway git repo for
`changed.sh`) so an intentionally failing suite never pollutes — and the git
fixture never touches — the kaappi repo's own state.
