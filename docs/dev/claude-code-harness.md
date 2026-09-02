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
| `Edit(.git/**)` | Repository integrity |

### Ask (empty)

The `ask` array is empty. Everything is either auto-approved or hard-blocked.
The bash-guard hook provides an additional safety layer for destructive git
operations not covered by the deny rules.

## Path-Scoped Rules

Rules are Markdown files that load automatically when editing files matching
specific glob patterns. The glob-to-rule mapping is defined via YAML front
matter inside each rule file (not in `settings.json`).

### `gc-safety.md`

**Globs:** `src/primitives_*.zig`, `src/memory.zig`, `src/gc_*.zig`,
`src/vm*.zig`, `src/compiler*.zig`, `src/expander*.zig`

Loaded when editing GC-sensitive code (the primitives files, the GC core and
its gc_alloc/gc_collect/gc_sweep/gc_deep_copy satellites, the VM files, and
the compiler/expander files, which do GC-sensitive rooting directly). The
headline rules:

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

4. **`popRoot()` is LIFO, not per-variable** — a `defer gc.popRoot()` is only
   safe when nothing else can push to the same stack before it fires. The rule
   carries a worked instance where a deferred pop removed the wrong root and
   surfaced much later as a baffling "invalid syntax" error.

5. **Tag a `gc_instance`/`vm_instance` guard by what the function was going to
   return anyway** — `OutOfMemory` for an allocator, the helper's own tag for
   an error-message helper, `InvalidBytecode` for everything else.

