# Claude Code Harness

The repo ships a Claude Code harness — hooks, permissions, path-scoped rules,
and skills — that enforces project conventions automatically during AI-assisted
development. This document covers every component, how they interact, and how
to extend them.

Configuration lives in `.claude/settings.json`. Hook scripts live in
`.claude/hooks/`. Rules live in `.claude/rules/`. Skills live in
`.claude/skills/`.

## Hooks

Hooks run shell scripts in response to Claude Code tool-use events. Four hooks
are configured, each with a timeout:

### `session-start.sh` — session context on startup

| Field | Value |
|-------|-------|
| Event | `SessionStart` |
| Matcher | (none — fires once at session start) |
| Timeout | 10 seconds |

Prints the current git branch, Zig version, and warns about any stale
worktrees (older than 7 days) in `.claude/worktrees/`. Purely informational
— never blocks. Helps prevent working on the wrong branch or with a stale
checkout.

### `zig-fmt-post.sh` — auto-format after edits

| Field | Value |
|-------|-------|
| Event | `PostToolUse` |
| Matcher | `Edit\|Write` |
| Timeout | 15 seconds |
| Status | "Formatting..." |

Runs `zig fmt` on the edited file after every Edit or Write. Reads the tool
call payload from stdin (JSON), extracts the file path via `jq`, and skips
non-`.zig` files. Silent on success. On failure, runs `zig fmt` a second time
to capture the error, then emits a JSON `hookSpecificOutput` message that
injects the formatting error back into Claude's context.

This supplements the git pre-commit hook (`.githooks/pre-commit`) which runs
`zig fmt --check` on staged files. The post-tool hook catches format issues
immediately rather than at commit time.

### `bash-guard-pre.sh` — block dangerous commands

| Field | Value |
|-------|-------|
| Event | `PreToolUse` |
| Matcher | `Bash` |
| Timeout | 5 seconds |

Reads the tool call payload from stdin (JSON), extracts the command via `jq`,
and tests it against five regex patterns:

| Pattern | Why |
|---------|-----|
| `rm\s+-rf\s+/` | Protects filesystem root |
| `(^\|\s\|;\|&&\|\|\|)sudo\s` | No privilege escalation |
| `git\s+push\s.*--force` | Protects remote history |
| `git\s+tag\s+-d` | Prevents accidental tag deletion |
| `git\s+reset\s+--hard` | Prevents loss of uncommitted work |

On match, emits `{"decision":"block","reason":"..."}` and exits 0. On no
match, exits 0 (permit). This is a defense-in-depth layer on top of the
permission deny rules — the hook also catches `git tag -d` and
`git reset --hard` which the deny rules don't cover.

### `test-on-stop.sh` — run tests before ending

| Field | Value |
|-------|-------|
| Event | `Stop` |
| Matcher | (none — fires on every stop) |
| Timeout | 150 seconds |
| Status | "Running unit tests..." |

1. Changes to the git repo root.
2. Checks for modified `.zig` files via `git diff --name-only HEAD` (unstaged)
   and `git diff --cached --name-only` (staged).
3. If no `.zig` files changed, exits 0 (allow stop).
4. Runs `zig build test` with a 120-second timeout (`timeout` on Linux,
   `gtimeout` on macOS, bare if neither available).
5. If tests pass, exits 0.
6. If tests fail, emits `{"decision":"block","reason":"Unit tests failed:\n..."}` 
   with the last 30 lines of test output, preventing Claude from finishing
   until it fixes the failures.

## Permissions

Permissions control which tool calls Claude Code can make without prompting.
Defined in `.claude/settings.json` under three tiers.

### Allow (auto-approved)

These exact patterns are in the `allow` array:

| Pattern | Purpose |
|---------|---------|
| `Read(**)` | Read any file in the project |
| `Bash(zig build)` | Build the interpreter |
| `Bash(zig build test)` | Run unit tests |
| `Bash(zig build run -- *)` | Run Scheme files and REPL |
| `Bash(zig build wasm)` | Build WebAssembly target |
| `Bash(zig build bench)` | Run benchmarks |
| `Bash(zig build coverage*)` | Code coverage (kcov) |
| `Bash(zig fmt *)` | Auto-format Zig source |
| `Bash(zig-out/bin/kaappi *)` | Run the built binary directly |
| `Bash(bash tests/scheme/*)` | Scheme test suites |
| `Bash(git status*)` | Working tree state |
| `Bash(git diff*)` | View diffs |
| `Bash(git log*)` | Commit history |
| `Bash(git branch*)` | Branch operations |
| `Bash(git add *)` | Stage files |
| `Bash(git commit -m *)` | Commit (message-only form) |
| `Bash(git checkout -b *)` | Create new branches |
| `Bash(find *)` | File search |
| `Bash(grep *)` | Text search |
| `Bash(wc *)` | Line counts |
| `Bash(ls *)` | Directory listing |
| `Bash(make *)` | Build C FFI shared libraries |
| `Bash(git push*)` | Push to remote |
| `Bash(podman *)` | Container operations |
| `Bash(gh release *)` | GitHub releases |
| `Bash(gh pr *)` | GitHub pull requests |
| `Read(~/.ssh/**)` | ssh config/host lookup for remote test machines (e.g. the win11 VM) |

