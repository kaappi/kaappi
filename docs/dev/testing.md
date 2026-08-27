# Testing Guide

Kaappi has four layers of testing: Zig unit tests, Scheme integration tests,
shell-based regression suites, and post-release acceptance tests.

---

## Quick Start

```bash
zig build test                                    # All Zig unit tests
zig build run -- tests/scheme/compliance/vectors.scm  # One Scheme test
bash tests/scheme/run-all.sh                      # All Scheme test suites
```

All must pass before any change is considered complete.

---

## Zig Unit Tests

### Location

Unit tests live in `src/tests_*.zig`, organized by feature. There are ~50 of
them; the ones below are the entry points you are most likely to want:

| File | Coverage |
|------|----------|
| `tests_core_eval.zig` | Basic eval, arithmetic, lambda, closures |
| `tests_tail_calls.zig` | Tail call optimization |
| `tests_derived_forms.zig` | Derived forms (let, cond, do, case) |
| `tests_numeric.zig` | Numeric tower (flonum, complex, exactness) |
| `tests_macros.zig` | Macros (syntax-rules, hygiene) |
| `tests_libraries.zig` | Libraries (import, define-library) |
| `tests_exceptions.zig` | Exceptions (guard, raise, error) |
| `tests_records.zig` | Records (define-record-type) |
| `tests_io.zig` | Ports and I/O |
| `tests_continuations.zig` | Continuations (call/cc, dynamic-wind) |
| `tests_advanced.zig` | Advanced R7RS features |
| `tests_filesystem.zig` | SRFI-170 filesystem operations |
| `tests_ir.zig` | IR lowering, the analysis pass, optimization passes, behavioral correctness |
| `tests_robustness.zig` | Edge cases and stress tests |

### Helper: makeTestVM

The `src/testing_helpers.zig` file provides a `makeTestVM` helper that creates
a fully bootstrapped VM suitable for testing:

```zig
const std = @import("std");
const th = @import("testing_helpers.zig");
const memory = @import("memory.zig");
const types = @import("types.zig");

test "my feature" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}
```

