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
| `r7rs/` | Full R7RS suite (1,395 tests, `chibi test`) | yes (special) |
| `errors/` | Error message format, exit code, and reader error regression tests | yes |
| `bench/` | Micro-benchmarks (no assertions, timing only) | no |
| `compile/` | Native compiler regression tests | yes |
| `test-runner/` | `kaappi test` runner (`--json`, `--seed`, `--changed`, `--lib-path`) | yes |
| `pipeline/` | `kaappi ast`/`expand`/`ir` stage dumps | yes |
| `doctor/` | `kaappi doctor` self-check | yes |
| `fmt/` | `kaappi fmt` formatter | yes |
| `cache/` | `.sbc` bytecode cache transparency | yes |
| `timings/` | `--timings` stage reporting | yes |
| `coverage/` | Coverage gap-fillers (`zig build coverage-scheme`) | no |
| `robustness/` | Stress tests | no (CI runs it separately) |
| `sandbox/` | Sandbox isolation tests | no (CI runs it separately) |

**The globs in `run-all.sh` are non-recursive** (`tests/scheme/srfi/*.scm`,
not `**`). A test placed in a subdirectory of a suite is silently never run —
`tests/scheme/srfi/slow/` is exactly that today (kaappi#1900). Put new files
directly in a suite directory, or wire the subdirectory up explicitly.

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

# Run .scm files N at a time (default: one per CPU; 1 = strictly sequential)
KAAPPI_TEST_JOBS=1 bash tests/scheme/run-all.sh
```

The `.scm` suites run concurrently because each file is a fresh interpreter with
no shared state (see Quirks below). Shell suites (`*.sh`) always run one at a
time: several call `ensure_runtime_lib`, which builds into the shared
`zig-out/lib`.

Results are reported in sorted file order regardless of the job count, so a
transcript diff between two runs stays meaningful.

## Shell test scripts (`*.sh`)

Suite directories may also hold bash drivers; `run-all.sh` runs them via
`run_shell_suite` (and the `windows-arm-test`/`windows-x64-test` CI jobs
run them under Git Bash on Windows — see `docs/dev/windows.md`).
Conventions:

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
  assertions), `rt_lib_name` (`libkaappi_rt.a` / `kaappi_rt.lib`),
  `skip_without_zig` (skip when the script itself must rebuild with a
  Zig toolchain — boxes running cross-compiled binaries have none, see
  `docs/dev/freebsd.md`), and `ensure_runtime_lib` (freshen
  `libkaappi_rt.a` with zig when present, else accept a prebuilt
  archive so `kaappi compile` tests still run).
- Don't bake POSIX-only spellings into assertions: kaappi prints native
  paths, the runtime archive name is per-platform, and a Windows abort
  exits 3 rather than dying by signal (see `errors/crash-handler.sh`).
- **No GNU regex extensions in `grep`/`sed` patterns.** `\?`, `\|` and `\+`
  are GNU additions to POSIX BRE. macOS, GNU, FreeBSD and NetBSD all accept
  them, so a pattern using one passes locally and on 16 of 17 CI checks —
  and then matches *nothing* on `openbsd-test`, the only leg whose grep is
  strict (kaappi#1862). Use `grep -E` and write them as plain ERE `?`, `|`,
  `+`, remembering that ERE makes `(`, `)`, `[` and `{` metacharacters that
  a literal match has to escape. A suite whose *assertions* all fail
  uniformly while its output comparisons stay clean is the signature of
  this, not of a real regression.

## Quirks

- `run-all.sh` parses R7RS suite output with awk — don't change its output format.
- Some older tests use manual pass/fail counters instead of SRFI-64. Prefer
  SRFI-64 for new tests.
- Tests run independently with no shared state. Each file is a fresh interpreter.
  `run-all.sh` relies on this to run them in parallel, so it is now a
  correctness requirement, not just a description: a new test must not depend on
  a fixed path, port, or file that another test also touches. Give temporary
  files a name unique to the test (or `mktemp` them) — a fixed `/tmp` path used
  by two files will flake under concurrency and pass when run alone.