### Deny (blocked)

| Pattern | Reason |
|---------|--------|
| `Bash(rm -rf /*)` | Filesystem root protection |
| `Bash(sudo *)` | No privilege escalation |
| `Bash(git push*--force*)` | Remote history protection |
| `Read(.env*)` | Secrets protection |
| `Write(.git/**)` | Repository integrity |

### Ask (empty)

The `ask` array is empty. Everything is either auto-approved or hard-blocked.
The bash-guard hook provides an additional safety layer for destructive git
operations not covered by the deny rules.

## Path-Scoped Rules

Rules are Markdown files that load automatically when editing files matching
specific glob patterns. The glob-to-rule mapping is defined via YAML front
matter inside each rule file (not in `settings.json`).

### `gc-safety.md`

**Globs:** `src/primitives_*.zig`, `src/memory.zig`, `src/vm*.zig`

Loaded when editing GC-sensitive code (all 21 primitives files, the GC
allocator, and all 8 VM files). Enforces three rules:

1. **Write barrier required** — call `gc.writeBarrier(container, new_val)`
   after storing a Value into a heap object field. Missing barriers corrupt the
   generational GC during minor collections — the collector won't know an
   old-generation object now references a young-generation object.

2. **Root before allocating** — if you hold a pointer to a heap object and then
   allocate (which may trigger GC), root the value first with
   `gc.pushRoot(&val)` / `gc.popRoot()`. Without this, GC can free an object
   between two allocations (classic use-after-free in GC'd runtimes).

3. **Root Function\* before vm.execute()** — `execute()` allocates a closure
   wrapper internally, so unrooted Function pointers can be collected.

Includes a dangerous/safe code example and a stress-test tip
(`-Dgc-threshold=1` forces GC on every allocation).

### `compiler-forms.md`

**Globs:** `src/compiler*.zig`, `src/ir.zig`, `src/tests_ir.zig`

Loaded when editing compiler or IR code (main compiler, 4 sub-modules,
re-export hub, IR module, IR tests). Provides a 6-step checklist for adding a
new compiler form:

1. Add IR node type in `ir.zig` — variant in `NodeTag`, `Data` union variant,
   lowering in `lowerFormWithMacros()`/`lowerForm()`, handle in all 3 analysis
   pass switch arms and all 5 optimization pass switch arms.
2. Add dispatch in `compileFromNode()` in `compiler.zig`.
3. Implement in the appropriate `compiler_*.zig` file.
4. Re-export through `compiler_forms.zig`.
5. Add IR tests in `tests_ir.zig` — bytecode parity with the legacy
   `compileExpr()` path.
6. Handle tail position — pass `tail=true` to sub-expressions that should
   receive tail call optimization.

## Skills

Skills are slash-command workflows defined as Markdown files in
`.claude/skills/`. Each provides step-by-step guidance for a specific task.

### `/add-builtin`

Guides adding a new built-in Scheme procedure. Steps: write the function in
the appropriate `primitives_*.zig` file with the standard signature, register
it in the file's `registerXxx` function with correct arity (`.exact` or
`.variadic`), add to library exports in `library.zig`.

### `/audit-primitives`

Audits a primitives file for R7RS correctness. Takes a filename argument
(e.g., `primitives_arithmetic.zig`). Five-step workflow:

1. Extract all procedures registered with `try reg(vm, ...)`.
2. Cross-reference against R7RS sections 6.1–6.14 — check correct behavior,
   type errors, boundary conditions, higher-order callbacks, optional args.
3. Write test file at `tests/scheme/audit/<basename>-audit.scm`.
4. Run tests, diagnose failures, fix bugs, run full regression suite.
5. Report summary.

Documents six common bug patterns found during prior audits (thunk not called,
missing overwrite semantics, truncation, ignored optional args, resource leaks,
missing type dispatch).

