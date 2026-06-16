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
zig build test     # Run all unit tests (~150 tests)
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
  compiler*.zig          S-expression to bytecode compiler (5 files)
  vm*.zig                Register-based VM (4 files)
  primitives*.zig        Built-in procedures (13 files)
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
- Keep individual source files under ~1000 lines; split into sub-modules when
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

- Zig unit tests live in `src/tests_phase1.zig` through `src/tests_phase11.zig`
- Scheme integration tests live in `tests/scheme/`
- Both types of tests must pass

## CI

GitHub Actions runs on every push and pull request:

- Zig unit tests on Ubuntu and macOS
- Scheme test suite

## Architecture Documentation

- [docs/dev/architecture.md](docs/dev/architecture.md) -- Pipeline, value
  representation, GC, file organization
- [docs/dev/adding-features.md](docs/dev/adding-features.md) -- How-to guides
  for extending the implementation
- [docs/dev/testing.md](docs/dev/testing.md) -- Testing infrastructure and
  conventions
- [CLAUDE.md](CLAUDE.md) -- Complete technical reference for the codebase