`makeTestVM` returns a heap-allocated `*VM` — never a struct copy. The GC
root marker and the `vm_instance` threadlocal reach the VM by pointer, so
the VM must live at a stable address from before the first primitive is
registered; a by-value VM left those pointers dangling, which is invisible
under normal GC thresholds but fatal under `-Dgc-stress=true` (#1401).
`vm.deinit()` also frees the VM struct itself (`heap_owned`).

For one-liner assertions use the wrappers: `th.expectEval(src, fixnum)`,
`th.expectEvalTrue(src)`, `th.expectEvalBool(src, bool)`,
`th.expectEvalVoid(src)`, or `th.TestContext` for multi-step tests.

Use `std.testing.expectEqual` for value comparisons and `std.testing.expect`
for boolean checks.

### Running

```bash
zig build test                            # Run all tests
zig build test 2>&1 | head                # Quick check for failures
zig build test -Dtest-filter=tests_io     # Only tests whose names match
zig build test -Dtest-filter="eval quote" # Substring match on test names
zig build test -Dgc-stress=true           # Collection on every allocation
```

Individual test files cannot be run in isolation -- `zig build test` runs all
tests discovered through the import graph from `main.zig`. Use
`-Dtest-filter` (repeatable) to narrow a run; test names are prefixed with
their module (e.g. `tests_io.test.eval read-char`), so a file name is an
effective per-file filter.

A `-Dgc-stress=true` test run forces a collection at every allocation,
turning latent rooting bugs into immediate failures. Every test must stay
green under stress; loop-heavy tests that allocate per iteration should
scale their iteration count down via `@import("build_options").gc_stress`
(see `tests_records.zig` for the pattern) so the stress suite stays
tractable.

Stress builds also detect marking-time use-after-free deterministically
(#1687): freeing an object stamps its header's `owner` with the reserved
`memory.FREED_OWNER` sentinel, and the freed slot is quarantined (withheld
from the allocator, released only after a later collection's mark phase,
capped at `GC.quarantine_max_bytes`). Marking a dangling value therefore
panics with `GC: marking freed object (use-after-free)` on the first run —
it can no longer be silently absorbed by the foreign-owner skip or hidden
by the freed slot being recycled into a live same-size object, the two
modes that let #1682 pass twelve nightly stress runs. Plain Debug builds
stamp and check the sentinel too (best-effort, without the quarantine);
release builds compile both features out.

This covers *cross-heap* dangling values only because a joined SRFI-18
child hands its withheld slots to the parent GC (`quarantine_heir`) rather
than to the allocator. Until #2127 it did not, and a stress run over a
child-heap use-after-free was byte-identical to a release run — so treat
"the gc-stress suite is green" as evidence only for teardown paths that
name an heir (`docs/dev/gc-safety-and-error-handling.md`).

### Injecting an out-of-memory failure

`gc.oom_countdown` fails a chosen heap allocation: set it to `n` and the
next `n` allocations succeed while the one after returns `OutOfMemory`.
Sweeping `n` over a range therefore walks the failure across every
allocation a form performs, which is how `tests_gc_root_boundary.zig`
reaches error paths deep inside the expander and compiler (#1855):

```zig
var n: usize = 0;
while (n <= 200) : (n += 1) {
    ctx.gc.oom_countdown = n;
    _ = ctx.vm.eval(source) catch {};
    ctx.gc.oom_countdown = null;
    // ...assert whatever must hold after a failed allocation
}
```

Prefer it over the two alternatives for anything past the first few
allocations. `std.testing.FailingAllocator` has a documented deep-pipeline
limitation, and `gc.memory_limit` is an absolute watermark that only trips
once one form *retains* more than its headroom — in practice it fails within
the first handful of allocations and never reaches the expander at all.
`oom_countdown` is gated on `builtin.is_test`, so it compiles out of every
non-test build.

---

## Scheme Integration Tests

### Location

Scheme tests live in `tests/scheme/`, organized by purpose:

```text
tests/scheme/
  CLAUDE.md         Directory layout rules + the verdict-channel inventory
  r7rs/             R7RS test suite (1,395 tests via chibi test)
    r7rs-tests.scm  Canonical suite — imports (chibi test)

  # .scm suites (globbed by run-all.sh, one fresh interpreter per file)
  smoke/            Quick sanity checks (basic, tail-calls, derived, numeric,
                    macros, libraries) plus per-issue regressions
  compliance/       Targeted conformance tests by topic
                    (strings.scm, vectors.scm, chars.scm, unicode.scm, …)
  continuations/    Advanced call/cc and call/ec edge cases
  hygiene/          Macro hygiene edge cases
  srfi/             SRFI library tests, plus srfi231-official.scm — the
                    OFFICIAL SRFI 231 suite (generated; see its subsection
                    below) — and srfi231-official-fixtures/ holding its
                    pristine upstream source and girl.pgm fixture
  ffi/              C FFI tests (+ fixtures/ built on the fly by run-all.sh)
  audit/            Primitives correctness audits

  # shell suites (each directory's *.sh, run in parallel)
  errors/           Error format, diagnostics JSON, exit codes, crash handler
  compile/          Native tier — the only suite that runs `kaappi compile`
  test-runner/      `kaappi test`: discovery, --json, --seed, --jobs
  pipeline/         `kaappi ast` / `expand` / `ir` dumps
  doctor/ fmt/ cache/ timings/ completions/ lsp/ thottam/
                    One per CLI subcommand or tool surface
  differential/     Execution-tier differential (opt-off, warm cache, WASM)

  # not run by run-all.sh
  robustness/       Malformed and adversarial input handling (its own .sh)
  sandbox/          Sandbox escape prevention (its own .sh)
  bench/ coverage/  Deliberately skipped by run-all.sh

  run-all.sh        Run all suites with summary
  shell-common.sh   Shared helpers for the .sh suites
```

Two structural checks run before any suite. **Reachability** fails the run if a
file containing `test-begin` sits in a suite *subdirectory*, where the
non-recursive globs cannot see it — that is how `tests/scheme/srfi/slow/` hid
two full SRFI 257 suites for eleven days (kaappi#1900). **Verdict-channel**
fails it if a globbed file contains none of `test-begin`, `(exit`, `(error` or
`(assert`; see "Do not write a test that prints its answer" below.

### Running

```bash
# Run a specific test file
zig build run -- tests/scheme/compliance/strings.scm

# Run all test suites with summary. Build FIRST — run-all.sh refuses to build
# for you, because a bare `zig build` here would silently substitute a
# default-configured binary for the one you meant to measure (kaappi#2163).
# The run header names the binary's version, build id, target, build mode and
# gc_stress so the log says which configuration produced the counts.
zig build
bash tests/scheme/run-all.sh

# Run the full R7RS suite (1,395 tests). Use the wrapper, not a bare
# invocation: the (chibi test) shim has no exit-on-fail epilogue, so
# `kaappi tests/scheme/r7rs/r7rs-tests.scm; echo $?` prints 0 with failed
# assertions in the log (kaappi#2157). The wrapper parses the counts.
bash tools/run-r7rs-suite.sh zig-out/bin/kaappi
```

### An installed `~/.kaappi/lib` shadows the checkout's `lib/`

The library search order is (1) the script's own directory, (2)
`$KAAPPI_HOME/lib` (default `~/.kaappi/lib`), (3) the exe-relative
`<exe>/../lib` — which is `zig-out/lib`, populated from the checkout by
`zig build`. Step 2 is checked before step 3 on purpose, so a from-source
binary never shadows a real install (kaappi#1523).

The trap for library development (kaappi#2352) falls straight out of that
order: if you have ever installed Kaappi, `~/.kaappi/lib` holds the last
release's `.sld` files, and it wins over your working tree. So editing, say,
`lib/srfi/231/views.sld` and running

```bash
zig build && zig-out/bin/kaappi /tmp/t.scm
```

loads the **old** installed copy — the edit looks like a no-op, and neither
another rebuild nor `kaappi cache clear` helps, because it is the wrong source
file being read, not a stale cache of the right one. Run local `.sld` work with
an isolated home so the checkout's `lib/` (via `zig-out/lib`) wins:

```bash
KAAPPI_HOME=$(mktemp -d) zig-out/bin/kaappi /tmp/t.scm
```

`run-all.sh` already exports a fresh `mktemp` `KAAPPI_HOME` for the whole run,
so the suite always exercises the working tree — this only bites ad-hoc
`zig-out/bin/kaappi file.scm` invocations. CI never has a `~/.kaappi/lib`, which
is why the hazard is local-only and easy to miss.

### The official SRFI 231 conformance suite

`tests/scheme/srfi/srfi231-official.scm` is the SRFI's **official** test
suite (`test-arrays.scm`, by the SRFI's author — 744 test sites, ~8,800
evaluations with the random loops), adapted from its Gambit flavor to
portable R7RS. It is the broadest single conformance asset in the tree and
the one that found the #2362 family (124 official-suite failures invisible
to kaappi's own SRFI 231 tests).

It is **generated — never hand-edit it**. Regenerate with:

```bash
python3 tests/scheme/srfi/srfi231-official-transform.py
```

which reads the pristine upstream source vendored in
`srfi231-official-fixtures/` (commit recorded in the generated header) and
applies both the Gambit→R7RS adaptation and the kaappi vendoring postlude
(fixture path resolution, PGM output redirection to `TMPDIR`, and the
known-divergence verdict machinery). Commit the regenerated file together
with any change to the transformer or the vendored upstream source.

Conventions specific to this suite:

- **Known divergences are accounted, not failed.** A table of test ids in
  the generated file maps each documented kaappi-vs-reference divergence to
  its reason and issue reference (f16 deferral, the unsafe-view UB choice,
  the Gambit string-mutability expectation). The suite exits nonzero only
  on *unexpected* failures — or when a known divergence stops diverging,
  which means its entry is stale and hiding real coverage: prune it.
- **Error-expecting tests pass on any error** — only the Gambit message
  text differs from kaappi's (counted separately as "error-message-only").
- **It runs ~150 s** (the isolated `KAAPPI_HOME` compiles the SRFI's
  libraries fresh, and the PGM convolution timing blocks dominate), so
  `run-all.sh` gives it a per-file timeout override
  (`KAAPPI_SRFI231_OFFICIAL_TIMEOUT`, default 600 s) instead of the 60 s
  default.

### Writing a Scheme test

A Scheme test is a SRFI-64 suite that **exits nonzero when an assertion
fails**. Nothing reads the output; the exit status is the verdict.

Create a `.scm` file in the appropriate directory:

```scheme
;; tests/scheme/compliance/my-feature.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "my-feature")

;; Test basic functionality
(test-equal "my-proc on 42" 43 (my-proc 42))

;; Test edge cases
(test-equal "my-proc on 0" 1 (my-proc 0))

;; Test error handling
(test-assert "my-proc rejects a non-number"
  (guard (e (#t #t))
    (my-proc "not-a-number")
    #f))

(let ((runner (test-runner-current)))
  (test-end "my-feature")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
```

Grab the runner **before** `(test-end ...)` — the outermost `test-end` resets
the current runner, so `(test-runner-current)` afterwards no longer returns it.

Run it:

```bash
zig build run -- tests/scheme/compliance/my-feature.scm
echo $?     # 0 = pass; anything else = fail
```

#### Do not write a test that prints its answer

This section used to teach the opposite — "evaluate expressions and print
results, verify the output manually" — and 56 files were written that way.
None of them could fail. `(display (= x 43))` prints `#f` and exits 0; so does
`(display "FAIL: ...")`. Both runners reported every one of them as passing
whatever they computed, and `tests/scheme/smoke/thread-sleep-876.scm` was
demonstrably green under the very regression it was written to catch
(kaappi#2116). "Verify the output manually" happens once, at review; the test
then runs thousands of times with nobody looking.

`run-all.sh` now fails the run if a globbed suite file contains none of
`test-begin`, `(exit`, `(error` or `(assert`, so the count cannot grow back
silently. That check is a backstop, not the standard: use the SRFI-64 shape
above.

**Four** files in the corpus are exempt and say so in their own headers —
`smoke/large-index-bounds-1912.scm`, `smoke/deep-nesting-print.scm`,
`smoke/deep-nesting-print-tier-margin.scm` and
`continuations/coroutine-repl-echo.scm`. The first three are cross-tier probes
whose bare top-level forms are the measurement, so they stay import-free to run
identically on every tier rather than being wrapped in a SRFI-64 suite; the
fourth must leave its top-level forms bare because consuming their values is
what hid the bug it exists to catch. All four carry a hand-rolled `(exit 1)`
instead.

`tests/scheme/CLAUDE.md` holds the single inventory table (56 verdictless
files → 52 converted + 4 exempt, plus `fiber-error-handling.scm` = 53
conversions); keep any count here in step with it.

### Test conventions

- Each test file should be self-contained (include its own imports if needed).
- Name every assertion — an unnamed SRFI-64 failure prints a bare `#f`, which
  says nothing about which check broke.
- Test both normal cases and edge cases.
- Tests run in parallel and each file is a fresh interpreter, so a file must
  not depend on a fixed path, port, or scratch file another file also touches.

---

## Shell-Based Test Suites

Roughly sixty shell scripts test behaviors that are easier to verify from
outside the interpreter — exit codes, stderr text, subcommand output, native
compilation. Most live in a per-topic directory that `run-all.sh` picks up
wholesale via `run_shell_suite` (see the tree above); each sources
`tests/scheme/shell-common.sh` for the shared assertion helpers.

### Compile (`tests/scheme/compile/*.sh`)

The native tier's only test surface. A `.scm` regression test is
interpreter-only evidence: it never reaches `kaappi compile`, and three of them
passed for years while the native backend failed them. Any fix touching the
LLVM backend belongs here.

```bash
bash tests/scheme/compile/native-lexical-scope-fold-2117-2118.sh
```

### Robustness (`tests/scheme/robustness/robustness.sh`)

Not wired into `run-all.sh` — CI invokes it directly. Tests that malformed,
adversarial, or extreme inputs produce clean errors rather than panics or
crashes. Uses `assert_error` (must produce `error:`) and `assert_no_crash`
(must not exit by signal) helpers.

```bash
bash tests/scheme/robustness/robustness.sh
```

### Sandbox escape (`tests/scheme/sandbox/sandbox-escape.sh`)

Also invoked directly by CI rather than through `run-all.sh`. Verifies that
`--sandbox` mode blocks all restricted operations (FFI, file I/O, eval, load,
environment access) while allowing safe operations (arithmetic, string ports,
hash tables). Uses `assert_blocked` and `assert_works` helpers.

```bash
bash tests/scheme/sandbox/sandbox-escape.sh
```

### Error format (`tests/scheme/errors/error-format.sh`)

One of the `errors/` suite's scripts, so `run-all.sh` already covers it.
Checks that error messages include proper `file:line` location info for
reader, compile, and runtime errors.

```bash
bash tests/scheme/errors/error-format.sh
```

CI runs all of these on every push and pull request.

---

## Post-Release Acceptance Tests

After a release is published, a separate workflow downloads the actual
release artifacts and tests them as an end user would experience them.
This catches issues invisible to CI, such as code signing problems or
missing entitlements on macOS.

### Location

Tests live in `tests/acceptance/`:

| File | Purpose |
|------|---------|
| `acceptance.sh` | ~36 assertions: version, arithmetic, data structures, Unicode, library imports, file execution, tail calls, closures, continuations, error handling, sandbox, thottam |
| `test-wasm.sh` | ~13 WASM-specific assertions via wasmtime (no FFI) |
| `hello.scm` | Minimal test program for file execution |

### Running locally

```bash
KAAPPI=./zig-out/bin/kaappi THOTTAM=./zig-out/bin/thottam \
  bash tests/acceptance/acceptance.sh 0.6.3

KAAPPI_WASM=./zig-out/bin/kaappi.wasm \
  bash tests/acceptance/test-wasm.sh
```

### CI workflow

The `post-release.yml` workflow triggers automatically on `release: published`
events. It runs these jobs in parallel, then a `summary` job that fails the run
if any of them did:

| Job | What it tests |
|-----|--------------|
| `test-macos` | macOS ARM release binary |
| `test-linux-x86` | Linux x86_64 release binary |
| `test-linux-arm` | Linux ARM release binary |
| `test-windows-x64` | Windows x86_64 release binary |
| `test-wasm` | WASM binary via wasmtime |
| `test-checksums` | SHA256SUMS verification + GPG signature |
| `test-install-script` | The live install script from the docs repo, end to end |

To trigger manually against an existing release:

```bash
gh workflow run post-release.yml -f tag=v0.6.3
```

---

## Benchmarks

### Suite

Benchmarks live in `benchmarks/`. Each has a `.scm` file using the
`run-r7rs-benchmark` harness (from `common.scm`) and a `.input` file with
`count input expected` parameters.

| Benchmark | Subsystem | What it stresses |
|-----------|-----------|-----------------|
| `fib` | Fixnum arithmetic | Recursive Fibonacci, non-tail call overhead |
| `nqueens` | List allocation | N-Queens backtracking, pair allocation |
| `primes` | Iteration | Prime sieve, numeric predicates |
| `tak` | Deep recursion | Takeuchi function, stack frame management |
| `string` | String ops | String construction and manipulation |
| `list` | List ops | List construction and traversal |
| `vector` | Vector ops | Vector allocation and access |
| `hashtable` | Hash tables | SRFI-69 insert/lookup throughput |
| `continuations` | call/cc | Continuation capture/restore (5M iterations) |
| `tailcall` | TCO | Deep tail-recursive loop (10M iterations) |
| `closures` | Higher-order | Closure allocation via map (10K rounds × 1000 elements) |
| `bignum` | Bignum arith | factorial(5000), fixnum→bignum promotion |
| `gc-pressure` | GC | Rapid short-lived pair allocation (5M allocs) |

The harness runs each benchmark 5 times (after a warmup), reports median/min/max.

### Running locally

```bash
# Human-readable table (all benchmarks)
bash benchmarks/run-benchmarks.sh

# JSON output for tooling
bash benchmarks/run-benchmarks.sh --json

# Single benchmark
echo "1 35 9227465" | zig-out/bin/kaappi benchmarks/fib.scm

# call/cc vs call/ec micro-benchmark (Zig-level)
zig build bench

# Compare two JSON result files (flags >10% regressions)
bash benchmarks/compare-benchmarks.sh baseline.json current.json
THRESHOLD=20 bash benchmarks/compare-benchmarks.sh baseline.json current.json
```

### CI integration

**Push to main** (`ci.yml` → `benchmark` job): runs the full suite, uploads
results as a GitHub Actions artifact (30-day retention), and stores them on the
`gh-pages` branch via `github-action-benchmark`. This builds a historical
time series used for trend visualization and regression detection.

**Pull requests** (`benchmark-pr.yml`): triggered by path filter when `src/`,
`benchmarks/`, `lib/`, or build files change. Builds and benchmarks both the
PR branch and the base branch, then posts a comparison table as a PR comment
via `github-action-pull-request-benchmark`. Alert threshold: 120% (flags >20%
regression).

### Trend dashboard

After the benchmark job has run at least once on `main`, a trend chart is
published to GitHub Pages. Access it at:

```text
https://kaappi-lang.org/kaappi/dev/bench/
```

The chart shows per-benchmark time series with up to 100 data points. Each
point is keyed by commit SHA. When a benchmark regresses >30% vs. the previous
run, a commit comment is posted automatically.

### Reading benchmark results

**Table output** (local): the `Median` column is the primary metric. Compare
`Min`/`Max` to gauge noise — a wide spread means the result is unreliable.
`GC#` shows garbage collection count, useful for GC-sensitive benchmarks.

**PR comparison comment**: shows per-benchmark deltas (percentage change). A
positive delta means the PR is slower. Values within ±10% are typically noise
on shared CI runners.

**Trend chart**: look for step changes (sudden jumps) rather than gradual
drift. A sudden regression correlating with a specific commit is actionable;
slow drift over many commits is usually runner variance.

### Adding a new benchmark

1. Create `benchmarks/<name>.scm` using the harness:

   ```scheme
   (include "benchmarks/common.scm")

   (define (my-bench n) ...)

   (let* ((count (read))
          (input (read))
          (expected (read)))
     (run-r7rs-benchmark
      (string-append "<name>(" (number->string input) ")")
      count
      (lambda () (my-bench input))
      (lambda (result) (= result expected))))
   ```

2. Create `benchmarks/<name>.input` with `count input expected` (one per line).
   Calibrate so each iteration runs 0.5–3 seconds.
3. Add the entry to the `BENCHMARKS` array in `benchmarks/run-benchmarks.sh`.
4. Run `bash benchmarks/run-benchmarks.sh` to verify status is `ok`.

---

## Code Coverage

Code coverage is measured with [kcov](https://simonkagstrom.github.io/kcov/),
which uses DWARF debug info to track which Zig source lines execute. Install
with `brew install kcov`.

### Running

```bash
# Unit test coverage
zig build coverage

# Scheme file coverage (e.g. R7RS test suite)
zig build coverage-scheme -- tests/scheme/r7rs/r7rs-tests.scm

# View the HTML report
open coverage/index.html
```

Both steps always build in Debug mode (regardless of `-Doptimize`) since kcov
requires DWARF line info. Only files under `src/` are included — standard
library and vendored code are excluded.

### Merging results

Coverage accumulates across runs. The `coverage` step cleans previous unit test
data each time, but `coverage-scheme` accumulates so you can run multiple `.scm`
files against the same report:

```bash
zig build coverage                                          # unit tests
zig build coverage-scheme -- tests/scheme/r7rs/r7rs-tests.scm   # R7RS suite
zig build coverage-scheme -- tests/scheme/compliance/strings.scm # more tests
open coverage/index.html                                    # merged view
```

Delete `coverage/` to start fresh.

---

## CI

GitHub Actions runs on every push and pull request (`ci.yml`). The CI
matrix covers:

| Job | Platforms | What it runs |
|-----|-----------|-------------|
| `format` | Ubuntu | `zig fmt --check`, markdownlint, bare-`TypeError` ratchet (zero allowed) |
| `test` | Ubuntu (x86, ARM), macOS | Unit tests, `run-all.sh`, robustness, sandbox, thottam integration, SRFI final-status guard |
| `gc-stress` | Ubuntu | Unit suite under `-Dgc-stress=true` |
| `gc-stress-scheme` | Ubuntu | Scheme suites under `-Dgc-stress=true` |
| `riscv64-test` | Ubuntu (QEMU) | Cross-compiled unit tests + R7RS suite |
| `s390x-test` | Ubuntu (QEMU) | Big-endian leg — the byte-order canary (kaappi#1654) |
| `ppc64le-test` | Ubuntu (QEMU) | Cross-compiled unit tests + R7RS suite |
| `freebsd-test`, `openbsd-test`, `netbsd-test` | Ubuntu (VM action) | Per-BSD build + tests; see the matching `docs/dev/<os>.md` |
| `windows-cross` | Ubuntu | Cross-compile check for both Windows targets |
| `windows-arm-test` | Windows 11 ARM | Native build + tests |
| `windows-x64-test` | Windows x86_64 | Native build + tests |
| `wasm` | Ubuntu | WASM build + wasmtime smoke test |
| `coverage` | Ubuntu (push to main only) | kcov unit + Scheme coverage, Codecov upload |
| `benchmark` | Ubuntu (push to main only) | Performance benchmarks, trend data to `gh-pages` |
| `benchmark-pr` | Ubuntu (PRs, path-filtered) | PR vs base branch benchmark comparison (`benchmark-pr.yml`) |

`fuzz.yml` runs the fuzz targets on a schedule — see
[fuzzing.md](fuzzing.md).

Post-release: `post-release.yml` runs automatically after each release,
testing the actual published artifacts on all platforms.

A pull request will not be merged if CI fails.

---

## End-to-End Tests (LLVM Native Backend)

E2e tests verify that the LLVM native backend produces binaries with
identical output to the interpreter. They live in `tests/e2e/`:

```text
tests/e2e/
  run-e2e.sh              Shell runner (BDD specs + native parity tests)
  run-e2e.ps1             PowerShell equivalent for the Windows legs
  test-llvm-backend.scm   BDD specs using kaappi-bdd
  test-argv.scm           Command-line argument handling in a native binary
  programs/               ~37 Scheme programs compiled to native binaries,
                          covering the language surface the backend emits
                          directly (arithmetic, closures, captures, variadic
                          and mutual tail calls, cond/case/do, guard, call/cc)
                          plus the cache and fallback paths
```

Each program is run through the interpreter and through a compiled binary; any
output difference is a failure. Adding one is the cheapest way to pin a native
codegen fix — but note that a bug reproducible only through `kaappi compile`
with a *specific* flag or import belongs in `tests/scheme/compile/*.sh`
instead, where the invocation itself is part of the test.

### Running

```bash
bash tests/e2e/run-e2e.sh
```

The script:

1. Builds `kaappi` and `libkaappi_rt.a`
2. Runs BDD specs via the interpreter
3. For each program in `programs/`: runs via interpreter, compiles to
   native via `--emit-llvm` + `zig cc`, diffs output

Uses `KAAPPI_CC` env var for the C compiler (defaults to `zig cc`).
Runs in CI on Ubuntu ReleaseSafe builds.

---

## Testing Checklist

When making changes, verify:

1. `zig build` compiles without errors
2. `zig build test` passes all unit tests
3. Relevant Scheme tests pass (e.g., `tests/scheme/compliance/strings.scm`
   for string changes)
4. `bash tests/scheme/run-all.sh` passes all suites
5. New features have both Zig unit tests and Scheme integration tests
6. Bug fixes include a regression test that fails without the fix
7. Anything touching the native tier has a `tests/scheme/compile/*.sh` test —
   a `.scm` file never reaches `kaappi compile` and so proves nothing about it
8. No regressions in related areas
