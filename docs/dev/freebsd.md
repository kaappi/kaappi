# FreeBSD port

FreeBSD is the smallest OS port in the tree: it is a full POSIX platform
whose native readiness API is kqueue — the same backend the macOS port
uses — so it sits on rung 1 of the degradation ladder
([porting.md](porting.md)) with **no runtime degradations at all**. The
port touches four surfaces; everything else worked through the existing
POSIX paths unmodified.

## What the port touches

| Surface | Change |
|---------|--------|
| `src/reactor.zig` | `.freebsd` added to the four per-OS switches (`Backend`, `NotifierBackend`, `ThreadNotifier.notify`, `releaseNotifier`), all resolving to the existing `KqueueBackend` — FreeBSD kqueue provides `EVFILT_USER`/`NOTE_TRIGGER` for the cross-thread notifier exactly like Darwin. One constant gap: this Zig's freebsd `std.c.EV` binding omits `EOF`, so the backend carries a guarded `EV_EOF = 0x8000` fallback (the value in every kqueue OS's `sys/event.h`). |
| `src/kaappi_paths.zig` | Self-exe lookup via `sysctl kern.proc.pathname` (pid −1): procfs is typically not mounted on FreeBSD, and the sysctl returns a kernel-resolved canonical path, so no realpath pass is needed. |
| `src/llvm_emit.zig` | `aarch64-unknown-freebsd` / `x86_64-unknown-freebsd` module triples for the native backend. |
| CI + release | `freebsd-test` job in `ci.yml`; two `release.yml` matrix rows (`x86_64-freebsd`, `aarch64-freebsd`). |

Nothing else changed: `platform.zig`'s non-Linux fallthroughs
(`std.c.fstatat`, `arc4random`, …) are plain POSIX that FreeBSD provides
natively (the `.linux` blocks are statx/getrandom fast paths, not
requirements); `dl_suffixes` already tries `.so`; thottam takes the
`.so`/`$HOME` paths, including `build:` manifests; linenoise (termios)
works, so the REPL is the full one — history, editing, completion.
SRFI-170 is complete (uid/gid, symlinks, user/group info — the POSIX
slice Windows refuses).

## cond-expand / (features)

FreeBSD builds expose `posix`. The project convention is exactly one
OS-class identifier per build (`types.zig` `platform_features`), and
FreeBSD is a POSIX platform — there is no `freebsd` identifier, just as
macOS builds expose no `darwin`. The triple in `kaappi features` and the
crash banner (`aarch64-freebsd-none`) distinguishes the OS when it
matters. All capability identifiers (`kaappi-threads`, `kaappi-fibers`,
`kaappi-reactor`, `kaappi-diagnostics`) are present — nothing is gated.

## Native backend (`kaappi compile`)

Works, including on a box with no Zig toolchain: `kaappi compile` falls
back to the base system's `cc` (clang), which links the cross-compiled
`libkaappi_rt.a` cleanly — FreeBSD's compiler-rt supplies the builtins
the Zig-built archive references (verified on aarch64; `kaappi doctor`'s
smoke-link check confirms it per machine). The full E2E suite
(`tests/e2e/run-e2e.sh`) rebuilds the runtime lib with Zig, so it needs
a Zig toolchain; on a zig-less box, `kaappi doctor` plus a manual
`kaappi compile` run is the verification.

## The overcommit lesson (`GC.max_payload_bytes`)

The one genuine behavioral divergence the port surfaced: the graceful
out-of-memory diagnostic (its registry example is
`(make-bytevector 100000000000000)`) relied on malloc *refusing* absurd
requests. macOS and Linux do refuse 100 TB; FreeBSD's default
overcommit happily reserves it, and the bytevector zero-fill then
commits pages until the kernel's OOM killer ends the process — taking
the test harness with it. The fix is in the runtime, not the port:
`memory.zig` caps any single payload allocation (vector/bytevector/
string data) at `GC.max_payload_bytes` (1 TiB) and fails with the same
catchable out-of-memory error *before* asking the OS — deterministic on
every kernel, regardless of overcommit policy. Regression test:
`tests_exceptions.zig` "absurd payload requests raise catchable errors".

## Testing on a FreeBSD machine

No Zig toolchain is needed on the box — cross-compile everything and
copy it over (the same build-anywhere/execute-on-target idea as the
Windows port):

```bash
# on the dev machine
zig build -Dtarget=aarch64-freebsd            # or x86_64-freebsd
zig build test -Dtarget=aarch64-freebsd       # compiles unit-tests / thottam-tests
zig build lib -Dtarget=aarch64-freebsd        # native-backend runtime lib
rsync -a --exclude .zig-cache --exclude .git ./ box:kaappi/
rsync -a zig-out/bin/ box:kaappi/zig-out/bin/
rsync -a zig-out/lib/ box:kaappi/zig-out/lib/
rsync -a "$(ls -t .zig-cache/o/*/unit-tests | head -1)" \
         "$(ls -t .zig-cache/o/*/thottam-tests | head -1)" box:kaappi/

# on the box (base system has cc; bash comes from pkg)
doas pkg install -y bash
cd kaappi && ./unit-tests && ./thottam-tests
cc -shared -fPIC tests/scheme/ffi/fixtures/u64test.c \
   -o tests/scheme/ffi/fixtures/libu64test.so
bash tests/scheme/run-all.sh
```

The `compile/` shell suite self-skips without Zig on the box, exactly as
on Windows runners.

Reference machine for this port: FreeBSD 15.1-RELEASE aarch64 (4-core
VM). Zig's bundled FreeBSD libc floor is 14.0 (`file` on the binaries
shows "for FreeBSD 14.0"), so 14.x and 15.x are both in range.

## CI

`freebsd-test` (ci.yml) cross-compiles the binaries, test executables,
and `libkaappi_rt.a` for x86_64-freebsd on ubuntu-latest — the compile
gate — then boots a
FreeBSD 14.3 VM (vmactions/freebsd-vm, KVM-accelerated; GitHub hosts no
FreeBSD runners) that shares the workspace and executes the unit suite,
the thottam suite, and `run-all.sh` inside it. One job, no artifact
handoff, because the VM syncs the workspace directly. The VM release
pins the oldest supported line (14.x); the reference machine covers
15.x and aarch64.

## Known gaps

* Building natively with Zig **on** FreeBSD is expected to work (the
  target is fully supported upstream) but hasn't been exercised — the
  cross-compile + copy flow covers development, and the native backend
  needs only base `cc` at runtime.
* `tests/e2e/run-e2e.sh` and the `compile/` suite need a Zig toolchain
  on the box (see above); they run wherever one exists.
