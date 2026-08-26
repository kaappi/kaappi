# Porting to a new OS or CPU architecture

How Kaappi's existing platform support is structured, and staged checklists
for bringing up a new operating system or a new CPU architecture. The
completed ports are the reference material: **Windows aarch64**
(#1606, #1608, #1609 — the OS-port exemplar, documented in
[windows.md](windows.md)),
**wasm32-wasi** (KEP-0001 Phase 4 — the capability-degradation exemplar),
**riscv64-linux** (the CPU-architecture exemplar, tested under QEMU),
**s390x-linux** (the big-endian exemplar — the first byte-order-flipped
target, which the interpreter passed unmodified; #1654) with its
little-endian sibling **ppc64le-linux**,
**FreeBSD** (the POSIX-audit exemplar — a port where nearly everything
already works and the job is verifying it, documented in
[freebsd.md](freebsd.md)), **OpenBSD** (the toolchain-hardening exemplar
— a POSIX/kqueue platform whose BTCFI enforcement and tight default resource
limits forced accommodations that nothing else needs, documented in
[openbsd.md](openbsd.md)), and **NetBSD** (the ABI-compatibility exemplar —
a POSIX/kqueue platform whose versioned libc symbols and non-IEEE aarch64
FP default produce silent wrong-data bugs rather than crashes, documented
in [netbsd.md](netbsd.md)).

## Current support matrix

| OS | Arch | Build | Tests in CI | CI job (`ci.yml`) | Release artifact |
|----|------|:-----:|-------------|-------------------|------------------|
| macOS | aarch64 | native | unit + all Scheme suites + sandbox + robustness + native-backend E2E | `test` (macos-latest) | yes (signed + notarized) |
| Linux | x86_64 | native | same as macOS, in Debug/ReleaseSafe/ReleaseFast | `test` (ubuntu-latest) | yes |
| Linux | aarch64 | native | same | `test` (ubuntu-24.04-arm) | yes |
| Linux | riscv64 | cross-compiled | unit + R7RS under QEMU user-mode | `riscv64-test` | yes |
| Linux | s390x | cross-compiled | unit + R7RS under QEMU user-mode; full battery (unit + thottam + R7RS + `tests/scheme/`) on a real-kernel Alpine VM (#1654) | `s390x-test` | yes |
| Linux | ppc64le | cross-compiled | unit + R7RS under QEMU user-mode; full battery on a real-kernel Alpine VM (#1654) | `ppc64le-test` | yes |
| Windows | aarch64 | cross-compiled only (#1613) | unit + thottam + R7RS + VM-verified `.scm` suites on `windows-11-arm` runners | `windows-cross` + `windows-arm-test` | yes (unstripped, #1607) |
| Windows | x86_64 | cross-compiled or native | same as aarch64 plus the native-backend e2e (`run-e2e.ps1`) on `windows-latest` runners | `windows-cross` + `windows-x64-test` | yes |
| FreeBSD | x86_64, aarch64 | cross-compiled | unit + thottam + full `.scm` suites in a KVM FreeBSD VM (x86_64); verified on a real 15.1 aarch64 box | `freebsd-test` | yes (both arches) |
| OpenBSD | x86_64, aarch64 | cross-compiled | unit + thottam + full `.scm` suites in a KVM OpenBSD 7.9 VM (x86_64); verified on a real 7.9 aarch64 box | `openbsd-test` | yes (both arches, `PT_OPENBSD_NOBTCFI`-marked) |
| NetBSD | x86_64, aarch64 | cross-compiled | unit + thottam + full `.scm` suites in a KVM NetBSD 10.1 VM (x86_64); verified on a real 10.1 aarch64 box | `netbsd-test` | yes (both arches) |
| WASI | wasm32 | cross-compiled (`zig build wasm`) | smoke + timer + parallel-pool under wasmtime | `wasm` | yes (`kaappi.wasm`) |

Everything builds from any host — Zig cross-compiles all rows; no target
needs its own build machine (Windows **aarch64** currently *requires*
cross-compilation because the 0.16.0 toolchain is itself miscompiled on
that target, #1613; Windows x86_64 is unaffected and builds natively).

## Where portability lives

The interpreter core is portable by construction. These subsystems need
**no** work for a new target:

* **Fibers and continuations** — fibers snapshot VM state (registers +
  call frames, `fiber.zig`); continuations stack-copy VM frames
  (`vm_continuations.zig`). There is no per-architecture context-switch
  assembly anywhere in the tree.
* **Bytecode** — operands are composed byte-by-byte in the dispatch
  readers (`vm_dispatch_helpers.zig` `readU16`/`readI16`), so there are no
  unaligned multi-byte loads for strict-alignment CPUs to trap on. `.sbc`
  files are canonically little-endian (`bytecode_file_read.zig` converts
  via `littleToNative`), so they are portable across hosts.
* **GC** — scans VM registers and rooted slots, never the machine stack.
* **Reader / expander / compiler / printer** — pure byte and Value
  manipulation.
* **Value representation** — NaN-boxed u64 (`types.zig`). Fixnums are
  i48; bignum limbs are u64 in little-endian *limb order* (not byte
  order). Endian-neutral in memory; see the CPU section for the one real
  constraint (48-bit pointers).

What a port actually touches, in dependency order:

| Surface | File(s) | What it is |
|---------|---------|------------|
| Syscall shim | `src/platform.zig` (+ `platform_win.zig`, `platform_win_sock.zig`, `platform_win_pipe.zig`) | The single boundary for every OS call: fd-based read/write/open/close, stat, directory iteration, env vars, clocks, sleep, console setup, terminal width, self-exe path, `dlopen`/`dlsym` (FFI), process spawn, temp dir, random seed. POSIX targets forward to `std.posix`/`std.c`; non-POSIX targets reimplement the same integer-fd surface. |
| Reactor backend | `src/reactor.zig` | Per-OS-thread readiness multiplexer. `Backend` is an exhaustive `switch (builtin.os.tag)` — kqueue (Apple platforms, FreeBSD, OpenBSD, NetBSD), epoll (Linux), `poll_oneoff` (WASI), WSAEventSelect (Windows) — with `else => @compileError`. **This is the one hard compile gate a new OS hits**: every BSD port, where `KqueueBackend` was already the right code, still had to add its tag to the switch arms. Also per-OS: `NotifierBackend`, `ThreadNotifier.notify` (cross-thread wakeup: `EVFILT_USER` / eventfd / `SetEvent`), and `releaseNotifier`'s close path. The timer heap is portable userspace. |
| Non-blocking probe | `src/primitives_io.zig` (`maybeSetNonblocking`) | Per-OS strategy for flipping port fds to would-block mode, and the degradation trigger when the OS can't (see "the degradation ladder"). |
| Feature identifiers | `src/types.zig` (`platform_features`) | The `cond-expand` table. Exactly one OS-class identifier per build (`posix` or `windows` today); capability identifiers (`kaappi-threads`, …) dropped where unsupported. `kaappi features`, `(features)`, and `cond-expand` all read this one table. |
| Library/primitive gates | `src/primitives.zig` (`Lib.wasmAvailable`, `PrimSpec.wasm`), `src/library.zig` | Which built-in libraries and individual primitives register on a constrained target. |
| REPL | `src/main.zig`, `src/repl.zig`, `src/repl_commands.zig`, `src/repl_highlight.zig`, `src/repl_eval.zig`, `build.zig` (`use_isocline`) | isocline covers POSIX and Windows (console API). Only WASI falls back to the plain line-reader REPL, and only to keep compiling — `main.zig` never reaches the REPL there. |
| Package manager | `src/thottam.zig`, `src/thottam_fs.zig` | File operations run on shim-based helpers (no shell-outs) on every platform; `HOME` vs `USERPROFILE`; `build:` manifest lines need a platform build story. |
| Paths | `src/kaappi_paths.zig` | Self-exe lookup per OS (`/proc/self/exe`, `_NSGetExecutablePath`, `GetModuleFileNameW`); returns null gracefully where none exists. UTF-8 with `/` separators at every internal boundary. |
| Build gates | `build.zig` | `use_isocline` (hosted targets; off for WASI), `single_threaded` (wasm), `emulated_target` (relaxes wall-clock fuzz deadlines under QEMU, #1573). |
| Test helpers | `src/testing_helpers.zig` | `makeFdPair`/`makeBidiFdPair` abstract POSIX pipes/socketpairs vs loopback TCP pairs so the reactor/scheduler/port-I/O unit suites run on every target. |
| Scheme test gates | `tests/scheme/**` | `cond-expand` skip blocks in tests that exercise platform-only functionality; names stay bound so `guard` probes work. |
| CI | `.github/workflows/ci.yml` | One job (or cross+execute job pair) per target. |
| Release | `.github/workflows/release.yml` | One matrix row per target: `target`, artifact name, `exe_ext`, `lib_ext`, `strip`. |

Self-describing infrastructure needs **verification, not porting**:
`crash.zig`, `features.zig`, and `doctor.zig` derive the target triple and
capability lists from `builtin` and `types.platform_features` — there is no
second hardcoded list to update, but check their output on the new target.

## The degradation ladder (OS ports)

Fiber I/O suspension (KEP-0001) is the subsystem with the widest range of
OS capability, so it defines a graceful-degradation contract rather than a
hard requirement. The three levels, all shipped today:

1. **Full readiness** (macOS kqueue, Linux epoll): every port fd can flip
   non-blocking and register with the reactor. Fibers never block the OS
   thread on I/O.
2. **Partial readiness** (Windows, #1608 stage 1): only fds the platform
   can express readiness for (sockets, probed per-fd with `isSocketFd`)
   participate; pipe/file ports stay blocking.
3. **No readiness** (WASI under a host whose `fd_fdstat_set_flags(NONBLOCK)`
   probe fails, e.g. the browser playground shim): no fd ever registers;
   the reactor degrades to clock-only waits. Timers and `thread-sleep!`
   still work.

Invariants every level must preserve:

* **Sequential programs keep their exact syscall profile.** Fds flip
  non-blocking *lazily*, only once a fiber scheduler exists
  (`fiber.ensureScheduler`), and stdin/stdout/stderr (fd 0/1/2) are never
  flipped.
* **Capability is probed at runtime, per object — never assumed at
  compile time.** The WASI NONBLOCK probe and the Windows `isSocketFd`
  probe are the models: try the flip once, remember the answer on the
  port, degrade that port only.
* **Degraded ports still work** — reads/writes block the thread instead
  of suspending the fiber. Wrong results are never acceptable; slower
  scheduling is.

A new OS port picks its rung, ships correct-but-degraded first, and climbs
later (the Windows port shipped fully blocking, then added socket
readiness as a separate stage; pipes/files remain a tracked follow-up).

## Porting to a new operating system

Stages are ordered so each lands green before the next starts — this is
how the Windows port was actually staged (#1606 build+shim → #1609
thottam → #1608 readiness), and it kept every intermediate PR shippable.

### Stage 0 — feasibility

- [ ] Zig supports the target (`zig targets`) at a usable tier, and libc
      is available — every Kaappi module links libc (`link_libc = true` in
      `build.zig`'s `kaappiModule`).
- [ ] Decide the I/O model mapping: the runtime is written against
      integer fds with POSIX read/write semantics. Identify what provides
      that surface (POSIX-family: `std.posix` directly; Windows: the CRT's
      low-level io layer; WASI: the wasi-libc fd table).
- [ ] Pick the degradation rung (ladder above) and write down the
      deliberate degradations *before* coding — the Windows list
      (POSIX-only SRFI-170 raises, plain REPL, `build:` refusal) was
      decided up front, which kept scope honest.
- [ ] Check the toolchain on a real box early. The Zig toolchain itself
      can be the bug: 0.16.0's aarch64-windows zig.exe carries an LLVM TLS
      miscompile that access-violates on *any* native build (#1613), and
      the same miscompile broke stripped kaappi.exe binaries only (#1607).
      Budget for tiny standalone probes to separate "our bug" from
      "toolchain bug".

### Stage 1 — cross-compile gate

- [ ] `zig build -Dtarget=<arch>-<os>` compiles all three binaries
      (kaappi, thottam, kaappi-lsp). Expect the first failure at
      `reactor.zig`'s `Backend` switch — add the OS to the switch (even
      pointing at a stub backend) to proceed; everything else in
      `platform.zig` defaults to the POSIX path for a non-Windows,
      non-WASI OS.
- [ ] `zig build test -Dtarget=<arch>-<os>` *compiles* the unit-test
      binaries. `skip_foreign_checks = true` in `build.zig` makes this a
      compile-only gate on hosts that can't execute the target — CI runs
      exactly this for Windows.
- [ ] Extend `build.zig` gates if needed: `use_isocline` (any target with
      a tty or console), `single_threaded` (if the target has no OS threads).

### Stage 2 — the platform shim

- [ ] Work through `src/platform.zig` top to bottom. For a POSIX-family
      OS most functions already work via `std.posix`/`std.c` — audit
      rather than rewrite. For a non-POSIX OS, reimplement the surface
      per function family: read/write/close/pipe/dup, open*, unlink/
      mkdir/rmdir/rename/chdir, stat (path/fd/lstat), dir iteration,
      env get/set/iterate, monotonic + real clocks, sleep, console init,
      terminal width, self-exe path, dlopen/dlsym/dlclose + `dl_suffixes`,
      process spawn, temp dir, pid, cwd, random seed.
- [ ] Keep the shim's contracts: fd_t is i32 everywhere; errno values
      map onto `std.c.E` names; paths are UTF-8 at every public boundary
      (convert internally — Windows widens to UTF-16); path separators
      normalize to `/` at the boundaries that produce paths; files open
      in binary mode (R7RS ports must never see newline translation or
      EOF-character semantics — Windows passes `O_BINARY` everywhere).
- [ ] File ownership stays single-owner. The Windows close path is the
      cautionary tale: pairing `closesocket` with `_close` on the same
      underlying handle is a double-close TOCTOU (`platform.close`'s
      comment) — decide who owns each handle type once.
- [ ] `src/kaappi_paths.zig`: add self-exe lookup if the OS has one
      (or return null — the callers degrade).
- [ ] `src/thottam_fs.zig` + `src/thottam.zig`: home directory
      resolution, and decide the `build:` manifest policy (refuse loudly
      like Windows, or support it).

### Stage 3 — fd readiness

- [ ] Implement the reactor backend in `src/reactor.zig`: `init`/
      `deinit`, `arm(fd, read, write, first_time)`, `disarmAll(fd)`,
      `wait(timeout)` returning normalized `ReadyEvent`s, and
      `notifierBackend()`. Study `WasiPollBackend` for a minimal
      poll-style backend and `WindowsEventBackend` for an event-style
      one; note kqueue vs epoll re-arm semantics differ (`Reg.
      kernel_registered` exists because epoll must distinguish ADD from
      MOD).
- [ ] Wire the three per-OS switches that accompany `Backend`:
      `NotifierBackend`, `ThreadNotifier.notify` (must be callable from
      any thread; retry EINTR), and `releaseNotifier`'s close path.
- [ ] Implement the non-blocking strategy in `primitives_io.zig`'s
      `maybeSetNonblocking`, with a runtime capability probe if support
      is conditional. All byte I/O already funnels through `readOneByte`
      / `portWriteBytes` — hook there, not around.
- [ ] The fd-readiness unit suites (`tests_reactor.zig`,
      `tests_reactor_parity.zig`, `tests_scheduler.zig`,
      `tests_port_io.zig`) pass. If the OS lacks
      POSIX pipes/socketpairs, extend `testing_helpers.zig`'s
      `makeFdPair`/`makeBidiFdPair` (Windows substitutes loopback TCP
      pairs) rather than skipping the suites.
      `tests_reactor_parity.zig` is the one written *as* the
      cross-backend comparison: it names no backend, so a property that
      holds on kqueue/epoll/Windows and fails on the new one is a parity
      defect by construction.
      **WASI is a documented exception to the fd criterion, and the
      boundary is the runtime, not us** (kaappi#2153): WASI p1 has no
      pipe/socketpair creation syscalls, and wasmtime — the only runtime
      CI has — leaves the nonstandard `sock_open` unimplemented, so a
      guest cannot construct *any* EAGAIN-capable fd there (moreover,
      `poll_oneoff` fails the whole call with `BADF` for an fd
      subscription on every fd a guest *can* obtain). The fd suites skip
      on wasm with per-test comptime gates, and
      `testing_helpers.wasmNoFdPairs` panics if a test reaches a pair
      constructor without its skip. What *is* required of the WASI leg —
      and enforced by the `wasm` CI job — is: `zig build test
      -Dtarget=wasm32-wasi` compiles (the same compile-gate discipline as
      `-Dtarget=<arch>-windows`; the module also runs under `wasmtime
      run --dir=. --dir=/tmp zig-out/bin/unit-tests.wasm`, executing the
      suites' timer/scheduler halves — i.e. `WasiPollBackend`'s CLOCK
      path). A future WASI runtime with working sockets should promote
      the fd suites by giving `makeFdPair` a real WASI arm and deleting
      the skips.

### Stage 4 — feature identifier, gates, degradations

- [ ] Add the OS-class feature identifier in `types.zig`
      (`platform_features`) — exactly one per build, R7RS appendix B
      names where they exist. `cond-expand`, `(features)`, and `kaappi
      features` all follow automatically.
- [ ] Gate unsupported libraries/primitives (`Lib` availability methods,
      `PrimSpec` flags) following the wasm pattern.
- [ ] Unsupported OS-specific procedures (SRFI-170 territory) **stay
      bound and raise a catchable error** naming the platform — portable
      code probes with `guard`. Never unbind them.
- [ ] Gate Scheme tests that exercise platform-only behavior with
      `cond-expand` skip blocks (grep `tests/scheme/` for `windows` for
      the pattern).
- [ ] `kaappi features`, `kaappi doctor`, and the crash banner
      (`--panic-test`) report the correct triple and capabilities on the
      target.

### Stage 5 — CI

- [ ] Add a `ci.yml` job. If GitHub hosts native runners for the target,
      mirror the `test` matrix. If only cross-compilation works, mirror
      the `windows-cross` → `windows-arm-test` pattern: one job
      cross-compiles binaries *and* test executables and uploads an
      artifact; a second job on the target runner downloads and executes
      — no toolchain on the target box. If neither exists, mirror
      `riscv64-test`'s QEMU pattern (OS emulation permitting).
- [ ] Run what can run: unit tests, thottam tests, the R7RS suite, and
      the VM-verified `.scm` suites. Shell-based suites need a POSIX
      shell — on Windows they're tracked as a gap (#1612), which is an
      acceptable initial state; say so in the port doc.
- [ ] Nothing about the new job weakens existing jobs (`fail-fast:
      false`, separate timeout).

### Stage 6 — release + docs

- [ ] Add a `release.yml` matrix row: `target`, `artifact`, `exe_ext`,
      `lib_ext`, `strip`, plus any post-processing (macOS signs +
      notarizes; Windows ships unstripped until #1613's toolchain bump).
- [ ] Smoke-test a release artifact on a real machine (the post-release
      workflow checksums but does not yet execute all targets).
- [ ] Teach the installer the new platform. It does **not** live in this
      repo — it is `docs/install.sh` in
      [kaappi.github.io](https://github.com/kaappi/kaappi.github.io), served
      at <https://kaappi-lang.org/install.sh>, which is the only copy anyone
      runs. It needs a `detect_platform` arm mapping `uname` output to the
      `release.yml` artifact name (these disagree more often than you would
      expect — NetBSD's `uname -m` reports the kernel port, FreeBSD and
      OpenBSD report `amd64` for x86_64, Linux reports `ppc64le` where the
      artifacts spell out `powerpc64le`), and, for an aarch64/x86_64 target,
      an arm in the `rt_artifact` case so `libkaappi_rt.a` installs and
      `kaappi compile` works.
- [ ] Write `docs/dev/<os>.md` modeled on [windows.md](windows.md):
      the mapping architecture, each deliberate degradation and *why*,
      the feature identifier, how to test on a real machine, known gaps
      with issue links.
- [ ] Update: this file's support matrix, `docs/dev/README.md`'s guide
      table, `CLAUDE.md`'s supported-platforms table, and
      `README.md`'s platform list.

## Porting to a new CPU architecture

A new architecture on an already-supported OS is much smaller than an OS
port — riscv64, s390x, and ppc64le each needed no runtime code changes at
all, only build/CI work — *provided* the preconditions hold.

### Preconditions (check before anything else)

- [ ] **Zig supports the target** with libc. This is the real gate; the
      runtime contains no per-architecture assembly to port.
- [ ] **User-space pointers fit in 48 bits.** The NaN-box heap tag stores
      the raw pointer in a 48-bit payload, and `types.makePointer` does
      **no masking** — it ORs the address with the tag. 32-bit
      architectures (wasm32) trivially satisfy this. 64-bit architectures
      with 48-bit virtual addressing (x86_64 4-level, aarch64 default,
      riscv64 Sv39/Sv48) satisfy it. Configurations that hand out higher
      addresses — x86_64 5-level paging (57-bit VA), aarch64 LVA (52-bit)
      — are safe in practice only because kernels don't allocate above
      2^47 unless a program opts in via mmap hints; an architecture/OS
      that freely returns high addresses (or tags pointer high bits) is
      **blocked** until `makePointer`/`toObject` grow a masking scheme.
      Verify empirically: run the unit suite and check `--gc-stats` on a
      heap-heavy program early — and check `/proc/self/maps` on a *real*
      kernel, since QEMU user-mode inherits the host's layout and proves
      nothing. Verified this way: s390x keeps user VA below 4 TB = 2^42
      (3-level page tables, upgraded only when a mapping demands more)
      and ppc64le below its 128 TB = 2^47 default map window (#1654).
- [ ] **Byte order goes through the codec helpers.** `.sbc` files are
      canonically little-endian via explicit conversions
      (`littleToNative`/`nativeToLittle`), and the NaN-box word is only
      ever manipulated as a u64, never byte-punned. Big-endian is
      **tested**: s390x passes the unit suite, the R7RS suite, and the
      `.sbc` cache round-trip unchanged (#1654), and the `s390x-test` CI
      job guards the invariant on every PR. The obligation this
      precondition now expresses: new serialization or byte-punning code
      must use the same explicit-conversion helpers — the s390x job is
      the canary that catches it if it doesn't.

      **Exactly what that job runs, and what it therefore cannot see.**
      Four steps: the cross-compile, `zig build test
      -Dtarget=s390x-linux`, `tests/scheme/r7rs/r7rs-tests.scm`, and (as
      of audit v2 Phase 7C) `bash tools/run-endian-suite.sh`. It does
      **not** run `tests/scheme/run-all.sh`, which is why the endian
      suite is a separate, deliberately small entry point rather than
      the whole tree. Two blind spots remain, both structural:

      * **A paired byte-swap used to cancel out — closed by golden
        bytes (audit v2 Phase 7D).** Every `.sbc` *round-trip* test still
        writes and reads on the same host, so a bug swapping both
        directions leaves those green everywhere; no test writes a file on
        one endianness and reads it on the other, and the nightly
        `cross-diff` fuzz job does not close that either (both sides run
        against their own arch's cache). What removes the need for a
        second machine is a committed **golden byte sequence**:
        `GOLDEN_BODY` in `src/tests_endian.zig` is a literal, hand-derived
        from the format, used twice with no contact between the uses — the
        serializer must reproduce it, and the deserializer must decode it.
        Neither expected value is a function of the host, so a swap on
        either side, or on both, fails on every target. Measured: flipping
        `nativeToLittle`→`nativeToBig` in `writeU32` **and**
        `littleToNative`→`bigToNative` in `readU32` leaves all 10
        `bytecode_file.zig` round-trip tests passing and fails both golden
        tests. The same shape covers SRFI 271's determinized random ports
        in `tests/scheme/audit/endianness-audit.scm`, whose own suite is
        likewise blind: a `.little`→`.big` flip in the seed-word read
        leaves `tests/scheme/srfi/srfi271.scm` at 35/35.
        **Still not covered:** what a `.sbc` carries that is
        target-*dependent* rather than byte-order-dependent. The cache key
        has no target component, so a binary built for one target loads
        another's bytecode with its `cond-expand` branches already
        chosen (#2155).
      * **A local `zig build test -Dtarget=s390x-linux` proves nothing
        about behaviour.** `build.zig` sets `skip_foreign_checks = true`,
        so on a host with no emulator registered the run step is
        *skipped* and the command still exits 0 (`--summary all` shows
        `run test unit-tests skipped`). On the CI leg it does execute,
        because `docker/setup-qemu-action` registers binfmt_misc and the
        direct spawn succeeds. Locally that command is a compile gate,
        which is exactly what it was added for.
      * **`%host-big-endian?` is the only Scheme-visible witness of host
        byte order.** SRFI 74's `(endianness native)` is defined as
        `(if (%host-big-endian?) 'big 'little)`, so no Scheme test can
        check that primitive non-circularly — a test can only ask it
        again. It is pinned against an actual memory probe in
        `src/tests_endian.zig`, which is why that pin is Zig and not
        Scheme.
- [ ] **f64 hardware or soft-float** with IEEE-754 semantics (flonums
      are NaN-boxed doubles; NaN canonicalization assumes IEEE bit
      patterns).
- [ ] Threads: `std.Thread.spawn` works on the target (SRFI-18), or the
      target follows the wasm route (`single_threaded`, gate `srfi_18`
      off, drop `kaappi-threads` from `platform_features`). Note wasm32
      also lacks 64-bit atomics — `primitives_srfi18.zig` documents the
      workaround pattern.
- [ ] The default 64 MB `stack_size` (set on all three executables in
      `build.zig`) is materializable on the target.

### Interpreter bring-up

- [ ] `zig build -Dtarget=<arch>-linux` (or the relevant OS) compiles.
- [ ] Run the unit suite under emulation if no hardware is at hand:
      `zig build test -Dtarget=<arch>-linux` under QEMU user-mode
      (binfmt), exactly as CI's `riscv64-test` job does. `build.zig`
      auto-detects cross targets (`emulated_target`) and switches the
      fuzz-generator gates from 100 ms wall-clock deadlines to
      instruction-count bounds — QEMU is 10–30× slower and wall-clock
      gates flake spuriously (#1573). If a new kind of timing-sensitive
      test flakes only under emulation, bound it by work, not time.
- [ ] Run the R7RS suite (~1,400 tests) and the smoke suites under
      emulation.
- [ ] Validate on real hardware or a faithful container before calling
      it supported. Beware translation layers with different limits:
      podman + Rosetta cannot even load the full kaappi executable
      (bss-size overflow) — use a native-arch container or real machine
      (the `/linux-test` and `/do-linux-test` skills automate both).
- [ ] Unit suite green under `-Dgc-stress=true` on the new arch (GC
      bugs are where "portable" code turns out to be
      allocation-order-dependent).

### Native (LLVM) backend

The interpreter ships without this; the native backend is a separate,
optional tier (riscv64, s390x, and ppc64le ship interpreter-only today).

- [ ] Add the triple to `llvm_emit.zig`'s `emitPreamble` switch
      (currently aarch64/x86_64 × macos/linux; everything else emits
      `unknown-unknown-unknown` and is unsupported).
- [ ] Decide `fast_tailcalls_supported` (`llvm_emit.zig`): `musttail` +
      `tailcc` codegen quality is per-architecture in LLVM. `false` is
      always safe — mutual tail calls fall back to the trampoline
      (#1499); constant-stack self-tail-calls compile as loops
      regardless.
- [ ] `zig build lib -Dtarget=…` builds `libkaappi_rt.a`, and
      `kaappi compile` produces a working binary on the target. Link
      with `zig cc`, never bare `clang` (Zig compiler-rt intrinsics).
- [ ] Run the native-backend E2E tests (`bash tests/e2e/run-e2e.sh`,
      the "E2E tests" CI step) on the target.

### CI + release

- [ ] Add the CI job: native runner if hosted (`ubuntu-24.04-arm`
      pattern), else cross-compile + QEMU (`riscv64-test` pattern).
- [ ] Add the `release.yml` matrix row.
- [ ] Update the support matrices (here, `CLAUDE.md`, `README.md`).

## What "supported" means

A target earns a row in the support matrix when all of these hold:

1. `zig build` (all three binaries) and `zig build test` are green on or
   for the target.
2. The R7RS suite passes.
3. The `tests/scheme/` suites pass, minus explicitly documented,
   issue-tracked gaps (the Windows precedent: VM-verified suites run in
   CI; shell-based suites are #1612).
4. A CI job runs on every PR — untested support rots within weeks.
5. `release.yml` ships artifacts with checksums, smoke-tested once on a
   real machine.
6. Degradations are documented in a `docs/dev/<target>.md` (OS ports) or
   in this file's matrix notes, each with an issue link if it's meant to
   be lifted.

## Lessons from past ports

Hard-won specifics worth re-reading before starting (fuller detail in
[windows.md](windows.md) and [lessons-learned.md](lessons-learned.md)):

* **Suspect the toolchain when the target is young.** The Windows port
  lost days to an LLVM TLS miscompile inside the shipped zig.exe (#1613)
  that also broke only-stripped binaries (#1607). Reduce with minimal
  probes before assuming the bug is in this repo, and document the
  workaround next to the release row (`strip: false`).
* **A hardened OS can reject the whole toolchain's output.** OpenBSD/arm64
  enforces BTCFI — every indirect branch must hit a `bti` landing pad or
  the kernel raises `SIGILL`/`ILL_BTCFI` — and Zig 0.16 emits none, so the
  binary trapped on its first function-pointer call before `main` ran. The
  fix wasn't in our code: OpenBSD ships an opt-out (`-z nobtcfi` →
  `PT_OPENBSD_NOBTCFI`), applied to the native-backend link directly and
  to Zig-linked binaries by a post-link ELF patch (`tools/openbsd_nobtcfi.zig`,
  wired into `build.zig`). `ktrace`/`kdump` on the box named the exact
  `ILL_BTCFI` fault; a two-line C probe (function pointer with vs. without
  `-mbranch-protection`) proved it was enforcement, not our bug. Watch for
  the same class on any CFI-enforcing OS (amd64 IBT, future arm64 targets).
* **A young target's default resource limits may be far tighter.** OpenBSD's
  `default` login class caps the main stack at 4 MiB (deep interpreter
  recursion overflowed it — the fix was the existing 64 MiB worker thread
  plus a startup `setrlimit`) and the data segment at 1.5 GiB (the
  DebugAllocator's unbounded virtual growth flakily OOM'd the *unit-test*
  binary — the fix was raising `ulimit -d` for the test run, a harness
  concern the shipped C-allocator binaries never hit). Check `ulimit -a`
  early and separate "the runtime needs this" from "only the test binary
  does." The memory variant: a swapless 4 GiB NetBSD box OOM-killed the
  unit suite outright (`UVM: killed: out of swap`) — the DebugAllocator's
  poison-on-free *commits* every freed page, so the suite's footprint is
  cumulative-allocations, not live-set. Check `swapctl -l` too.
* **A binary-compatible OS hides ABI breaks behind symbol renames — and
  the plain name is the trap.** NetBSD keeps every old-ABI function under
  its original name for old binaries and renames the modern one
  (`__kevent50`, `__opendir30`, `__getpwnam50`); C code gets the rename
  from the headers, but a toolchain that declares externs by plain name
  (Zig's `std.c` in spots) links the compat symbol and misparses modern
  structs. Nothing crashes: directory listings come back name-shifted,
  passwd fields come back shuffled — silent wrong data. Audit every
  `std.c.*` call against `nm --dynamic libc.so` (weak plain symbol beside
  a `__name<NN>` strong one = versioned) and bind the versioned name
  explicitly. See [netbsd.md](netbsd.md) for the worked audit.
* **Don't assume the FP environment starts IEEE-default.** NetBSD/aarch64
  boots every process with FPCR.FZ|DN set: denormals flush to zero, so
  SRFI-144's `(> fl-least 0.0)` was *false* — a wrong-answer bug in
  ordinary arithmetic, invisible until a conformance test probed gradual
  underflow. The runtime now resets FPCR at startup
  (`platform.normalizeFpEnvBestEffort`), relying on the (empirically
  verified) fact that threads inherit the creator's FP state. Probe
  `fl-least`-class arithmetic early on any new OS/arch pair.
* **Probe capabilities at runtime, per object.** Comptime OS checks
  can't see host differences (WASI browser shim vs wasmtime; socket vs
  pipe fds behind the same CRT). One-time probes with remembered answers
  (`isSocketFd`, the WASI NONBLOCK probe) degrade exactly the objects
  that need it.
* **Keep the sequential syscall profile untouched.** Lazy non-blocking
  flips (only once a scheduler exists, never fd 0/1/2) meant the port
  couldn't regress plain scripts — the majority of real usage.
* **Names stay bound; unsupported raises catchable errors.** Portable
  code must be able to `guard`-probe. Deleting bindings breaks imports;
  raising at call time with a clear platform message doesn't.
* **Binary mode and UTF-8 boundaries are non-negotiable.** Text-mode
  newline rewriting and ANSI code pages corrupt R7RS port semantics
  silently; force binary I/O and convert path encodings inside the shim.
* **Decide handle ownership once.** Double-close across two API layers
  (CRT fd vs SOCKET) is a TOCTOU that only fires under thread churn.
* **Never rely on malloc refusal for graceful errors.** Overcommitting
  kernels (FreeBSD's default) reserve absurd allocation requests and
  kill the process only when page commit catches up — the FreeBSD port
  turned the out-of-memory diagnostic's own example into an OOM-killer
  crash until the runtime learned to bound single payloads itself
  (`GC.max_payload_bytes`, memory.zig; see freebsd.md).
* **Emulation changes timing, not correctness — write gates
  accordingly.** Wall-clock bounds flake under QEMU (#1573);
  `emulated_target` exists so tests can bound by instruction count.
* **Artifact-handoff CI beats waiting for a native toolchain.** The
  `windows-cross` → `windows-arm-test` pattern (build anywhere, execute
  on the target runner, no toolchain installed there) got full test
  coverage before native builds were even possible.
* **Stage the port; ship degraded-but-correct.** Build gate → shim →
  package manager → readiness, each landing green. The degradation
  ladder exists so "sockets only" or "blocking everywhere" are
  shippable, honest intermediate states.
