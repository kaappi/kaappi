# riscv64 native backend: the July segfault was #1808, not the triple

Investigation behind the riscv64 native-backend port (2026-09-14). The
2026-07-19 decision record
([native-backend-architecture-scope.md](../decisions/native-backend-architecture-scope.md))
rested on an experiment: on a riscv64 box, `kaappi compile` of a
self-tail-call loop plus a closure linked successfully and segfaulted, and
the record attributed that to the emitter's `unknown-unknown-unknown`
triple being silently overridden by the `-w` link. The port re-ran the
experiment and found a different bug.

## Status

**Resolved** (2026-09-14). `llvm_emit.targetTriple` returns
`riscv64-unknown-linux-gnu` for riscv64 × linux, which flips
`native_backend_supported` there; `fast_tailcalls_supported` stays `false`
on riscv64. The e2e suite (37 programs plus the argv passthrough) passes
under QEMU with the release's own artifacts, and CI's `riscv64-native-test`
job keeps it that way via `tests/e2e/run-e2e-cross.sh`.

(2026-09-19: superseded on the tail-call point by kaappi#2602 — riscv64 now
has padded `fastcc` fast entries with a guaranteed `musttail`, every define
that names another user function compiles natively there, and
`run-e2e-cross.sh` checks the stack stays flat on a 1 MB guest stack. See
llvm-backend.md, "Per-target gate". The rest of this record stands.)

## What the July experiment actually showed

Three runs on riscv64 (Ubuntu 24.04 builder image under QEMU user-mode,
`kaappi` and `libkaappi_rt.a` cross-built with `-Dtarget=riscv64-linux`,
the image's riscv64 Zig 0.16 as the C compiler):

1. **Today's emitter, unknown triple, `-w` link** — the exact pre-#1656
   path. The driver warns `overriding the module target triple with
   riscv64-unknown-linux6.12.13-gnu2.39.0` (visible without `-w`), links,
   and the binary runs correctly. On a riscv64 host the "host default" the
   driver substitutes *is* riscv64, so the override was never the wrong
   target. The same holds with the `target triple` line deleted outright.
2. **The 2026-07-19 tree (commit 935a9869, #1659) with only the riscv64
   triple arm added** — the repro shape, at three loop counts:

   ```console
   $ kaappi compile loop.scm -o old && ./old
   42          # (make-adder 5) applied to 37
   1000        # (count-up 1000 0)
   100000      # (count-up 100000 0)
   Segmentation fault (core dumped)   # (count-up 10000000 0)
   ```

3. **Today's emitter, same program** — all four lines, exit 0.

A crash that depends on the iteration count, with a correct triple, on a
loop that carries a rooted call per pass, is #1808: every pass of a native
self-tail-call loop grew the machine stack by that call's `alloca`
footprint (root-push slots, argument arrays), because `alloca` frees at
function *return*, never at "next iteration", until the 8 MB main-thread
stack overflowed. #1813 fixed it on 2026-07-28 — nine days after the
decision — by bracketing each pass with `llvm.stacksave`/`stackrestore`.
The bug was arch-independent; the aarch64 and x86_64 e2e programs simply
never iterated far enough to hit it, and the riscv64 experiment happened
to. The decision record's instruction to "root-cause the unknown-triple
segfault rather than assuming driver override was the only bug" was
right; the answer was already in the tree by the time anyone looked.

## What the port needed

- `targetTriple`: one arm. `emitPreamble` reads it; `native_backend_supported`,
  the `kaappi compile` refusal, and the `doctor` WARN all derive from it
  (#1656), so nothing else in the gate changed. The `doctor` and refusal
  message texts name the new arch.
- No `target datalayout`, for riscv64 or anyone: none of the twelve
  existing triples emit one, the driver's default for a triple is by
  construction the one its own LLVM expects, and a pinned string is
  *less* portable across driver versions (LLVM 19 added `-Fn32` to the
  AArch64 layout; LLVM 17 changed RISC-V's `n64` to `n32:64`). A
  mismatch is a hard `clang` error, so pinning would break the BSD hosts
  that link with an older base `clang` and gain nothing on the `zig cc`
  route. The decision record's "real triple **and datalayout**" item is
  withdrawn on that basis.
- `fast_tailcalls_supported` left `false` (at the time — see the Status
  note): riscv64 gets the single
  uniform entry per function and a best-effort `tail call` hint, so
  mutual recursion has no constant-stack guarantee there (the #1499
  `@name.fast` entries and their `@name` trampolines are not emitted at
  all on such hosts). The port was scoped to interpreter parity —
  `native-mutual-tail.scm` checks output, not stack depth. Enabling
  `musttail`/`tailcc` on RISC-V is its own step, with the suite re-run on
  the target.
- Verification with both archive ABIs: the musl-static
  `-Dtarget=riscv64-linux` archive `release.yml` ships (linked on-target
  against glibc by the image's `zig cc`, which is what a riscv64 distro
  user gets) and a `-Dtarget=riscv64-linux-gnu` archive. 38/38 each.
- An on-target `kaappi compile` takes ~19 s under TCG on an M-series host
  (and the interpreter build would take hours), so the CI job does not
  build or link on the target. `run-e2e-cross.sh` cross-builds and
  cross-links on the host — the IR is target-independent text until the
  link — and emulates only the cross-built `kaappi` (oracle and
  `--emit-llvm`; the emitter is a comptime switch on the *host* arch, so
  the IR must come from a kaappi that believes it is riscv64) and the
  linked binaries, plus one genuine on-target `kaappi compile` as a smoke.

## Lesson

A crash on a *new* target is not evidence about the port until the same
program has been run on an established target at the same scale. The
July experiment's program had never been run at its loop count on
aarch64 or x86_64; had it been, #1808 would have been found on the
primary platform and the riscv64 result would have read as "works". See
[lessons-learned.md](../lessons-learned.md).
