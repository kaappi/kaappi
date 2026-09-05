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
`build.zig` appends the literal suffix whenever `git status --porcelain -uno`
prints anything — tracked changes only; untracked files are not part of a
tracked-source build's output, kaappi#2097). So every uncommitted state at the
same commit shares one build id:

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

The **CPU model** is not part of it either: `compile_target_id` hashes the
arch/os/abi triple plus `platform_features`, and none of those move when the
same target is tuned for baseline instead of the host's exact CPU. That is
what lets a `-Dbundle=` bundler — baseline by default since kaappi#2515, so
the standalone binary runs on other machines of the same architecture —
embed an `.sbc` produced by a plain host-tuned `kaappi --compile` from the
same tree, which is the documented two-command bundle flow.

A *filename* collision is self-correcting, never a wrong result: even if two
different source paths hashed to the same cache filename, the stored source
hash would not match, so the load misses and recompiles. The dirty-build-id
case above is different in kind — the key genuinely matches — which is why it
needs the manual step.

The header also records, purely for `cache status` to display, the **producing
build id** and the **source path**, and since format v14
([#2514](https://github.com/kaappi/kaappi/issues/2514)) the producing binary's
**compile target** and **version string** too — the last two so a rejected
embedded bundle can say *which* of the three compiler-key components differed
(`renderForeignBuildDiagnostic` in `src/bytecode_file_read.zig`, re-exported by
`src/bytecode_file.zig`; for a cross-target bundle the build id matches on both
sides, so it cannot carry the diagnosis alone). Older headers lack the last two
fields and read them back as absent: the reader accepts
`MIN_READ_VERSION..VERSION`, and anything older reads back as a miss.

That read window is narrower than it looks. Loading still requires the
compiler hash to match, and the hash folds in the version string and the build
id — so the only v13 entry that can *hit* under the v14 reader is one written
at the same commit and tree state, in practice a dirty build on the author's
own machine; for every released or per-commit binary a v13 entry is a miss
either way. What the window actually buys: a v13 embedded bundle still
classifies as a foreign build (and gets the "not recorded" advice rather than
"invalid"), `cache status` still parses v13 entries, and the checked-in
fuzz-seed fixture did not need regenerating. A format bump that changes the
entry *layout* must raise `MIN_READ_VERSION` (see the `VERSION` doc-comment)
and so invalidates every older entry.

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
- **Cached — top-level declarations, positionally
  ([#1888](https://github.com/kaappi/kaappi/issues/1888)):** `import`,
  `define-library`, `include`, `include-ci`, `define-record-type`,
  `define-values`, `begin`, and `cond-expand` at top level no longer refuse
  anything. A cold run records the *positional replay stream*: one slot per
  top-level form, either the compiled function or the declaration's verbatim
  source span. A HIT replays the slots in order, re-reading each declaration
  span and dispatching it through the same `handleTopLevelForm` path the cold
  run used — so an `(import ...)` between two defines stays between them (no
  preamble hoisting; the reorder class of
  [#2200](https://github.com/kaappi/kaappi/issues/2200) cannot arise), and a
  mid-file `define-values` keeps its position in the stream. Each declaration
  slot also carries the reader's fold-case state as of the form (a
  `#!fold-case` directive falls inside an earlier form's span), so a folded
  `(IMPORT ...)` is claimed as a declaration warm exactly as cold. The forms a
  declaration *interprets* (a top-level `begin`'s body, an included file's
  forms) are compiled fresh on a HIT exactly as on a miss — correct, just not
  cached.

  **Cached — `.sld` libraries ([#1888](https://github.com/kaappi/kaappi/issues/1888)):**
  a file-backed library load writes its own entry. The design is "structure
  from source, code from cache": the entry stores the compiled body
  functions, the macro transformers (`define-syntax`) as data, and an ordered
  event log; a HIT re-reads and re-parses the (hash-validated) `.sld`, walks
  its declarations through the ordinary loader — imports really load, exports
  are re-derived by name, `cond-expand` re-selects, `define-record-type` runs
  as data — but replays cached functions/transformers wherever the cold path
  compiled. Running the body against the reconstructed environment is what
  makes this safe where value-serialization cannot be: closures capture the
  live environment, record types and every other runtime value are created
  exactly as cold, and the export table comes out of the normal export-name
  lookup — so an export contributed by `include-library-declarations` or a
  `cond-expand` branch is present warm for the same reason it is present
  cold (the failure mode of the old, pre-#1888 cache-read path).

  Invalidation is layered on the key, and identically for libraries and
  programs: the entry records every include-family file the run read (path +
  content hash) and every file-backed dependency it resolved (relative path,
  resolved path, content hash), all re-validated before a warm replay starts.
  Editing an included file misses; editing a dependency misses *and* stales
  every entry that transitively imported it — a program's compiled slots
  embed imported-macro expansions just like a library body's, so a program
  entry goes stale on a library edit too. A dependency found already in the
  registry (loaded by an earlier import) is recorded through its
  `Library.source_path` provenance, so import ORDER cannot hide a dependency.
  A `--lib-path` change that re-resolves a dependency elsewhere misses. A library whose `cond-expand`
  consulted *library availability* (`(library …)` requirements, `srfi-<n>`
  feature ids) is never cached — that answer depends on the live
  registry/lib-path, not on anything a key can hash (platform-only features
  are compile-time constants already covered by the compiler hash).

- **Not cached — compile-time registrations
  ([#2112](https://github.com/kaappi/kaappi/issues/2112)):** a top-level
  `define-syntax` or `define-property` (or a macro use expanding into one)
  registers into the VM's macro / syntax-property tables as a side effect of
  compilation. A HIT compiles nothing, so it would not replay the
  registration and a run-time `eval` would diverge from the cold run; such
  files are refused instead (reason: `define-syntax`). This applies to the
  *main file's own* top level — macros *inside* a cached library are fine,
  because the library entry serializes the transformers themselves.
- **Not cached — compile errors:** if any top-level form fails to compile,
  nothing is written (reason: `compile error`) — a HIT would otherwise run the
  partial program with exit 0 and no diagnostic where the cold run reported
  the error with exit 1.
- **Not cached — constants past the format's limits
  ([#2113](https://github.com/kaappi/kaappi/issues/2113)):** the writer
  refuses anything the reader would reject — nesting deeper than 256 (a long
  *list* is fine: spines cost no depth), or an oversized
  string/vector/bytevector/bignum literal (reason:
  `constant exceeds .sbc limits`). Refusing at write time is what prevents
  the pathological alternative: an entry that recompiles and rewrites itself on
  every run, forever, while looking cached. The same contract covers the
  library sections (a procedural transformer whose `proc` the codec cannot
  represent, an unrepresentable constant, oversized event/include/deps
  tables): the library simply stays uncached.
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
  *selection* is a compile-time question). Until
  [#2156](https://github.com/kaappi/kaappi/issues/2156) those bodies — and a
  `define-values` producer — were evaluated for real, so
  `(begin (delete-file "x"))` deleted the file while producing the `.sbc` and
  again at run time from the preamble. `--disassemble` follows the same
  discipline.

  **The preamble replays in full before any compiled form**, so a recorded
  declaration does not keep its position in the program. That is harmless for
  the five env-setup heads — they are declarations, and hoisting them ahead of
  the compiled stream is what a preamble is for.

  `define-values` is **not** hoisted
  ([#2200](https://github.com/kaappi/kaappi/issues/2200)): its producer is
  arbitrary program code that can depend on an earlier top-level form, so
  reordering it would fail where the interpreter succeeds. It has a compilable
  lowering (`compileDefineValues` desugars it to `define` + `call-with-values` +
  `set!`), so `--compile` routes it through ordinary compilation and it keeps
  its position in the compiled stream, exactly like `begin`/`cond-expand`
  splicing does for their bodies.

  ```scheme
  (define x 1)
  (define-values (a b) (values x 2))   ; compiled in order, sees x = 1
  (display (list a b))
  ```

  Both the interpreter and the standalone binary print `(1 2)`. Before #2200
  the `define-values` was recorded in the preamble and replayed first, with `x`
  still unbound, so the binary failed with
  `preamble error[KP3001]: undefined variable 'x'` and exited 1.
  (The auto-run cache does not have this hazard: its slots are positional.)
- Sandboxed and WASM loads never touch the `.sld` cache, and neither do
  embedded or bundled library sources — only file-backed, non-sandboxed
  loads.

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
entry must actually HIT (a main-file entry via `cache: HIT`, a library entry
via `libcache: N hits`). The `.sld` half of the contract — dependency and
include staleness, export-set completeness across `include-library-declarations`
and `cond-expand`, `--lib-path` re-resolution — is pinned by
`tests/scheme/cache/library-cache-1888.sh`.

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
