# P1 access-semantics codegen experiment (kaappi#1473)

Step 2 of research problem **P1** (KEP-0003 Unresolved Question 2): does shared
flat-buffer element access have to compile to `unordered` atomics to be sound,
and if so, what does that cost the numeric inner loops KEP-0003 exists to serve?

This directory is the codegen experiment the
[P1 constraints memo](https://github.com/kaappi/keps/blob/main/research/p1-access-semantics.md)
§9 refined and the
[pre-registered P1 criteria](https://github.com/kaappi/keps/blob/main/research/open-problems.md#p1--racing-element-access-semantics-for-shared-buffers)
decide. The write-up is
[`docs/dev/kep-0003-access-semantics-experiment.md`](../../docs/dev/kep-0003-access-semantics-experiment.md).

## What it measures

Six numeric kernels × three element-access encodings, compiled through Kaappi's
**exact native pipeline** — `zig cc -w -O2`, the flags in
[`src/native_compiler.zig`](../../src/native_compiler.zig) `tryLink` — then
inspected for vectorization and timed per element.

| Kernel | Shape | Idiom exercised |
|--------|-------|-----------------|
| `f64_fill` | `out[i] = c` | splat / `memset_pattern` |
| `f64_map` | `out[i] = a*x[i] + b` | two-stream vectorization |
| `f64_sum` | `acc += x[i]` (strict) | reduction — **drops out** unless FP reassociates |
| `i64_checksum` | `acc += x[i]` (integer) | reduction (reassociation legal) |
| `u8_fill` | `out[i] = c` | `memset` |
| `u8_copy` | `out[i] = in[i]` | `memcpy` |

Encodings: `plain` load/store · `unordered` atomic · `monotonic` atomic. The
hybrid candidate (d) *is* plain codegen (a semantics choice, not a fourth
build), so it shares the `plain` numbers.

### Why LLVM IR, not Scheme

KEP-0003's `shared-f64vector`/`shared-bytevector` do not exist yet — this
experiment is what gates building them (#1475). So the kernels are emitted as
LLVM IR matching KEP-0003's stated element-access lowering ("a single aligned
load/store of the element width"): a counted loop whose body is one
`getelementptr <elemty>` + one `load`/`store`. That IR is compiled by the same
`zig cc -w -O2` the backend shells out to. The payload-pointer unmask and the
bounds check that a real `-ref`/`-set!` carry are loop-invariant and hoisted, so
they do not affect inner-loop vectorization; the clean counted loop is the
**ceiling** each encoding is measured against (memo §9.1 "ceiling-validated").
Realizing that ceiling makes "KEP-0003's lowering must present a counted loop
with a hoisted bounds check" a normative requirement, recorded in the report.

## Files

| File | Role |
|------|------|
| `gen_kernels.py` | emits the 18 kernel `.ll` files; the three encodings of a kernel differ only in the atomic annotation |
| `driver.c` | common timing driver (ns/element); linked once per kernel object, no LTO |
| `build.sh` | `python3 gen_kernels.py` + `zig cc -w -O2` compile/link of all 18 binaries |
| `evidence.sh` | classifies each kernel's disassembly VECTOR / LIBCALL / SCALAR (memo §9.1) |
| `run-access.py` | Kalibera–Jones timing driver — invocations × iterations, bootstrap CIs, shuffle + env-size randomization (mirrors `../gate/run-gate.py`) |
| `run-all.sh` | record env → build → evidence → timing, into `results/<machine>-*` |
| `interp/` | interpreter-tier control (memo §9.4): dispatch-model plain-vs-unordered + real `bytevector-u8-ref/-set!` throughput |
| `results/` | per-machine CSVs, evidence, metadata |

## Reproduce

```bash
# aarch64-macos (or any host: uses the host zig cc / target)
bash run-all.sh macos-aarch64 full
# interpreter-tier control (optional real-VM leg needs a kaappi binary)
bash interp/run-interp.sh ../../zig-out/bin/kaappi
```

Requires `zig` 0.16 (`zig cc`), `python3` + `numpy`, and `llvm-objdump`/`objdump`.
The statistics protocol (two-level invocation × iteration, bootstrap 95% CIs,
no best-of-N, order + environment-size randomization, floors 20 × 10) is the
same one Phase 7 pre-registers in
[keps `research/benchmarks/README.md` §4](https://github.com/kaappi/keps/blob/main/research/benchmarks/README.md).
