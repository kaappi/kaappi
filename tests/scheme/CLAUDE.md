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
| `errors/` | Error message format, exit code, and reader error regression tests | yes |
| `bench/` | Micro-benchmarks (no assertions, timing only) | no |
| `compile/` | Native compiler regression tests | no |
| `coverage/` | Coverage gap-fillers (`zig build coverage-scheme`) | no |
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

   (let ((runner (test-runner-current)))
     (test-end "descriptive-name")
     (when (> (test-runner-fail-count runner) 0) (exit 1)))
   ```
3. The `(exit 1)` on failure is required — `run-all.sh` uses exit codes.
   Grab the runner **before** `(test-end ...)`: the outermost `test-end`
   resets the current runner, so `(test-runner-current)` afterwards no
   longer returns the runner and `test-runner-fail-count` raises a type
   error.
4. No registration needed — `run-all.sh` picks up `*.scm` files automatically.
5. For bug regressions, name the file after the bug and add a comment:
   ```scheme
   ;; Regression test for #123: describe the bug
   ```
6. Fixture files (`.sld` libraries, included sources, data) must go in a
   subdirectory (e.g. `fixtures/`, `lib868/`), never as loose `.scm` files
   next to the tests — `run-all.sh` executes every top-level `.scm` file
   standalone. Libraries next to a test script are importable because the
   script's directory is on the library search path.

## Running

```bash
bash tests/scheme/run-all.sh              # all suites (60s timeout per file)
zig build run -- tests/scheme/smoke/foo.scm  # single file
zig build run -- tests/scheme/r7rs/r7rs-tests.scm  # full R7RS suite

# Override per-file timeout (default 60s)
KAAPPI_TEST_TIMEOUT=120 bash tests/scheme/run-all.sh

# Skip specific files (space-separated basenames)
KAAPPI_TEST_SKIP="callcc-bench.scm" bash tests/scheme/run-all.sh
```

## Shell test scripts (`*.sh`)

Suite directories may also hold bash drivers; `run-all.sh` runs them via
`run_shell_suite` (and the `windows-arm-test` CI job runs them under Git
Bash on Windows — see `docs/dev/windows.md`). Conventions:

- Accept the binary as `${KAAPPI:-zig-out/bin/kaappi}` or `${1:-...}` —
  runners pass both.
- Exit 0 = pass, anything else = fail, **exit 77 = skip** (the automake
  convention). To skip on Windows, source the shared helper and gate:

  ```bash
  . "$(dirname "$0")/../shell-common.sh"
  skip_on_windows "why the premise cannot hold on Windows"
  ```

  This is the shell analogue of the `cond-expand (windows ...)` gate
  above. `shell-common.sh` also provides `is_windows`, `native_path`
  (the C:/-style path spelling kaappi itself prints, for output
  assertions), and `rt_lib_name` (`libkaappi_rt.a` / `kaappi_rt.lib`).
- Don't bake POSIX-only spellings into assertions: kaappi prints native
  paths, the runtime archive name is per-platform, and a Windows abort
  exits 3 rather than dying by signal (see `errors/crash-handler.sh`).

## Quirks

- `run-all.sh` parses R7RS suite output with awk — don't change its output format.
- Some older tests use manual pass/fail counters instead of SRFI-64. Prefer
  SRFI-64 for new tests.
- Tests run independently with no shared state. Each file is a fresh interpreter.
