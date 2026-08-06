# Kaappi — R7RS Scheme in Zig

Complete R7RS-small Scheme implementation. Zig 0.16, ~100k lines, 692 built-in
procedures, 178 SRFIs.

This file is the orientation map. Detail lives in `docs/dev/` — every section
below names the document that owns it. `docs/dev/README.md` is the full index.

## Build

```bash
zig build                          # build executable (zig-out/bin/kaappi)
zig build run                      # launch REPL (isocline: multi-line editing, history, completion)
zig build run -- f.scm             # run a Scheme file
zig build test                     # run all unit tests
zig build test -Dtest-filter=tests_io  # only tests whose NAMES match (repeatable)
zig build coverage                 # unit test coverage (requires kcov)
zig build coverage-scheme -- f.scm # Scheme file coverage (requires kcov)
zig build bench                    # call/cc vs call/ec capture micro-benchmark
zig build bench-fibers             # per-fiber switch time, RSS, footprint (KEP-0001 P7)
zig build bench-reactor            # reactor re-arm, wake-all, timer granularity (KEP-0001 P7)
zig build -Dbundle-src=program.scm # standalone binary (compile + embed in one step)
zig build -Dbundle=program.sbc     # standalone binary from pre-compiled .sbc
zig build wasm                     # WebAssembly binary (wasm32-wasi)
```

Requires Zig 0.16+ and libc (for isocline terminal handling).

Builds default to **ReleaseSafe** (fast, bounds/safety checks retained; fixnum
overflow auto-promotes to bignum). Debug is ~500x slower for allocation- and
continuation-heavy workloads — only use it when debugging
(`-Doptimize=Debug`). For maximum throughput: `-Doptimize=ReleaseFast`.

### Build-time limits

| Option | Default | Grows to |
|--------|---------|----------|
| `-Dmax-frames=N` | 480 | 32768 |
| `-Dmax-registers=N` | 2048 | 65536 |
| `-Dmax-handlers=N` | 64 | 32768 |
| `-Dmax-winds=N` | 64 | 32768 |
| `-Dgc-threshold=N` | 8192 | — (initial GC object threshold) |

`-Dgc-stress=true` forces a collection on every allocation.

