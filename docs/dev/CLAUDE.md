# docs/dev/ — Developer Documentation

Contributor documentation for the Kaappi core repo. End-user docs live in
`kaappi.github.io/` and are served at kaappi-lang.org — nothing end-user-facing
belongs here.

## Directory layout

| Path | Genre | Rule |
|------|-------|------|
| `*.md` (top level) | Guides & reference | Evergreen — keep current as the code changes |
| `decisions/` | Design decisions | Point-in-time — only the status line is updated after the fact |
| `postmortems/` | Bug investigations | Point-in-time — named `YYYY-MM-DD-<slug>.md` by investigation date |

`README.md` is the full index with every document listed and categorized.

## Key documents

| When you're working on… | Read first |
|-------------------------|-----------|
| Architecture / pipeline | `architecture.md` |
| Compiler IR | `ir.md` |
| The VM: frames, calls, continuations, error propagation | `vm.md` (+ `bytecode.md` for the ISA) |
| The reader: grammar, `#` forms, datum labels, spans, `read` on ports | `reader.md` |
| Macro expansion, hygiene, `syntax-rules`, SRFI 211 | `expander.md` |
| LLVM native backend | `llvm-backend.md` |
| GC safety (the rules) | `gc-safety-and-error-handling.md` |
| The collector and value model (why the rules) | `memory.md` |
| SRFI-18 threads / what may cross a thread boundary | `thread-value-sharing.md` |
| Fibers, the I/O reactor, port blocking | `fibers-and-reactor.md` |
| Whether a behaviour is a documented deviation or a bug | `known-limitations.md` |
| Subprocesses / `(kaappi process)` | `subprocess.md` |
| The C FFI, `--sandbox` | `ffi.md` |
| Implementing or editing a SRFI library | `srfi-implementation-notes.md` |
| The package manager | `thottam.md` |
| Tests | `testing.md`, `test-runner.md` |
| A slowdown (compiler or generated code) | `performance.md` |
| Fuzzing | `fuzzing.md`, `fuzzing-feasibility.md` |
| Porting to a new OS/arch | `porting.md` + the OS-specific doc (`windows.md`, `freebsd.md`, `openbsd.md`, `netbsd.md`) |
| CLI subcommands | `check.md`, `fmt.md`, `features.md`, `doctor.md`, `cache.md`, `timings.md` |
| Diagnostics / lint codes | `diagnostics.md`, `diagnostics-json.md`, `explain.md` |
| The language server (`kaappi-lsp`) | `lsp.md` |
| Claude Code harness | `claude-code-harness.md` |
| Filing or triaging an issue | `github-issues.md` |
| Workflow YAML | `github-actions.md` |
| Dumping a pipeline stage (`ast` / `expand` / `ir` / `--disassemble`) | `observing-the-pipeline.md` |
| The REPL | `repl.md` |
| The panic handler / crash banner | `crash-reporting.md` |
| Bounded-step execution (the WASM stepper) | `bounded-step.md` |
| A bug class that feels familiar | `lessons-learned.md` |
| SRFI policy | `srfi-exclusions.md`, `srfi-status-check.md` |
| CLI flags themselves (what each one is for) | `cli-surface.md` |

## Conventions

- One topic per file. Don't merge unrelated subjects.
- Guides must stay accurate — if you change the code, update the guide.
- Decisions and postmortems are immutable records. Only update the `## Status`
  line after the fact.
- Open bugs belong in the issue tracker, not here. Only add a doc when the
  investigation itself is worth preserving.
- Roadmap and future work go in issues, not docs — "future work" sections rot.
- Cross-cutting bug-class entries go in `lessons-learned.md` with a link to the
  full postmortem.

## Adding a new document

1. Check if an existing guide already covers it (`adding-features.md`,
   `testing.md`, etc.) — extend rather than create.
2. Pick the genre: guide (top level), decision (`decisions/`), or postmortem
   (`postmortems/`).
3. Add an entry to the appropriate table in `README.md`.
