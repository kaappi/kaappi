# OpenBSD port

OpenBSD is the fifth completed OS port. Like FreeBSD it is a full-POSIX
platform whose native readiness API is **kqueue** — the same backend macOS
uses — so it sits on rung 1 of the degradation ladder ([porting.md](porting.md))
with **no I/O degradation**: every port fd flips non-blocking and registers
with the reactor. What makes OpenBSD different from FreeBSD is its security
hardening, which forces two accommodations nothing else in the tree needs:

1. **BTCFI** — the kernel enforces Branch Target CFI, and Zig 0.16 cannot emit
   the landing pads it requires, so every Zig-linked binary must carry an
   explicit opt-out marker (added post-link).
2. **Small default resource limits** — the `default` login class caps the main
   thread's stack at 4 MiB and the data segment at 1.5 GiB, both well under
   what the interpreter and the unit-test binary use elsewhere.

Everything else worked through the existing POSIX paths.

## What the port touches

| Surface | Change |
|---------|--------|
| `src/reactor.zig` | `.openbsd` added to the four per-OS switches (`Backend`, `NotifierBackend`, `ThreadNotifier.notify`, `releaseNotifier`), all resolving to the existing `KqueueBackend`. OpenBSD's `std.c` kqueue bindings are complete — `EVFILT.USER`, `NOTE.TRIGGER`, `EV.EOF` all present — so unlike FreeBSD no constant fallback was needed (the guarded `EV_EOF` stays for FreeBSD). |
| `src/kaappi_paths.zig` | `getExePath` via `sysctl KERN_PROC_ARGS`/`KERN_PROC_ARGV` → argv[0] → `realpath`. OpenBSD has **no `KERN_PROC_PATHNAME`** (and no procfs), so there is no kernel-canonical exe path; argv[0] resolution is the portable route. |
| `src/platform.zig` | `is_openbsd` const; `raiseStackLimitBestEffort()` — raises the soft stack limit to the hard limit at startup (OpenBSD-only, no-op elsewhere). |
| `src/main.zig`, `src/kaappi_lsp.zig` | Call `raiseStackLimitBestEffort()` at startup. |
| `src/native_compiler.zig` | `-z nobtcfi` added to the `kaappi compile` link line on OpenBSD. |
| `src/llvm_emit.zig` | `aarch64-unknown-openbsd` / `x86_64-unknown-openbsd` module triples. |
| `build.zig` + `tools/openbsd_nobtcfi.zig` | Post-link ELF patcher (host tool) that marks each installed Zig-linked binary `PT_OPENBSD_NOBTCFI`, so `zig build -Dtarget=<arch>-openbsd` yields working binaries directly. |
| `src/testing_helpers.zig`, `src/cache.zig`, `src/tests_libraries.zig` | Resolve `std.testing.tmpDir` paths with a path-string `realpath` instead of `Io.Dir.realPathFile` (fd→path is `OperationUnsupported` on OpenBSD). |
| CI + release | `openbsd-test` job in `ci.yml`; two `release.yml` matrix rows (`x86_64-openbsd`, `aarch64-openbsd`). |

## BTCFI: the `PT_OPENBSD_NOBTCFI` opt-out

The port's defining problem. OpenBSD on arm64 (and amd64, via IBT) enforces
**BTCFI**: an indirect branch (`BLR`/`BR`) must land on a `bti` instruction, or
the CPU raises `SIGILL` with `code=ILL_BTCFI`. OpenBSD's base clang emits those
landing pads by default and rebuilds the entire base system with them; **Zig
0.16 cannot** — it has no `-mbranch-protection` flag and no `bti` CPU feature,
so a Zig-linked binary has no landing pads and traps on its very first
function-pointer call (in practice, a thread entry trampoline right after
`__tfork`). This is a young-toolchain limitation, the class the porting guide
warns about — not a Kaappi bug.

OpenBSD's own escape hatch for foreign toolchains is the linker flag
`-z nobtcfi`, which emits a **`PT_OPENBSD_NOBTCFI`** program header — a pure
marker (type only; zero offset/size) that tells `ld.so` and the kernel to skip
BTCFI enforcement for that binary. Two paths use it:

