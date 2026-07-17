# Developer Documentation

Contributor documentation for the Kaappi core repo. End-user documentation
(guides, API reference, cookbook) lives in the
[kaappi.github.io](https://github.com/kaappi/kaappi.github.io) repo and is
served at https://kaappi-lang.org/ — nothing end-user-facing belongs here.

The documents fall into distinct genres, reflected in the directory
layout. **Guides** (top level) are evergreen and must be kept current as
the code changes. **Design decisions** (`decisions/`) and **postmortems**
(`postmortems/`, date-prefixed) are point-in-time records: each carries a
status and date, and only the status line is updated after the fact.
**Reference notes** document a subsystem's current shape. Open bugs belong
in the issue tracker, not here — a doc is only warranted when an
investigation produced analysis worth keeping.

## Guides

| Document | Contents |
|----------|----------|
| [vision.md](vision.md) | Why Kaappi exists, what it values, how those values guide decisions |
| [architecture.md](architecture.md) | Major subsystems: pipeline, value representation, VM, GC, file organization |
| [ir.md](ir.md) | Compiler IR: 33 node types, analysis passes, optimization passes |
| [observing-the-pipeline.md](observing-the-pipeline.md) | `kaappi ast` / `expand` / `ir` / `--disassemble`: read-only dumps of every stage between source and bytecode |
| [llvm-backend.md](llvm-backend.md) | LLVM native backend: what LLVM provides vs what the runtime provides |
| [windows.md](windows.md) | Windows aarch64 port: the platform.zig shim, the two deliberate degradations, the `windows` feature identifier, how to test on a Windows machine |
| [porting.md](porting.md) | Porting to a new OS or CPU architecture: the support matrix, where portability lives, the degradation ladder, staged checklists, what "supported" means |
| [adding-features.md](adding-features.md) | Step-by-step guides for the most common extension tasks |
| [testing.md](testing.md) | The four test layers, how to run them, where new tests go |
| [test-runner.md](test-runner.md) | `kaappi test`: the first-class SRFI-64 runner — discovery, worker subprocesses, `--json` schema, `--seed` |
| [fmt.md](fmt.md) | `kaappi fmt`: the canonical comment-preserving formatter — the CST reader, the layout rules, the round-trip safety net, `--check` |
| [fuzzing.md](fuzzing.md) | Fuzzing runbook: the targets, the scheduled CI job, turning a failure into a regression test |
| [github-actions.md](github-actions.md) | Workflow hardening rules: SHA-pinned actions, `persist-credentials: false`, least-privilege tokens |
| [gc-safety-and-error-handling.md](gc-safety-and-error-handling.md) | Rooting, write barriers, and error propagation patterns contributors must follow |
| [diagnostics.md](diagnostics.md) | Diagnostic `KP` codes: the registry, the taxonomy, the stability policy, how to add a code |
| [diagnostics-json.md](diagnostics-json.md) | `--diagnostics=json`: the LSP `Diagnostic` JSON Lines schema shared by the CLI and the language server |
| [explain.md](explain.md) | `kaappi explain <code>`: the binary's own offline diagnostic reference (prose + example + fix), and the generator for the kaappi-lang.org page |
| [features.md](features.md) | `kaappi features [--json]`: machine-readable capability discovery — version/build id, subsystems (the shared `cond-expand` table), SRFIs, limits |
| [doctor.md](doctor.md) | `kaappi doctor`: installation/environment self-check — the checks, the exit-code contract, the native-backend smoke link |
| [cache.md](cache.md) | The `.sbc` bytecode cache: what the key contains (source hash + build id), where entries live, what invalidates them, how to inspect/clear/bypass |
| [claude-code-harness.md](claude-code-harness.md) | Hooks, permissions, path-scoped rules, and skills for AI-assisted development |

## Design decisions

| Document | Decision |
|----------|----------|
| [continuation-strategy.md](decisions/continuation-strategy.md) | Native codegen uses direct-style IR; `call/cc` side-exits to the bytecode VM |
| [self-tail-call-optimization.md](decisions/self-tail-call-optimization.md) | Dedicated `self_tail_call` opcode (Option A shipped; Option B attempted and reverted) |

## Postmortems

[lessons-learned.md](lessons-learned.md) is the cross-cutting index: one
short entry per bug class. The standalone postmortems below hold the full
investigations.

| Document | Bug | Status |
|----------|-----|--------|
| [gc-reachability-bug](postmortems/2026-06-17-gc-reachability-bug.md) | String literals freed mid-execution — unrooted source datum during read/compile | Fixed 2026-06-17 |
| [global-cache-not-gc-traced](postmortems/2026-06-17-global-cache-not-gc-traced.md) | `Function.global_cache` not traced by `markValue` | Fixed 2026-06-17 |
| [deep-recursion-register-overflow](postmortems/2026-06-17-deep-recursion-register-overflow.md) | Fixed-capacity register file overflowed under deep non-tail recursion | Fixed 2026-06-30 |
| [fixnum-overflow-promotion](postmortems/2026-06-18-fixnum-overflow-promotion.md) | Arithmetic results in the fixnum/i64 gap silently wrapped | Fixed 2026-06-18 |
| [complex-number-test-precision](postmortems/2026-06-18-complex-number-test-precision.md) | `test-approx=?` didn't compare complex numbers component-wise | Fixed 2026-06-18 |

## Reference notes

| Document | Contents |
|----------|----------|
| [bytecode.md](bytecode.md) | Bytecode instruction set (32 opcodes), encoding, disassembler |
| [repl.md](repl.md) | REPL reference: line editing, comma commands, completion |
| [unicode-case-mapping.md](unicode-case-mapping.md) | Case-conversion coverage by script |
| [fuzzing-feasibility.md](fuzzing-feasibility.md) | Why neither Fuzzilli nor AFL++ is the tool, the existing `std.testing.fuzz` targets, and where fuzzing can improve |

## Policy

| Document | Contents |
|----------|----------|
| [ecosystem-library-bar.md](ecosystem-library-bar.md) | Quality bar for `kaappi-*` packages (applies ecosystem-wide, not just this repo) |

## Adding a new document

- **Extending the implementation?** It probably belongs in an existing
  guide (`adding-features.md`, `testing.md`) rather than a new file.
- **Recording a design decision?** New file in `decisions/`, one decision
  per file. State the decision and its date in the first paragraph, then
  the analysis.
- **Writing up a fixed bug?** New postmortem in `postmortems/`, named
  `YYYY-MM-DD-<slug>.md` by investigation date, with a `## Status` section
  giving the fix date and commit. Add a one-paragraph summary entry to
  `lessons-learned.md` linking to it.
- **Found an open bug?** File a GitHub issue. Only add a doc here if the
  investigation itself is worth preserving, and link the issue.
- **Roadmap items and future work** go in the issue tracker, not in docs —
  "future work" sections in documents rot silently.
