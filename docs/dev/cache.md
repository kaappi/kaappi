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
2. **Compiler hash** — a hash of the release version string **and the git build
   id** (short `HEAD` hash, with a `-dirty` suffix when the working tree had
   uncommitted changes at build time; `unknown` when git was unavailable).

The build id is the important half for contributors. Before #1516 the compiler
half hashed only the *version string*, which does not change between rebuilds
during development — so a freshly rebuilt `kaappi` would silently execute
bytecode compiled by the **previous** binary. The standing workaround was
"delete the cache before testing compiler changes," which was tribal knowledge.
Folding the build id into the key removes the footgun by construction:

- Rebuild after any edit → dirty tree → build id changes → **miss**.
- A different commit → different `HEAD` hash → **miss**.
- Clean vs. dirty tree at the same commit → different id → **miss**.
- Two clean builds of the *same* commit → same id → a hit is safe (identical
  compiler), so CI builds and installed releases can share entries.

A collision is self-correcting, never a wrong result: even if two different
source paths hashed to the same cache filename, the stored source hash would not
match, so the load misses and recompiles.

The header also records, purely for `cache status` to display, the **producing
build id** and the **source path** (see `src/bytecode_file.zig`, format
`VERSION`). Bumping the on-disk format `VERSION` invalidates every older entry —
a version mismatch reads back as a miss.

## Location

Entries live in a single directory:

```
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

- **Cached:** a plain `kaappi file.scm` run of a program that does **not**
  `import`. (Programs that import are skipped: library loading can free
  collected function pointers, so their top-level functions are not safe to
  serialize after the fact.)
- **Not the cache:** `kaappi --compile file.scm [-o out.sbc]` writes an
  *explicit* bytecode artifact you named — for embedding into a standalone
  binary via `zig build -Dbundle=out.sbc`, not for the auto-run path. It is
  never read as the run-cache, so `--no-ir-opt --compile` can't poison a plain
  run.
- `.sld` library loads are never cached in either direction.

## Inspect, clear, bypass

```
kaappi cache status    # location, entry count, total size, and per entry:
                       #   size, producing build id, current/stale, source path
kaappi cache clear     # remove every entry (the supported way to wipe it)
```

`cache status` marks each entry **current** (produced by the running binary, so
a plain run of its still-unchanged source would hit) or **stale** (produced by
some other build — it will be re-compiled on next use). Both subcommands are
pure filesystem queries — no VM — and operate only on `*.sbc` files in the cache
directory (`cache clear` never touches anything else).

Bypass the cache entirely with either of:

- `--no-ir-opt` — disables the IR optimization passes and skips the cache in
  both directions (no read, no write), so a no-opt run neither reuses optimized
  bytecode nor writes unoptimized bytecode a later run would load.
- `--sandbox` — no filesystem side effects, so no cache read or write.

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
