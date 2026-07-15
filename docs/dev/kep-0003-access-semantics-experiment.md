# KEP-0003 access-semantics codegen experiment (kaappi#1473)

**Status: aarch64-macos complete (timing + evidence); x86_64-linux codegen
evidence complete via cross-compile; x86_64-linux *timing* a documented
follow-up.** This is method **step 2** of research problem
[P1](https://github.com/kaappi/keps/blob/main/research/open-problems.md#p1--racing-element-access-semantics-for-shared-buffers)
(KEP-0003 Unresolved Question 2). It answers, by the **pre-registered
criteria** (not by prediction), whether shared flat-buffer element access must
compile to `unordered` atomics — and what that costs.

The reading is **hybrid** (native-tier plain codegen + interpreter-tier
`unordered`, soundness carried by KEP-0002 channel happens-before edges): on
every ceiling-validated kernel, `unordered` element access costs far more than
the registered 10 % threshold — from **+55 %** (f64 map, CI lower bound) to
**+2747 %** (u8 fill) on aarch64-macos — with the same codegen gap confirmed on
x86_64-linux. The harness, raw CSVs, and metadata are under
[`benchmarks/access-semantics/`](../../benchmarks/access-semantics/).

## What this is, and the one rule that governs it

The [P1 constraints memo](https://github.com/kaappi/keps/blob/main/research/p1-access-semantics.md)
(step 1) rejected plain-accesses-everywhere *a priori* on Boehm-2011 grounds
(LLVM's NotAtomic contract returns `undef` under a race and licenses load
re-introduction, so the bounds-check/index split breaks VM memory safety even
for flat byte data — memo §3), established that `unordered` implements
KEP-0003's promise in LLVM's own words at zero *instruction* cost, and left the
real cost — optimizer inhibition, chiefly auto-vectorization and the
memset/memcpy libcall idiom — to be **measured**. This is that measurement.

The decision criterion is quoted verbatim and is the only thing that governs
the outcome:

> If `unordered` element access costs < 10 % on the vectorizable kernels, take
> it unconditionally (full memory-safety, no caveats). If it costs more than
> that, adopt the hybrid and require the guide to state the overlapping-slices
> caveat in its first paragraph. Plain-accesses-everywhere is rejected *a
> priori* on Boehm 2011 grounds. An `Atomics`-style ordered subset is out of
> scope for v1 either way.

Per memo §9.1, **"vectorizable kernels" means kernels whose plain build
demonstrably hits a fast path** (vectorization *or* the memset/memcpy libcall
idiom the doc's prohibited-transforms list names). A kernel whose plain build is
already scalar carries no ceiling and is excluded — it is a control, not
evidence.

## Pipeline fidelity

The experiment compiles through Kaappi's **exact** native pipeline:
`zig cc -w -O2`, the flags in
[`src/native_compiler.zig`](../../src/native_compiler.zig) `tryLink` (the `-O2`
choice and its rationale are documented there and in #1492). `kaappi compile`
searches `zig`, `cc`, `clang`, `gcc` in order and picks the first found; on both
reference machines that is `zig cc`, so the compiler under test is the shipping
one.

Because KEP-0003's `shared-f64vector`/`shared-bytevector` do not exist yet
(building them is #1475, *gated on this experiment*), the kernels are emitted as
LLVM IR matching KEP-0003's stated element-access lowering — "a single aligned
load/store of the element width": a counted loop whose body is one
`getelementptr <elemty>` + one `load`/`store`, generated so the three encodings
of a kernel are **mechanically identical IR except the atomic annotation**
([`gen_kernels.py`](../../benchmarks/access-semantics/gen_kernels.py)). The
payload-pointer unmask and per-access bounds check a real `-ref`/`-set!` carry
are loop-invariant and hoisted, so they do not affect inner-loop vectorization;
the clean counted loop is the **ceiling** each encoding is measured against.
Realizing that ceiling is therefore a normative requirement on KEP-0003's
lowering (see *Threats to validity*), not an assumption hidden in the harness.

**aarch64-macos reference machine** (`benchmarks/access-semantics/results/macos-aarch64-metadata.txt`):
Apple M3 Pro, 12 physical cores, L1d 64 KiB / L2 4 MiB / 36 GiB RAM;
Darwin 25.5.0; `zig` 0.16.0 with `zig cc` = Homebrew clang/LLVM 21.1.8; kaappi
`9e797a76`; ReleaseSafe for the interpreter-tier VM leg. Sizes 16 KiB / 512 KiB
/ 8 MiB / 64 MiB span L1 / L2 / LLC-edge / DRAM on this machine.

## Step 9.1 — baseline validity (does the pipeline vectorize the plain baseline?)

The gating pre-check: an `unordered`-costs-<10 % pass against a
*never-vectorizing* baseline would be vacuous. It is not — Kaappi's pipeline
vectorizes or idiom-izes the plain baseline on 5 of 6 kernels. Classification is
from each kernel's disassembly
([`evidence.sh`](../../benchmarks/access-semantics/evidence.sh)): genuine
vectorization = lane-suffixed arithmetic or a vector store (a bare vector *load*
does not count — see f64 sum); LIBCALL = a memset/memcpy-family call.

| Kernel | aarch64 plain | x86_64 plain † | unordered / monotonic (both) |
|--------|---------------|----------------|------------------------------|
| f64 fill | **LIBCALL** `memset_pattern16` | **VECTOR** | SCALAR |
| f64 map | **VECTOR** | **VECTOR** | SCALAR |
| f64 sum (strict) | SCALAR — *drops out* | SCALAR — *drops out* | SCALAR |
| i64 checksum | **VECTOR** | **VECTOR** | SCALAR |
| u8 fill | **LIBCALL** `memset` | **LIBCALL** `memset` | SCALAR |
| u8 copy | **VECTOR** | **VECTOR** | SCALAR |

† x86_64 by cross-compile (`zig cc -target x86_64-linux-gnu -w -O2`); asm
classified, not run. CSVs: `results/evidence-darwin-arm64.csv`,
`results/evidence-linux-x86_64-crosscompiled.csv`.

Three readings:

- **Every `unordered` and `monotonic` build is SCALAR, on every kernel, on both
  targets.** The atomic annotation forecloses the loop vectorizer (which refuses
  atomics at any ordering — the `-Rpass-missed=loop-vectorize` remark says "loop
  not vectorized" for exactly these builds) *and* the memset/memcpy libcall
  idiom, uniformly.
- **The fast path is platform-specific; the gap is universal.** f64 fill hits
  Darwin's `memset_pattern16` libcall on aarch64 but plain SIMD stores on
  x86_64. Either way the plain baseline gets a fast path `unordered` never does.
- **f64 sum drops out exactly as the memo predicted.** Kaappi's `+` is strict
  left-to-right, so no encoding — plain included — may reassociate the f64
  reduction into vector arithmetic. Its plain build uses vector *loads*
  (`ldp q`) feeding *scalar* `fadd`, which is not a vectorized reduction. It is
  the internal control; the integer checksum (reassociation legal) is the
  reduction gap carrier.

Ceiling-validated set (carry the <10 % criterion): **f64 fill, f64 map, i64
checksum, u8 fill, u8 copy**. Excluded control: **f64 sum**.

## Step 9.2 / 9.3 — timing (ns per element)

Full Kalibera–Jones discipline
([`run-access.py`](../../benchmarks/access-semantics/run-access.py), mirroring
`benchmarks/gate/run-gate.py`): two levels (fresh process × in-process
iteration), floors **20 invocations × 10 iterations**, mean + 95 % **bootstrap**
CI over invocation means, **never best-of-N, no outlier discard**, per-invocation
cell-order shuffle and a random-length dummy env var (the Mytkowicz
environment-size effect), ASLR left on, one driver binary per cell with no LTO.
`cost% = (ns_enc − ns_plain)/ns_plain × 100`, CI by independently resampling the
two arms' invocation means (unpaired: they are different processes).

**aarch64-macos, `unordered` vs plain** (full per-size table:
`results/macos-aarch64-access.csv`; `monotonic` within noise of `unordered`
throughout):

| Kernel | ceiling | cost range (16 KiB→64 MiB) | worst-case CI lower bound |
|--------|---------|----------------------------|---------------------------|
| f64 fill | memset_pattern16 | **+142 % … +270 %** | ≥ +133 % |
| f64 map | SIMD ×2 stream | **+61 % … +95 %** | ≥ +55 % |
| i64 checksum | SIMD reduction | **+162 % … +334 %** | ≥ +151 % |
| u8 fill | memset | **+1968 % … +2747 %** | ≥ +1767 % |
| u8 copy | SIMD/memcpy | **+550 % … +847 %** | ≥ +524 % |
| f64 sum *(control)* | — (drops out) | **−5 % … +3 %** | straddles 0 |

Every ceiling-validated kernel's cost is an **integer factor**, not a
percentage — the memo's standing prediction confirmed. The **memset/memcpy u8
kernels gap widest** (up to ~29×), also as predicted: `unordered` forbids the
libcall conversion outright, a mechanism beyond vectorization loss. The one
kernel that costs "only" tens of percent, f64 map, still has a CI lower bound of
+55 % — 5.5× the threshold. The control, f64 sum, costs ~0 with a CI that
straddles zero: **where the plain build has no fast path, `unordered` is free —
the harness is not manufacturing a gap.**

## Step 9.4 — interpreter-tier control

Expected Δ ≈ 0 (dispatch dominates). Confirmed three ways
([`interp/`](../../benchmarks/access-semantics/interp/)):

1. **Instruction identity.** An aligned scalar `unordered` access lowers to the
   *same machine instruction* as plain: `prim_ref` is `ldrb w0, [x0, x1]` and
   `prim_set` is `strb w3, [x0, x1]` byte-for-byte under both encodings. Zero
   cost by construction.
2. **Dispatch-model microbench.** Element access behind an opaque, volatile
   indirect call (one call per element — the model of every `-ref`/`-set!` as a
   NativeFn dispatch): plain→unordered Δ = **−0.16 %** (ref) / **−0.14 %** (set)
   at ~0.81 ns/call — within noise. This is a *conservative* floor: a bare
   indirect call is far cheaper than real VM dispatch.
3. **Real VM throughput** (ReleaseSafe): `bytevector-u8-ref` **107.6 ns/call**,
   `bytevector-u8-set!` **106.9 ns/call**. Real dispatch is ~130× the
   dispatch-model floor and ~1000× the native access-level difference. The
   ordering annotation is unobservable at dispatch scale.

**Consequence for the hybrid:** the interpreter tier uses `unordered`
unconditionally (free, full memory-safety); only native-compiled loops observe
the difference.

## Step 9.5 — the criterion applied

> If `unordered` element access costs < 10 % on the vectorizable kernels, take
> it unconditionally … If it costs more than that, adopt the hybrid …

`unordered` costs **+55 % to +2747 %** (CI lower bounds) on the five
ceiling-validated kernels — every one statistically resolved far above 10 %.
Plain-accesses-everywhere remains rejected *a priori*. `monotonic` matches
`unordered` on cost while over-promising per-location coherence KEP-0003's
contract does not want (memo §5) — dominated, not chosen.

**Reading: the hybrid.** Not the prediction — the numbers.

## The hybrid, made normative (for the KEP-0003 amendment)

Precisely (memo §6):

- **Interpreter primitives use `unordered` always** (free, §9.4).
- **The LLVM backend compiles `-ref`/`-set!` to plain accesses.** Soundness
  shifts from per-access to whole-program: KEP-0003's semantics hold for
  executions that are data-race-free at element granularity, with happens-before
  supplied by KEP-0002 (envelope push/pop under the `SharedChannel` mutex + the
  §5 notifier `acq_rel` protocol — the edge structure the P2 TLA+ model checks).
  DRF programs are indistinguishable from the `unordered` build; racing programs
  get LLVM-level UB.
- **The guide sentence weakens.** "the race is *your* nondeterminism, not
  undefined behavior" becomes false as written for the native tier and must
  carry a DRF proviso **in the shared-buffer documentation's first paragraph**
  (the pre-registered condition).

Three **containments**, to be specified in the amendment and costed where
measurable:

1. **Debug and `--gc-stress` builds compile buffer access `unordered`
   regardless** — races stay *defined* in exactly the builds that hunt
   corruption, so a misbehaving program under test yields wrong numbers, not a
   corrupted VM. (Cost is the §9.4 interpreter-tier result: free at those
   builds' scale; and these builds already forgo native-tier vectorization.)
2. **`(kaappi parallel)` slice helpers take disjoint ranges by construction and
   assert disjointness at submission time** — making the blessed
   fill-your-slice idiom mechanically safe and confining the UB surface to
   hand-rolled index arithmetic.
3. **The guide documents the hole is *per element*, not per buffer** — distinct
   elements never interfere; false sharing is a performance topic, not a
   correctness one.

## Threats to validity

- **IR faithfulness / bounds-check hoisting.** The kernels are the *ceiling*: a
  counted loop with no per-iteration bounds check, because a real slice loop's
  bounds check is loop-invariant and standard check-motion hoists it. If
  KEP-0003's actual lowering emits a per-iteration trap the optimizer cannot
  prove removable, the plain baseline would under-vectorize and the *measured*
  gap would shrink — but so would the plain fast path the whole KEP is chasing.
  This makes **"the SharedBuffer lowering must present a counted loop with a
  hoisted bounds check and a raw element GEP"** a normative implementation
  requirement of #1475, not a harness assumption. The gap direction is
  unaffected either way (atomic never vectorizes).
- **x86_64 timing deferred.** The x86_64 *codegen* gap is confirmed (same
  vectorizable/scalar split on every kernel, cross-compiled); only the ns/element
  *magnitudes* are unmeasured on real x86_64 hardware. The decision is a codegen
  property of LLVM (the loop vectorizer refuses atomics regardless of target), so
  the direction cannot flip; per the P5 cross-machine rule the magnitudes should
  still be filled from a real x86_64 box before the classification is called
  cross-machine-agreed. Follow-up: run
  `bash benchmarks/access-semantics/run-all.sh linux-x86_64 full` on the Linux
  reference machine and add the table. This mirrors the KEP-0002 gate
  worksheet's "macOS filled, Linux pending" precedent.
- **LLVM 21 vs the memo's probe LLVM 22.** Minor-version difference; the
  vectorizer's refusal of atomics is long-standing and reproduces here on 21.1.8.
- **The FFI path is identical under every candidate** (memo §7) and is not part
  of this experiment: C code handed the payload pointer performs NotAtomic
  accesses no matter what Kaappi emits; the hand-off discipline (no concurrent
  access across an FFI call) is a KEP-0003 lifetime rule, not a codegen choice.

## Resolution

KEP-0003 UQ 2 resolves to the **hybrid**, by the pre-registered criteria. The
amendment PR in the keps repo makes the access semantics normative (the hybrid +
its three containments + the weakened guide sentence) and reduces the P1 section
of `research/open-problems.md` to a pointer at the memo and this report. The
`Atomics`-style ordered subset stays out of scope for v1 (revisit only with a
concrete user demand), and `monotonic` is recorded as dominated.

## Reproduce

```bash
cd benchmarks/access-semantics
bash run-all.sh macos-aarch64 full          # env → build → evidence → timing
bash interp/run-interp.sh ../../zig-out/bin/kaappi   # interpreter-tier control
# x86_64 codegen evidence (cross-compile, no run) is in results/evidence-linux-x86_64-crosscompiled.csv
```

## Provenance

- Criteria (pre-registered): keps `research/open-problems.md` P1 (registered
  2026-07-12); refinements in `research/p1-access-semantics.md` §9.
- Statistics discipline: keps `research/benchmarks/README.md` §4 (the same
  protocol Phase 7 registers), via `benchmarks/access-semantics/run-access.py`.
- Feeds: the KEP-0003 UQ 2 resolution — keps amendment PR making access
  semantics normative + `open-problems.md` P1 reduced to a pointer.
