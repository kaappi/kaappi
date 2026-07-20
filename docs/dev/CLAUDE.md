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
| LLVM native backend | `llvm-backend.md` |
| GC safety | `gc-safety-and-error-handling.md` |
| Tests | `testing.md`, `test-runner.md` |
| Fuzzing | `fuzzing.md`, `fuzzing-feasibility.md` |
| Porting to a new OS/arch | `porting.md` + the OS-specific doc (`windows.md`, `freebsd.md`, `openbsd.md`, `netbsd.md`) |
| CLI subcommands | `check.md`, `fmt.md`, `features.md`, `doctor.md`, `cache.md`, `timings.md` |
| Diagnostics / lint codes | `diagnostics.md`, `diagnostics-json.md`, `explain.md` |
| Claude Code harness | `claude-code-harness.md` |
| SRFI policy | `srfi-exclusions.md`, `srfi-status-check.md` |

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
