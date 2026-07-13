# Vision & Philosophy

Why Kaappi exists, what it values, and how those values guide decisions.

---

## Why another Scheme?

Scheme has dozens of implementations. Most optimize for one end of a spectrum:
production-grade systems (Chez, Gambit) that are large and complex, or
pedagogical ones (SICP interpreters) that are small but incomplete. Kaappi
occupies a different point: a **complete R7RS-small implementation** that
remains **readable and hackable** as a single-person codebase.

The project started as an exercise in building a real language runtime from
scratch in Zig — not to compete with mature Schemes on performance, but to
prove that a single developer (with AI assistance) can build a complete,
correct, and useful Scheme without cutting corners on the spec.

---

## Core values

### 1. Correctness over cleverness

R7RS-small is the contract. Every identifier in Appendix A works. Tail calls
are proper, not optimistic. Continuations copy the full stack, not a subset.
Hygienic macros rename correctly even in edge cases nobody writes in practice.

When correctness and performance conflict, correctness wins. The default build
mode is ReleaseSafe — bounds checks and overflow detection stay on. Fixnum
overflow silently promotes to bignum rather than wrapping.

### 2. Completeness over minimalism

A Scheme that passes 90% of the spec is a toy. The last 10% — `dynamic-wind`
interacting with continuations, `syntax-rules` with nested ellipsis, proper
Unicode case-folding in identifiers — is where implementations diverge from the
standard. Kaappi does the last 10%.

This extends to the ecosystem: 72 SRFIs, a C FFI, a package manager, TCP/TLS
networking, database clients, a web framework. A language is only as useful as
the things you can build with it without leaving it.

### 3. Transparency over magic

The runtime should be understandable. The full pipeline — reader, expander,
compiler, VM, GC — fits in ~39k lines of Zig across files that stay under
1500 lines each. There are no generated parser tables, no hidden
meta-compilation steps, no dependencies beyond libc and a vendored line-editing
library.

You can trace any Scheme expression from source text to bytecode to execution
with `--disassemble` and the stepping debugger. The value representation is one
type (`u64`) with a NaN-boxing scheme that fits on a whiteboard.

### 4. Pragmatism over purity

Scheme is a minimal language by design, but real programs need batteries. Kaappi
ships built-in support for things the spec doesn't cover: hash tables (SRFI-69),
pattern matching via `syntax-rules`, OS threads (SRFI-18), filesystem access
(SRFI-170), and a C FFI for everything else.

The package manager exists because `(import (kaappi json))` should just work
after `thottam install kaappi-json`. The WASM build exists because a playground
in the browser is the fastest way for someone to try the language. These aren't
spec requirements — they're what makes a language usable.

### 5. Simplicity over abstraction

The codebase avoids abstraction layers that don't earn their keep. The GC is a
generational mark-and-sweep collector over an intrusive linked list: a young/old
split with an old→young write barrier — machinery that earned its place on
allocation-heavy workloads — but no read barriers and no copying or compaction
beyond that. The compiler lowers to an IR with analysis and optimization passes,
then emits bytecode. The LLVM backend compiles Scheme programs to native
executables via LLVM IR.

When something is slow, we measure first. The answer is usually "use
ReleaseSafe instead of Debug" or "the algorithm is O(n^2)", not "add a
compilation pass."

---

## Machine legibility

The third core value, transparency, is about the *implementation* being
understandable to a contributor reading the Zig. **Machine legibility** turns
that value outward: from a runtime transparent to the people who build it, to a
toolchain transparent to the programs that *drive* it. The audience is no longer
only the person tracing an expression with `--disassemble`; it is equally the AI
agent — or the human in a hurry — that runs `kaappi`, reads what comes back, and
acts on it without a human in the loop.

Stated as one sentence: **Kaappi aims to be the most legible Scheme — a complete
R7RS-small where every stage of the toolchain can explain itself, to a human in
prose and to a machine in stable, structured output.**

### The operational test

"Legible" is only worth anything if it can be falsified, so it reduces to a
concrete test:

> An agent can go from a failing program to a correct fix — *and know the fix is
> correct* — using only documented CLI output. No screen-scraping prose, no
> reading compiler source, no guessing.

Every feature under this banner either serves that test or it doesn't. A
friendlier error message an agent still has to pattern-match against English
fails it. A stable diagnostic code the agent can match exactly, explain offline,
and consume as JSON passes it. The test is what keeps "friendly for agents" from
degenerating into "prettier for humans."

### Three pillars

