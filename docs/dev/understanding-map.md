# Understanding Map

Where theory must live in a maintainer's head (**core tier**), and where a
contract makes shallow understanding a deliberate, safe choice (**fenced
tier**). This is the policy that turns "do I understand this codebase?"
from a source of anxiety into a portfolio decision.

## Why this exists

Most of this codebase is written in AI-assisted sessions. Code is generated
faster than a human forms a theory of it, and the gap is **cognitive
debt**: code you are responsible for without holding its model. (Naur,
*Programming as Theory Building*, 1985: the program is not the text — it is
the theory in the programmers' heads, and the text is a lossy projection.
AI-generated code is born without a theory-holder unless the human builds
one alongside.)

Not all of the gap needs paying down. We already run on oceans of code
nobody here understands (LLVM, libc, the kernel) — safely, because someone
else holds the theory and a contract fences the interface. Debt is only
un-understood code **on our side of the responsibility boundary**. So every
subsystem gets one of two legitimate treatments:

1. **Hold the theory** — invest in a real mental model (core tier).
2. **Build the fence** — put a contract (spec + tests) around it and
   deliberately stay shallow (fenced tier).

Trying to hold the theory of everything is also a failure mode: you drown,
and you re-serialize yourself as the bottleneck the tooling removed.

## The decision rule

```
understanding priority ≈ expected touches × boundary leakiness × centrality
```

- **Touches** — how often changes land there.
- **Leakiness** — whether its obligations bind code *outside* it (the GC's
  rooting rules bind every primitives file; a SRFI `.sld` binds nothing).
- **Centrality** — how much else breaks when its invariants do.

Pay down understanding where change is coming, not where anxiety is.

## What each tier obligates

