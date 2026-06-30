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

Unit tests live in `src/tests_*.zig`, organized by feature:

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
| `tests_ir.zig` | IR lowering, analysis passes, optimization passes, bytecode parity |
| `tests_robustness.zig` | Edge cases and stress tests |

### Helper: makeTestVM

The `src/testing_helpers.zig` file provides a `makeTestVM` helper that creates
a fully initialized VM suitable for testing:

```zig
const helpers = @import("testing_helpers.zig");

test "my feature" {
    var ctx = try helpers.makeTestVM();
    defer ctx.deinit();

    const result = ctx.vm.eval("(+ 1 2)") catch unreachable;
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}
```

### Writing a unit test

```zig
test "string-length with Unicode" {
    var ctx = try helpers.makeTestVM();
    defer ctx.deinit();

    const result = ctx.vm.eval("(string-length \"hello\")") catch unreachable;
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(result));
}
```

Use `std.testing.expectEqual` for value comparisons and `std.testing.expect`
for boolean checks.

### Running

```bash
zig build test              # Run all tests
zig build test 2>&1 | head  # Quick check for failures
```

Individual test files cannot be run in isolation -- `zig build test` runs all
tests discovered through the import graph from `main.zig`.

---

## Scheme Integration Tests

### Location

Scheme tests live in `tests/scheme/`, organized by purpose:

```
tests/scheme/
  r7rs/             R7RS test suite (1,391 tests via chibi test)
    r7rs-tests.scm  Canonical suite — imports (chibi test)
  smoke/            Quick sanity checks
    basic.scm       Arithmetic, if, define, lambda, pairs
    tail-calls.scm  Proper tail recursion
    derived.scm     and/or/when/unless/cond/do/case/let*
    numeric.scm     Flonums, inf/nan, mixed arithmetic
    macros.scm      syntax-rules, ellipsis, hygiene
    libraries.scm   import/only/rename/prefix
  compliance/       Targeted conformance tests by topic
    strings.scm, vectors.scm, chars.scm, unicode.scm, etc.
  continuations/    Advanced call/cc and call/ec edge cases
  hygiene/          Macro hygiene edge cases
  srfi/             SRFI library tests
  ffi/              C FFI tests
  audit/            Primitives correctness audits
  errors/           Error message format regression tests
  robustness/       Malformed and adversarial input handling
  sandbox/          Sandbox escape prevention tests
  run-all.sh        Run all suites with summary
```

### Running

```bash
# Run the full R7RS suite (1,391 tests)
zig build run -- tests/scheme/r7rs/r7rs-tests.scm

# Run a specific test file
zig build run -- tests/scheme/compliance/strings.scm

# Run all test suites with summary
bash tests/scheme/run-all.sh
```

### Writing a Scheme test

Scheme tests are simple: they evaluate expressions and print results. If the
output matches expectations, the test passes.

Create a `.scm` file in the appropriate directory:

```scheme
;; tests/scheme/compliance/my-feature.scm

;; Test basic functionality
(display (my-proc 42))
(newline)
;; Expected output: 43

;; Test edge cases
(display (my-proc 0))
(newline)
;; Expected output: 1

;; Test error handling
(guard (e (#t (display "caught")))
  (my-proc "not-a-number"))
(newline)
;; Expected output: caught
```

Run it and verify the output manually:

```bash
zig build run -- tests/scheme/compliance/my-feature.scm
```

### Test conventions

- Each test file should be self-contained (include its own imports if needed).
- Use `display` and `newline` for output.
- Test both normal cases and edge cases.
- Include comments showing expected output.

---

## Shell-Based Test Suites

Three shell scripts test behaviors that are easier to verify from outside
the interpreter:

### Robustness (`tests/scheme/robustness/robustness.sh`)

Tests that malformed, adversarial, or extreme inputs produce clean errors
rather than panics or crashes. Uses `assert_error` (must produce `error:`)
and `assert_no_crash` (must not exit by signal) helpers.

```bash
bash tests/scheme/robustness/robustness.sh
```

### Sandbox escape (`tests/scheme/sandbox/sandbox-escape.sh`)

Verifies that `--sandbox` mode blocks all restricted operations (FFI,
file I/O, eval, load, environment access) while allowing safe operations
(arithmetic, string ports, hash tables). Uses `assert_blocked` and
`assert_works` helpers.

```bash
bash tests/scheme/sandbox/sandbox-escape.sh
```

### Error format (`tests/scheme/errors/error-format.sh`)

Checks that error messages include proper `file:line` location info for
reader, compile, and runtime errors.

```bash
bash tests/scheme/errors/error-format.sh
```

All three are run by CI on every push and pull request.

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
| `acceptance.sh` | 34 tests: version, arithmetic, data structures, Unicode, library imports, file execution, tail calls, closures, continuations, error handling, sandbox, thottam |
| `test-wasm.sh` | 14 WASM-specific tests via wasmtime (no FFI) |
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
events. It runs 6 jobs in parallel:

| Job | What it tests |
|-----|--------------|
| `test-macos` | macOS ARM release binary |
| `test-linux-x86` | Linux x86_64 release binary |
| `test-linux-arm` | Linux ARM release binary |
| `test-wasm` | WASM binary via wasmtime |
| `test-checksums` | SHA256SUMS verification + GPG signature |
| `test-install-script` | Full install script end-to-end |

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

```
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
| `format` | Ubuntu | `zig fmt --check`, TypeError regression baseline |
| `test` | Ubuntu (x86, ARM), macOS | Unit tests, all Scheme suites, robustness, sandbox, error format, thottam integration |
| `riscv64-test` | Ubuntu (QEMU) | Cross-compiled unit tests + R7RS suite |
| `wasm` | Ubuntu | WASM build + wasmtime smoke test |
| `coverage` | Ubuntu (push to main only) | kcov unit + Scheme coverage, Codecov upload |
| `benchmark` | Ubuntu (push to main only) | Performance benchmarks, trend data to `gh-pages` |
| `benchmark-pr` | Ubuntu (PRs, path-filtered) | PR vs base branch benchmark comparison |

Post-release: `post-release.yml` runs automatically after each release,
testing the actual published artifacts on all platforms.

A pull request will not be merged if CI fails.

---

## End-to-End Tests (LLVM Native Backend)

E2e tests verify that the LLVM native backend produces binaries with
identical output to the interpreter. They live in `tests/e2e/`:

```
tests/e2e/
  run-e2e.sh              Shell runner (BDD specs + native parity tests)
  test-llvm-backend.scm   BDD specs using kaappi-bdd
  programs/               Scheme programs compiled to native binaries
    arithmetic.scm         Constant-folded addition
    string.scm             String display
    define.scm             Global variable binding
    if-expr.scm            Conditional branching
    lambda-basic.scm       Lambda and application
    lambda-closure.scm     Closures with upvalues
    nested-calls.scm       Non-foldable nested calls
    and-or.scm             Short-circuit boolean logic
    when-unless.scm        Conditional body execution
    set-bang.scm           Variable mutation
    let-binding.scm        Local bindings via kaappi_eval
    import.scm             Library imports
    symbol-eq.scm          Symbol identity in closures
    quoted-list.scm        Quoted list constants
    macro.scm              User-defined macros
```

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
7. No regressions in related areas
