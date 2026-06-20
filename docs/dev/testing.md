# Testing Guide

Kaappi uses two layers of testing: Zig unit tests for internal correctness
and Scheme integration tests for end-to-end behavior.

---

## Quick Start

```bash
zig build test                                    # All Zig unit tests
zig build run -- tests/scheme/compliance/vectors.scm  # One Scheme test
```

Both must pass before any change is considered complete.

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
  r7rs/             R7RS test suite (1,380 tests via chibi test)
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
  run-all.sh        Run all suites with summary
```

### Running

```bash
# Run the full R7RS suite (1,380 tests)
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

## Benchmark Tests

Benchmarks live in the `benchmarks/` directory:

| File | Measures |
|------|----------|
| `fib.scm` | Recursive Fibonacci (CPU-bound) |
| `nqueens.scm` | N-queens puzzle (allocation + recursion) |
| `primes.scm` | Prime sieve (list operations) |
| `tak.scm` | Takeuchi function (deeply recursive) |

Each benchmark has a corresponding `.input` file with expected output and a
pre-compiled `.sbc` cache.

Run a benchmark:

```bash
time zig build run -- benchmarks/fib.scm < benchmarks/fib.input
```

There is also a Zig-level benchmark for continuations:

```bash
zig build bench
```

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

GitHub Actions runs on every push and pull request. The CI matrix covers:

- **Ubuntu** and **macOS**
- `zig build test` (all unit tests)
- Scheme test suite execution

A pull request will not be merged if CI fails.

---

## Testing Checklist

When making changes, verify:

1. `zig build` compiles without errors
2. `zig build test` passes all unit tests
3. Relevant Scheme tests pass (e.g., `tests/scheme/compliance/strings.scm`
   for string changes)
4. New features have both Zig unit tests and Scheme integration tests
5. No regressions in related areas