All four stacks grow geometrically and are hard-capped; exceeding a cap is
`KP3008` and, unlike a program's own `raise`, is **not** catchable — a `guard`
clause never sees it (kaappi#1886). `errors.isUncatchable` is the single list
of what unwinds past every handler: VM limits (`StackOverflow`,
`ExecutionTimeout`) and control-flow signals (`Terminated`, `Yielded`). See
`docs/dev/gc-safety-and-error-handling.md`.

### Git hooks

After cloning, enable the pre-commit format check:

```bash
git config core.hooksPath .githooks
```

This runs `zig fmt --check` on staged `.zig` files before each commit.

## CLI

`kaappi --help` is generated from `src/cli_spec.zig` and is the authority.
**`docs/dev/cli-surface.md` is the annotated version** — every flag, every
subcommand, what each is for, and which doc explains it — plus the comptime
gate that keeps the parsers, `--help`, and all six shell completion scripts
from drifting apart.

Subcommands: `compile`, `check`, `explain`, `features`, `test`,
`ast`/`expand`/`ir`, `doctor`, `fmt`, `cache`. Each has its own document
(`check.md`, `features.md`, `test-runner.md`, `observing-the-pipeline.md`,
`doctor.md`, `fmt.md`, `cache.md`, `timings.md`).

Environment: `KAAPPI_LIB_DIR` overrides `libkaappi_rt.a` lookup; `KAAPPI_HOME`
(default `~/.kaappi`) locates the bytecode cache, installed libraries, and REPL
history.

## Supported platforms

| OS | Architecture | Build | Unit Tests | Notes |
|----|-------------|-------|------------|-------|
| macOS | aarch64 (Apple Silicon) | yes | yes | Primary dev platform |
| Linux | x86_64 | yes | yes | CI tested (Ubuntu) |
| Linux | aarch64 | yes | yes | CI tested (Ubuntu ARM) |
| Linux | riscv64 | yes | yes | CI tested (QEMU) |
| Linux | s390x (big-endian) | yes | yes | CI tested (QEMU); the byte-order canary (kaappi#1654) |
| Linux | ppc64le | yes | yes | CI tested (QEMU) |
| Windows | aarch64, x86_64 | yes | yes | `docs/dev/windows.md` |
| FreeBSD | x86_64, aarch64 | yes | yes | kqueue reactor; `docs/dev/freebsd.md` |
| OpenBSD | x86_64, aarch64 | yes | yes | kqueue; binaries auto-marked `PT_OPENBSD_NOBTCFI`; `docs/dev/openbsd.md` |
| NetBSD | x86_64, aarch64 | yes | yes | kqueue; versioned libc symbols; aarch64 FPCR reset; `docs/dev/netbsd.md` |
| WebAssembly | wasm32-wasi | yes | — | `zig build wasm`, browser/WASI |

Every non-macOS target cross-compiles from macOS ARM with
`zig build -Dtarget=<arch>-<os>`. The LLVM native backend covers
aarch64/x86_64 only; other arches are interpreter-tier. Linux binaries run in
containers via podman (x86_64 via Rosetta, riscv64/s390x/ppc64le via QEMU).

**Porting to a new OS or CPU architecture: `docs/dev/porting.md`** — porting
surfaces, the degradation ladder, staged checklists, and the per-OS
particulars each of the four BSD/Windows docs above expands on.

## LLVM native backend

```bash
kaappi compile program.scm -o program            # recommended single command
zig build native -Dnative-src=program.scm        # via build system
```

`docs/dev/llvm-backend.md` is the full reference. The three things worth
knowing before touching it:

1. **Three gates decide native vs. eval fallback, and all three are
   comptime-derived** — `ir.eval_fallback_form_names` (from `llvm_node_table` +
   every `FormKind` + `other_special_forms`), `isRejectedFormHead`
   (`rejected_form_heads`, derived since kaappi#1896), and
   `LLVMEmitter.lexicalNames`. None needs maintenance; a new `FormKind` joins
   automatically. A hand-kept parallel list is exactly what drifted each time.
2. **The backend re-derives lexical scope**, because every lambda/closure/`let`
   body is still a raw S-expression in the IR it was handed and gets re-lowered
   during emission. `LLVMEmitter.lowerScoped` is the *only* way to re-lower a
   sub-form — a bare `ir.lowerSingleExpr*` drops `bound_names`/`set_targets`
   and silently reopens kaappi#2117/#2118.
3. **A `.scm` regression test is interpreter-only evidence.** Three of them
   passed for years while the native tier failed them, because no suite ran
   them through `kaappi compile`. Native regressions belong in
   `tests/scheme/compile/*.sh`.

**Always use `zig cc`, not `clang`, to link against `libkaappi_rt.a`** — the
Zig-compiled static library references `__zig_probe_stack` and other Zig
compiler-rt intrinsics that `clang` cannot resolve.

## Architecture

```text
Source → Reader → Expander → IR → Analysis → Optimization → Bytecode Emission → VM
         (UTF-8    (syntax-    (18 node  (tail pos)    (const fold,     (register-   (generational
          lexer)    rules)      types)                  dead branch,      based)       GC)
                                                        boolean, etc.)
```

| Stage | File | Role |
|-------|------|------|
| Reader | `reader.zig` (+ `reader_tokens.zig`, `reader_datum.zig`) | Tokenizer + recursive descent parser. R7RS lexical syntax including Unicode identifiers and `#\λ`. |
| Expander | `expander.zig` (+ `expander_instantiate.zig`) | `syntax-rules` pattern matching and template instantiation. Called by the compiler when a macro keyword is encountered. |
| IR | `ir.zig` | Lowers S-expressions to tree-structured IR (18 node types; `sexpr_form` carries 18 `FormKind`s). 1 analysis pass (tail positions), 5 optimization passes. `docs/dev/ir.md` |
| Compiler | `compiler.zig` | IR nodes → register-based bytecode via `compileFromNode()`. `docs/dev/bytecode.md` |
| VM | `vm.zig` | Executes bytecode. Growable register file + call frame stack. Continuations (stack-copying), handler stack, dynamic-wind stack, stepping debugger. |
| GC | `memory.zig` | Generational (young/old), minor and full collections, write barrier for old→young. Roots via `gc.pushRoot`/`gc.popRoot`. |

**`docs/dev/architecture.md` holds the full file-organization tables** — core
runtime, the 11 `types_*.zig` heap-type domain files, compiler & IR (11
files), VM (10), primitives (31), and everything else. Consult it before
adding a file or hunting for where something lives.

### Value representation

NaN-boxed u64 — flonums, fixnums, booleans, characters, and nil all fit in a
single word with zero heap allocation:

- **Any non-NaN f64**: flonum (stored directly)
- **0xFFFC | 48-bit pointer**: heap `Object` (8-byte aligned)
- **0xFFFD | 48-bit integer**: fixnum (signed, up to ±2^47; auto-promotes to bignum)
- **0xFFFE | payload**: immediate (nil, true, false, void, eof, char with 21-bit codepoint)

Heap objects share an `Object` header with `ObjectTag` (u6, 64 slots), GC mark
bit, generation (u1), and survive count (u2) — 41 types.

### Strings

Stored as UTF-8 byte arrays. All string operations index by **codepoint
position**, not byte offset. Mutation via `string-set!` rebuilds the string
when byte widths change.

## File size policy

Keep source files under **1500 lines**. When a file grows past that, split it
along natural seams (arch-specific code, dispatch vs helpers, call
infrastructure vs struct definition). Do NOT split flat lists of independent
functions (e.g. primitives files) — size from breadth is fine; size from
tangled coupling is not.

Exceptions: auto-generated data files (`unicode_tables.zig`) are exempt.

## Libraries and SRFIs

178 SRFIs supported: 12 built-in as Zig primitives (1, 9, 13, 18, 39, 69, 133,
170, 192, 254, 258, 260), 162 portable `.sld` files under `lib/srfi/` loaded on
demand, plus SRFI 261 (an import-resolver convention with no library file) and
the sub-library-only 160, 211 and 226. Every supported SRFI is also a
`cond-expand` feature identifier `srfi-<n>`, derived rather than listed.

Re-derive the counts after each release with `kaappi features --json` — it
reports only the 12 + 162, since it scans just the top-level `lib/srfi/N.sld`
files; add the other four by hand.

The library loader in `vm_library.zig` supports `cond-expand`, `include` (paths
resolved relative to the `.sld`), and `(export (rename ...))` in
`define-library`. Macro transformers defined with `define-syntax` in library
`begin` blocks are exported and imported correctly.

- **`docs/dev/srfi-implementation-notes.md`** — how each non-trivial SRFI is
  implemented: what needed engine changes, resolved spec ambiguities, and the
  bugs each port surfaced. **Read the relevant section before editing a SRFI
  library**; several carry hard-won constraints that are invisible from the
  code.
- **`docs/dev/srfi-exclusions.md`** — the 30 excluded SRFIs, one section each.
- **`docs/dev/srfi-status-check.md`** — the CI guard that fails if a shipped
  SRFI is `draft` or `withdrawn`, and how it re-derives the set from the binary.

## Zig 0.16 patterns

These differ from earlier Zig versions and are easy to get wrong (full set in
`docs/dev/adding-features.md`):

```zig
// ArrayList is UNMANAGED — pass allocator to every method
var list: std.ArrayList(u8) = .empty;           // NOT .{} or .init(alloc)
list.append(allocator, item) catch {};
list.deinit(allocator);

// No std.io — use std.Io.Writer, or raw syscalls for stdout/stderr
var buf: [256]u8 = undefined;
var w: std.Io.Writer = .fixed(&buf);
w.print("{d}", .{42}) catch {};
std.posix.system.write(2, bytes.ptr, bytes.len);  // stderr

// main() takes Init.Minimal for args
pub fn main(init: std.process.Init.Minimal) !void { ... }

// StringHashMap is still managed (stores allocator internally)
var map = std.StringHashMap(Value).init(allocator);
map.deinit();  // no allocator arg needed
```

## How to add a new built-in procedure

`docs/dev/adding-features.md` is the reference; the `/add-builtin` skill is the
walkthrough. The parts most often got wrong:

1. Write the function in the appropriate `src/primitives_*.zig` domain file —
   not `primitives.zig` itself (that's the registration hub plus core list/pair
   ops).

2. **Report type errors with `primitives.typeError(proc, expected, got)`, never
   a bare `return PrimitiveError.TypeError`.** The CI `format` job rejects any
   unannotated bare return (zero allowed since kaappi#1868); infrastructure
   guards with no procedure context opt out with `// bare-ok: <reason>`. A bare
   return is not silent — `vm_calls.mapNativeError` synthesizes `type error in
   '<primitive>': got <args[0]>` — which is what makes it dangerous: the
   message looks deliberate while omitting the expected type and, when the
   offending value is not the first argument, naming the wrong one. Use
   `expectFixnum`/`expectString`/`expectPair`/… to validate and unwrap in one
   step, and the siblings `indexError` (KP3006) and `argError` (KP3007) rather
   than stretching `typeError` over failures that are not type errors.

3. Add one entry to the file's `specs` table — name, function, arity, exporting
   libraries. `registerAll` walks `all_specs` and `library.zig` derives every
   export set from the same tags; there is no second list and no manual `reg()`:

   ```zig
   .{ .name = "my-proc", .func = &myProc, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
   ```

4. A `%`-prefixed internal helper takes `primitives.INTERNAL` instead —
   registered in `vm.globals`, exported by nothing, so it doesn't reserve the
   name against user libraries (kaappi#1856). `INTERNAL_PUBLIC` additionally
   exports it from `(kaappi primitives)`. Synthesize *references* with
   `Compiler.trueBuiltinRefOrSymbol` / `globals_mod.baseBindingSymbol`, never a
   bare `allocSymbol("%foo")`, or a user binding of the same name silently wins.

5. Heap allocation uses `memory.gc_instance`; calling Scheme procedures uses
   `vm_mod.vm_instance` + `vm.callWithArgs`. Both are `orelse`-optional — tag
   the guard by what the function was going to return anyway (see GC safety).

6. Add a unit test in the matching `src/tests_*.zig` using
   `testing_helpers.zig`, plus a Scheme test under `tests/scheme/` when the
   behavior is visible end-to-end.

## How to add a new compiler form

See `.claude/rules/compiler-forms.md` (auto-loaded when editing compiler or IR
files). Covers: IR node type, dispatch, implementation, re-export, IR tests,
tail position handling.

## How to add a new heap type

Full walkthrough in `docs/dev/adding-features.md`. The five places a new
`ObjectTag` must be handled, none of which the compiler will remind you about
twice:

1. The struct, with `header: Object` as the first-declared field, in the
   matching `types_*.zig` domain file (re-exported from `types.zig`). Heap
   Values always carry the address of the `header` field: build with
   `makePointer(&x.header)`, recover with `Object.as()`/`@fieldParentPtr`,
   never a direct cast.
2. `allocXxx` in `gc_alloc.zig`, aliased into `GC` in `memory.zig`.
3. The 5 exhaustive per-tag switches — `markObjectContents`, `markValueInner`'s
   worklist, `referencesYoung` (`gc_collect.zig`); `objectSize`, `freeObject`
   (`gc_sweep.zig`). A type with no Value fields still needs a no-op arm.
4. `types.typeName`, for error messages.
5. `printer.printValueOnce` — **and if the arm recurses into contained Values,
   `isTraversable` + `childAt` too.** A printed edge invisible to cycle
   detection is the four-procedure hang of kaappi#1954.

## GC safety

See `.claude/rules/gc-safety.md` (auto-loaded when editing primitives, memory,
or VM files) and `docs/dev/gc-safety-and-error-handling.md`. Key rules: root
before allocating, write barrier after mutating heap object fields, root
`Function*` before `vm.execute()`, and never `defer gc.popRoot()` across a
stretch that itself pushes a root — the stack is LIFO, not per-variable.

## Tests

**Every bug fix MUST include a regression test** that fails without the fix and
passes with it — Zig unit test in `src/tests_*.zig` for VM/compiler/GC
internals, Scheme test under `tests/scheme/` for behavior visible from Scheme,
and a `tests/scheme/compile/*.sh` script when the native tier is involved.

```bash
zig build test                                          # unit tests
bash tools/run-r7rs-suite.sh zig-out/bin/kaappi         # R7RS suite (1,395 tests)
bash tests/scheme/run-all.sh                            # everything (build FIRST)
```

The unit suite must also stay green under `zig build test -Dgc-stress=true`
(collection on every allocation — kaappi#1401). Tests holding heap values in
Zig locals across allocations must root them; loop-heavy tests should scale
counts down via `@import("build_options").gc_stress`.

`tests/scheme/` by purpose: `smoke/`, `compliance/`, `continuations/`,
`hygiene/`, `srfi/`, `ffi/`, `audit/`, `errors/`, `compile/` (native tier),
plus `bench/` and `coverage/` which `run-all.sh` deliberately skips.

**`docs/dev/testing.md`** is the full guide — the helper API, injecting an OOM
with `gc.oom_countdown`, the shell suites, post-release acceptance tests, and
the benchmark harness.

## Code coverage

[kcov](https://simonkagstrom.github.io/kcov/) tracks which Zig source lines
execute. Install with `brew install kcov`. Both steps build in Debug mode
regardless of `-Doptimize`, since kcov needs DWARF line info.

```bash
zig build coverage                                             # unit tests only
zig build coverage-scheme -- tests/scheme/r7rs/r7rs-tests.scm  # R7RS suite
open coverage/index.html
```

Coverage accumulates across runs — kcov merges results from the unit test
binary (`coverage-tests`) and the Scheme runner (`kaappi-cov`) into a single
report. `coverage` cleans previous unit-test data on each run;
`coverage-scheme` accumulates so you can run multiple `.scm` files. Delete
`coverage/` to start fresh. Only files under `src/` are included (standard
library and vendored code are excluded).

## Concurrency

- **Fibers and the I/O reactor (KEP-0001)** — `docs/dev/fibers-and-reactor.md`.
  Each OS thread's scheduler owns a `Reactor`
  (kqueue/epoll/WASI-`poll_oneoff`/Windows-`WSAEventSelect` + a userspace timer
  heap). A port read that would block parks the fiber, or drives the scheduler
  in place under re-entrant native frames. `readOneByte` / `portWriteBytes` in
  `primitives_io.zig` are the single byte source/sink for every port
  primitive — hook new I/O through them, not around them.

- **OS threads (SRFI-18)** — `docs/dev/thread-value-sharing.md`. Each child
  thread gets its own VM and GC with an independent heap. A value reaches
  another thread by one of **two routes with separate, unrelated enforcement**:
  the **copy route** (deep copy at thread start, join, and channel messages;
  `gc_deep_copy.zig` refuses 14 tags) and the **globals route**
  (`VM.initForThread` shares the root's `globals` map *by pointer* — every
  thread chains to the same map its ancestors use, kaappi#2129 — so
  naming a top-level binding gets the root's own uncopied object — that list
  of 14 does not apply, and only four types defend themselves via
  `Object.owner`). Consequence worth memorizing: **mutexes and condition
  variables must be shared through a global; channels must be captured
  lexically** — exactly inverted. Mutating shared state through a global is a
  live hazard (kaappi#1924), not a supported idiom.

## Dependencies

**isocline** (vendored in `vendor/isocline/`): MIT-licensed C library for REPL
line editing, history, completion, and syntax highlighting, on POSIX *and*
Windows. Compiled as part of the Zig build — `src/isocline.c` `#include`s the
other translation units, so it is one C file to the build system.

It holds a whole form in one buffer, which is why `repl.zig` no longer joins
continuation lines: `ic_readline` returns a finished expression, newlines
included, and every line of it stays editable until submit.

**The copy is patched** — four changes, each marked `KAAPPI PATCH` in the
source and documented in `vendor/isocline/PATCHES.md`: an input-completeness
callback (upstream's Enter always submits), a configurable history size
(upstream caps at 200), structural s-expression editing — slurp, barf,
raise, rotate, whose transforms live in `src/repl_sexp.zig` (`docs/dev/repl.md`)
— and `TCSADRAIN` instead of `TCSAFLUSH` around raw-mode transitions, so a
multi-line paste that submits partway through doesn't get its still-unread
tail silently discarded (kaappi#2226). Re-apply all four when updating;
`grep -rn 'KAAPPI PATCH' vendor/isocline/` finds every site.

## Package manager (thottam)

`src/thottam.zig` installs Kaappi ecosystem libraries; built alongside `kaappi`
and shipped in the release artifacts for every platform.

```bash
thottam install kaappi-web        # also: @v1.0.0, @">=0.2.0", ::custom-url
thottam list / update / remove
```

`docs/dev/thottam.md` covers the manifest format, version constraints,
auto-discovery, and the `kaappi-*` library layout. `docs/dev/ecosystem-library-bar.md`
is the quality bar for ecosystem packages.

## Documentation

**End-user docs** (guide, procedures, libraries, benchmarks) live in the
[kaappi/kaappi.github.io](https://github.com/kaappi/kaappi.github.io) repo and
are served at **https://kaappi-lang.org/**. That repo is exclusively for
end-user documentation — no dev docs there.

**Developer/contributor docs** live in `docs/dev/` in this repo — the single
source of truth for contributor documentation. `docs/dev/README.md` indexes
every document; `docs/dev/CLAUDE.md` states the conventions.

**The install script lives in the docs repo too** — `docs/install.sh`, served
at **https://kaappi-lang.org/install.sh**, which is the `curl … | bash` line in
`README.md` and the only copy anyone runs. There is deliberately **no copy in
this repo**: one existed until 0.22.0, was served and tested by nothing, and
drifted three commits behind the real one — so "fix install.sh" here shipped
nothing to users, which is how the missing `libkaappi_rt.a` install went
unnoticed. Edit it there. The `test-install-script` job in
`.github/workflows/post-release.yml` curls and tests the live script after
every release across `ubuntu-latest`, `ubuntu-24.04-arm`, and `macos-latest`.
Adding a platform means teaching its `detect_platform` the `uname` spelling and
its `rt_artifact` case — `docs/dev/porting.md` Stage 6.

## Issue tracker

**Every issue you file or triage gets exactly one `priority:` label** —
`critical`, `high`, `medium`, or `low`. Set it when filing; an issue that
arrives without one is not triaged.

| Level | The question it answers |
|-------|------------------------|
| critical | Does this compromise the process — memory unsafety, or an abort reachable from an ordinary program? |
| high | Does a legal program get a silently wrong answer, hang, or lose data in a path users actually reach? |
| medium | Is behaviour wrong against a spec or a documented guarantee, but loud, narrow, or recoverable? |
| low | Is the behaviour right and only its *description* or *diagnostic* wrong? |

`critical` is process-level unsafety **only**: a correctness bug tops out at
`high` however broad or silent, and so does a hang. Reachability is what
separates the two — an abort needing a stress harness is `high`, one reachable
from a five-line program is `critical`. Silence is an aggravator that moves an
issue up *within* its level, not a level of its own.

**`docs/dev/github-issues.md` is the full rubric** — the four label axes, the
boundary rules, severity-vs-priority, and the triage commands, including the
query that finds every open issue with none *or* more than one priority label.

## Claude Code harness

Hooks, permissions, path-scoped rules, and skills that enforce the conventions
above automatically. **`docs/dev/claude-code-harness.md` is the full
documentation** — every component, how they interact, how to extend them. When
changing the harness, update both.

| Hook (`.claude/hooks/`) | Event | What it does |
|------|-------|-------------|
| `session-start.sh` | SessionStart | Branch, Zig version, stale-worktree warning |
| `zig-fmt-post.sh` | PostToolUse (Edit/Write) | Auto-formats `.zig` files. Silent on success |
| `bash-guard-pre.sh` | PreToolUse (Bash) | Blocks `rm -rf /`, `sudo`, `git push --force`, `git tag -d`, `git reset --hard` |
| `test-on-stop.sh` | Stop | Runs `zig build test` if any `.zig` file changed. Blocks on failure |

Path-scoped rules in `.claude/rules/` load automatically:
`gc-safety.md` (primitives, memory, VM, compiler, expander) and
`compiler-forms.md` (compiler, IR).

Skills in `.claude/skills/`: `/add-builtin`, `/audit-primitives`,
`/bytecode-isa`, `/github-release`, `/create-announcement`, `/r7rs-reader`,
`/linux-test`, `/do-linux-test`, `/do-stress-test`, `/do-gate-benchmark`,
`/pr-groups`, `/quiz`, `/vm-test`. The `infra/` repo additionally hosts the
`kaappi-dev` plugin (ecosystem-wide skills, a bash guard, an
`ecosystem-reviewer` agent), loaded from the workspace-level settings.

### Enforcement map

| Rule | Enforced by | Where |
|------|------------|-------|
| Zig formatting | PostToolUse hook + git pre-commit | `.claude/hooks/zig-fmt-post.sh`, `.githooks/pre-commit` |
| Markdown structure | CI `format` job (markdownlint) | `.markdownlint-cli2.jsonc` |
| No bare `PrimitiveError.TypeError` | CI `format` job (grep, zero allowed) | `.github/workflows/ci.yml` |
| No destructive commands | Deny permissions + PreToolUse hook | `.claude/settings.json`, `.claude/hooks/bash-guard-pre.sh` |
| Tests pass before stop | Stop hook | `.claude/hooks/test-on-stop.sh` |
| GC safety checklist | Path-scoped rule (auto-loaded) | `.claude/rules/gc-safety.md` |
| Compiler form checklist | Path-scoped rule (auto-loaded) | `.claude/rules/compiler-forms.md` |
| Bug fixes need tests | Advisory only | This file (Tests) |
| Files ≤ 1500 lines | Advisory only | This file (File size policy) |
| One `priority:` label per issue | Advisory only | This file, `docs/dev/github-issues.md` |
| Commit message format | Advisory only | Parent `CLAUDE.md` (Conventions) |

## Known limitations

See the "Known limitations" section in `README.md` (single source of truth).
