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

```text
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

- **Where:** `src/types.zig` (`Value`, `Object`/`ObjectTag`, type
  predicates); individual heap-type structs are split across 12
  `types_*.zig` domain files (kaappi#1731), re-exported from `types.zig`
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
  `.claude/rules/gc-safety.md`; the collector as built in
  [memory.md](memory.md)
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

- **Where:** `src/ir.zig`, `src/compiler_ir.zig`, `src/compiler.zig`; the
  VM side of the contract in [vm.md](vm.md)
- **Theory:** the lowering shape (structured nodes vs. `sexpr_form`
  passthrough), what the tail-position analysis pass establishes, what the
  5 optimization passes are allowed to assume, and the
  contract emitted bytecode relies on from the VM: register file, frames,
  gap registers, the in-place frame reuse of the tail-call opcodes, and the
  `returns_to_native` rule (a frame whose result belongs to a Zig caller
  must not deliver it into whatever bytecode frame sits below once that
  caller is gone — #1377, #2453). The opcode set itself is *not* theory to
  hold: it changed three times in September 2026 (`apply`, `values_list`,
  `guard_builtin`) and is a same-build contract keyed into the `.sbc`
  cache; what an opcode does to the register window is, and that is what
  the rows above are.
- **Why core:** every new form passes through it, and tail-position
  mistakes are semantic bugs, not slowdowns. The gap-register capture
  class (#1464, fixed by PR #1528 + `clearGapRegisters` #1529) came from
  holding the register contract shallowly.

### 4. Continuations & dynamic-wind

- **Where:** `src/vm_continuations.zig`; [vm.md](vm.md)
- **Theory:** stack-copying capture (what exactly is copied and when),
  wind-stack transitions, the invariant that a callee's return never
  unwinds the caller's winds, and the native-frame limit (a continuation
  captured under a native frame cannot be resumed after that frame
  returns).
- **Why core:** it interacts with everything — errors, fibers, the native
  backend — and wind bugs corrupt control flow in ways tests rarely catch
  on first contact.

### 5. Expander hygiene

- **Where:** `src/expander.zig`, `src/compiler_macro.zig`;
  [expander.md](expander.md)
- **Theory:** syntax-rules matching and template instantiation, free-ref
  collection (`computeBoundFreeRefs`, PR #1344), why renaming is the hard
  part, and where the current model's edges are. Since PR #1811 also the
  procedural-transformer path (SRFI 211/213): `expandProceduralMacro`'s
  threadlocal per-invocation ER context, why `rename` *is*
  `renameForHygiene` under a fresh scope (procedural macros inherit
  exactly the engine's syntax-rules hygiene strength, holes included),
  and why import copies a procedural transformer's *whole* def_env where
  template macros get a free-ref scan — their references are computed by
  running code, so no static scan exists.
- **Why core:** the one subsystem where bugs proved effectively unbounded —
  the first attempt at SRFI-257 (#1644) was abandoned because each expander
  fix uncovered another; the port that eventually shipped (PR #1678) took
  seven of them. Judging which macro bugs are fixable vs. structural
  requires a real model, not pattern-matching on past fixes.

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

### 8. Native backend strategy (not emitter mechanics)

- **Where:** the gating and re-lowering layer of `src/llvm_emit*.zig` and
  `src/native_compiler.zig`; [llvm-backend.md](llvm-backend.md)'s first
  three rules
- **Theory:** the what-compiles-natively line and the three gates that
  decide it (`ir.eval_fallback_form_names`, `isRejectedFormHead`,
  `LLVMEmitter.lexicalNames`, all comptime-derived since #1896); that the
  backend re-derives lexical scope because every lambda body it is handed
  is still a raw S-expression, so `LLVMEmitter.lowerScoped` is the *only*
  way to re-lower a sub-form; the boxing rule (#1497) and the tailcc
  trampoline (#1499); and that native code side-exits to the VM for
  `call/cc` ([decisions/continuation-strategy.md](decisions/continuation-strategy.md)).
- **Why core:** each rule was learned by the same bug recurring at a new
  site — the lexical-scope rule at seven (#2117, #2118, #2211), the gate
  rule each time a hand-kept parallel list drifted. And the fence below it
  is blind to a whole class: a `.scm` regression test is interpreter-only
  evidence, and three of them passed for years while the native tier
  failed them. Someone has to hold *where* the fence does not reach.
- **The mechanics stay fenced:** instruction selection, register
  allocation and calling-convention emission are checked by 39
  `tests/scheme/compile/*.sh` scripts that assert on `--emit-llvm` output
  and by the nightly VM-vs-native differential fuzz
  (`tests/fuzz/native-diff.sh`). Edit those contract-first.

## Fenced tier

| Area | The fence | Notes |
|------|-----------|-------|
| 165 portable SRFI `.sld`s | The SRFI documents (external spec) + `tests/scheme/srfi/` conformance suites | The ideal fence: a spec someone else wrote, mechanically checked |
| Primitive bodies (`src/primitives_*.zig`) | R7RS spec + audit suites (`tests/scheme/audit/`) + procedure coverage | The GC rules *inside* them stay core — see below |
| LLVM emitter mechanics (`src/llvm_emit*.zig`) | Differential fence: 39 `compile/*.sh` IR-assertion scripts + nightly `native-diff.sh` fuzz | The *strategy* layer is core #8 |
| Platform ports (`src/platform*.zig`) | The `platform.zig` facade + real-VM CI jobs per OS/arch | Per-OS theory lives in `docs/dev/<os>.md` |
| `.sbc` bytecode codec (`src/bytecode_file*.zig`) | Format contract + build-id cache keys (#1516) + round-trip | Build-id keys retired the stale-cache footgun class outright |
| `kaappi fmt` layout engine (`src/fmt_print.zig`) | Real-reader `equal?` round-trip: a formatter bug cannot change a program | A fence so strong even its author needn't trust the layout code |
| thottam (`src/thottam.zig`) | CLI contract + end-to-end install flows; blast radius contained to `~/.kaappi` | |
| VM debugger (`src/vm_debug.zig`) | `tests/scheme/smoke/step-debug-mode-823.sh` | Adjudicated fenced 2026-09-14 (below). The fence is one script — extend it before changing behaviour |
| Dispatch loop mechanics (`src/vm_dispatch.zig`) | The Scheme suites + `native-diff.sh` + the Chibi oracle (`oracle-diff.sh`) + `ensureOperands` validating every arm against `fixed_operand_bytes` | The register/frame *contract* an arm must honour is core #3 |
| Reader lexical syntax (`src/reader*.zig`) | R7RS §7.1 grammar + `compliance/reader-*.scm` + the incomplete-input prefix sweep (`tests_reader_incremental.zig`) + `fuzz reader` | Adjudicated fenced 2026-09-14 (below); its one leaky *product* is a core rule — see the next section. [reader.md](reader.md) |
| Bignum arithmetic (`src/bignum.zig`) | Audit tests against mathematical ground truth | #1414 lived here, but it was a GC-rule violation, not an arithmetic one |
| Generated (`src/unicode_tables.zig`) | The generator | Never hand-edit |
| Vendored (`vendor/isocline/`) | Upstream project | Patched — every local change is marked `KAAPPI PATCH` and documented in `vendor/isocline/PATCHES.md`. Re-apply on update; do not edit casually. |

Anything unlisted defaults to fenced-if-tested. Being repeatedly surprised
by an unlisted area is evidence for promotion — change this map in the
same PR.

## Core rules run through fenced code

Fencing a *file* does not fence the cross-cutting rules that run through
it. The GC discipline (rooting, barriers, copy-before-collect) is core
even inside individually-fenced `primitives_*.zig` bodies — #1414 was a
GC-rule violation inside fenced bignum code. When a core rule and a fenced
file intersect, the rule sets the review depth.

A second rule of the same kind, learned in September 2026: **a datum
walker is not finished until it survives `#0=(a . #0#)`.** The reader is
fenced, and it correctly produces cyclic data for R7RS datum labels; what
leaked was every downstream walker's assumption that data is acyclic —
`rename` in an ER macro (#2403, critical), `compare` and the `set!`
pre-scan (#2404), and `lowerWithMacros` itself (#2405, critical). The rule
belongs to whoever writes a walk over user data, in any file:
[reader.md](reader.md) lists the walks that have learned it.

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

## Adjudicated calls

The four classifications the draft left open, decided 2026-09-14 by the
decision rule above and the evidence in the tree at that date. Each names
the trigger that would reopen it.

- **LLVM backend strategy → core (#8); emitter mechanics stay fenced.**
  Touches are high (the gate work of #2467/#2469/#2481 all landed in one
  fortnight), the strategy's rules are leaky (the lexical-scope rule
  recurred at seven sites), and the parity fence has a documented blind
  spot (`.scm` tests are interpreter-only evidence). Reopen if the three
  gates and `lowerScoped` reach rung 4 — a comptime check that rejects a
  bare `ir.lowerSingleExpr*` in the emitter would demote the strategy.
- **Reader → fenced; the cyclic-datum rule → core, cross-cutting.** The
  draft's own revisit trigger fired: reader products reached the expander
  and compiler as #2403–#2405. But the reader's contract held — the
  datum was correct — and the fence has since grown a rung-4 instrument
  of its own (the prefix-sweep invariant for incomplete input). What
  leaked was a rule about walking data, which is why it is recorded under
  "core rules run through fenced code" rather than by promoting the file.
  Reopen if a reader defect (not a consumer's assumption) recurs across
  releases.
- **VM debugger → fenced.** 336 lines, three touch points in the dispatch
  loop, no bug class in the record. The fence is a single smoke script,
  which is thin: a change to stepping or breakpoints is edited
  contract-first by extending that script. Reopen only if it ever gains
  a second consumer.
- **Bytecode ISA → not a tier of its own.** The draft's "core-lite" has no
  obligations attached, and the opcode *set* is the wrong thing to hold:
  it moved from 31 to 34 in one month and is a same-build contract, not a
  stable one (KEP-0021's first open question). What must be held is what
  an opcode does to the register window and the frame — and that is core
  #3, now stated there and described in [vm.md](vm.md). The dispatch
  loop's mechanics are fenced by three independent oracles (table above).
  Reopen if the ISA is ever declared stable, at which point the set itself
  becomes a contract to document and version.

## Status

Drafted 2026-07-19 by Claude (Opus 4.8) as part of the cognitive-debt
work; the four open calls were adjudicated 2026-09-14 (above), at the
maintainer's request, against the tree at that date. The tier assignments
remain a reading of the code, not a ruling from first principles. Corrections to this map are themselves retrieval practice — a wrong
tier here is a bug, so fix it in place, and record why in the section it
belongs to.
