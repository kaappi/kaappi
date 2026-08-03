# The `.sbc` bytecode cache

A plain `kaappi file.scm` run compiles the source (read → expand → IR →
bytecode) and then caches the result, so a second run of the same file skips
the whole pipeline and executes the cached bytecode directly. The cache is
transparent to correctness — a miss just recompiles — but an *invisible* cache
is a hazard: a stale entry that silently runs the wrong bytecode manufactures
phantom bugs and masks real fixes. This page is the contract: what the key
contains, what invalidates an entry, where entries live, and how to inspect,
clear, or bypass the cache.

Part of the machine-legibility epic
([#1503](https://github.com/kaappi/kaappi/issues/1503)); tracked in
[#1516](https://github.com/kaappi/kaappi/issues/1516).

## The key: source **and** compiler

An entry is reused only when **both** halves of its key match the current run:

1. **Source hash** — a hash of the exact source bytes. Edit the file, miss.
2. **Compiler hash** — a hash of the release version string, the **git build
   id** (short `HEAD` hash, with a `-dirty` suffix when the working tree had
   uncommitted changes at build time; `unknown` when git was unavailable),
   and the **compile target** — the triple plus the compile-time feature set
   `cond-expand` is resolved against (`compile_target_id` in
   `src/bytecode_file.zig`; [#2155](https://github.com/kaappi/kaappi/issues/2155)).

The build id is the important half for contributors. Before #1516 the compiler
half hashed only the *version string*, which does not change between rebuilds
during development — so a freshly rebuilt `kaappi` would silently execute
bytecode compiled by the **previous** binary. The standing workaround was
"delete the cache before testing compiler changes," which was tribal knowledge.
Folding the build id into the key covers the committed cases:

- A different commit → different `HEAD` hash → **miss**.
- Clean vs. dirty tree at the same commit → different id → **miss**.
- Two clean builds of the *same* commit → same id → a hit is safe (identical
  compiler), so CI builds and installed releases can share entries.

### The one case it does *not* cover: two dirty builds

`-dirty` is a **flag, not a hash of the working tree** (`gitBuildId` in
`build.zig` appends the literal suffix whenever `git status --porcelain`
prints anything). So every uncommitted state at the same commit shares one
build id:

```text
edit A, uncommitted, at 370d8e85  →  370d8e85-dirty
edit B, uncommitted, at 370d8e85  →  370d8e85-dirty   ← identical
```

The id changes on the first clean→dirty transition and then stays put no
matter how many further edits you make. Two rebuilds of *different*
uncommitted compiler changes therefore **share cache entries**, and the
second one can execute bytecode the first one produced.

This is the original footgun surviving in the case contributors hit most —
iterating on uncommitted changes — and it is worst during A/B work, where
toggling between two versions (`git stash`, `git checkout <sha> -- <path>`)
makes the same input file answer differently across otherwise-identical
rebuilds. It reads exactly like nondeterminism in the code under test.

**Run `kaappi cache clear` after every rebuild when A/B-testing compiler
changes, or measure with `--no-ir-opt`, which bypasses the cache in both
directions.** See [performance.md](performance.md) for the full A/B protocol.

### Why the target is part of the key

Bytecode is not target-independent: `cond-expand` is resolved at compile time
against `types.platform_features` and only the taken branch survives into the
`.sbc`. All 17 platform binaries in a release are built from one clean
checkout, so before [#2155](https://github.com/kaappi/kaappi/issues/2155) they
shared one compiler hash and would happily load each other's bytecode — the
reachable case being `kaappi --compile` on POSIX feeding
`zig build -Dbundle=out.sbc -Dtarget=<windows>`, where every
`(cond-expand (windows …) (posix …))` inside a procedure had already been
decided the wrong way. Folding the triple *and* the feature list into the key
turns every such pair into an ordinary miss (or, for a `-Dbundle` of a
cross-target artifact, a loud "invalid embedded bytecode" instead of silent
wrong branches), and hashing the feature list means the key also reacts the
day a feature identifier becomes arch- or OS-gated in a way the triple alone
would not capture.

Byte order is *not* part of this: `.sbc` scalars are canonically little-endian
through explicit conversions, pinned against committed golden bytes in
`src/tests_endian.zig` (audit v2 Phase 7D) so a swap on either side — or on
both — fails on every host.

A *filename* collision is self-correcting, never a wrong result: even if two
different source paths hashed to the same cache filename, the stored source
hash would not match, so the load misses and recompiles. The dirty-build-id
case above is different in kind — the key genuinely matches — which is why it
needs the manual step.

The header also records, purely for `cache status` to display, the **producing
build id** and the **source path** (see `src/bytecode_file.zig`, format
`VERSION`). Bumping the on-disk format `VERSION` invalidates every older entry —
a version mismatch reads back as a miss.

## Location

Entries live in a single directory:

```text
$KAAPPI_HOME/cache        # if KAAPPI_HOME is set
~/.kaappi/cache           # otherwise
```

Each entry is named by a hash of the **absolute** source path
(`<16-hex>.sbc`), so the same file resolves to one entry regardless of the
directory you invoke it from, and distinct files never collide. If no home
directory can be resolved (neither `KAAPPI_HOME` nor `HOME` set), caching is
silently disabled and every run compiles from source.

This is a change from the pre-#1516 layout, where the cache was written *next
to* the source as `file.sbc`. A central store is what makes `cache status` /
`cache clear` coherent — one location to inspect and one command to wipe.

## What is and isn't cached

- **Cached:** a plain `kaappi file.scm` run of a program that none of the
  refusals below applies to. `--timings` names the refusal that fired
  (`not cached: <reason>`).
- **Not cached — top-level forms the VM handles directly:** one occurrence of
  any of `import`, `define-library`, `include`, `include-ci`,
  `define-record-type`, `define-values`, `begin`, or `cond-expand` at top
  level skips caching for the whole file — every other form in it included.
  These eight are `vm_eval.TopLevelHead`, the set `handleTopLevelForm`
  claims; `--timings` names the one that fired (`not cached: top-level
  cond-expand`). Until
  [#2114](https://github.com/kaappi/kaappi/issues/2114) it reported all eight
  as `imports`, so a file with no `import` in it was told an import was the
  cause.

  They are refused for one shared reason: `handleTopLevelForm` *interprets*
  such a form and appends no `Function` to the run's compiled list, so a HIT —
  which compiles nothing — would skip that form's work entirely. (The separate
  hazard that library loading can free collected function pointers is real,
  but specific to the three heads that load libraries.)

  The rule is **top-level head position only**. The same constructs nested
  inside a body are ordinary code and leave caching alive:

  ```scheme
  (define (a) (begin 1 2 3))                     ; still cacheable
  (define (b) (cond-expand (else 'chosen)))
  (define (c) (define-values (x y) (values 1 2)) (+ x y))
  ```

- **Not cached — compile-time registrations
  ([#2112](https://github.com/kaappi/kaappi/issues/2112)):** a top-level
  `define-syntax` or `define-property` (or a macro use expanding into one)
  registers into the VM's macro / syntax-property tables as a side effect of
  compilation. A HIT compiles nothing, so it would not replay the
  registration and a run-time `eval` would diverge from the cold run; such
  files are refused instead (reason: `define-syntax`).
- **Not cached — compile errors:** if any top-level form fails to compile,
  nothing is written (reason: `compile error`) — a HIT would otherwise run
  the partial program with exit 0 and no diagnostic where the cold run
  reported the error with exit 1.
- **Not cached — constants past the format's limits
  ([#2113](https://github.com/kaappi/kaappi/issues/2113)):** the writer
  refuses anything the reader would reject — nesting deeper than 256 (a long
  *list* is fine: spines cost no depth), or an oversized
  string/vector/bytevector/bignum literal (reason:
  `constant exceeds .sbc limits`). Refusing at write time is what prevents
  the pathological alternative: an entry that recompiles and rewrites itself
  on every run, forever, while looking cached.
- **Not the cache:** `kaappi --compile file.scm [-o out.sbc]` writes an
  *explicit* bytecode artifact you named — for embedding into a standalone
  binary via `zig build -Dbundle=out.sbc`, not for the auto-run path. It is
  never read as the run-cache, so `--no-ir-opt --compile` can't poison a plain
  run.

  `--compile` does **not** run the program. Of the eight heads above it
  evaluates only the five `TopLevelHead.isEnvSetup()` names — the declarations
  later forms are compiled *against* (`import`, `include`, `include-ci`,
  `define-library`, `define-record-type`) — and records them in the artifact's
  preamble for replay. `begin` and `cond-expand` are spliced into the form
  stream so their bodies are compiled (only a `cond-expand`'s branch
  *selection* is a compile-time question), and a `define-values` is recorded
  without its producer expression being evaluated. Until
  [#2156](https://github.com/kaappi/kaappi/issues/2156) all three were
  evaluated for real, so `(begin (delete-file "x"))` deleted the file while
  producing the `.sbc` and again at run time from the preamble — and, because
  the preamble replays entirely *before* the compiled forms, a top-level
  `begin` also ran out of program order in the artifact. `--disassemble`
  follows the same discipline.
- `.sld` library loads are never cached in either direction.

## Inspect, clear, bypass

```bash
kaappi cache status    # location, entry count, total size, and per entry:
                       #   size, producing build id, current/stale, source path
kaappi cache clear     # remove every entry (the supported way to wipe it)
```

`cache status` marks each entry **current** (produced by the running binary,
so a plain run of its still-unchanged source would hit), **stale** (produced
by some other build — it will be re-compiled on next use), or **unloadable**
(produced by this build but rejected by the loader — truncation, corruption,
or a writer/reader drift; it can never hit). "Current" is verified, not
assumed: the entry's body is dry-run through the deserializer, because a
header alone cannot distinguish a hit-to-be from an entry that recompiles
forever ([#2113](https://github.com/kaappi/kaappi/issues/2113)). Both
subcommands are pure filesystem queries — no VM — and operate only on `*.sbc`
files in the cache directory (`cache clear` never touches anything else).

Bypass the cache entirely with either of:

- `--no-ir-opt` — disables the IR optimization passes and skips the cache in
  both directions (no read, no write), so a no-opt run neither reuses optimized
  bytecode nor writes unoptimized bytecode a later run would load.
- `--sandbox` — no filesystem side effects, so no cache read or write.

## Transparency guarantees

A HIT must behave exactly like a MISS — stdout, exit code, *and* diagnostics.
Three properties of the constant codec exist specifically for this
(format v11):

- **Immutability** ([#2110](https://github.com/kaappi/kaappi/issues/2110)):
  literal constants carry their `Object.flags.immutable` bit, so a `set-car!`
  on a literal raises KP3002 warm exactly as cold.
- **Sharing** ([#2111](https://github.com/kaappi/kaappi/issues/2111)):
  datum-label structure (`'(#1=(1 2) #1#)`, cycles included) round-trips via
  back-references as the *same* object, so `eq?` and `write-shared` agree
  across a HIT, shared DAGs stay linear on disk, and cyclic literals load.
- **Error locations** ([#1922](https://github.com/kaappi/kaappi/issues/1922)):
  the HIT path feeds runtime-error reporting the same per-form fallback line
  (`Function.source_line`) the fresh-compile path uses, so an error with no
  line-table entry (`raise`, division by zero) keeps its `file:line` and
  source snippet.

`tests/scheme/differential/run-differential.sh` enforces all of this per run:
cold vs. warm must agree byte for byte over the corpus, and every written
entry must actually HIT.

## For contributors

You no longer need to delete the cache before testing compiler changes: a
rebuild changes the build id, so the new binary cannot serve the old binary's
bytecode. If you want to observe a from-scratch compile anyway (e.g. comparing
`--disassemble` output), `--no-ir-opt` skips the cache, or `kaappi cache clear`
wipes it.

The `kaappi test` and legacy `run-all.sh` suites point `KAAPPI_HOME` at a
throwaway directory so a suite run never reads or pollutes your real cache.

Implementation: `src/cache.zig` (location policy + the subcommand),
`src/bytecode_file.zig` (`compilerHash` / `compilerHashFor`, the header format,
`readHeaderInfo`). HIT/MISS visibility under `--timings` is tracked separately
in [#1515](https://github.com/kaappi/kaappi/issues/1515).
