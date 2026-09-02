# NetBSD port

NetBSD is the sixth completed OS port. Like FreeBSD and OpenBSD it is a
full-POSIX platform whose native readiness API is **kqueue** — the same
backend macOS uses — so it sits on rung 1 of the degradation ladder
([porting.md](porting.md)) with **no I/O degradation**: every port fd flips
non-blocking and registers with the reactor. What makes NetBSD different
from the other BSDs is not security hardening but **binary-compatibility
engineering**: NetBSD never breaks old binaries, so every libc function
whose ABI ever changed keeps its old name as a compat symbol and hides the
modern one behind a rename. A foreign toolchain that declares the plain
name — as Zig's `std.c` does for a handful of functions — silently links
the *compat* version and misparses modern structs. That, plus a
non-IEEE floating-point default on aarch64, are the port's two defining
problems. Everything else worked through the existing POSIX paths.

## What the port touches

| Surface | Change |
|---------|--------|
| `src/reactor.zig` | `.netbsd` added to the four per-OS switches (`Backend`, `NotifierBackend`, `ThreadNotifier.notify`, `releaseNotifier`), all resolving to the existing `KqueueBackend`. NetBSD's kqueue constants are complete in Zig's `std.c` (`EVFILT.USER = 8` — NetBSD filters are positive, unlike every other kqueue OS — `NOTE.TRIGGER`, `EV.EOF`), but the `kevent` *symbol* is versioned: the backend calls `__kevent50` explicitly (see below). |
| `src/platform.zig` | `is_netbsd`; `DirIter` calls `__opendir30`/`__readdir30` (see below); `raiseStackLimitBestEffort()` extended to NetBSD (8 MiB default soft stack → 64 MiB hard); `normalizeFpEnvBestEffort()` — clears FPCR.FZ\|DN on NetBSD/aarch64 at startup (see below). |
| `src/primitives_filesystem.zig` | SRFI-170 `user-info` calls `__getpwnam50`/`__getpwuid50` (see below). |
| `src/kaappi_paths.zig` | Self-exe lookup via `sysctl {KERN, PROC_ARGS, -1, PROC_PATHNAME}` — kernel-canonical like FreeBSD's, just filed under the `KERN_PROC_ARGS` node. |
| `src/native_compiler.zig` | C-compiler discovery probes `clang` before `cc` on NetBSD — base cc is GCC, which cannot consume the `.ll` the backend emits. |
| `src/llvm_emit.zig` | `aarch64-unknown-netbsd` / `x86_64-unknown-netbsd` module triples. |
| `src/main.zig`, `src/kaappi_lsp.zig`, `src/runtime_exports.zig` | Call `normalizeFpEnvBestEffort()` at startup. |
| `docs/install.sh` (in [kaappi.github.io](https://github.com/kaappi/kaappi.github.io)) | `NetBSD` platform detection — **`uname -m` reports the kernel port (`evbarm`, `amd64`), not the CPU**, so the NetBSD arm reads `uname -p`; download via base `ftp`, checksums via base `sha256`. |
| CI + release | `netbsd-test` job in `ci.yml`; two `release.yml` matrix rows (`x86_64-netbsd`, `aarch64-netbsd`). |

## Versioned libc symbols: the port's defining problem

When a struct or typedef in a libc function's signature changes ABI, NetBSD
keeps the old function under its plain name (for old binaries) and gives the
new one a suffixed name — `__kevent50`, `__opendir30` — which the system
headers map back via `__RENAME`. Compiling C against the headers always
gets the modern symbol; **declaring the plain name directly gets the compat
one**. Zig's `std.c` maps most of these for NetBSD (`__fstat50`,
`__socket30`, `__clock_gettime50`, `__getdents30`, …) but not all, and the
gaps produced three real bugs, none of which crashed — they all *silently
returned wrong data*, the worst failure mode:

| Plain symbol | Modern symbol | ABI change | Observed failure |
|--------------|---------------|-----------|------------------|
| `kevent` | `__kevent50` (6.0) | timeout `timespec` grew 64-bit `tv_sec` | None observed — on LP64 the old/new layouts coincide except for `tv_sec` truncation — but bound explicitly anyway (`reactor.zig` `kevent_sys`) rather than rely on layout luck. |
| `opendir`/`readdir` | `__opendir30`/`__readdir30` (3.0) | `dirent` grew u64 `d_fileno`, wider `d_namlen` | Directory listings misparse: every name shifted, so `kaappi cache status` saw an empty cache, thottam tree walks copied nothing, SRFI-170 directory streams returned garbage. (`platform.zig` `opendir_sys`/`readdir_sys`.) |
| `getpwnam`/`getpwuid` | `__getpwnam50`/`__getpwuid50` (6.0) | `passwd` grew 64-bit `pw_change`/`pw_expire` | SRFI-170 `user-info` returned shifted strings for home dir/shell. (`primitives_filesystem.zig` `getpwnam_sys`/`getpwuid_sys`.) |
| `lstat` | `__lstat50` (6.0) | `struct stat` time fields widened | No-follow `file-info` (SRFI-170) could return timestamps with garbage high bits — the compat syscall writes 32-bit seconds and leaves the modern layout's padding uninitialized. Size/mode happened to coincide on LP64. (`primitives_filesystem.zig` `doStat`.) |
| `unsetenv` | `__unsetenv13` (1.3) | return type void → int | Behaviorally none (the return is ignored); bound for a correct signature. (`platform.zig`.) |

Two detection methods, both used by this port:

* **Inventory + nm**: list every `std.c.*` call in the tree, then on a
  NetBSD box check each with
  `nm --dynamic /usr/lib/libc.so | grep -w <name>` — a **weak plain symbol
  next to a `__<name><NN>` strong one** means versioned; a plain `T` symbol
  (e.g. `fstatat`, `socketpair`, `setenv`, added or unchanged after the
  relevant ABI break) means safe. `closedir` never changed (no dirent in
  its signature) and needs no shim.
* **Link through NetBSD's ld**: libc embeds `.gnu.warning` sections on
  compat symbols, so any link done *on the box with GNU ld* prints
  `warning: reference to compatibility lstat()` for each trapped
  reference. `kaappi compile`'s clang/ld link of `libkaappi_rt.a` surfaced
  `lstat` and `unsetenv` this way after the nm audit had already caught
  the first three — run one on-box link before calling the audit done.
  (Zig-linked binaries use LLD, which stays silent; check them with
  `nm --dynamic --undefined-only zig-out/bin/kaappi`.)

The fix pattern is a comptime-selected extern:

```zig
const kevent_sys = if (builtin.os.tag == .netbsd) struct {
    extern "c" fn __kevent50(...) c_int;
}.__kevent50 else std.c.kevent;
```

## Floating point: FPCR flush-to-zero on aarch64

NetBSD/aarch64 starts every process with **FPCR = 0x3000000** — FZ
(flush-to-zero) and DN (default NaN) set — unlike Linux, macOS, and the
other BSDs, which start at the IEEE-754 default (0). Under FZ, denormal
operands and results flush to zero: `(/ 4.94e-308 1e16)` returns `0.0`
instead of `5e-324`, and SRFI-144's `(> fl-least 0.0)` is *false*. That is
a wrong-answer class, not a performance class, so the runtime corrects it:
`platform.normalizeFpEnvBestEffort()` writes FPCR = 0 at startup (kaappi,
kaappi-lsp, and `kaappi_runtime_init` for native binaries). FPCR is
inherited across `pthread_create` — verified empirically on NetBSD 10.1 —
so one call before the interpreter worker spawns corrects every SRFI-18
thread and pool worker transitively. DN=0 also restores IEEE NaN payload
propagation; the NaN-boxing scheme is indifferent to it (hardware NaN
results sit at `0x7FF8…`, far from the `0xFFFC–0xFFFE` tag space).

Regression tests: `tests_platform.zig` "denormal arithmetic survives after
normalizeFpEnvBestEffort" (unit), `tests/scheme/srfi/srfi144.scm` test 6
(end-to-end). x86_64-netbsd starts with a standard MXCSR (no FTZ/DAZ);
the call is a comptime no-op there and everywhere else.

## Resource limits and memory

* **Stack (8 MiB soft / 64 MiB hard).** NetBSD ignores the ELF
  `PT_GNU_STACK` size hint and bounds main-stack growth by `RLIMIT_STACK`
  at fault time. The kaappi binary runs on a 64 MiB worker thread anyway;
  kaappi-lsp compiles on the main thread. Both call
  `raiseStackLimitBestEffort()` (shared with OpenBSD), which lifts the soft
  limit to the 64 MiB hard limit — the same headroom every other platform
  gets, so no NetBSD-specific stack gap remains.
* **Data segment (4 GiB soft / 64 GiB hard).** Only the **unit-test
  binary** approaches it: `std.testing`'s DebugAllocator never reuses freed
  address space *and poisons freed memory* (committing the pages), so its
  footprint grows monotonically to ~4 GiB across the 1141 tests. Raise the
  limit before running it (`ulimit -d $(ulimit -H -d)`), as the CI job and
  the recipe below do. The shipped binaries use the C allocator and never
  accumulate.
* **No-swap machines OOM-kill the unit suite.** The same ~4 GiB commit
  means a 4 GiB-RAM box with no swap configured (common on small ARM
  images) kills the unit-test binary partway through: `dmesg` shows
  `UVM: pid N (unit-tests) killed: out of swap`. Give the box swap
  (`dd if=/dev/zero of=/swapfile bs=1m count=6144 && chmod 600 /swapfile &&
  swapctl -a /swapfile`) or ≥ 6 GiB RAM; the CI VM sets `mem: 6144`. This
  is a test-harness concern only — the interpreter itself runs fine in the
  default limits.

## Scheduler: a preempted lock holder starves under a pure spin

NetBSD's default scheduler is 4BSD (`sys/kern/sched_4bsd.c`): a user LWP's
priority is `63 − estcpu/2048`, `estcpu` grows by 1024 on every clock tick
the LWP is running and decays only slowly (90% in `5 × loadavg` seconds),
and a new LWP **inherits its spawner's `estcpu`**. Each CPU always runs the
highest-priority runnable LWP, and `sched_yield` requeues an LWP behind the
others *of its own priority* — never behind a lower one.

That combination turns any userspace pure spin into a hang under CPU
contention (kaappi#2446): a thread that has been doing real work sits at
priority 0; the moment the kernel preempts it while it holds a lock — say,
inside the `kevent` ring `wakeCrossThreadWaiters` issues per parked thread —
every thread that then arrives at that lock spins at a *higher* priority
(fresh from a sleep, or a new LWP whose spawner had been idle), and with
more spinners than CPUs the holder is never scheduled again. Observed as
`srfi18-join-spawn-grandchild-2129.scm` running until killed at ~290% CPU:
17 LWPs in `memory.spinLock` from `withdrawCrossThreadWaiter`, one LWP
runnable (`R`, no wchan) at priority 0 inside `_sys___kevent50`. Linux CFS
and macOS never reproduce it — a fair scheduler always gives the holder its
share, so the same spin is a latency cost there, not a liveness one.

Two kaappi-side rules follow, both of which hold everywhere but were only
ever *needed* here:

* **Never `pthread_join` a `thread-start!`ed thread.** `_lwp_wait` makes the
  joining LWP absorb the dead LWP's `estcpu` with no cap
  (`sched_lwp_collect` lacks the `ESTCPULIM` every other path applies), and
  `sched_lwp_fork` copies the estimate into every LWP the joiner creates. A
  nice-0 thread cannot get below priority 25 by running, but three joins of
  busy threads put the joiner — and all its future children — at 0, below
  every ordinary process, where CPU contention starves them outright. SRFI-18
  threads are therefore detached at spawn and joined through a per-spawn
  exit flag (`Fiber.os_exit`, raised after the child's outermost defer).
  Upstream fixed the cap in trunk (`sched_4bsd.c` 1.48, 2026-03-01) and
  netbsd-11, not netbsd-10 — so the rule stands for as long as 10.x is a
  supported target (kaappi#2471 tracks the pull-up).
* **Every cross-thread wait loop goes through `platform.spinBackoff`** (spin,
  then yield, then sleep 32 µs doubling to 1 ms): `memory.spinLock`, the GC
  stop-the-world handshake on both sides, the globals RW lock and the reap
  wait above. A sleep is what a yield is not — it takes the waiter off the
  run queue, so a preempted holder at the same priority gets its turn. A
  bare `spinLoopHint` loop reintroduces the convoy on this platform.

**Diagnosing a hang here.** gdb alone misleads: a starved LWP shows a frozen
PC and no syscall, which reads as "the OS never scheduled this thread" (the
original diagnosis of kaappi#2446). The kernel-side view is what settles
it — per-LWP state, wait channel, priority and whether the process's CPU
time is still climbing:

```bash
ps -s -o pid,lid,lstate,wchan,cpuid,pri,time,pcpu -p <pid>   # twice, a few seconds apart
gdb -batch -p <pid> -ex 'info threads' -ex 'thread apply all bt 8'
```

`R` with no wchan and `pri 0` while other LWPs sit at 25+ and `TIME` grows by
seconds per second is starvation by spinners; `S` with a wchan is a kernel
sleep; a lone `R` LWP in an otherwise idle process would be the scheduler's
fault. Measure under load (`sh -c 'while :; do :; done' &` × ncpu) — the
hang needs more runnable LWPs than CPUs — and kill the burners by PID
afterwards; orphaned ones poison every later measurement.

## Self-exe path

NetBSD has `KERN_PROC_PATHNAME`, but filed under the `KERN_PROC_ARGS`
sysctl node: `{CTL_KERN, KERN_PROC_ARGS, -1, KERN_PROC_PATHNAME}` (pid −1 =
calling process) returns the kernel-resolved canonical executable path, so
no realpath pass is needed — same shape as FreeBSD, different mib. procfs
would offer `/proc/curproc/exe` but is typically not mounted.

## Native backend (`kaappi compile`)

**NetBSD's base `cc` is GCC** (10.5 on NetBSD 10), and the backend links
`.ll` LLVM IR — which GCC rejects outright ("file format not recognized").
This is the one place NetBSD differs from FreeBSD/OpenBSD, whose base cc is
clang. Two accommodations:

* The compiler discovery order on NetBSD is `zig, clang, cc, gcc` (vs
  `zig, cc, clang, gcc` elsewhere), so a pkgsrc clang is found before the
  guaranteed-to-fail base GCC and the common failure mode (no clang
  installed yet) reports one clean miss instead of two GCC spews.
* Install clang from pkgsrc for the native backend:
  `pkgin install clang`. Everything else about the flow is standard — it
  links the cross-compiled `libkaappi_rt.a` (compiler-rt bundled) against
  base libc/libm/libpthread; `kaappi doctor`'s smoke-link check confirms
  it per machine.

The interpreter, thottam, REPL (full isocline), FFI, and SRFI-170 need no
packages beyond the base system.

## cond-expand / (features)

NetBSD builds expose `posix` — the project convention is exactly one
OS-class identifier per build, and NetBSD is a POSIX platform (there is no
`netbsd` identifier, just as macOS exposes no `darwin`). The triple in
`kaappi features` and the crash banner (`aarch64-netbsd-none`)
distinguishes the OS when it matters. All capability identifiers
(`kaappi-threads`, `kaappi-fibers`, `kaappi-reactor`,
`kaappi-diagnostics`, `kaappi-shared-channels`) are present — nothing is
gated.

## Testing on a NetBSD machine

No Zig toolchain is needed on the box — cross-compile everything and copy
it over (the build-anywhere / execute-on-target model). Zig 0.16 bundles
NetBSD libc (binaries stamp "for NetBSD 10.1"), so
`zig build -Dtarget=<arch>-netbsd` from any host yields ready binaries.

```bash
# on the dev machine
zig build -Dtarget=aarch64-netbsd             # or x86_64-netbsd
zig build lib -Dtarget=aarch64-netbsd         # native-backend runtime lib
zig build test -Dtarget=aarch64-netbsd        # compiles unit-tests / thottam-tests
# pick the NetBSD ELFs from the cache (a later host build may be newer —
# check the signature, not just mtime):
file .zig-cache/o/*/unit-tests | grep NetBSD

# copy repo + zig-out + the two test binaries to the box, then:
doas pkgin install bash git-base clang python313   # clang: native backend;
                                                   # python3/git: two shell suites
doas ln -sf /usr/pkg/bin/python3.13 /usr/pkg/bin/python3
ulimit -s $(ulimit -H -s)     # 64 MiB — the test runner recurses on the main thread
ulimit -d $(ulimit -H -d)     # DebugAllocator growth (see above; add swap on 4 GiB boxes)
./unit-tests && ./thottam-tests
cc -shared -fPIC tests/scheme/ffi/fixtures/u64test.c \
   -o tests/scheme/ffi/fixtures/libu64test.so
bash tests/scheme/run-all.sh
```

Reference machine for this port: **NetBSD 10.1 aarch64** (evbarm GENERIC64,
4-core / 4 GiB VM + 6 GiB swapfile).

## CI

`netbsd-test` (ci.yml) cross-compiles the binaries, test executables, and
`libkaappi_rt.a` for **x86_64-netbsd** on ubuntu-latest — the compile gate —
then boots a NetBSD 10.1 VM (`vmactions/netbsd-vm`, `mem: 6144`; GitHub
hosts no NetBSD runners) that shares the workspace and executes the unit
suite, the thottam suite, and `run-all.sh` with the stack and data limits
raised. One job, no artifact handoff, because the VM syncs the workspace
directly. The VM tracks 10.1 to match the aarch64 reference machine and
Zig's bundled libc floor.

## Known gaps

* **The versioned-symbol audit covers what the runtime calls today.** A
  future `std.c.*` call whose NetBSD symbol is versioned and unmapped by
  Zig would regress silently — re-run the `nm` audit (above) when adding
  platform calls, until Zig's std.c closes the gaps upstream.
* **The native backend needs pkgsrc clang** (base cc is GCC, which cannot
  consume LLVM IR). Interpreter and thottam need base only.
* Building natively with Zig **on** NetBSD is expected to work (the target
  is supported upstream) but hasn't been exercised — the cross-compile +
  copy flow covers development.
* `tests/e2e/run-e2e.sh` and the `-Dbundle` shell scripts need a Zig
  toolchain on the box; they run wherever one exists.