* **`kaappi compile` native output** takes the honest path: the system cc/ld
  accepts `-z nobtcfi` directly, so `native_compiler.zig` adds it to the link
  line on OpenBSD. (The native binary calls into the no-landing-pad
  `libkaappi_rt.a`, so it needs the marker too.)
* **Zig-linked binaries** (kaappi, thottam, kaappi-lsp, the unit-test
  executables) can't use the flag — Zig's CLI rejects `-z nobtcfi` before it
  reaches LLD. So `tools/openbsd_nobtcfi.zig` adds the marker **post-link**.
  The program header table sits immediately before `.interp` with no room to
  append an entry, so instead of growing the table the tool **repurposes the
  `PT_GNU_STACK` entry in place**: OpenBSD ignores `PT_GNU_STACK` (it enforces
  W^X independently and sizes the main stack from `RLIMIT_STACK`), so
  overwriting its 56 bytes with the marker is a no-op for stack handling and
  gains the opt-out. The tool is idempotent and arch-agnostic (same fix for
  arm64 BTCFI and amd64 IBT).

`build.zig` compiles this tool for the host and runs it on each installed
executable for OpenBSD targets (`installExe`), so a plain
`zig build -Dtarget=<arch>-openbsd` produces working binaries — no separate
patch step, no footgun. It is a deliberate, documented security degradation
(BTCFI off for our binaries), directly analogous to the Windows port shipping
`strip: false` around its own toolchain bug; it lifts when Zig can emit
aarch64 branch-protection landing pads.

## Resource limits

OpenBSD's `default` login class sets much lower limits than other platforms,
and two of them bite:

* **Stack (4 MiB soft / 32 MiB hard).** OpenBSD ignores the ELF `PT_GNU_STACK`
  size hint (`build.zig`'s `--stack`) and sizes the main thread's stack from
  `RLIMIT_STACK`; 4 MiB overflows on the interpreter's deep recursion (the
  macro expander, nested compile). The **kaappi binary is unaffected** — it
  already runs all work on a 64 MiB worker thread (`main.zig`), whose mmap'd
  stack is not `RLIMIT_STACK`-bound. **kaappi-lsp** compiles user code on the
  main thread, so it calls `platform.raiseStackLimitBestEffort()` at startup to
  raise the soft limit to the 32 MiB hard limit. (kaappi calls it too, to
  harden the rare worker-spawn-failure fallback.) 32 MiB is below the 64 MiB
  other platforms get; a non-root process can't exceed the hard limit, so
  extremely deep nesting in the LSP could still overflow — raise the login
  class's `stacksize` in `login.conf` if so.