|  | Core | Fenced |
|--|------|--------|
| Mental model | The theory: invariants, failure modes, design rationale | The contract: what it promises and how that's verified |
| PR review | Slow; predict the approach before reading the diff | Contract-first: does the fence (tests) still hold? |
| `/quiz` | Quizzed periodically | Not quizzed — not knowing is the point |
| AI sessions | End with a ≤3-line **theory delta** (what changed in the system's theory, not the repo) | Normal |

## Core tier

Seven subsystems. For each: where it lives, the theory to hold, and the
bug history that earned it core status — the recurring bug classes *are*
the leakiness measurement.

### 1. Value representation & heap-object layout

- **Where:** `src/types.zig`
- **Theory:** the NaN-boxing scheme (which payloads are immediate and why
  any non-NaN f64 is a flonum), fixnum range and bignum promotion, and the
  heap-Value convention: a heap Value carries the address of the `header`
  field — built with `makePointer(&x.header)`, recovered via
  `Object.as()`, never a direct cast.
- **Why core:** everything touches it, and layout mistakes corrupt
  silently and surface far away. #1618 (Value built from a struct pointer
  instead of its header) was fixed and then reified into a compile error
  (the `*Object` parameter, PR #1622). s390x is kept in CI purely as the
  byte-order canary for this layer (#1654).

### 2. GC: rooting, write barrier, generations

- **Where:** `src/memory.zig`, `src/gc_collect.zig`; rules in
  `.claude/rules/gc-safety.md`
- **Theory:** root-before-allocate, and why an unrooted fresh result dies
  between two allocations (#1414: every bignum/bignum division returned 1
  by aliasing); the write barrier's direction (old→young) and what a minor
  collection misses without it; copy-before-collect ordering inside
  allocators; why `vm_instance` is itself effectively a root (#1401);
  ephemeron/guardian processing during collection (SRFI-254).
- **Why core:** maximal leakiness — these rules bind every primitives file
  and every VM file, permanently. The gc-stress campaign (#1401) and the
  unrooted-desugar bug class exist because these obligations were held
  shallowly.

### 3. IR pipeline & the register/frame contract

- **Where:** `src/ir.zig`, `src/compiler_ir.zig`, `src/compiler.zig`
- **Theory:** the lowering shape (structured nodes vs. `sexpr_form`
  passthrough), what the 3 analysis passes establish (tail positions above
  all), what the 5 optimization passes are allowed to assume, and the
  contract emitted bytecode relies on from the VM: register file, frames,
  gap registers.
- **Why core:** every new form passes through it, and tail-position
  mistakes are semantic bugs, not slowdowns. The gap-register capture
  class (#1464, fixed by PR #1528 + `clearGapRegisters` #1529) came from
  holding the register contract shallowly.

### 4. Continuations & dynamic-wind

- **Where:** `src/vm_continuations.zig`
- **Theory:** stack-copying capture (what exactly is copied and when),
  wind-stack transitions, the invariant that a callee's return never
  unwinds the caller's winds, and the native-frame limit (a continuation
  captured under a native frame cannot be resumed after that frame
  returns).
- **Why core:** it interacts with everything — errors, fibers, the native
  backend — and wind bugs corrupt control flow in ways tests rarely catch
  on first contact.

### 5. Expander hygiene

- **Where:** `src/expander.zig`, `src/compiler_macro.zig`
- **Theory:** syntax-rules matching and template instantiation, free-ref
  collection (`computeBoundFreeRefs`, PR #1344), why renaming is the hard
  part, and where the current model's edges are.
- **Why core:** the one subsystem where bugs proved effectively unbounded —
  SRFI-257 was dropped (#1644) because each expander fix uncovered more.
  Judging which macro bugs are fixable vs. structural requires a real
  model, not pattern-matching on past fixes.

### 6. Fibers & the I/O reactor (KEP-0001)

- **Where:** `src/fiber.zig`, `src/reactor.zig`, `src/primitives_fiber.zig`
- **Theory:** park vs. drive-in-place (who is allowed to block and when),
  the yield-retry re-execution protocol and why partial progress must be
  stashed in `port.read_buf` first, the `driving_waits` abandonment rule
  (#1625), the lazy `O_NONBLOCK` flip as a capability probe, and the
  per-platform readiness models (kqueue / epoll / WASI `poll_oneoff` /
  `WSAEventSelect`).
- **Why core:** a distributed protocol across the scheduler, the reactor,
  and every port primitive; its failure mode is a hang — the least
  debuggable symptom there is. Even *stating* #1625's "port I/O abandoned"
  rule required holding the whole protocol at once.

### 7. Cross-thread ownership (SRFI-18)

- **Where:** `src/primitives_srfi18.zig`, deep copy in `src/memory.zig` /
  `src/gc_deep_copy.zig`
- **Theory:** per-thread VM+GC with deep copy at the boundaries (start and
  join) and why no heap value may cross otherwise; `Object.owner` and why
  a child's marking must skip parent-owned objects (#958); foreign-owner
  checks on fiber/channel primitives (#1484); the symbol-interning lock.
- **Why core:** violations are use-after-free across heaps — the
  worst-case debugging experience. The cross-thread named-helper hang
  (#1520) showed this model must be held, not rediscovered per incident.

## Fenced tier

| Area | The fence | Notes |
|------|-----------|-------|
| 68 portable SRFI `.sld`s | The SRFI documents (external spec) + `tests/scheme/srfi/` conformance suites | The ideal fence: a spec someone else wrote, mechanically checked |
| Primitive bodies (`src/primitives_*.zig`) | R7RS spec + audit suites (`tests/scheme/audit/`) + procedure coverage | The GC rules *inside* them stay core — see below |
| LLVM emitter mechanics (`src/llvm_emit.zig`) | Differential fence: native output must agree with the interpreter (parity tests) | The *strategy* layer is borderline — see below |
| Platform ports (`src/platform*.zig`) | The `platform.zig` facade + real-VM CI jobs per OS/arch | Per-OS theory lives in `docs/dev/<os>.md` |
| `.sbc` bytecode codec (`src/bytecode_file*.zig`) | Format contract + build-id cache keys (#1516) + round-trip | Build-id keys retired the stale-cache footgun class outright |
| `kaappi fmt` layout engine (`src/fmt_print.zig`) | Real-reader `equal?` round-trip: a formatter bug cannot change a program | A fence so strong even its author needn't trust the layout code |
| thottam (`src/thottam.zig`) | CLI contract + end-to-end install flows; blast radius contained to `~/.kaappi` | |
| Reader lexical syntax (`src/reader*.zig`) | R7RS §7.1 formal grammar + compliance tests | Borderline — see below |
| Bignum arithmetic (`src/bignum.zig`) | Audit tests against mathematical ground truth | #1414 lived here, but it was a GC-rule violation, not an arithmetic one |
| Vendored + generated (`vendor/linenoise/`, `src/unicode_tables.zig`) | Upstream project / the generator | Never hand-edit |

Anything unlisted defaults to fenced-if-tested. Being repeatedly surprised
by an unlisted area is evidence for promotion — change this map in the
same PR.

## Core rules run through fenced code

Fencing a *file* does not fence the cross-cutting rules that run through
it. The GC discipline (rooting, barriers, copy-before-collect) is core
even inside individually-fenced `primitives_*.zig` bodies — #1414 was a
GC-rule violation inside fenced bignum code. When a core rule and a fenced
file intersect, the rule sets the review depth.

## Fence integrity

A fence is only as strong as its enforcement:

- **Weakening or skipping tests silently promotes code to core.** A
  disabled conformance suite means someone must now hold that theory — and
  nobody decided to.
- **Edit fenced code contract-first**: write the failing test (the
  contract's missing clause), then change the code. Editing fenced code
  from "understanding" nobody holds, without strengthening the fence, is
  how debt compounds.
- **Tier changes are explicit.** Promote when a bug class recurs or
  obligations start leaking past the fence; demote when a machine-checked
  contract lands (see the ladder). Either way, edit this file in the same
  PR.

## The reification ladder

Every hard-won piece of theory should climb as high as it can:

| Rung | Form | Examples in this repo |
|------|------|-----------------------|
| 1. Tacit | In a head | Where all theory starts — and all debt |
| 2. Documented | Postmortems, `docs/dev/` | `gc-safety-and-error-handling.md`, `lessons-learned.md` |
| 3. Checklisted | Auto-loaded rules | `.claude/rules/gc-safety.md`, `compiler-forms.md` |
| 4. Machine-checked | Compile errors, stress builds, differential tests | The `*Object` param (#1618→#1622), `-Dgc-stress`, fmt's `equal?` round-trip, native/interpreter parity tests, build-id cache keys (#1516), the `(features)`-vs-table equality check (#1517) |

Rungs 2–3 are still consumed by trust; rung 4 no longer needs to be held
by anyone. **Every postmortem should end by asking: which rung did this
lesson reach, and can it go one higher?**

## Practices

The map is the *what*; these are the *how*. All four are prediction-first,
because understanding is built by generating answers, not by reading them.

1. **`/quiz <subsystem>`** — periodic prediction-with-commitment quiz on a
   core-tier subsystem, graded against the code and live runs, logged to
   `~/.kaappi/quiz-ledger.md`. The ledger is comprehension coverage.
2. **PR prediction line** — before reading an AI-authored diff that
   touches core tier, write one sentence: how do you think it solved it?
   The delta between guess and diff is the signal.
3. **Theory delta** — an AI session that touched core-tier files ends with
   ≤3 lines on what changed in the *system's theory* (new invariant,
   changed contract, retired assumption) — distinct from the changelog.
4. **Per-release retrieval note** — once per release, pick one core
   subsystem and write its theory from memory, ten lines, no peeking; then
   diff against `docs/dev/` and fix whichever side is wrong.

## Borderline calls

Classifications the maintainer should adjudicate (initial lean in
parentheses):

- **LLVM backend strategy** — the what-compiles-natively line, the boxing
  rule (#1497), the tailcc trampoline (#1499): core-adjacent theory even
  though emitter mechanics stay fenced by parity. (Lean: split exactly
  there — strategy core, mechanics fenced.)
- **Reader** — spec'd and conformance-tested like a fenced area, but
  hygiene's raw material (datum identity) originates here. (Lean: fenced;
  revisit if reader bugs ever leak into the expander.)
- **VM debugger (`src/vm_debug.zig`)** — low centrality, self-contained.
  (Lean: fenced.)
- **Bytecode ISA** — the opcode set vs. the dispatch loop. (Lean: the ISA
  contract is core-lite via `bytecode.md` + `/bytecode-isa`; the dispatch
  loop is fenced by the Scheme suites.)

## Status

Drafted 2026-07-19 by Claude (Opus 4.8) as part of the cognitive-debt
work; awaiting the maintainer's correction pass. Corrections to this map
are themselves retrieval practice — a wrong tier here is a bug, and the
map only becomes authoritative once a human has disagreed with it at
least once.