### `/bytecode-isa`

Reference for the bytecode instruction set. Points at
[bytecode.md](bytecode.md) (the single source of truth for the 32-opcode
table and encodings) and carries the adding-a-new-opcode checklist. Used
when working on the compiler or VM.

### `/github-release`

Full release workflow with 10 steps and multiple confirmation gates:

1. Analyze changes since last tag, recommend semver bump.
2. Generate release notes from CHANGELOG.md and unreflected commits.
3. Update CHANGELOG.md (clear Unreleased, insert new version section).
4. Bump version in `main.zig`, `thottam.zig`, `build.zig.zon`, and the docs
   site download page.
5. Build verification (`zig build`).
6. Commit and create annotated tag.
7. Push (requires explicit confirmation — triggers CI release workflow).
8. Verify release workflow (platform binaries, macOS signing, GitHub Release).
9. Verify post-release acceptance tests.
10. Update docs site (WASM binary, download page).

Includes error recovery procedures for both pre-push and post-push failures.

### `/r7rs-reader`

R7RS lexical syntax reference (Section 7.1). Documents implemented token types,
identifier rules, string escape sequences, character names, and comment forms.
Used when modifying the reader (`src/reader.zig`).

### `/linux-test`

Build and test on Linux via podman containers. Five steps across three
architectures:

| Arch | Method | Time |
|------|--------|------|
| aarch64 | Native via Virtualization.framework | ~2 min |
| x86_64 | Cross-compile, run in AMD64 container via Rosetta | ~1 min |
| riscv64 | Cross-compile, run in RISC-V container via QEMU | ~5 min |

Uses `kaappi-builder` Docker images from `ci-images/builder/`.

### `/do-linux-test`

Build and run the full test suite (unit + Scheme) on a real x86-64 Linux
machine via a temporary DigitalOcean droplet. Complements `/linux-test` by
providing real hardware instead of emulation. Steps: create `s-2vcpu-4gb`
droplet, install Zig 0.16, clone and build, run unit tests, run `run-all.sh`,
fetch results, destroy the droplet. Self-destruct timer (55 min) guarantees
cleanup even if the session dies. Uses `~/.ssh/id_rsa` and the DO API token
from `~/.zshrc`. Cost: ~$0.03/hr, full run takes 10–15 minutes.

### `/do-stress-test`

Run the unit suite with `-Dgc-stress=true` (collection on every allocation) on
a temporary DigitalOcean droplet. Same provisioning flow as `/do-linux-test` but
with more resources (`s-4vcpu-8gb-amd`, 8 GB swap) and a 3-hour lifetime. The
stress suite is CPU-bound for 1.5–3 hours, so it runs detached on the droplet
and is polled for completion. Self-destruct timer arms immediately before the
stress suite launch (after provisioning and a plain sanity check). Cost:
~$0.084/hr, full 3-hour window costs ~$0.25.

### `/do-gate-benchmark`

