# `kaappi test` — first-class SRFI-64 runner

The suite standardises on [SRFI-64](https://srfi.schemers.org/srfi-64/) as its
test harness. `kaappi test` is the runner an agent or CI drives on top of it: it
discovers SRFI-64 suites, runs each one, and aggregates pass/fail/skip counts
**from the SRFI-64 runner's own counters** — never by scraping the
`# of expected passes` lines. It is part of the machine-legibility epic
(kaappi#1503, kaappi#1509); the guiding rule is that a caller can go from a
failing suite to a fix using documented, structured output alone.

```
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
results instead of scraped text. It also mirrors the future parallel-execution
story (kaappi#1509 stretch): files are already independent units.

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
   `(exit 1)` failure epilogue becomes a *recorded* no-op (`vm.exit_requested`)
   instead of terminating the worker before it can emit its result. A test
   file's `(exit 1)` is redundant with the fail counts we already collected, so
   it is **not** treated as a file error.
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

A **file-level error** (`"error": true`) means an *uncaught* read/compile/runtime
error at top level. SRFI-64 catches ordinary test failures internally via
`guard`, so those never set it — they show up in the counts and `failures`.

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
  "files": 108, "files_failed": 1, "errors": 0,
  "tests": 1611, "pass": 1610, "fail": 1, "xpass": 0, "xfail": 0, "skip": 0,
  "seed": 543286,
  "duration_ms": 15825.0
}
```

## Relationship to `run-all.sh`

[`tests/scheme/run-all.sh`](../../tests/scheme/run-all.sh) is the **legacy**
runner and stays: it also drives the chibi-test R7RS suite and the shell-based
error/compile suites, which are outside `kaappi test`'s SRFI-64 scope, and it
runs `kaappi test`'s own acceptance shell tests
(`tests/scheme/test-runner/*.sh`). Over time SRFI-64 suites can delegate to
`kaappi test`; nothing forces the switch.

`--changed` (affected-test selection over the import graph) is tracked
separately in kaappi#1510 and is intentionally not part of this runner.

## Tests

- `src/test_runner.zig` unit tests — JSON serialization round-trips, the
  SRFI-64 discovery gate, and the `suppress_exit` behaviour (the guard on the
  `exitFn` change in `src/primitives_r7rs.zig`).
- `tests/scheme/test-runner/json.sh` — the `--json` contract, validated with a
  real JSON parser (python3): per-file + summary objects, counts, failure
  detail, errored-file message, pure-JSON stdout, and exit status.
- `tests/scheme/test-runner/seed.sh` — `--seed` reproducibility (same seed →
  same draw, different seed → different draw, seed echoed on every run),
  observed through the JSON.

Both shell tests generate their fixtures in a temp dir so an intentionally
failing suite never pollutes a plain `kaappi test ./tests` run of the repo.
