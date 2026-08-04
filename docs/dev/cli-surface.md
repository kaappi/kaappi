# The CLI surface: one table, five consumers

`src/cli_spec.zig` is the single authoritative description of the `kaappi` and
`thottam` command lines. Everything that needs to know how a flag is spelled,
whether it takes a value, or what it does reads that file:

| Consumer | What it reads it for |
|---|---|
| `src/cli.zig` — `parse` / `preScanSandbox` | recognizing global flags |
| `src/cli.zig` — `printUsage` | the `Options:` block, generated |
| `src/explain.zig`, `features.zig`, `doctor.zig`, `test_runner.zig`, `cache.zig` | each subcommand's own flags |
| `src/thottam.zig` | thottam's flags |
| `src/completions.zig` | all six shell scripts, generated at comptime |

**Add a flag in one place and every one of those follows.** There is no second
list to update and no golden file to regenerate.

## The surface itself

`kaappi --help` is generated from the table and is the authority. This is the
annotated version — what each flag is *for*, and which document explains it.

### Global flags

| Flag | Notes |
|------|-------|
| `-h`/`--help`, `--version` | |
| `--lib-path <path>` | Prepends to the library search path |
| `--compile`, `-o <file>` | Compile to `.sbc`, or name the output |
| `--disassemble` | |
| `--no-ir-opt` | Disables the IR optimization passes, and skips the `.sbc` cache in **both** directions. Useful for miscompilation triage and `--disassemble` comparisons. The cache key folds in the git build id, so a rebuilt binary never serves the old binary's bytecode — the old "delete the cache before testing compiler changes" footgun is fixed (`cache.md`) |
| `--sandbox` | Restricts filesystem and process access |
| `--gc-stats`, `--profile` | |
| `--timings[=text\|json]` | Per-stage pipeline wall time (read/expand/lower/optimize/emit/execute, plus native `llvm-emit`/`link`) and cache HIT/MISS + path, all on stderr. Disjoint self-timed stages, zero overhead when absent — `timings.md` |
| `--coverage` | |
| `--diagnostics=<text\|json>` | JSON Lines of LSP `Diagnostic` objects on stderr — `diagnostics-json.md` |
| `--deny-warnings` | `check`-only: promotes lint warnings to errors |
| `--completions <shell>` | |

### Subcommands