- **Diagnose** — the keystone. Stable, `KP`-prefixed codes on every reader,
  compile, and runtime error; structured `--diagnostics=json` in the LSP
  `Diagnostic` shape the language server already emits; exact source spans; a
  self-explaining registry (`kaappi explain KP3001`); and first-class test
  tooling (`kaappi test` with `--json`, `--seed`, `--changed`). The design is
  KEP-0005 ([kaappi/keps#18](https://github.com/kaappi/keps/pull/18)).
- **Understand** — introspection at every pipeline stage: `kaappi expand` /
  `ast` / `ir` alongside the existing `--disassemble`, so the pipeline diagram
  above is observable rather than described; `kaappi check` to compile and lint
  without running; `kaappi doctor` for environment self-checks; and honest crash
  reports in place of bare panics.
- **Automate** — deterministic, *visible* builds: cache hits and misses reported
  rather than silent, `.sbc` keys that can't lie about which compiler produced
  them; machine-readable capability discovery (`kaappi features --json`); and
  per-stage timings. The whole program is tracked in
  [kaappi#1503](https://github.com/kaappi/kaappi/issues/1503).

### Extension, not deviation

Machine legibility lives entirely in the space R7RS-small has no opinion on —
CLIs, diagnostic formats, caches, test runners, editor protocols. It follows the
same discipline as
[KEP-0004](https://github.com/kaappi/keps/blob/main/keps/0004-discoverable-deviations.md):
extend where the spec is silent, never deviate where it speaks. The non-goals
that hold that line are as much a part of this direction as the features:

- **No static type system, and no type annotations.** "Will this call fail?" is
  answered by lint-level analysis over the known primitives (`kaappi check`),
  not by inference or a new type language. R7RS is latently typed; Kaappi stays
  that way. This is the one idea on the original wishlist that would have been a
  true deviation, and it is declined on purpose.
- **No new surface syntax** for tooling's benefit — sources stay `.scm` and
  `.sld`.
- **No change to R7RS error semantics.** `error-object?`,
  `error-object-message`, and `error-object-irritants` keep their exact
  behavior; diagnostic codes are additive metadata reached through a new
  `(kaappi diagnostics)` library, never a change to `(scheme base)`.
- **No bespoke diagnostic schema** — structured output reuses the LSP
  `Diagnostic` shape, which the language server already serializes.
- **Fuzzing is settled, not aspirational.** The coverage-guided fuzzing
  infrastructure (seven targets, CI-integrated; see [fuzzing.md](fuzzing.md))
  already shipped. It is cited here as evidence the approach works, and its
  generators are reused — property-testing a formatter's idempotence, for one —
  not listed as future work.

---

## Design decisions and their rationale

### Register-based bytecode (not stack-based)

Register machines map naturally to the Scheme evaluation model where
intermediate results already have names (in `let` bindings) or positions (in
nested calls). Fewer instructions per operation, and the compiler can reason
about register lifetimes for tail-call optimization.

### NaN-boxing (not tagged pointers)

Flonums are unboxed — arithmetic on floating-point numbers has zero allocation
overhead. Fixnums get 48 bits of range before promoting to bignum. Booleans,
characters, nil, void, and eof are all immediates. The only heap allocations
are for compound structures (pairs, strings, vectors, closures).

### Generational mark-and-sweep GC (not copying)

Still mark-and-sweep in mechanism, but generational: a young/old split. Frequent
minor collections scan only the young objects — where most garbage dies — and
promote the ones that keep surviving into the old generation; periodic full
collections scan everything. The cost of the split is a write barrier on
old→young pointer stores, which records them in a remembered set so a minor
collection can treat them as roots without walking the old generation. In return,
allocation stays O(1) (bump a counter, check a threshold) and a minor collection
is O(live young objects) rather than O(all live objects) — the win on the
allocation-heavy workloads Scheme produces. There is still no compaction: a
copying collector would halve available memory, and fragmentation is possible but
hasn't been a problem in practice.

### Deep-copy threading (not shared-heap)

Each OS thread gets its own GC heap. Values crossing thread boundaries are
deep-copied. This eliminates all shared-mutable-state bugs and GC
synchronization overhead at the cost of copying data at thread boundaries.
For Scheme programs — which favor immutable data and message-passing — this
is a natural fit.

### Zig (not C, not Rust)

Zig gives manual memory control (necessary for a GC), comptime generics
(used throughout the type system), built-in cross-compilation (macOS builds
produce Linux and WASM binaries), and no hidden allocations or control flow.
The lack of a borrow checker is fine — the GC owns all heap memory, and the
`pushRoot`/`popRoot` discipline is simple enough to enforce by convention.

---

## What Kaappi is not

- **Not a production-optimized Scheme.** Chez Scheme will be faster. Kaappi
  prioritizes correctness and readability of the implementation over
  benchmark performance.

- **Not a research vehicle.** The goal is a solid, complete R7RS-small, not
  novel PL research. When the spec says how something should work, that's
  how it works.

- **Not a Scheme-flavored scripting language.** Kaappi follows R7RS closely.
  It doesn't add non-standard syntax, change evaluation order, or break
  compatibility for convenience.

---

## Guiding questions for decisions

When facing a design choice, these questions help:

1. **Does R7RS say what to do?** If yes, do that. Don't innovate on
   standardized behavior.

2. **Will a user hit this?** Invest effort proportional to how often real
   programs exercise a feature. `map` and `let` matter more than
   `call-with-current-continuation` edge cases — but the edge cases still
   need to be correct.

3. **Can someone new read this?** A contributor should be able to open any
   source file and understand what it does within a few minutes. If a
   function needs a paragraph of comments to explain, the function is too
   clever.

4. **Is this the simplest thing that works?** Not the most elegant, not the
   most general, not the most future-proof — the simplest. Add complexity
   only when a concrete problem demands it.
