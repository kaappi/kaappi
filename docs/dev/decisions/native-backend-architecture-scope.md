# Native-Backend Architecture Scope

**Decision** (2026-07-19): The LLVM native backend targets **aarch64 and
x86_64 only**. Interpreter-tier architectures — riscv64, and s390x/ppc64le
(#1654, #1657) — ship without `kaappi compile`, deliberately. Adding an
architecture to the native backend is a per-architecture engineering
project (days, dominated by triage and verification infrastructure), not a
checklist item, and there is no user demand paying for one. Revisit when a
concrete user needs native binaries on an interpreter-tier architecture;
riscv64 is the designated pathfinder if that happens.

Prerequisite shipped independently of any port: #1656 — `kaappi compile`
on an unsupported architecture must refuse loudly instead of linking a
binary that crashes (see "The failure mode that forced this decision").
**Done:** `llvm_emit.native_backend_supported` (the single source of truth
derived from `targetTriple`, so a future arch arm flips it automatically)
now gates both `emitLlvmFile` — which exits nonzero naming the arch and
pointing at the interpreter, before any codegen — and `kaappi doctor`,
which reports one honest `arch` WARN instead of a misleading PASS trio.

## Problem

[porting.md](../porting.md) shows CPU-architecture ports are nearly free:
riscv64, s390x, and ppc64le each needed **zero runtime code changes** —
the interpreter is portable by construction (no per-arch assembly, no
byte-punned values, GC never scans the machine stack). It is tempting to
conclude the native backend comes along equally cheaply, since the emitter
change looks tiny: add a triple to `emitPreamble`
([llvm_emit.zig](../../../src/llvm_emit.zig)) and decide
`fast_tailcalls_supported` (`false` is always safe — mutual tail calls
fall back to the #1499 trampoline; self-tail-calls compile as loops
regardless, and the `tailcc` fast entries are properly gated on the flag).

That conclusion is wrong, and we have the experiment that proves it.

## The failure mode that forced this decision

`emitPreamble` emits a real target triple only for aarch64/x86_64 (×
macos/linux/windows/freebsd/openbsd/netbsd). Every other architecture
gets `target triple = "unknown-unknown-unknown"` — and **no
`target datalayout` at all** (no arch gets one today). The `-w` on the
`zig cc` link then lets the driver silently override the mismatched
triple with the host default, so on an interpreter-tier box the link
*succeeds*.

Verified 2026-07-19 on riscv64 (Alpine container under QEMU, riscv64 Zig
0.16 as the C compiler, cross-built `libkaappi_rt.a`), with a program
squarely inside the natively-compiled feature set (self-tail-call loop +
closure):

```
$ kaappi compile hello.scm -o hello
Compiled hello              # ~29 s under TCG, warm caches
$ ./hello
Segmentation fault (core dumped)
```

Compile-and-link success on an unsupported architecture is therefore
**worse than failure**: the user gets a crashing binary with no hint the
target was never supported. That is what #1656 fixes, independent of
whether any port ever happens.

## Why "add the triple" is not the port

Four challenge layers, in increasing order of long-term cost:

### 1. Correctness triage with hostile ergonomics

The riscv64 segfault above has no root cause yet, and finding it is
representative: optimized cross-compiled codegen, debugged under QEMU
TCG, where the toolchain itself is a standing suspect — the Windows port
lost days to an LLVM TLS miscompile inside the shipped `zig.exe`
(#1613), and the runtime's `threadlocal vm_instance` makes TLS-model
choice a live risk on every new target. The #1654 validation also showed
the triage tooling itself degrades per-arch: Zig 0.16's panic unwinder
prints `(empty stack trace)` on ppc64le (no frame-walk support), while
s390x unwinds with a trailing "unwind info unavailable" warning. On one
of the two candidate targets, the primary debugging tool is missing.

### 2. The runtime tether multiplies the correctness surface

Native binaries are not standalone. They re-enter the interpreter
constantly — 21 C-ABI exports in
[runtime_exports.zig](../../../src/runtime_exports.zig), plus the
`kaappi_eval`/`kaappi_eval_cached` fallback for every form the backend
doesn't compile natively. "Native backend works on arch X" therefore
means *codegen × C-ABI contract × runtime library* all agree on X. Each
factor is individually probable (LLVM's SystemZ and PPC64 ELFv2 ABIs are
mature; the runtime library's unit suite passes on both targets — #1654
ran it), but the product of three "probablies" is exactly what the e2e
suite exists to test, and nothing else substitutes for it.

### 3. Per-architecture LLVM feature variance

`musttail`/`tailcc` codegen quality is per-target (the reason
`fast_tailcalls_supported` exists); RISC-V support is recent LLVM work
and s390x/ppc64le are less trodden still. A proper port also emits the
correct **datalayout** alongside the triple, so codegen stops depending
on driver-side defaults. s390x adds the byte-order dimension: NaN-boxing
at the IR level is endian-neutral (pure i64 register ops — the same
reason the interpreter passed unmodified), but every place the emitter
or the quote cache (#1495) materializes constants into memory needs the
same explicit-byte-order discipline the `.sbc` codec has. "Probably
fine" is not the standard; the s390x e2e run is.

### 4. The verification bill, then the permanent tax

[porting.md](../porting.md)'s bar for the native tier is the e2e suite
(`tests/e2e/`, 37 programs, each a full `kaappi compile` + execute
cycle) **on the target**, plus CI so it doesn't rot. The compile step is
the expensive part and it runs on the target side: ~29 s per program
under TCG with warm caches, i.e. a 30–60+ minute emulated CI job per
architecture, versus ~12 minutes for the entire interpreter-tier job.
The realistic alternative is IBM's free hosted runners for Power/Z
(`power-z-gha-runner` GitHub App) — real hardware, but its own
enrollment and maintenance project.

The tax then never ends: the native backend is the fastest-moving part
of the codebase (#1492–#1500 all landed within weeks), and every
supported architecture multiplies the test matrix of every future
backend PR. The interpreter tier costs nothing ongoing precisely because
it has no per-arch code to break; the native tier institutionalizes
per-arch variance forever.

## If the decision is ever revisited

Order is forced by difficulty: **riscv64 first** (little-endian, the
most mature LLVM target of the three, an existing QEMU CI lane, and a
live segfault repro to start from), ppc64le second, s390x last. The
per-arch checklist extends porting.md's native-backend section: real
triple **and datalayout** in `emitPreamble`; a deliberate
`fast_tailcalls_supported` decision; root-cause the unknown-triple
segfault rather than assuming driver override was the only bug; e2e
suite green on the target; a CI story (emulated job or IBM runners); and
the support-matrix/docs updates. Budget days per architecture, dominated
by items one and four.