It also covers what the allocators root for you, the error-path root-stack
reset at the pipeline boundaries (#1855), injecting an OOM with
`gc.oom_countdown`, dangerous/safe code examples, and the stress-test lever
(`-Dgc-stress=true` forces a collection on every allocation).
[gc-safety-and-error-handling.md](gc-safety-and-error-handling.md) is the full
rationale the rule condenses.

### `compiler-forms.md`

**Globs:** `src/compiler*.zig`, `src/ir.zig`, `src/tests_ir.zig`

Loaded when editing compiler or IR code (the main compiler, its nine
sub-modules, the IR module, and the IR tests). It splits the checklist by which
kind of form you are adding, because the two cost wildly different amounts:

**A delegating form** — the common case, ~4 edits. The form keeps its tail as a
raw S-expression and rides the single `sexpr_form` node: add a `FormKind`
variant with its `keyword()`, add the `sexpr_form_map` entry, add a dispatch
arm in `compileFromNode()` (`compiler_ir.zig`), implement it in the right
`compiler_*.zig` and re-export through `compiler_forms.zig`, then add IR
behavioral tests. Nothing in `NodeTag`, `freeNode`, the analysis pass, or the
five optimization passes needs touching — they all handle `.sexpr_form`
through `else` arms.

**A structured form** — 7 steps, for forms that lower into IR-level children
like `if` and `when`: `NodeTag` variant and `Data` union field, lowering in
`lowerFormWithMacros()` plus a `makeXxx()` constructor, a `freeNode` arm if it
owns heap slices, a `markTailPositions` arm with the right tail propagation, an
`llvm_node_table` entry with its capability, dispatch, then implement and test.

Notably absent, and deliberately: there is no bytecode-parity test group any
more. It compared `ir.zig`'s standalone `Emitter` against the direct compiler
path, and that emitter was removed in v0.13.0 — `compileFromNode()` is now the
only IR-to-bytecode path.

## Skills

Skills are slash-command workflows defined as Markdown files in
`.claude/skills/`. Each provides step-by-step guidance for a specific task.

### `/add-builtin`

Guides adding a new built-in Scheme procedure. Steps: write the function in the
appropriate `primitives_*.zig` domain file with the standard signature, report
type errors through `primitives.typeError` rather than a bare
`PrimitiveError.TypeError`, then add **one** entry to that file's `specs`
table carrying name, function, arity and exporting libraries.

The single-registration-point part is the bit worth internalizing: there is no
second list and no manual `reg()` call. `registerAll` walks `all_specs`, and
`library.zig` derives every export set from the same `libs` tags, so a spec
entry is the whole registration. A `%`-prefixed internal helper takes
`primitives.INTERNAL` instead — registered in `vm.globals`, exported by
nothing, so it does not reserve the name against user libraries (kaappi#1856).
[adding-features.md](adding-features.md) is the long-form reference.

### `/audit-primitives`

Audits a primitives file for R7RS correctness. Takes a filename argument
(e.g., `primitives_arithmetic.zig`). Five-step workflow:

1. List every entry in the file's `specs` table (the single registration point).
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
[bytecode.md](bytecode.md) (the single source of truth for the 34-opcode
table and encodings) and carries the adding-a-new-opcode checklist. Used
when working on the compiler or VM.

### `/github-release`

Full release workflow with 10 steps and multiple confirmation gates:

1. Analyze changes since last tag, recommend semver bump.
2. Generate release notes from `git log` since the previous tag — this is
   where `CHANGELOG.md` gets written; PRs never touch it.
3. Update CHANGELOG.md (insert the new version section).
4. Bump version in `main.zig`, `thottam.zig`, `build.zig.zon`, and the docs
   site download page.
5. Build verification (`zig build`).
6. Commit and create annotated tag.
7. Push (requires explicit confirmation — triggers CI release workflow).
8. Verify release workflow (platform binaries, macOS signing, GitHub Release).
9. Verify post-release acceptance tests.
10. Update docs site (WASM binary, download page).

Includes error recovery procedures for both pre-push and post-push failures.

### `/create-announcement`

Drafts and posts a release announcement to the org Announcements forum at
<https://github.com/orgs/kaappi/discussions/categories/announcements>. Takes a
release tag (`/create-announcement v0.22.0`), defaulting to the latest release.

The non-obvious fact the skill records: **org-level discussions are backed by
the `kaappi/kaappi` repository** — the `.github` repo has discussions disabled,
so the discussion is created in `kaappi/kaappi` and GitHub serves it at the
`orgs/kaappi` URL. Repo and category ids are pinned in the skill for the
GraphQL fallback, since `gh discussion` is still a preview command.

Eight steps, numbered 0 through 7: resolve the tag, preflight (`gh auth`,
release exists and is neither draft nor prerelease, release not so old that the
next one is imminent), search the category for an existing announcement of that
tag so a re-run cannot double-post, gather material (release body, previous tag,
commit count, shipped assets), draft, **stop for explicit approval**, post, and
verify. The approval gate is mandatory — posting publishes public content in a
maintainer-restricted category and notifies every org watcher.

Both write paths guard against duplicating that notification. The duplicate
check searches by tag rather than listing the newest N, since announcing an
older release is precisely the case where a duplicate would not be among the
newest. And because `createDiscussion` is a non-idempotent write whose lost
response is indistinguishable from an outright failure, the GraphQL fallback
re-runs that search before firing rather than trusting the CLI's exit code.

Carries the editorial half too: how to pick 3–6 highlights (what a user can now
*do*, not what changed — internal refactors and CI work are explicitly out), a
title and body template, and accuracy rules requiring every claim to trace to
the release notes.

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

### `/vm-test`

Powers on one of the local UTM virtual machines via `utmctl` and runs the build
and test battery on it over SSH. These VMs are the reference machines for the
OS/architecture ports — FreeBSD, OpenBSD, NetBSD, Windows, and the s390x and
ppc64le Alpine guests — so this is the way to reproduce a CI failure on a real
guest rather than an emulated cross-compile. Complements `/linux-test`
(podman) and `/do-linux-test` (DigitalOcean) with the local fleet; the per-OS
particulars are in [porting.md](porting.md) and the four BSD/Windows docs.

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

### `/pr-groups`

Groups open GitHub issues into sets that each land as a **single PR**, with a
merge order and a parallelism verdict. Takes a milestone title, `label:<name>`,
or a comma-separated list of issue numbers.

It replaced `/parallel-issues`, which optimised the opposite property —
mutual file *disjointness*, so that N sessions could work N issues
concurrently. That granularity was wrong: it would split two issues sitting in
adjacent arms of one `switch` into different sets, buying parallelism at the
cost of two reviews of the same diff and a conflict between the author's own
branches. `/pr-groups` runs the same disjointness analysis one level up, across
groups rather than issues, and keeps the old paste-able launcher output as its
wave format.

Three steps carry the value, and all three came from grouping the 0.22.2 and
0.22.3 milestones by hand:

1. **Verify before grouping.** Run each issue's own reproduction against a
   current build first. kaappi#2043 was scheduled into 0.22.3 and turned out to
   have been fixed by PR #2174 — the PR closed its four siblings (#1893, #1920,
   #1940, #1945) and missed it. Scheduling fixed work discredits the whole plan.
2. **Ground the file claims.** An issue's diagnosis is a hypothesis; `grep` the
   named sites before pairing on them.
3. **Check what the group would blow in aggregate.** Four issues grouped into
   `primitives_srfi18.zig` would have pushed it past the 1500-line cap from
   1472 — the group has to plan its split, or become two PRs.

Ordering has two land-first categories: **instrument before subject** (a broken
detector for the bug class the other issues are in — kaappi#2127) and **signal
before work** (anything making CI produce false reds — kaappi#1870, kaappi#1930,
kaappi#2097). Design-first groups go last and alone, with an explicit statement
of what ships without them.

### `/quiz`

Prediction-with-commitment comprehension quiz on a core-tier subsystem
from [understanding-map.md](understanding-map.md) — the practice half of
the cognitive-debt policy that document defines. Protocol: silently
prepare — the map section is the syllabus, the current sources are
ground truth, and the relevant `docs/dev/` pages are read last, purely
to detect doc/code drift — then ask 3–5
prediction/invariant/design/debugging questions, require committed
answers before revealing anything, and grade with evidence — live runs
and `file:line` citations, never recall. Results append to a per-user
ledger at `~/.kaappi/quiz-ledger.md`, kept outside the repo deliberately
(survives worktrees, stays private). Doc-vs-code drift and
user-beats-code disagreements surface as findings to file or fix.

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
| `/kaappi-dev:test-ecosystem` | Run tests for one or all 20 ecosystem libraries against the local kaappi binary |
| `/kaappi-dev:repo-status` | Git status dashboard across all repos (branch, dirty files, ahead/behind, CI) |
| `/kaappi-dev:ci-check` | GitHub Actions status across all repos plus nightly workflow |
| `/kaappi-dev:pull-all` | Fetch and rebase every repo on `origin/main` |
| `/kaappi-dev:new-ecosystem-lib` | Scaffold a new `kaappi-*` library with the standard layout, CI, and tests (`--ffi`, `--depends`) |
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

- `repos.json` — inventory of all 27 repos with categories and expected files
  (20 ecosystem, 3 meta, plus core, tooling, infra and docs)
- `labels.json` — the standard GitHub labels synced across all repos
- `scripts/` — Kaappi Scheme scripts for repo auditing and license generation
- `docs/` — repo conventions, CI architecture, and release process docs
- `.github/workflows/sync-labels.yml` — syncs labels to all org repos

## How the layers interact

The harness has three layers that reinforce each other:

```text
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

#### Argument expansion rewrites shell snippets before they are read

A `SKILL.md` body is not delivered verbatim. Slash-command argument expansion
rewrites positional tokens **before** the body reaches the model, so a shell
snippet in the file is not necessarily the snippet that runs. Measured
directly (three probe invocations at 0, 2, and 3 arguments):

| Token in the file | What arrives |
|-------------------|--------------|
| `$0`, `$1`, `$2`, … | The **(N+1)-th** argument — the numbering is zero-indexed, so `$0` is the *first* argument |
| `$0`, `$1`, … with no such argument | Left untouched — **not** replaced with an empty string |
| `$ARGUMENTS` | The full argument string; empty when the skill is invoked with none |
| `$@`, `$*`, `$#` | Never substituted |
| `${1}` (braced) | Never substituted — the braced form is immune |
| `$TAG` and other named variables | Never substituted |

Position in the file is irrelevant: prose, inline code spans, and fenced code
blocks are all rewritten alike. Fencing a snippet does **not** protect it.

The failure mode is silent. `awk '$0==t{f=1}'` in a skill invoked as
`/that-skill v0.21.0` arrives as `awk 'v0.21.0==t{f=1}'`, which matches nothing,
exits 0, and yields an empty result far from the apparent cause — this is a real
defect that shipped in `create-announcement` and was caught only by running it.

Rules when authoring:

- Prefer `git describe`, `cut -d' ' -f2`, or `sed -E` over `awk` field
  variables. Where a field variable is unavoidable, `${2}` is safe.
- Watch for `$` immediately before a digit in ordinary prose too — a cost note
  reading `~$0.03/hr` renders as `~<first-argument>.03/hr`. Write `USD 0.03/hr`.
- Before shipping, run `grep -nE '\$[0-9]' .claude/skills/<name>/SKILL.md` and
  confirm every hit is deliberate.
- When documenting this hazard *inside* a skill, describe it in prose ("a dollar
  sign followed by a digit"). A warning containing the literal token rewrites
  itself into an example of the bug.

A no-argument skill is exposed only if someone passes arguments anyway; `$0` is
the most fragile slot, since a single stray argument is enough to hit it.
