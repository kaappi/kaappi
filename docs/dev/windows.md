# Windows port (aarch64 + x86_64)

Kaappi builds and runs on Windows 11, on both ARM64 and x86_64. The port
keeps the runtime's integer-fd POSIX-shaped I/O layer intact by mapping
it onto the C runtime's low-level io functions, and concentrates every
syscall-level platform difference in one file. Everything below is
OS-gated, not arch-gated — both architectures run the same platform
code; only the toolchain caveats differ.

```bash
zig build -Dtarget=aarch64-windows        # kaappi.exe, thottam.exe, kaappi-lsp.exe
zig build -Dtarget=x86_64-windows         # same three, x64
zig build test -Dtarget=aarch64-windows   # compiles unit-tests.exe (run it on Windows)
zig build test -Dtarget=x86_64-windows
```

Builds use Zig's bundled mingw-w64, so no Windows SDK or MSVC install is
needed on the build machine.

On **aarch64**, cross-compilation is currently the **only** way to
build: the official Zig 0.16.0 aarch64-windows toolchain
access-violates compiling anything natively on Windows ARM64
(`zig build` and `zig build-exe` alike, on any project — #1613). Root
cause: LLVM miscompiled `private thread_local` access on
aarch64-windows (ziglang#31865 on Codeberg), and the shipped zig.exe —
itself a stripped, LLVM-built aarch64-windows binary — carries the
miscompile. The LLVM fix landed ~2026-06 and Zig master nightlies
compile natively on the box; kaappi native builds unblock when the
first fixed release (0.17.0) ships and the pinned toolchain moves to
it.

On **x86_64**, none of that applies: #1613 is a bug in LLVM's aarch64
COFF backend, and the standard Zig 0.16.0 x86_64-windows toolchain
compiles natively. Cross-compiling from macOS/Linux and building
natively on an x64 Windows box both work today.

## Architecture: src/platform.zig

The runtime is written against integer file descriptors with POSIX
`read`/`write`/`open`/`close` semantics. `src/platform.zig` is the single
shim behind that surface:

* **POSIX targets** forward to `std.posix` / `std.c` — the exact calls the
  code made before the port; zero behavior change.
* **Windows** maps the same calls onto the CRT's low-level io layer
  (`_open`/`_read`/`_write`/`_close`: integer fds with 0/1/2 preopened),
  with wide-char path entry points (`_wopen`, `_wstat64`, …) so UTF-8
  paths survive regardless of the ANSI code page, plus a handful of Win32
  calls for what the CRT lacks: `QueryPerformanceCounter` (monotonic
  clock), console UTF-8 + VT mode, `GetModuleFileNameW` (self-exe path),
  `CreateProcessW` (process spawning with correct argument quoting),
  `LoadLibraryW`/`GetProcAddress` (FFI), `FindFirstFileW` (directory
  iteration), Win32 events for the reactor, and the ws2_32 slice behind
  socket readiness (`WSAEventSelect`, `recv`/`send`, `ioctlsocket` —
  see "Fd readiness" below).

Files are always opened `O_BINARY` — the CRT's default text mode would
rewrite `\n`/`\r\n` and treat `^Z` as EOF, which R7RS ports must never
see. The preopened standard fds get the same treatment at startup
(`platform.initStandardStreams`, called first thing in every binary's
main): stdout/stderr flip to binary unconditionally — piped output is
byte-identical to POSIX, and the console still renders bare `\n`
correctly (newline auto-return is independent of the CRT fd mode) —
while stdin flips only when it is *not* the interactive console, whose
line input relies on text mode (`\r\n` → `\n`, ^Z+Enter = EOF) for the
plain REPL. The same call switches the console to UTF-8 both ways and
enables VT processing. In kaappi-lsp this is also what keeps the
length-framed wire format intact: text-mode `\n`→`\r\n` rewriting on
fd 1 would corrupt `Content-Length` framing. Paths are normalized to
`/` at the boundaries that produce them (argv script path,
`GetModuleFileNameW`, `getcwd`, `_wfullpath`): Win32 accepts forward
slashes everywhere the runtime passes paths, and every internal path
split/join is written for `/` (a `std.fs.path.join`, which uses `\` on
Windows, is a bug — it broke `kaappi test --changed` suite discovery,
#1612).

## Fd readiness: sockets and pipes (#1608)

Fiber I/O suspension works on **sockets** (stage 1, event-driven) and
**pipes** (stage 2, polled); files keep blocking reads — which is not a
degradation at all, see below. Win32 has no unified readiness API for
arbitrary handles, so each kind uses what the platform can express. The
one-time `fdKind` probe (platform_win_pipe.zig) classifies a port's fd on
first touch: `GetFileType` separates disk files out, and `isSocketFd`'s
kernel-verified gates split PIPE-typed handles into sockets and pipes.

* **Socket ports.** A socket enters the port layer as a CRT fd created
  with `_open_osfhandle((intptr_t)sock, 0)` — the bridge contract for
  kaappi-net-style FFI code and `fd->port`. The probe marks the port
  `fd_state.is_socket`, so reads/writes route through
  `platform.sockRecv`/`sockSend` from the start — CRT `_read`/`_write`
  cannot operate on (overlapped) SOCKET handles at all — and once a
  scheduler exists the port also flips non-blocking via `FIONBIO`, whose
  `WSAEWOULDBLOCK → EAGAIN` errno mapping drives the shared
  park-and-retry protocol unchanged. The reactor backend
  (`WindowsEventBackend`, reactor.zig) arms `WSAEventSelect` on a single
  shared manual-reset event and sweeps `WSAEnumNetworkEvents` after each
  wakeup; a 0-timeout `select()` probe right after each arm closes the
  documented WSAEventSelect races (`FD_WRITE`/`FD_CLOSE` are
  edge-recorded, and re-issuing `WSAEventSelect` clears pending
  records). Ownership stays single-owner: the CRT owns the handle, so
  `platform.close` is plain `_close` even for sockets (kernel teardown
  is identical; a paired `closesocket` would double-close the handle
  value — a TOCTOU against other threads' allocations). The stale
  ws2_32 bookkeeping that leaves behind is neutralized in the probe:
  `isSocketFd` requires GetFileType == PIPE, getsockopt(`SO_TYPE`), and
  a kernel-verified `ioctlsocket(FIONREAD)` round-trip, so a file or
  pipe recycling a dead socket's handle value can never be
  misclassified as a socket.
* **Pipe ports** (anonymous or named, e.g. an fd from CRT `_pipe` bridged
  via `fd->port`) get *polled* readiness (platform_win_pipe.zig). Pipe
  fds have no would-block mode, so under a scheduler the port enters
  emulated non-blocking mode: `nonblocking` is set with no OS-level flip,
  and reads/writes route through `pipeRead`/`pipeWrite`, whose
  non-destructive pre-checks synthesize the EAGAIN the shared protocol
  expects — `PeekNamedPipe` gates reads, and
  `NtQueryInformationFile(FilePipeLocalInformation).WriteQuotaAvailable`
  (the same query libuv uses for non-overlapped pipe writes) gates
  writes, clamping each write to the space known to be free so the
  blocking CRT write underneath can never actually block. The reactor
  answers "when is it ready again" by re-running the same checks: while
  any pipe interest is armed, the backend bounds its wait at a 10 ms poll
  quantum and sweeps `pipePollReady` — the same latency order as the
  ~15 ms OS timer granularity that already bounds this backend, paid only
  while a fiber is actually parked on a pipe. Any check failure (broken
  pipe, wrong-direction end) reports ready so the retried syscall
  surfaces the real EOF/error; a failed write-quota query falls back to
  the plain blocking write (the pre-stage-2 behavior, never a wrong
  result). Sequential programs never set the flag: their pipe ports keep
  plain blocking `_read`/`_write` and the exact pre-stage-2 syscall
  profile.
* **File ports** stay fully blocking — deliberately and permanently,
  because that is the cross-platform baseline, not a Windows gap: POSIX
  has no readiness for regular files either (`O_NONBLOCK` is a no-op on
  them; epoll rejects them with EPERM, kqueue reports them always-ready),
  so the kqueue/epoll builds also block the OS thread for the duration of
  a disk read. Only a true async-file-I/O model (io_uring-class) would
  change this, on every platform alike — out of scope for the KEP-0001
  readiness model.
* **Timers and cross-thread wakeups** are unaffected either way: the
  same backend serves `thread-sleep!` and timed channel/mutex waits
  (`WaitForMultipleObjects` bounded by the nearest deadline) and the
  KEP-0002 notify ring (`SetEvent` on the auto-reset notify event).
  Timer granularity is the OS scheduler's (~15 ms), coarser than
  kqueue/epoll.

Fibers, channels (including capacity-0 rendezvous), SRFI-18 OS threads,
and cross-thread SharedChannel promotion all work on top of this.

### Why polling, not IOCP (#1608 stage 2 evaluation)

The issue's stage-2 question — do pipes/files justify a completion-based
(IOCP/overlapped) rework of the park-and-retry protocol? — resolved to
**no**, on three grounds:

1. **IOCP cannot serve the fds the port layer actually sees.** Overlapped
   I/O requires `FILE_FLAG_OVERLAPPED` at handle creation, and the pipe
   fds that reach the runtime — CRT `_pipe`, inherited descriptors,
   foreign FFI code wrapping `CreatePipe` handles — are synchronous
   handles without it. The only general completion design is a blocking
   worker-thread pool (libuv's fallback for non-overlapped pipes), a new
   subsystem whose issued-read semantics also break the retry protocol's
   guarantees: a worker that has consumed bytes when the waiting fiber is
   terminated or the port closed loses data that the park-and-retry
   model, which never reads until readiness is known, cannot lose.
2. **Files gain nothing from any of it** — POSIX offers no regular-file
   readiness either (see above), so there is no behavior gap to close.
3. **Pipes don't need completion.** The polled design above keeps the
   protocol byte-for-byte, reuses the backend's existing per-wait sweep
   shape, and its 10 ms worst-case wake latency sits inside the latency
   envelope the platform's own timer granularity already imposes — and
   the quantum is paid only while a pipe waiter exists.

## Other deliberate degradations

* **POSIX-only SRFI-170 raises.** uid/gid, `user-info`/`group-info`,
  symlinks, hard links, FIFOs, `set-file-mode`, `umask`, `nice`,
  `truncate-file`, and `set-file-times` raise a catchable file error
  ("… not supported on Windows") — the names stay bound so portable code
  can probe with `guard`. `file-info` works; inode, blksize, and blocks
  report 0 (Windows has no such concepts at the CRT layer).
* **`long` FFI type is 32-bit** on Windows (LLP64), faithfully matching
  C. `normalizeType` (ffi.zig) routes it through the 32-bit `.int`
  marshaling class there; `int64`/`uint64`/`size_t` use the 64-bit
  carrier (`i64`) everywhere.
* **`(ffi-open #f)` sees the whole process.** The process self-handle
  gets POSIX `dlopen(NULL)` semantics: `dlSym` (platform.zig) probes
  every loaded module in load order via `K32EnumProcessModules`, so CRT
  symbols (`abs`, `qsort`, `strlen`, …) resolve even though they live in
  `ucrtbase.dll` rather than the exe — `GetProcAddress` on the exe module
  alone would find nothing (mingw exes export no symbols). Named opens
  probe a `.dll` suffix (`dl_suffixes`); there is no `libm.dll`, so tests
  that need the math functions `cond-expand` to `(ffi-open "ucrtbase")`
  on Windows. FFI callbacks (comptime Zig trampolines, `callconv(.c)`)
  work unchanged — the qsort-with-Scheme-comparator tests pass.
* **thottam `build:` commands are refused.** The package manager itself
  is fully ported (#1609): install/remove/update/list/verify all work —
  the install pipeline's file work (recursive copy/remove/walk,
  `mkdir -p`, `touch`) runs on shim-based helpers (`thottam_fs.zig`)
  instead of POSIX userland, on every platform. What remains
  Windows-refused is a manifest's `build:` line: it ran via `/bin/sh -c`
  and every ecosystem `build:` is a Makefile producing POSIX shared
  libraries, so thottam errors clearly instead — pure-Scheme packages
  (most of the ecosystem) have no `build:` line and install fine. Needs
  Git for Windows on PATH, like every git operation.
* **REPL** uses a plain prompt + line reader (linenoise is termios-only):
  the full REPL loop — debug commands, multi-line input, themes — works,
  without history/completion/editing.

## cond-expand / (features)

Windows builds expose the `windows` feature identifier and omit `posix`
(exactly one OS-class identifier per build — `types.platform_features`).
Scheme tests that exercise POSIX-only functionality gate themselves:

```scheme
(cond-expand
  (windows (display "skipped on windows\n") (exit 0))
  (else #f))
```

## Native backend (`kaappi compile`)

The full pipeline — emit LLVM IR, discover the runtime archive, link with
the first C compiler on PATH, run the native binary — works on the box
and is exercised end-to-end by `tests/e2e/run-e2e.ps1` (the PowerShell
port of run-e2e.sh's parity phase): all 37 `tests/e2e/programs` compile
natively and match the interpreter's output, and `kaappi doctor`'s
smoke-link passes. Verified on Windows 11 ARM64 (build 26100) with a Zig
master toolchain as the linker (#1610); with the 0.16.0 toolchain,
`zig cc` on the box access-violates like every native toolchain use
(#1613), so aarch64 end users get this at the 0.17.0 bump. On x86_64
the stock 0.16.0 toolchain already works as the linker: the same e2e
suite passes on the reference VM under x64 emulation with
zig-x86_64-windows-0.16.0 on PATH, and the `windows-x64-test` CI job
runs it on every PR.

Windows-specific pieces of the path (#1610):

* The runtime archive is `kaappi_rt.lib` (Zig's COFF naming), not
  `libkaappi_rt.a` — `platform.rt_lib_name` carries the platform
  spelling, and the `findLibDir`/doctor probes and messages use it. The
  search order is unchanged: `KAAPPI_LIB_DIR`, `<exe>/../lib`,
  `zig-out/lib`, `/usr/local/lib`.
* `kaappi compile foo.scm` derives `foo.exe` (PATH lookup and
  double-click need the extension); an explicit `-o name` is used as
  given.
* The emitted module triple is `aarch64-pc-windows-gnu` /
  `x86_64-pc-windows-gnu` per arch — the gnu (MinGW) ABI the runtime
  lib is built with and the ABI `zig cc` targets on a box without MSVC.
* The link line adds `-lws2_32` and drops `-lpthread`: the fd-readiness
  backends call Winsock through `extern "ws2_32"` declarations, which
  Zig links automatically only when it builds the final binary itself —
  a foreign `zig cc` link of the static archive must name the import lib
  explicitly. The equivalent manual link is:

  ```
  zig cc -w -O2 out.ll -o prog.exe -L<libdir> -lkaappi_rt -lc -lm -lws2_32
  ```

## Testing on a Windows machine

CI covers the target three ways (ci.yml): `windows-cross`
cross-compiles the binaries and the test exes from Linux for **both**
arches (a matrix over aarch64/x86_64), guarding the path release.yml
ships with, and two execution jobs run the unit suite, the thottam
suite plus a real package install/remove integration test, the R7RS
suite, the VM-verified `.scm` suites, and the shell-based suites
(#1612) on every PR: `windows-arm-test` on GitHub's hosted
`windows-11-arm` runners and `windows-x64-test` on the standard
x86_64 `windows-latest` runners. Both execution jobs run the suites
from the cross-compiled artifacts with no toolchain installed — on
aarch64 because native compilation is broken in the Zig 0.16.0
toolchain itself (#1613), on x64 so both jobs exercise identical
no-toolchain conditions. The x64 job then installs the (natively
working) x86_64 Zig and runs the native-backend e2e suite
(`tests/e2e/run-e2e.ps1`, #1610) — the one leg the arm job cannot
have until the 0.17.0 bump. The FFI suite runs against a fixture DLL
that `windows-cross` cross-compiles into each artifact
(`zig cc -target <arch>-windows-gnu -shared`).

The shell-based drivers (errors, test-runner, pipeline, doctor, fmt,
cache, timings, the smoke `.sh` scripts, sandbox, robustness) run under
the runner's Git Bash, whose MSYS userland supplies bash, coreutils,
git, and — via a CI shim when the image only exposes `python` — python3.
A driver whose premise cannot hold on Windows sources
`tests/scheme/shell-common.sh` and calls `skip_on_windows <reason>`,
exiting 77 (the shell analogue of the `cond-expand (windows ...)` gate
the `.scm` tests use); run-all.sh and the CI loop report those as SKIP.
Today that is the `compile/` suite (each script rebuilds the runtime
archive or interpreter with a native `zig` on the box — #1613, so the
gates lift work at the 0.17.0 toolchain bump) and
`profile-json-escaping.sh` (it plants `"`/`\` in a real directory name,
which Windows filenames cannot contain). shell-common.sh also carries
the portability helpers the drivers need on Windows: `native_path` (the
C:/-style spelling the binary itself prints, via `cygpath -m` — MSYS
`/tmp/...` paths never appear in kaappi's own output) and `rt_lib_name`
(`kaappi_rt.lib` vs `libkaappi_rt.a`).

What CI still can't run — interactive surfaces like the console REPL —
is verified against a real Windows 11 ARM64 machine (e.g. a UTM VM with
ssh). Before any decisive run on the box, `kaappi cache clear` — dirty
builds at the same commit share bytecode-cache ids with different code.
The unit-test binary compiles with the same target flag and runs on the
box:

```bash
zig build test -Dtarget=aarch64-windows       # compiles; foreign run steps skip cleanly
scp .zig-cache/o/*/unit-tests.exe win11:...   # run it there
```

Two environment notes for the suite:

* Create `C:\tmp` first — the Scheme/Zig tests write scratch files under
  `/tmp/...`, which Windows resolves to `\tmp` on the current drive.
* Run from a writable directory; a few tests create files in the CWD.

Verified on Windows 11 ARM64 (build 26100): full unit suite, the
complete R7RS suite, every `tests/scheme/{smoke,compliance,
continuations,hygiene,srfi,ffi,audit}` file, and the shell-based
suites under Git Bash (34 pass, 15 skip: the 14 `compile/` gates plus
`profile-json-escaping.sh`) — the same set the `windows-arm-test` CI
job now runs on every PR.

The **x86_64** build was verified on the same reference machine via
Windows 11's built-in x64 emulation layer (x64 binaries run
transparently on ARM64 Windows), which is also how to re-test it
there: cross-compile with `-Dtarget=x86_64-windows`, ship, run. The
full set passed under emulation — unit suite (1166/0, 15 skips),
thottam suite, R7RS, all 436 `.scm` suite files, the shell suites
(same 34/15/0 profile as aarch64), the post-release acceptance script
(34/34), and the native-backend e2e (see above). A stripped x86_64
kaappi.exe starts and runs correctly — the #1607 strip crash does not
exist on this arch. Emulation is a fidelity compromise (it validates
the port's logic, not x64 silicon); the `windows-x64-test` CI job runs
the same suites on real x86_64 runners on every PR, so the VM is only
needed for what CI can't reach (interactive REPL, release smoke
tests). The fd-readiness unit
suites (`tests_reactor.zig`, `tests_scheduler.zig`, `tests_port_io.zig`)
run on Windows too: testing_helpers' cross-platform fd pairs substitute
loopback TCP socket pairs for the POSIX pipes/socketpairs, so those
suites double as the socket-readiness backend's coverage, and their
"#1608:" tests run the same park/wake patterns over real CRT `_pipe`
pairs, covering the polled pipe backend (stage 2). The
POSIX-permission/FIFO/uid tests and the dup2-based fd-recycle reactor
test skip. With a fixed (master) toolchain on the box, the
native-backend parity suite `tests/e2e/run-e2e.ps1` passes too (#1610,
see "Native backend" above).

## Releasing

`release.yml` cross-compiles both Windows rows from ubuntu runners and
ships `kaappi-{aarch64,x86_64}-windows.exe`,
`thottam-{aarch64,x86_64}-windows.exe`, and
`libkaappi_rt-{aarch64,x86_64}-windows.lib` (the gnu-ABI static lib is
emitted as `kaappi_rt.lib`). The **aarch64** row builds with
`-Dstrip=false`: a **stripped** kaappi.exe access-violates at startup
on ARM64 Windows (0xC0000005 before any output — #1607). Root cause:
under strip, Zig demotes threadlocals to `private` linkage and LLVM
emits a broken +64 KB TLS offset for them on aarch64-windows
(ziglang#31865) — kaappi reaches `vm_instance`/`gc_instance` at
startup, while thottam and small probes have no affected threadlocal
access, which is why only kaappi.exe crashed. Fixed in LLVM/Zig
master; re-enable strip for the row and retest after the toolchain
bump (#1613). The **x86_64** row strips like every other platform —
the miscompile lives in LLVM's aarch64 COFF backend, and a stripped
x64 kaappi.exe was verified working on the reference VM. Post-release,
the x86_64 artifact has a real acceptance leg (`test-windows-x64` in
post-release.yml, on windows-latest); the aarch64 artifact is
checksummed but not executed (a `windows-11-arm` leg is still open) —
smoke-test it manually per the github-release skill's Step 10.

## Known gaps / follow-ups

* Native compilation on Windows **ARM64** crashes in the Zig 0.16.0
  toolchain (`zig build`/`zig build-exe`/`zig cc` access-violate on any
  project, #1613) — aarch64 builds must cross-compile, and `kaappi
  compile` needs a fixed toolchain on the box for its link step
  (verified end-to-end with Zig master, see "Native backend" above).
  Fixed upstream (ziglang#31865); everything unblocks at the 0.17.0
  toolchain bump. x86_64 Windows is unaffected.
* The `compile/` shell suite self-skips on Windows: every script
  rebuilds the runtime archive or the interpreter with a native `zig`
  on the box, which #1613 breaks on aarch64. The `skip_on_windows`
  gates (tests/scheme/shell-common.sh) are OS-level, so they also skip
  on x86_64 where a native zig would actually work — the scripts
  themselves have never been ported to Windows path/exe-suffix
  conventions. Lifting the gates (per-arch or wholesale at the 0.17.0
  bump) is open; the native-compile path on x64 is covered by
  run-e2e.ps1 in `windows-x64-test` meanwhile. (The rest of the
  shell-based suites run in CI — #1612.)
* thottam refuses manifests with a `build:` command (#1609 ported
  everything else — see Deliberate degradations above); lifting that
  needs a Windows build story for the C-FFI packages, which today are
  Makefiles producing `.dylib`/`.so` against POSIX headers.
* Console reads are byte-oriented ANSI/UTF-8; typing non-ASCII at the
  plain REPL depends on the console's UTF-8 code page (set at startup).
* Long paths (> 260 chars) need the system long-path opt-in.
* `-Dstrip=true` produces a kaappi.exe that access-violates at startup
  on ARM64 Windows (#1607, see Releasing above) — the aarch64 release
  row ships unstripped until the toolchain bump lands the LLVM TLS
  fix. The x86_64 row is unaffected and ships stripped.
