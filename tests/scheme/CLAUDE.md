# Scheme Test Suite

## Directory layout

| Directory | Purpose | In `run-all.sh`? |
|-----------|---------|:----------------:|
| `smoke/` | Regression tests for specific bugs and edge cases | yes |
| `compliance/` | R7RS conformance tests by topic | yes |
| `continuations/` | call/cc and call/ec edge cases | yes |
| `hygiene/` | Macro hygiene edge cases | yes |
| `srfi/` | SRFI library conformance | yes |
| `ffi/` | C FFI integration | yes |
| `audit/` | Auto-generated primitives audit tests | yes |
| `r7rs/` | Full R7RS suite (1,391 tests, `chibi test`) | yes (special) |
| `errors/` | Error message format regression (`error-format.sh`) | no |
| `bench/` | Micro-benchmarks (no assertions, timing only) | no |
| `coverage/` | Coverage gap-fillers (`zig build coverage-scheme`) | no |
| `deferred/` | Pre-compiled `.sbc` bytecode tests | no |
| `robustness/` | Stress tests | no |
| `sandbox/` | Sandbox isolation tests | no |

## Adding a test

1. Pick the right directory (smoke/ for bug regressions, compliance/ for spec conformance).
2. Use SRFI-64 for assertions:
   ```scheme
   (import (scheme base) (scheme write) (scheme process-context) (srfi 64))

   (test-begin "descriptive-name")

   (test-equal "what it tests" expected-value actual-expr)
   (test-assert "condition holds" bool-expr)

   (test-end "descriptive-name")
   (when (> (test-runner-fail-count (test-runner-current)) 0) (exit 1))
   ```
3. The `(exit 1)` on failure is required — `run-all.sh` uses exit codes.
4. No registration needed — `run-all.sh` picks up `*.scm` files automatically.
5. For bug regressions, name the file after the bug and add a comment:
   ```scheme
   ;; Regression test for #123: describe the bug
   ```

## Running

```bash
bash tests/scheme/run-all.sh              # all suites (60s timeout per file)
zig build run -- tests/scheme/smoke/foo.scm  # single file
zig build run -- tests/scheme/r7rs/r7rs-tests.scm  # full R7RS suite
```

## Quirks

- `run-all.sh` parses R7RS suite output with awk — don't change its output format.
- Some older tests use manual pass/fail counters instead of SRFI-64. Prefer
  SRFI-64 for new tests.
- Tests run independently with no shared state. Each file is a fresh interpreter.
