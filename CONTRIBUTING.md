# Contributing to Kaappi

Thank you for your interest in contributing to Kaappi! This document covers
the essentials: how to get involved, building, testing, and submitting changes.

---

## How to get involved

See [kaappi/community's CONTRIBUTING.md](https://github.com/kaappi/community/blob/main/CONTRIBUTING.md)
for how to join the conversation, request org access, and the typical path
for a new contributor. The rest of this document covers this repo's
build/test/PR workflow specifically.

---

## Prerequisites

- **Zig 0.16+** -- download from [ziglang.org/download](https://ziglang.org/download/)
  or `brew install zig` on macOS
- **C toolchain** -- GCC or Clang (for building the vendored isocline library)
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

```text
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

### Markdown

Markdown is linted too — CI runs markdownlint over every `.md` file in the
repo. The rule set, globs, and ignores all live in `.markdownlint-cli2.jsonc`,
so a bare local run lints exactly what CI lints:

```bash
npx markdownlint-cli2
```

Most findings are blank lines around headings, lists, and fences, which
`npx markdownlint-cli2 --fix` inserts for you. Only cosmetic rules are
disabled (line length, table padding, and similar) — the structural ones are
on, including **MD018**, which catches the silent failure that motivated the
check: prose wrapping that puts `#1573),` at the start of a line, where
Markdown reads it as a malformed heading.

Two rules must **never** be autofixed blindly, which is why the repo is kept
at zero findings rather than relying on `--fix` after the fact:

- **MD018** "fixes" a line-initial `#1699` by inserting a space — turning
  prose into a real `# 1699` heading. Rewrap the line instead so the issue
  reference isn't line-initial.
- **MD038** strips the space from `` `#\ ` `` — corrupting a Scheme character
  literal. `docs/dev/fmt.md` disables it around the one paragraph that
  documents that literal.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and PR.
All jobs must pass before merging.

| Job | Runner | What it does |
|-----|--------|--------------|
| **format** | ubuntu-latest | `zig fmt --check src/`, bare TypeError regression check, markdownlint over every `.md` |
| **test** (matrix) | ubuntu-latest (x86_64), ubuntu-24.04-arm (aarch64), macos-latest (aarch64) | Build, unit tests, Scheme suites, sandbox/robustness tests, thottam integration. Runs in Debug, ReleaseSafe, and ReleaseFast optimize modes on x86_64; ReleaseSafe only on ARM and macOS. |
| **riscv64-test** | ubuntu-latest + QEMU | Cross-compiles with `-Dtarget=riscv64-linux` and runs unit tests + R7RS suite under QEMU emulation. Separate from the matrix because it needs QEMU setup. |
| **coverage** | ubuntu-22.04 | Unit test + R7RS suite coverage via kcov (push only). Pinned to 22.04 because kcov is not in Ubuntu 24.04 apt repos. |
| **benchmark** | ubuntu-latest | Runs `benchmarks/run-benchmarks.sh` and uploads results as an artifact (push only). |

## Submitting changes

Anyone can open issues and pull requests here; no org membership is needed.

1. Fork the repo and create a branch from `main`.
2. Make your changes and ensure all tests pass (`zig build test` +
   `bash tests/scheme/run-all.sh`).
3. Run `zig fmt src/` to fix any formatting issues.
4. Sign off every commit (`git commit -s`). The DCO check is a required
   status check and the PR cannot merge without it.
5. Open a pull request against `main`. The PR template includes a checklist.

For bug fixes, include a test that fails without the fix and passes with it.
For new features, add both Zig unit tests and Scheme-level tests.

### What happens next

Every PR needs all CI checks green and an approving review from a
maintainer (see [CODEOWNERS](.github/CODEOWNERS)) before it merges. CI on a
PR from a fork waits for a maintainer to approve the workflow run, so the
checks may take a while to start; that is a GitHub safeguard on the
runners, not a judgement on the PR. Pushing new commits after an approval
dismisses it, and the PR is re-reviewed.

This project has one maintainer and review time is the scarcest resource
it has. A few rules keep it spent well:

- **Run the tests yourself before opening the PR.** CI is a check, not a
  substitute. A PR opened red is closed, not debugged.
- **Be able to explain the change.** The reviewer will ask why a line is
  there. "The tool generated it" is not an answer, and a PR whose author
  cannot walk through it is closed without further review.
- **Disclose AI assistance.** Using an LLM to write or review code is fine
  here (this repo even ships a Claude Code harness, below). Say so in the
  PR description, and understand that the sign-off certifies *you* stand
  behind the contribution and have the right to submit it under MIT.
- **One change per PR.** A fix and an unrelated refactor are two PRs.
  Drive-by reformatting of code you did not otherwise touch is reverted.
- **Talk first for anything large.** A new subsystem, a language-surface
  change, or a change to the build model goes through a
  [KEP](https://github.com/kaappi/keps) before code. A PR that arrives
  without one may be closed with a pointer there.

Note that contributions to the *Zig* project itself are governed by Zig's
own no-LLM policy (`docs/dev/zig-upstream-policy.md`); nothing above
changes that.

## Security

To report a security vulnerability, see [SECURITY.md](SECURITY.md). Do not
open a public issue for security reports.

## Claude Code

If you use [Claude Code](https://claude.com/claude-code) for development, this
repo includes a harness with auto-formatting hooks, permission guardrails,
path-scoped rules (GC safety, compiler forms), and skills (`/add-builtin`,
`/audit-primitives`, `/github-release`, etc.). See the "Claude Code harness"
section in [CLAUDE.md](CLAUDE.md) for details.

## Architecture documentation

- [docs/dev/architecture.md](docs/dev/architecture.md) -- Pipeline, value
  representation, GC, file organization
- [docs/dev/adding-features.md](docs/dev/adding-features.md) -- How-to guides
  for extending the implementation
- [docs/dev/testing.md](docs/dev/testing.md) -- Testing infrastructure and
  conventions
- [docs/dev/README.md](docs/dev/README.md) -- Index of all developer docs,
  including design decisions and postmortems
- [CLAUDE.md](CLAUDE.md) -- Complete technical reference for the codebase

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be
respectful and constructive in all interactions.
