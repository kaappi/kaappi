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

The codebase avoids abstraction layers that don't earn their keep. The GC is
mark-and-sweep with an intrusive linked list — no generational promotion, no
read barriers, no write barriers. The compiler is a single-pass tree walker,
not an SSA-based optimizer. The JIT compiles hot loops to native code with a
straightforward template approach — no IR, no register allocator.

When something is slow, we measure first. The answer is usually "use
ReleaseSafe instead of Debug" or "the algorithm is O(n^2)", not "add a
compilation pass."

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

### Mark-and-sweep GC (not copying/generational)

Simplicity. A copying collector would halve available memory. A generational
collector adds write barriers to every mutation. Mark-and-sweep is O(live objects)
for collection and O(1) for allocation (bump a counter, check threshold). The
tradeoff is no compaction — fragmentation is possible but hasn't been a problem
in practice.

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
