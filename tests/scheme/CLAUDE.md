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
| `completions/` | `--completions` scripts vs. the flag table (`docs/dev/cli-surface.md`) | yes |
| `lsp/` | `kaappi-lsp` end-to-end JSON-RPC session over stdio | yes |
| `differential/` | Execution-tier differential harnesses (`--no-ir-opt`, cold-vs-warm cache; WASM-vs-interpreter) + its `probes/` | yes |
| `coverage/` | Coverage gap-fillers (`zig build coverage-scheme`) | no |
| `robustness/` | Stress tests | no (CI runs it separately) |
| `sandbox/` | Sandbox isolation tests | no (CI runs it separately) |

**The globs in `run-all.sh` are non-recursive** (`tests/scheme/srfi/*.scm`,
not `**`). A test placed in a subdirectory of a suite would be silently never
run — `tests/scheme/srfi/slow/` was exactly that for eleven days, holding the
two full SRFI 257 reference suites (kaappi#1900). Put new files directly in a
suite directory, or wire the subdirectory up explicitly.

This is no longer silent: `run-all.sh` opens with a **reachability check** that
fails the run if any `.scm` file under a suite subdirectory contains
`test-begin`. Fixtures are exempt by construction — a fixture is a library or
an included fragment and never opens a SRFI-64 suite — so the check needs no
allowlist to maintain. If you add a genuine fixture that must call
`test-begin`, wire its directory into a glob rather than weakening the check.

## Every test file must be able to fail

A **verdict-channel check** runs right after the reachability check and fails
the run if a globbed suite file contains none of `test-begin`, `(exit`,
`(error` or `(assert` — i.e. has no way to turn a wrong answer into a nonzero
exit.

It exists because **56 files** had exactly that shape (kaappi#2116). They
computed the right thing and then discarded the verdict: `(display (= x 43))`
prints `#f` and exits 0, and `(display "FAIL: ...")` exits 0 too. `run-all.sh`'s
stdout net could not help — it matched a failure *count*, which neither shape
has. `smoke/thread-sleep-876.scm` was demonstrably green under the very
regression it was written to catch.

**The one inventory** — every other count in the tree should agree with this:

| | files |
|---|--:|
| had no verdict channel | **56** |
| ↳ converted to the SRFI-64 shape below | 52 |
| ↳ kept a hand-rolled `(exit 1)` (table below) | 4 |
| additionally converted: `smoke/fiber-error-handling.scm` | 1 |
| **SRFI-64 conversions in total** | **53** |

55 of the 56 came from #2116's own enumeration; the 56th,
`smoke/deep-nesting-print-tier-margin.scm`, was missed by that enumeration's
predicate because the word "assert" appears in one of its comments.
`fiber-error-handling.scm` was never verdictless by the gate's predicate — the
widened stdout net exposed it, still asserting the #551 behaviour that
kaappi#1155 deliberately reversed, printing `FAIL - should have raised` and
exiting 0 ever since.

The check is a heuristic and knows it — an `(error` inside a `guard` being
*tested* is not a verdict channel — so it is a backstop against the count
growing back from zero, not a substitute for writing the epilogue.

**The four exempt files**, each explaining why in its own header. The first
three are the WASM-tier group `run-all.sh` and `run-wasm-differential.sh` refer
to; the fourth is exempt for an unrelated reason:

| File | Why it cannot use `(srfi 64)` |
|------|-------------------------------|
| `smoke/large-index-bounds-1912.scm` | Must stay import-free: `(import (srfi 64))` fails at library load on WASM (kaappi#2108), which `run-wasm-differential.sh` classifies as LIBDIFF — silently retiring its `KNOWN_DIFFS` entry for #1912 |
| `smoke/deep-nesting-print.scm` | Same, for its own `KNOWN_DIFFS` entry against #2107 |
| `smoke/deep-nesting-print-tier-margin.scm` | Same, and it is the cross-tier positive control for #2107 |
| `continuations/coroutine-repl-echo.scm` | Its top-level forms must stay **bare** so the value-echo path runs; consuming them in `test-equal` is what hid the original bug |

Two of the four (`deep-nesting-print-tier-margin.scm`,
`coroutine-repl-echo.scm`) import `(scheme process-context)` for `exit` and
nothing else, so their verdict does not depend on Kaappi's ambient script-mode
globals. That is safe because `(scheme process-context)` is a **built-in**
library rather than a file-backed `.sld`, verified under wasmtime. The other
two are `KNOWN_DIFFS` probes whose divergence is the measurement, so they are
left exactly as they are.

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

   A file that deliberately provokes an **uncaught top-level error** — one
   no `guard` can reach, e.g. a known engine limitation at a macro-definition
   site — must also `(exit 0)` on the clean path, or the process's own exit
   status makes the suite look failed. Both runners honour that waiver and
   `kaappi test` prints it as a `note` rather than swallowing it, so the
   error stays on the transcript (kaappi#1903,
   `tests/scheme/test-runner/runner-agreement.sh`). The waiver covers only
   the file's own top-level error: a failing assertion still fails the file.
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
zig build                                 # REQUIRED first: run-all.sh will not
                                          # build for you (kaappi#2163)
bash tests/scheme/run-all.sh              # all suites (60s timeout per file)
zig build run -- tests/scheme/smoke/foo.scm  # single file
bash tools/run-r7rs-suite.sh zig-out/bin/kaappi  # full R7RS suite, count-gated

# Override per-file timeout (default 60s)
KAAPPI_TEST_TIMEOUT=120 bash tests/scheme/run-all.sh

# Skip specific files (space-separated basenames)
KAAPPI_TEST_SKIP="callcc-bench.scm" bash tests/scheme/run-all.sh

# Run .scm files N at a time (default: one per CPU; 1 = strictly sequential)
KAAPPI_TEST_JOBS=1 bash tests/scheme/run-all.sh

# Same for the *.sh suites (default: whatever KAAPPI_TEST_JOBS resolved to)
KAAPPI_SHELL_TEST_JOBS=2 bash tests/scheme/run-all.sh
```

The `.scm` suites run concurrently because each file is a fresh interpreter with
no shared state (see Quirks below). Shell suites (`*.sh`) run concurrently too
(kaappi#1926), with their own job count: a shell script can fork a whole
compiler, so a box that wants the `.scm` files N-wide does not necessarily want
N concurrent `zig build`s. Their shared state is `zig-out/`, which
`shell-common.sh` serialises with `build_lock` — a new script that installs
anything there must take that lock too. See `docs/dev/test-runner.md`.

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
  `docs/dev/freebsd.md`), `ensure_runtime_lib` (freshen
  `libkaappi_rt.a` with zig when present, else accept a prebuilt
  archive so `kaappi compile` tests still run), `build_lock`/`build_unlock`
  (serialise anything that installs into `zig-out/`), and
  `bundle_fixture_binary` (the standalone binary embedding
  `compile/fixtures/bundle-replay/`, shared so one `zig build -Dbundle`
  serves every test that needs one).
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
- **Never pipe into `grep -q` under `set -o pipefail`.** Write
  `grep -q PATTERN <<< "$output"`, not `echo "$output" | grep -q PATTERN`.
  `grep -q` exits the moment it matches, so when the match is on an early
  line the writer can still be mid-write and dies of SIGPIPE — and
  `pipefail` then reports the *pipeline* as failed even though the match
  succeeded. The assertion fails while printing the very text it was
  looking for. It is a race, so it passes locally and fails on a loaded CI
  runner (kaappi#1926 hit three of these at once on `freebsd-test`);
  matching the last line of the output hides it, matching the first line
  exposes it. The here-string has no pipeline for `pipefail` to judge.

### The interpreter is the oracle (`compile/`)

A test for a non-interpreter execution tier — a natively compiled binary, a
`-Dbundle` standalone — asserts `native output == interpreter output`, not
`native output == a string someone typed`. `shell-common.sh` provides
`interp_stdout` and `assert_tiers_agree`; its "interpreter as the native tier's
oracle" block is the full rationale and lists the three tier differences that
are **by design** (documented in `docs/dev/fuzzing.md`) and must not be
compared: the VM echoes a bare top-level expression's value and a native binary
does not, the VM continues past a top-level error while a native binary exits
at the first, and a procedure prints as `#<procedure name>` vs `#<procedure>`.

Keep the golden string too, as a second assertion against the *interpreter* —
it documents intent and still catches a bug both tiers share. What it must not
be is the only thing between a miscompilation and a green run: kaappi#2092 was
a form evaluated at the wrong *time* natively, printing `BPC` where the
interpreter printed `PBC`, and a golden only catches that if someone thought to
write `PBC` down. Converting the suite (kaappi#2110) found four live tier
divergences the golden strings had been silent about: kaappi#2115, kaappi#2117,
kaappi#2118, and kaappi#2119.

Three things genuinely have no interpreter counterpart, and stay golden:
assertions that **compilation fails** (`native-external-library-import-1743.sh`),
assertions about **emitted LLVM IR** — which tier ran, root-stack balance
(`native-let-internal-define-root-1854.sh`, `-1861`, `-1862`) — and the **text
of a native diagnostic**, since the VM frames one with file:line and a source
excerpt and the native runtime does not. A named `.sbc` is a fourth: nothing
can execute one (`kaappi out.sbc` reads it as source), so
`compile-preamble-699.sh` has no runnable second tier short of a ~180s
`-Dbundle` rebuild.

## Quirks

- The R7RS suite's verdict comes from its printed counts, not its exit status:
  the `(chibi test)` shim has no exit-on-fail epilogue and exits 0 with failed
  assertions in the log. `tools/run-r7rs-suite.sh` is the single parser —
  `run-all.sh`, `tools/run-gc-stress-suite.sh` and the five `ci.yml` steps
  (riscv64, s390x, ppc64le, both Windows legs) — seven callers — all call it,
  so they agree by construction. Those five used to invoke the suite bare and so could only ever
  catch a crash (kaappi#2157) — which matters most on s390x, the big-endian
  canary, where a byte-order bug presents as a wrong answer. **Don't change the
  suite's output format**, and don't add an eighth caller with its own awk.
- Some older tests use manual pass/fail counters instead of SRFI-64. Prefer
  SRFI-64 for new tests.
- Tests run independently with no shared state. Each file is a fresh interpreter.
  `run-all.sh` relies on this to run them in parallel, so it is now a
  correctness requirement, not just a description: a new test must not depend on
  a fixed path, port, or file that another test also touches. Give temporary
  files a name unique to the test (or `mktemp` them) — a fixed `/tmp` path used
  by two files will flake under concurrency and pass when run alone.
