# `kaappi doctor` — installation and environment self-check

`kaappi doctor` answers "why doesn't my setup work?" without a human tracing it
by hand. "Why doesn't `(import (kaappi json))` work?" has a fixed set of answers
— library-path resolution, thottam state, a missing native library, the wrong
binary on PATH — so the toolchain checks itself and prints, per check, a
`PASS`/`WARN`/`FAIL` line with a concrete suggestion on every failure.

Part of the machine-legibility epic ([#1503](https://github.com/kaappi/kaappi/issues/1503));
tracked in [#1513](https://github.com/kaappi/kaappi/issues/1513). Like
[`kaappi explain`](explain.md) and [`kaappi test`](test-runner.md), it is a
meta-command: it inspects the environment and runs no user code, so `main`
dispatches it (`doctor.maybeRun`) before any VM, GC, or library setup exists.

## What it checks

| Group | Checks |
|-------|--------|
| `binary` | version, target triple, build mode, the running binary's path, and the `kaappi` a shell would pick from PATH (so a mismatch — "wrong binary on PATH" — is visible). |
| `library` | the effective `.sld` search path in order: each `--lib-path`, the script directory (added per-run), `~/.kaappi/lib`, and the exe-relative `../lib` fallback — with whether each exists. |
| `package-manager` | `thottam` on PATH; every package in `~/.kaappi/thottam.lock` has a matching source tree in `~/.kaappi/src`. |
| `native-backend` | On an interpreter-tier arch (riscv64, s390x, ppc64le — where `kaappi compile` refuses, #1656) a single `arch` WARN says native compilation is unavailable and stops; otherwise C-compiler discovery (`zig`/`cc`/`clang`/`gcc`), the runtime archive (`libkaappi_rt.a`, or `kaappi_rt.lib` on Windows) across the four documented locations, and a **smoke link** if both are found. |
| `repl` | `~/.kaappi` writable (where history is saved); terminal capabilities (`isatty`, `TERM`). |
| `ffi` | every `.dylib`/`.so` in `~/.kaappi/lib` is `dlopen`-able (per-file result, with the `dlerror` on failure). |

Two forms: `kaappi doctor` (a human table, one line per check) and
`kaappi doctor --json` (one object — `version`/`target`/`build_mode` meta, an
overall `status`, an `ok` boolean, and a `checks` array of
`{group,label,status,detail,suggestion}`). Both are produced from the same
findings list, so they can never disagree.

## The exit-code contract

> Exit status is nonzero **only** when a check is `FAIL`.

`WARN` describes a degraded-but-usable environment — a missing `~/.kaappi/lib`
(no libraries installed yet), no C compiler (native compile unavailable), an
`.so` that won't load — and keeps the exit code 0. Those are common, legitimate
states, not broken installs, so they must not fail scripts or CI.

Only one condition is `FAIL`: an explicit **`KAAPPI_LIB_DIR` that does not
resolve** — the directory is missing, or it exists but has no `libkaappi_rt.a`.
`KAAPPI_LIB_DIR`'s sole purpose is to point the native backend at a runtime
library, so a set-but-wrong value is an unambiguous misconfiguration (the user
asked for a specific location and it is not there) — worth failing loudly, with
the suggestion to fix or unset it. Everything absent-by-default degrades to
`WARN` instead. The shell test (`tests/scheme/doctor/doctor.sh`) drives exactly
this: a bogus `KAAPPI_LIB_DIR` must exit 1; the healthy environment must exit 0.

## The smoke link

When both a C compiler and `libkaappi_rt.a` are found, doctor compiles and links
a tiny C program that references one leaf runtime export (`kaappi_fixnum_add`)
against the archive — the exact final step `kaappi compile` performs. A
successful link proves the compiler works *and* the archive is well-formed and
resolvable; the program is never executed. The compiler's own diagnostics are
sent to `/dev/null` (only the link's exit status matters), and the temp files
are removed. Under the unit-test binary the fork is skipped (`builtin.is_test`)
so tests stay hermetic; the shell test exercises the real link.

## Code layout

- `src/doctor.zig` — the whole command: `maybeRun` (arg parsing + dispatch), the
  `collect*` probes (one per group), the `Report`/`Finding` model, the smoke
  link, and the text/JSON renderers. Detail and suggestion strings live in one
  arena freed in a single `deinit`.
- `src/main.zig` — dispatches `doctor.maybeRun` alongside `explain` and `test`,
  before VM setup.
- `src/kaappi_paths.zig` — `getHome` and `getExeRelativeLibDir`, the shared path
  logic doctor reflects so its reported search path matches a real run's.

The findings model keeps rendering testable off synthetic data: `overall` (most
severe finding wins) and `exitCode` (nonzero iff any `FAIL`) are pure functions,
and the text/JSON renderers take a `Report`, so the unit tests assert on both
without touching the real environment.
