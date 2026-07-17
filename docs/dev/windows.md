# Windows port (aarch64)

Kaappi builds and runs on Windows 11 ARM64. The port keeps the runtime's
integer-fd POSIX-shaped I/O layer intact by mapping it onto the C
runtime's low-level io functions, and concentrates every syscall-level
platform difference in one file.

```bash
zig build -Dtarget=aarch64-windows        # kaappi.exe, thottam.exe, kaappi-lsp.exe
zig build test -Dtarget=aarch64-windows   # compiles unit-tests.exe (run it on Windows)
```

Builds use Zig's bundled mingw-w64, so no Windows SDK or MSVC install is
needed on the build machine.

Cross-compilation is currently the **only** way to build: the official
Zig 0.16.0 aarch64-windows toolchain access-violates compiling anything
natively on Windows ARM64 (`zig build` and `zig build-exe` alike, on any
project — #1613). Root cause: LLVM miscompiled `private thread_local`
access on aarch64-windows (ziglang#31865 on Codeberg), and the shipped
zig.exe — itself a stripped, LLVM-built aarch64-windows binary — carries
the miscompile. The LLVM fix landed ~2026-06 and Zig master nightlies
compile natively on the box; kaappi native builds unblock when the first
fixed release (0.17.0) ships and the pinned toolchain moves to it.

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
see. Paths are normalized to `/` at the boundaries that produce them
(argv script path, `GetModuleFileNameW`, `getcwd`, `_wfullpath`): Win32
accepts forward slashes everywhere the runtime passes paths, and every
internal path split/join is written for `/`.

## Fd readiness: sockets only (#1608 stage 1)

Fiber I/O suspension works on **sockets**; pipes and files keep blocking
reads. Win32 has no unified readiness API for arbitrary handles, so the
split follows what the platform can express:

* **Socket ports.** A socket enters the port layer as a CRT fd created
  with `_open_osfhandle((intptr_t)sock, 0)` — the bridge contract for
  kaappi-net-style FFI code and `fd->port`. `maybeSetNonblocking`'s
  one-time `isSocketFd` probe (GetFileType cross-check + getsockopt
  `SO_TYPE`) marks the port `sock_state.is_socket` on first touch, so
  reads/writes route through `platform.sockRecv`/`sockSend` from the
  start — CRT `_read`/`_write` cannot operate on (overlapped) SOCKET
  handles at all — and once a scheduler exists the port also flips
  non-blocking via `FIONBIO`, whose `WSAEWOULDBLOCK → EAGAIN` errno
  mapping drives the shared park-and-retry protocol unchanged. The
  reactor backend (`WindowsEventBackend`, reactor.zig) arms
  `WSAEventSelect` on a single shared manual-reset event and sweeps
  `WSAEnumNetworkEvents` after each wakeup; a 0-timeout `select()` probe
  right after each arm closes the documented WSAEventSelect races
  (`FD_WRITE`/`FD_CLOSE` are edge-recorded, and re-issuing
  `WSAEventSelect` clears pending records). `platform.close` tries
  `closesocket` before `_close` on every fd: a socket closed by bare
  CloseHandle leaks ws2_32's per-handle state, which then falsely claims
  whatever file later recycles that handle value is a socket.
* **Pipe and file ports.** CRT fds for pipes/files have no would-block
  mode, so these ports never flip non-blocking, never EAGAIN, and never
  reach the reactor — single-fiber blocking I/O, the WASI probe-fail
  shape. Lifting this needs a completion-based (IOCP/overlapped) rework
  of the retry protocol, deliberately deferred (#1608 stage 2).
* **Timers and cross-thread wakeups** are unaffected either way: the
  same backend serves `thread-sleep!` and timed channel/mutex waits
  (`WaitForMultipleObjects` bounded by the nearest deadline) and the
  KEP-0002 notify ring (`SetEvent` on the auto-reset notify event).
  Timer granularity is the OS scheduler's (~15 ms), coarser than
  kqueue/epoll.

Fibers, channels (including capacity-0 rendezvous), SRFI-18 OS threads,
and cross-thread SharedChannel promotion all work on top of this.

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
* **thottam** builds and runs (`list`, `verify`, `--help`); `install`/
  `remove`/`update` print a clear unsupported error — the install
  pipeline shells out to POSIX userland (`cp -R`, `find`, `sh -c`) that
  needs reimplementing on the shim first.
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

## Testing on a Windows machine

CI covers the target twice (ci.yml): `windows-cross` cross-compiles the
binaries and the unit-test exe from Linux, guarding the path release.yml
ships with, and `windows-arm-test` executes the unit suite, the R7RS
suite, and the VM-verified `.scm` suites on GitHub's hosted
`windows-11-arm` runners on every PR. The execution job installs no
toolchain — it downloads the binaries `windows-cross` built as an
artifact, because native compilation on Windows ARM64 is broken in the
Zig 0.16.0 toolchain itself (#1613). The FFI suite runs against a
fixture DLL that `windows-cross` cross-compiles into the same artifact
(`zig cc -target aarch64-windows-gnu -shared`). What CI can't run yet —
the shell-based suites (#1612) and interactive surfaces like the REPL —
is verified against a real Windows 11 ARM64 machine (e.g. a UTM VM with
ssh). The unit-test binary compiles with the same target flag and runs
on the box:

```bash
zig build test -Dtarget=aarch64-windows       # compiles; foreign run steps skip cleanly
scp .zig-cache/o/*/unit-tests.exe win11:...   # run it there
```

Two environment notes for the suite:

* Create `C:\tmp` first — the Scheme/Zig tests write scratch files under
  `/tmp/...`, which Windows resolves to `\tmp` on the current drive.
* Run from a writable directory; a few tests create files in the CWD.

Verified on Windows 11 ARM64 (build 26100): full unit suite, the
complete R7RS suite, and every `tests/scheme/{smoke,compliance,
continuations,hygiene,srfi,ffi,audit}` file — the same set the
`windows-arm-test` CI job now runs on every PR. The fd-readiness unit
suites (`tests_reactor.zig`, `tests_scheduler.zig`, `tests_port_io.zig`)
run on Windows too: testing_helpers' cross-platform fd pairs substitute
loopback TCP socket pairs for the POSIX pipes/socketpairs, so those
suites double as the socket-readiness backend's coverage (#1608). The
POSIX-permission/FIFO/uid tests and the dup2-based fd-recycle reactor
test skip.

## Releasing

`release.yml` cross-compiles the Windows row from an ubuntu runner and
ships `kaappi-aarch64-windows.exe`, `thottam-aarch64-windows.exe`, and
`libkaappi_rt-aarch64-windows.lib` (the gnu-ABI static lib is emitted as
`kaappi_rt.lib`). The row builds with `-Dstrip=false`: a **stripped**
kaappi.exe access-violates at startup on ARM64 Windows (0xC0000005
before any output — #1607). Root cause: under strip, Zig demotes
threadlocals to `private` linkage and LLVM emits a broken +64 KB TLS
offset for them on aarch64-windows (ziglang#31865) — kaappi reaches
`vm_instance`/`gc_instance` at startup, while thottam and small probes
have no affected threadlocal access, which is why only kaappi.exe
crashed. Fixed in LLVM/Zig master; re-enable strip for the row and
retest after the toolchain bump (#1613). The post-release acceptance workflow checksums the Windows
artifacts but does not yet execute them (wiring it to the hosted
`windows-11-arm` runners is open) — smoke-test a release manually per
the github-release skill's Step 10.

## Known gaps / follow-ups

* Fiber I/O suspension on **pipes and files** still blocks the OS thread
  (#1608 stage 2): CRT fds for those have no would-block mode, so lifting
  it means a completion-based (IOCP/overlapped) rework of the
  park-and-retry protocol. Sockets are done (stage 1, above).
* Native compilation on Windows ARM64 crashes in the Zig 0.16.0
  toolchain (`zig build`/`zig build-exe` access-violate on any project,
  #1613) — all builds must cross-compile, and `kaappi compile` on the
  box (#1610) is blocked on the same upstream fix. Fixed upstream
  (ziglang#31865; Zig master works on the box, verified 2026-07-17);
  both unblock at the 0.17.0 toolchain bump.
* The shell-based suites — errors, compile, test-runner, pipeline,
  doctor, fmt, cache, timings, the smoke `.sh` scripts, sandbox, and
  robustness — don't run on Windows (#1612).
* thottam package installation (replace the POSIX userland calls with
  shim-based recursive copy/remove/walk; git is already spawned via
  CreateProcessW and works when Git for Windows is on PATH).
* `kaappi compile` links with `zig cc` when Zig is installed on the box;
  untested beyond the doctor's smoke-link probe.
* Console reads are byte-oriented ANSI/UTF-8; typing non-ASCII at the
  plain REPL depends on the console's UTF-8 code page (set at startup).
* Long paths (> 260 chars) need the system long-path opt-in.
* `-Dstrip=true` produces a kaappi.exe that access-violates at startup
  on ARM64 Windows (#1607, see Releasing above) — releases ship it
  unstripped until the toolchain bump lands the LLVM TLS fix.
