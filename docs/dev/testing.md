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

Unit tests live in `src/tests_phase1.zig` through `src/tests_phase11.zig`,
split by implementation phase:

| File | Coverage |
|------|----------|
| `tests_phase1.zig` | Basic eval, arithmetic, lambda, closures |
| `tests_phase2.zig` | Tail call optimization |
| `tests_phase3.zig` | Derived forms (let, cond, do, case) |
| `tests_phase4.zig` | Numeric tower (flonum, complex, exactness) |
| `tests_phase5.zig` | Macros (syntax-rules, hygiene) |
| `tests_phase6.zig` | Libraries (import, define-library) |
| `tests_phase7.zig` | Exceptions (guard, raise, error) |
| `tests_phase8.zig` | Records (define-record-type) |
| `tests_phase9.zig` | Ports and I/O |
| `tests_phase10.zig` | Continuations (call/cc, dynamic-wind) |
| `tests_phase11.zig` | Remaining R7RS coverage |

Additional test files:
- `vm_tests.zig` -- VM-specific tests
- Individual modules also contain inline tests (e.g., `library.zig`, `types.zig`)

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

Scheme tests live in `tests/scheme/`, organized by category:

```
tests/scheme/
  phase1/         Basic eval, arithmetic, lambda
  phase2/         Tail calls
  phase3/         Derived forms
  phase4/         Numeric tower
  phase5/         Macros
  phase6/         Libraries
  deferred/       apply, case, case-lambda, complex, etc.
  compliance/     R7RS conformance tests by topic
    bytevectors.scm
    chars.scm
    eval.scm
    hygiene.scm
    lazy.scm
    lists.scm
    strings.scm
    unicode.scm
    vectors.scm
    ...
  r7rs/           R7RS-specific tests
  srfi/           SRFI library tests
    srfi1.scm
    srfi69.scm
  ffi/            FFI tests
    basic.scm
```

### Running

```bash
# Run a specific test file
zig build run -- tests/scheme/compliance/strings.scm

# Run SRFI tests
zig build run -- tests/scheme/srfi/srfi1.scm
zig build run -- tests/scheme/srfi/srfi69.scm
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