Run the KEP-0002 Phase 7 gate-campaign statistical benchmark
(`benchmarks/gate/run-gate.py` over `gate-harness.scm`) on a real x86-64 Linux
reference machine — the dataset a KEP acceptance gate (e.g. KEP-0003,
kaappi#1474) classifies mechanically via `benchmarks/gate/classify.py`. A
different workload class from `/do-stress-test`/`/do-linux-test` (a multi-hour
Kalibera-Jones statistics driver, not a test suite), needing ≥8 physical cores.
Uses `s-8vcpu-16gb-intel` (this account's dedicated CPU-Optimized `c-`/`c2-`/
`c5-` line is tier-restricted above 4 vCPUs) — verifies actual core topology
with `lscpu` rather than trusting the vCPU count. Requires a direct
single-iteration timing probe of the heaviest workload/size before committing
to the full run: the same benchmark can run 5–6× slower per-thread on a cloud
x86 vCPU than on the Apple Silicon reference for some interpreted kernels,
so a naive time estimate can be badly wrong. Self-destruct timer budgeted
1.5–2× the post-probe estimate. Grew out of collecting kaappi#1474's Linux
dataset (PR #1580); see the skill file for the full lesson set (droplet
tier-restriction gotcha, three bash-guard string-match footguns, splitting a
run around a per-machine workload cap).

## Ecosystem Plugin (`kaappi-dev`)

The `infra/` repo hosts a Claude Code plugin called `kaappi-dev` that provides
ecosystem-wide tooling. It loads automatically when working from the multi-repo
workspace root (`kaappi/`, one level above the core repo).

### Workspace wiring

The workspace `.claude/settings.json` registers a local directory-based
marketplace and enables the plugin:

```json
{
  "extraKnownMarketplaces": {
    "kaappi-marketplace": {
      "source": "directory",
      "path": "./infra"
    }
  },
  "enabledPlugins": {
    "kaappi-dev@kaappi-marketplace": true
  }
}
```

The plugin manifest lives at `infra/.claude-plugin/plugin.json`.

### Plugin skills

| Skill | Purpose |
|-------|---------|
| `/kaappi-dev:test-ecosystem` | Run tests for one or all 16 ecosystem libraries against the local kaappi binary |
| `/kaappi-dev:repo-status` | Git status dashboard across all 24 repos (branch, dirty files, ahead/behind, CI) |
| `/kaappi-dev:ci-check` | GitHub Actions status across all repos plus nightly workflow |
| `/kaappi-dev:pull-all` | Fetch and rebase all 24 repos on `origin/main` |
| `/kaappi-dev:release-ecosystem` | Cut a release for an ecosystem library (version bump, changelog, tag, push) |
| `/kaappi-dev:coverage-report` | Procedure-level `--coverage` across all ecosystem libs, highlights <80% |

### Plugin hooks

A `bash-guard.sh` hook (PreToolUse, Bash, 5s timeout) blocks the same five
dangerous patterns as the core repo's hook. Provides the same safety net when
working from the workspace root.

### Plugin agents

An `ecosystem-reviewer` agent (Sonnet, max 10 turns) reviews ecosystem library
code for Kaappi conventions:

- R7RS compliance and 2-space indentation in Scheme files
- `define-library` exports match implemented procedures in `.sld` files
- `kaappi.pkg` manifest correctness
- FFI type signatures match the 18 types in `ffi.zig`
- Test files exist for exported procedures
- Makefile builds `.dylib`/`.so` for C FFI repos
- CI workflow exists at `.github/workflows/ci.yml`

Reports issues by severity: error, warning, suggestion.

### Supporting infrastructure

The `infra/` repo also contains non-plugin resources:

- `repos.json` — inventory of all 24 repos with categories and expected files
- `labels.json` — 10 standard GitHub labels synced across all repos
- `scripts/` — Kaappi Scheme scripts for repo auditing and license generation
- `docs/` — repo conventions, CI architecture, and release process docs
- `.github/workflows/sync-labels.yml` — syncs labels to all org repos

## How the layers interact

The harness has three layers that reinforce each other:

```
Permissions (settings.json)     ← first gate: allow / deny
    ↓
Pre-tool hooks (bash-guard)     ← second gate: block dangerous patterns
    ↓
Tool execution                  ← the actual command runs
    ↓
Post-tool hooks (zig-fmt)       ← cleanup: auto-format edited files
    ↓
Stop hook (test-on-stop)        ← exit gate: tests must pass
```

Path-scoped rules operate orthogonally — they inject context based on which
files are being edited, not based on tool events.

The git pre-commit hook (`.githooks/pre-commit`) is a separate layer outside
Claude Code, catching format issues at commit time regardless of how the
changes were made.

**Defense in depth for destructive git ops:**

| Operation | Deny rule | Bash guard hook |
|-----------|:---------:|:---------------:|
| `rm -rf /` | yes | yes |
| `sudo` | yes | yes |
| `git push --force` | yes | yes |
| `git tag -d` | — | yes |
| `git reset --hard` | — | yes |

## Extending the harness

### Adding a hook

1. Write a shell script in `.claude/hooks/`.
2. Add a hook entry in `.claude/settings.json` under the appropriate event key:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "command": "bash .claude/hooks/my-hook.sh",
               "timeout": 10
             }
           ]
         }
       ]
     }
   }
   ```
3. The script receives the tool payload as JSON on stdin.
4. To block: emit `{"decision":"block","reason":"..."}` on stdout.
5. To permit: exit 0 with no blocking output.

### Adding a rule

1. Write a Markdown file in `.claude/rules/` with YAML front matter:
   ```markdown
   ---
   globs: ["src/my_*.zig"]
   description: "My convention checklist"
   ---
   
   Rule content here...
   ```
2. The rule loads automatically when editing files matching the globs.
   No `settings.json` change needed.

### Adding a skill

Create a directory in `.claude/skills/<name>/` with a `SKILL.md` file.
The directory name becomes the slash-command (`/name`). Skills are plain
Markdown with step-by-step instructions.