* **Data (1.5 GiB soft / 64 GiB hard).** Only the **unit-test binary** hits
  this. Zig's `std.testing.allocator` (a `DebugAllocator`) never reuses freed
  virtual address space — by design, to catch use-after-free — so its
  reservation grows monotonically across the 1141 tests and lands right at the
  1.5 GiB soft limit, where allocation-heavy tests (deepCopy of a 200 K-element
  list, #801) flakily fail with `OutOfMemory` and the thread-spawning channel
  tests abort. The shipped binaries use the C allocator and never accumulate
  this way. **Run the unit-test binary with the data limit raised to the hard
  limit** (`ulimit -d $(ulimit -Hd)`), which the CI job and the recipe below
  both do.

## Self-exe path

OpenBSD has neither `/proc/self/exe` nor `KERN_PROC_PATHNAME`, so there is no
kernel-canonical executable path. `getExePath` reads the process's own argv[0]
via `sysctl KERN_PROC_ARGS`/`KERN_PROC_ARGV` and resolves it with `realpath`:
argv[0] with a `/` resolves directly (absolute or relative to cwd); a bare
command name is searched on `$PATH`. This resolves the running binary for
exe-relative library discovery and `kaappi test` worker respawn; it returns
null (callers degrade) only for an argv[0] that cannot be found.

## The `realPathFile` test-harness gap

Three unit tests took the tmp dir's absolute path via
`Io.Dir.realPathFile`, which resolves an **fd → path** — `OperationUnsupported`
on OpenBSD (no `/proc/self/fd`, no `F_GETPATH`). The runtime never does this;
only the tests did. They now resolve the tmp dir with a path-string `realpath`
(`th.tmpDirRealPathAlloc`), which works on every platform — `std.testing`
places tmp dirs at `.zig-cache/tmp/<sub_path>` relative to the cwd.

## cond-expand / (features)

OpenBSD builds expose `posix` — the project convention is exactly one OS-class
identifier per build, and OpenBSD is a POSIX platform (there is no `openbsd`
identifier, just as macOS exposes no `darwin`). The triple in `kaappi features`
and the crash banner (`aarch64-openbsd-none`) distinguishes the OS when it
matters. All capability identifiers (`kaappi-threads`, `kaappi-fibers`,
`kaappi-reactor`, `kaappi-diagnostics`) are present — nothing is gated.

## Testing on an OpenBSD machine

No Zig toolchain is needed on the box — cross-compile everything, patch the
Zig-linked test binaries, and copy it over (the build-anywhere / execute-on-
target model). `zig build` already marks the three installed binaries; only the
unit-test executables need the tool run on them explicitly.

```bash
# on the dev machine
zig build -Dtarget=aarch64-openbsd            # or x86_64-openbsd (binaries auto-marked)
zig build lib -Dtarget=aarch64-openbsd        # native-backend runtime lib
zig build test -Dtarget=aarch64-openbsd       # compiles unit-tests / thottam-tests
UNIT=$(ls -t .zig-cache/o/*/unit-tests | head -1)
THOTTAM=$(ls -t .zig-cache/o/*/thottam-tests | head -1)
cp "$UNIT" ./unit-tests-openbsd; cp "$THOTTAM" ./thottam-tests-openbsd
zig run tools/openbsd_nobtcfi.zig -- ./unit-tests-openbsd ./thottam-tests-openbsd

# copy repo + binaries + lib + the two patched test binaries to the box, then:
doas pkg_add -I bash          # run-all.sh needs bash; base system has cc
ulimit -s $(ulimit -Hs)       # 32 MiB — the test runner recurses on the main thread
ulimit -d $(ulimit -Hd)       # 64 GiB — DebugAllocator virtual growth (see above)
./unit-tests-openbsd && ./thottam-tests-openbsd
cc -shared -fPIC tests/scheme/ffi/fixtures/u64test.c \
   -o tests/scheme/ffi/fixtures/libu64test.so
bash tests/scheme/run-all.sh
```

The native backend works with the base system `cc` (no Zig on the box):
`kaappi compile` links its output against `libkaappi_rt.a` with `-z nobtcfi`;
`kaappi doctor`'s smoke-link check confirms it per machine.

Reference machine for this port: **OpenBSD 7.9 aarch64** (4-core / 4 GiB VM).

## CI

`openbsd-test` (ci.yml) cross-compiles the binaries, test executables, and
`libkaappi_rt.a` for **x86_64-openbsd** on ubuntu-latest — the compile gate —
runs `tools/openbsd_nobtcfi.zig` over the two test binaries, then boots an
OpenBSD 7.9 VM (`vmactions/openbsd-vm`; GitHub hosts no OpenBSD runners) that
shares the workspace and executes the unit suite, the thottam suite, and
`run-all.sh` with the stack and data limits raised. One job, no artifact
handoff, because the VM syncs the workspace directly. The VM tracks 7.9 to
match the aarch64 reference machine (OpenBSD breaks ABI between releases, so the
Zig-targeted release and the VM release should agree).

## Known gaps

* **BTCFI is disabled** for the Zig-linked binaries (the `PT_OPENBSD_NOBTCFI`
  marker). This is a toolchain limitation, not a choice — it lifts when Zig can
  emit aarch64 branch-protection landing pads. The `kaappi compile` native
  backend is unaffected in principle (it could emit landing pads if Zig's C
  toolchain did), but currently also opts out for the runtime archive's sake.
* **kaappi-lsp's stack is capped at the 32 MiB hard limit** (vs 64 MiB
  elsewhere); a non-root process cannot exceed it. Raise `login.conf` if deeply
  nested LSP requests overflow.
* Building natively with Zig **on** OpenBSD is expected to work (the target is
  supported upstream) but hasn't been exercised — the cross-compile + copy flow
  covers development, and the native backend needs only base `cc` at runtime.
* `tests/e2e/run-e2e.sh` and the `compile/` suite need a Zig toolchain on the
  box; they run wherever one exists.
