# Contributing to Kaappi

Thank you for your interest in contributing to Kaappi. This document covers
the essentials: building, testing, making changes, and submitting them.

---

## Prerequisites

- **Zig 0.16+** -- download from [ziglang.org/download](https://ziglang.org/download/)
  or `brew install zig` on macOS
- **C toolchain** -- GCC or Clang (for building the vendored linenoise library)
- **Git**

## Getting Started

```bash
git clone <repo-url> kaappi
cd kaappi
zig build          # Build the executable
zig build test     # Run all unit tests
```

Verify the REPL works:

```bash
zig build run
```

## Project Structure

The codebase is organized into clear subsystems:

```
src/
  types.zig              Value type, heap objects, opcodes
  memory.zig             Mark-and-sweep GC
  reader.zig             Tokenizer + S-expression parser
  expander.zig           Macro expansion (syntax-rules)
  compiler*.zig          S-expression to bytecode compiler (6 files)
  vm*.zig                Register-based VM (6 files)
  primitives*.zig        Built-in procedures (21 files)
  library.zig            Library registry and standard libs
  printer.zig            Value to string conversion
  main.zig               Entry point and REPL
```

See [docs/dev/architecture.md](docs/dev/architecture.md) for the full
architectural overview.

## Making Changes

### Build and test cycle

```bash
zig build              # Compile (catches type errors, etc.)
zig build test         # Run Zig unit tests
zig build run -- tests/scheme/compliance/vectors.scm  # Run a specific Scheme test
```

All of `zig build test` must pass before submitting changes. If your change
affects a specific domain, also run the relevant Scheme tests:

```bash
zig build run -- tests/scheme/compliance/strings.scm
zig build run -- tests/scheme/srfi/srfi1.scm
```

### Commit conventions

- Write clear, concise commit messages describing what changed and why
- Keep each commit focused on a single logical change
- Reference issue numbers where applicable

### Code style

- Follow the patterns in existing code -- consistency matters more than personal
  preference
- Keep individual source files under 1500 lines; split into sub-modules when
  they grow beyond that (see how `compiler.zig` and `vm.zig` are split)
- Use Zig 0.16 idioms (see CLAUDE.md for the specific patterns)
- Name Scheme-facing procedures to match R7RS conventions

## Adding Features

For step-by-step instructions on common tasks, see
[docs/dev/adding-features.md](docs/dev/adding-features.md):

- Adding a built-in procedure
- Adding a compiler form (syntax)
- Adding a new heap type

## Testing

See [docs/dev/testing.md](docs/dev/testing.md) for the complete testing guide.

**Quick summary:**

- Zig unit tests live in `src/tests_*.zig (e.g., tests_core_eval.zig, tests_macros.zig, tests_io.zig)`
- Scheme integration tests live in `tests/scheme/`
- Both types of tests must pass

## Error messages in primitives

Type errors in `primitives_*.zig` must include the procedure name,
expected type, and actual value. Use the `primitives.typeError()` helper:

```zig
if (!types.isPair(args[0])) return primitives.typeError("car", "pair", args[0]);
```

**Do not** add bare `return PrimitiveError.TypeError` for user-facing type
checks. CI enforces this — new bare returns without a `// bare-ok` annotation
will fail the build.

Only use `// bare-ok: <reason>` for infrastructure guards where no user value
is available (e.g., `vm_instance orelse`, `catch` switch fallbacks).

## Code style

Run `zig fmt src/` before committing. CI enforces `zig fmt --check src/`.

To catch formatting issues locally before commit, enable the pre-commit hook:

```bash
git config core.hooksPath .githooks
```

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and PR.
All jobs must pass before merging.

| Job | Runner | What it does |
|-----|--------|--------------|
| **format** | ubuntu-latest | `zig fmt --check src/`, bare TypeError regression check |
| **test** (matrix) | ubuntu-latest (x86_64), ubuntu-24.04-arm (aarch64), macos-latest (aarch64) | Build, unit tests, Scheme suites, sandbox/robustness tests, thottam integration. Runs in Debug, ReleaseSafe, and ReleaseFast optimize modes on x86_64; ReleaseSafe only on ARM and macOS. |
| **riscv64-test** | ubuntu-latest + QEMU | Cross-compiles with `-Dtarget=riscv64-linux` and runs unit tests + R7RS suite under QEMU emulation. Separate from the matrix because it needs QEMU setup. |
| **coverage** | ubuntu-22.04 | Unit test + R7RS suite coverage via kcov (push only). Pinned to 22.04 because kcov is not in Ubuntu 24.04 apt repos. |
| **benchmark** | ubuntu-latest | Runs `benchmarks/run-benchmarks.sh` and uploads results as an artifact (push only). |

## Submitting changes

1. Fork the repo and create a branch from `main`.
2. Make your changes and ensure all tests pass (`zig build test` +
   `bash tests/scheme/run-all.sh`).
3. Run `zig fmt src/` to fix any formatting issues.
4. Open a pull request against `main`. The PR template includes a checklist.

For bug fixes, include a test that fails without the fix and passes with it.
For new features, add both Zig unit tests and Scheme-level tests.

## Security

To report a security vulnerability, see [SECURITY.md](SECURITY.md). Do not
open a public issue for security reports.

## Architecture documentation

- [docs/dev/architecture.md](docs/dev/architecture.md) -- Pipeline, value
  representation, GC, file organization
- [docs/dev/adding-features.md](docs/dev/adding-features.md) -- How-to guides
  for extending the implementation
- [docs/dev/testing.md](docs/dev/testing.md) -- Testing infrastructure and
  conventions
- [CLAUDE.md](CLAUDE.md) -- Complete technical reference for the codebase

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be
respectful and constructive in all interactions.