| Subcommand | What it does | Doc |
|------------|--------------|-----|
| `compile <file> [-o out]` | Compiles to a native binary via LLVM | `llvm-backend.md` |
| `check <file>` | Compile-only static analysis — reads, expands, compiles, executes no program code (only the five `vm_eval.TopLevelHead.isEnvSetup()` declarations that later forms are compiled *against*, which `--compile` and `--disassemble` have shared since kaappi#2156). Reports read/compile errors plus the `KP4xxx` lint findings: unknown top-level variable (warning), arity or wrong-type-literal on direct built-in calls (errors). Honors `--diagnostics=json` and `--deny-warnings` | `check.md` |
| `explain <code>` | Prints a diagnostic's reference entry | `explain.md` |
| `features [--json]` | This build's capabilities — version + git build id, target triple, build mode, compiled-in subsystems (the KEP-0004 `cond-expand` identifiers, sharing `types.platform_features`), built-in vs portable SRFIs, initial VM/GC limits. All derived; no hardcoded second list | `features.md` |
| `test [paths…]` | Runs SRFI-64 suites (`--json`, `--seed <n>`, `--lib-path`), aggregating from the runner's own counters. `-j`/`--jobs <n>` runs files concurrently (default one per CPU; Windows always 1) with verdicts and output order identical at any job count, since each file was already its own worker process. `--changed`/`--list-affected` (with `--since <rev>`) select only suites whose R7RS import closure changed, falling back to a loud full run when the graph can't be trusted | `test-runner.md` |
| `ast\|expand\|ir <file>` | Read-only pipeline-stage dumps. `ast` prints post-read datums (`read`+`write`); `expand` prints the program after full macro expansion (round-trips); `ir` prints the IR tree (`--no-opt` = before the optimization passes). None executes program code | `observing-the-pipeline.md` |
| `doctor [--json]` | Installation/environment self-check (binary, library search path, thottam state, native backend + smoke link, REPL, FFI), printing `PASS`/`WARN`/`FAIL` per check with a fix for each failure. Exit is nonzero only on `FAIL` | `doctor.md` |
| `fmt [--check] files…` | The canonical, comment-preserving formatter: 2-space R7RS indentation, single-space separators, closing parens gathered, reflowed to 80 cols. Rewrites in place (or formats stdin to stdout); `--check` writes nothing and exits nonzero listing paths that need formatting. Every write is guarded by a real-reader `equal?` round-trip, so it can never change a program | `fmt.md` |
| `cache status\|clear` | Inspects and wipes the central bytecode cache. `status` prints location, entry count, total size, and per entry the size, producing build id (current vs. stale) and source path. `clear` removes every entry — the supported way to wipe it, so you never need to know the path | `cache.md` |

### Environment

| Variable | Effect |
|----------|--------|
| `KAAPPI_LIB_DIR` | Overrides `libkaappi_rt.a` lookup |
| `KAAPPI_HOME` (default `~/.kaappi`) | Locates the bytecode cache (`$KAAPPI_HOME/cache`), installed libraries, and REPL history |

The version string is `pub const version` in `main.zig`.

## Why it exists

The completion scripts used to be hand-written string literals parallel to the
parsers — the same structural hazard as `isRejectedFormHead`
(`docs/dev/llvm-backend.md`) and the `%`-prefix incident: two lists that must
agree, with nothing enforcing it. They had drifted in **both** directions:

- `--no-ir-opt` was in the parser and in none of the three kaappi scripts.
- `kaappi test` grew `-j`/`--jobs`, `--changed`, `--list-affected` and
  `--since`; none of the three offered any of them, and only bash offered
  `--seed`.
- The zsh and fish scripts offered the whole global flag set inside
  `explain`, `features`, `test`, `doctor` and `cache` — 15 of which those
  subcommands' own parsers reject outright with exit 2. **Completing a flag
  that then errors is the worse failure**, and it was the larger of the two.

## The shape of the table

```zig
pub const GlobalId = enum { help, version_flag, /* … */ };

pub const global_flags = [_]Flag(GlobalId){
    .{ .long = "--sandbox", .id = .sandbox, .desc = "Restrict filesystem and process access" },
    .{ .long = "--lib-path", .id = .lib_path, .value = .separate, .kind = .dir,
       .value_name = "path", .desc = "Add a library search path (repeatable)" },
    .{ .long = "--diagnostics", .id = .diagnostics, .value = .inline_eq, .kind = .choice,
       .choices = &fmts, .value_name = "fmt", .desc = "…" },
    // …
};
```

`ValueSyntax` is what lets the table hold every spelling the CLI actually
accepts:

| Syntax | Example | Consumes the next argv word? |
|---|---|---|
| `.none` | `--sandbox` | no |
| `.separate` | `--lib-path <path>` | yes |
| `.inline_eq` | `--diagnostics=json` | no — bare `--diagnostics` is *not* a flag |
| `.inline_eq_optional` | `--timings`, `--timings=json` | no |

That last distinction is load-bearing in two directions. `--diagnostics=` and
`--timings` were previously matched by `std.mem.startsWith` *outside* the flag
table, because the old table had no way to say "GNU `=` syntax" — and that
escape hatch is precisely how they, and later `--no-ir-opt`, drifted out of
the completions. Encoding the syntax closes the hatch. It also makes the zsh
specs correct for the first time: an attached-only value is `--opt=-`, and
`::` marks it optional, so zsh now completes `--diagnostics=json` rather than
the separated `--diagnostics json` that the parser rejects.

## The gate

Three mechanisms, in order of how early they fire.

1. **A parse loop cannot see a flag that is not in a table.** Every loop
   dispatches on `switch (m.flag.id)` over that table's `Id` enum. Zig requires
   the switch to be exhaustive, so adding a row with a new id is a *compile
   error* until the parser handles it.

2. **A table cannot lag its enum.** The `comptime` block at the bottom of
   `cli_spec.zig` requires every `Id` variant to appear exactly once, rejects
   duplicate spellings, requires a `value_name` on any value-taking flag, and
   restricts descriptions to characters that need no quoting inside a zsh
   `'…[desc]'` spec or a fish `-d '…'` string.

3. **The scripts cannot lag the table**, because they are generated from it.
   `src/completions.zig`'s own tests then assert both directions anyway —
   every table flag appears in every script, and every `--word` token in every
   script names a declared flag — plus per-shell invariants (balanced quotes,
   ASCII only, the zsh `=-` spelling, the fish bare-`--timings` spelling).

`tests/scheme/completions/completions.sh` closes the loop against the **real
binary**: it sources the generated bash function, drives it per context, and
feeds every offered flag back to the binary, requiring that none of them comes
back named as `unknown option '<flag>'` / `unexpected argument '<flag>'` /
`unknown subcommand '<flag>'`. It carries its own discriminating control
(`kaappi features --sandbox` *must* be rejected, and the matcher must see it),
so a broken matcher cannot make the soundness checks pass vacuously.

All four were verified to fire by mutation:

| Mutation | Caught by |
|---|---|
| add a `GlobalId` variant with no table row | `cli_spec.zig` comptime: "frobnicate must appear exactly once" |
| add a table row for a flag the parser does not handle | `cli.zig`: "switch must handle all possibilities" |
| delete `--seed` from `test_flags` | `cli_spec.zig` comptime: "seed must appear exactly once" |
| drop `--no-ir-opt` from the top-level offer | `completions.zig` and `cli.zig` unit tests, and all three shell assertions |

## Scoping rules

`SubcommandDesc.global_flags_ok` records the one structural fact that decides
what is sound to offer where:

- **`true`** — `compile`, `check`, `ast`, `expand`, `ir`, `fmt`. `cli.parse`
  consumes these words itself and keeps using the *global* loop, so every
  global flag is legal after them.
- **`false`** — `explain`, `features`, `test`, `doctor`, `cache`. Each
  intercepts argv in its own module, before `cli.parse` runs, and rejects
  anything outside its own table. Their completions are scoped to that table:
  bash and zsh dispatch on the detected subcommand word, fish suppresses the
  global specs with `not __fish_seen_subcommand_from explain features test
  doctor cache`.

thottam's subcommands are all `true`: it parses one flat loop that keeps
scanning past the subcommand word, so `thottam install --locked pkg` is as
valid as `thottam --locked install pkg`.

## Adding a flag

1. Add the `Id` variant and the table row in `src/cli_spec.zig`.
2. Build. The compiler names the parse loop that must now handle it.
3. Handle it. Done — `--help`, all six completion scripts, and every test
   follow automatically.

For a flag that belongs to one subcommand only, put it in that subcommand's
table. For a global flag that is only *meaningful* under one subcommand — as
`--no-opt` (ir) and `--check` (fmt) are — leave it in `global_flags`, set
`top_level = false`, and name it in that subcommand's `globalSubset`: the
parser keeps accepting it anywhere (unchanged behaviour), while `--help` and
the top-level completion list stay uncluttered.

## Known limitations

`--no-opt` and `--check` carry `top_level = false`, which scopes them for
`--help` and the completions but **not** for the parser: the global loop still
accepts them anywhere. For `--check` that is a live hazard, since it is one
hyphen-pair from the `check` subcommand whose contract is that nothing
executes — `kaappi --check foo.scm` runs the program. Tracked as
[kaappi#2096](https://github.com/kaappi/kaappi/issues/2096); the scoping data
this fix would need already lives in `subcommands`.

fish has no way to express an optional attached value, so `--timings` is
emitted without `-r`: the bare spelling — the common one — completes, and
`--timings=json` still parses if a user attaches a value, but fish will not
suggest `text`/`json`. bash and zsh both offer the full set.
