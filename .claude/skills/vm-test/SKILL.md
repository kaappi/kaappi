---
name: vm-test
description: Power on a local UTM virtual machine and run Kaappi builds/tests on it over SSH. Use when the user asks to turn on a VM and test/build, to test or build on a UTM VM, on FreeBSD/OpenBSD/NetBSD/Windows, on the s390x or ppc64le Alpine VMs, on a real BSD or Windows box, or to verify the current branch on one of the local VMs. Complements /linux-test (podman) and /do-linux-test (DigitalOcean) with the local UTM fleet.
---

# UTM VM build/test

Power on one of the local UTM virtual machines and run the Kaappi build +
test suite on it over SSH. These VMs are the reference machines for Kaappi's
OS/architecture ports; this skill automates powering them on (via `utmctl`)
and running the same test battery CI runs on each.

All VMs are reachable through `~/.ssh/config` aliases with **passwordless
key auth** and passwordless admin (`doas` on the BSDs, `sudo` on Alpine).

## The fleet

| ssh alias | UTM name | OS / arch | Zig target | admin | `file` sig |
|-----------|----------|-----------|------------|-------|------------|
| `freebsd` | FreeBSD 15.1 | FreeBSD aarch64 | `aarch64-freebsd` | `doas` | `FreeBSD` |
| `openbsd` | OpenBSD 7.9 | OpenBSD aarch64 | `aarch64-openbsd` | `doas` | `OpenBSD` |
| `netbsd` | NetBSD 10.1 | NetBSD aarch64 | `aarch64-netbsd` | `doas` | `NetBSD` |
| `alpine` | Alpine-s390x | Linux **s390x** (big-endian) | `s390x-linux-musl` | `sudo` | `IBM S/390` |
| `alpine-ppc64le` | Alpine-ppc64le | Linux **ppc64le** | `powerpc64le-linux-musl` | `sudo` | `PowerPC` |
| `win11` | Windows 11 | Windows aarch64 | `aarch64-windows` | — | (see Windows) |

The s390x/ppc64le boxes are **emulated** (QEMU inside UTM) — slow to boot
and slow to run. The Alpine targets must be **`-musl`** (static): Alpine has
no glibc loader, so a glibc binary won't run there.

## Model: build-anywhere / execute-on-target

There is **no Zig toolchain on any box.** Cross-compile everything on the
Mac (`zig` cross-compiles all these targets), ship the repo + `zig-out` +
the two test executables over SSH, and run them on the box. This is exactly
what the port CI does. The native-backend `compile/` shell suite self-skips
when there is no Zig on the box (expected).

> Windows is different enough that it has its **own section** at the end —
> follow that, not the POSIX steps below.

---

## POSIX VMs (freebsd / openbsd / netbsd / alpine / alpine-ppc64le)

### 1. Pre-flight

Pick the VM with the user. Record the branch. **The working tree is shipped
via `tar` (step 4), so uncommitted changes _are_ tested** — no need to push
first (unlike `/do-linux-test`).

```bash
git -C "$PWD" rev-parse --abbrev-ref HEAD   # note the branch being tested
```

Copy the per-VM variable block for the chosen VM from **Per-VM specifics**
below — it sets `ALIAS TARGET SIG DEST CC DEPS RUNPREFIX`, which everything
downstream reads. For example, FreeBSD:

```bash
ALIAS=freebsd; TARGET=aarch64-freebsd; SIG=FreeBSD; DEST='~/kaappi'
CC=cc; DEPS='doas pkg install -y bash'; RUNPREFIX=''
```

### 2. Power on and wait for SSH

```bash
bash .claude/skills/vm-test/vm-up.sh "$ALIAS"
```

Starts the VM if it isn't running and blocks until SSH answers. For a cold
emulated boot (`alpine`, `alpine-ppc64le`) allow more time:
`WAIT_ITERS=120 bash .claude/skills/vm-test/vm-up.sh "$ALIAS"`.

### 3. Build for the target (on the Mac)

Rebuild for **this** target immediately before shipping — a `zig build` for
any other target clobbers `zig-out`, and stale test binaries from an earlier
target linger in `.zig-cache` (the recurring stale-binary footgun).

```bash
zig build            -Dtarget="$TARGET"    # kaappi, thottam, kaappi-lsp → zig-out/bin
zig build lib        -Dtarget="$TARGET"    # libkaappi_rt.a + stdlib .sld trees → zig-out/lib
zig build test       -Dtarget="$TARGET"    # compiles unit-tests + thottam-tests into .zig-cache
```

Select the two test executables **by `file` signature, not by mtime** — a
later host build leaves newer wrong-arch binaries in the cache:

```bash
rm -f ./unit-tests ./thottam-tests          # drop any stale staged copies first
UNIT=$(file .zig-cache/o/*/unit-tests     2>/dev/null | grep "$SIG" | head -1 | cut -d: -f1)
THOTTAM=$(file .zig-cache/o/*/thottam-tests 2>/dev/null | grep "$SIG" | head -1 | cut -d: -f1)
if [ -z "$UNIT" ] || [ -z "$THOTTAM" ]; then
  echo "no $SIG test binaries found — did 'zig build test -Dtarget=$TARGET' run?" >&2
else
  cp "$UNIT" ./unit-tests; cp "$THOTTAM" ./thottam-tests
fi
```

The `rm` first, then guard, means a missing target build fails closed — no
empty `cp`, and no stale binary from an earlier run left behind to ship.

**OpenBSD only** — patch the two test binaries so they survive BTCFI
enforcement (installed binaries in `zig-out` are auto-patched by the build;
the test executables are not). `-lc` is required — the tool uses libc I/O:

```bash
zig run tools/openbsd_nobtcfi.zig -lc -- ./unit-tests ./thottam-tests
```

### 4. Ship to the box

`rsync` is not present on every box, so sync with `tar` over SSH. `tar` from
macOS injects `._*` AppleDouble files that fail the fmt suite's `.sld`
scan — `COPYFILE_DISABLE=1` suppresses them. Ship the working tree, `zig-out`
(fresh target binaries + the full `lib` trees), and the two test binaries;
exclude `.git` and `.zig-cache`.

```bash
ssh "$ALIAS" "mkdir -p $DEST"
COPYFILE_DISABLE=1 tar --exclude=.git --exclude=.zig-cache -czf - . \
  | ssh "$ALIAS" "tar -xzf - -C $DEST"
rm -f ./unit-tests ./thottam-tests          # clean the staged copies from the worktree
```

Ship the **full** `zig-out/lib` (the srfi/chibi/kaappi `.sld` trees, not just
`libkaappi_rt.a`) or `kaappi test` workers fail with "test collector setup
failed" — the `tar .` above already includes it.

### 5. Run on the box

Install the one-time dependencies, then run the suites. See **Per-VM
specifics** below for the exact `DEPS`, `CC`, `BASH`, and `RUNPREFIX`
(ulimits) per box. Keep steps as separate SSH calls so no single call trips
the ~14-minute Bash tool timeout, and redirect the long Scheme run to a file
on the box so results survive a dropped stream.

`$RUNPREFIX` contains semicolons (`ulimit …; ulimit …;`), so each remote
command is wrapped in a `{ …; }` group — otherwise the `;` breaks the `&&`
chain and a failing suite is masked by the last command's status.

```bash
# 5a. one-time deps + FFI fixture ($DEPS and $CC are per-VM; see specifics)
ssh "$ALIAS" "cd $DEST && $DEPS && $CC -shared -fPIC \
  tests/scheme/ffi/fixtures/u64test.c -o tests/scheme/ffi/fixtures/libu64test.so"

# 5b. unit + thottam suites  ($RUNPREFIX raises ulimits on openbsd/netbsd; empty elsewhere)
ssh "$ALIAS" "cd $DEST && { $RUNPREFIX ./unit-tests; } && { $RUNPREFIX ./thottam-tests; }"

# 5c. Scheme suites → file on the box, propagating run-all.sh's real exit status
#     ($BASH is bare 'bash' except netbsd, where it's /usr/pkg/bin/bash)
ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=40 "$ALIAS" \
  "cd $DEST && { $RUNPREFIX $BASH tests/scheme/run-all.sh > /tmp/kaappi-vm-results.txt 2>&1; \
    status=\$?; echo EXIT: \$status; exit \$status; }"

# 5d. fetch results
ssh "$ALIAS" "cat /tmp/kaappi-vm-results.txt"
```

### 6. Report

Summarize: **Build** OK/FAIL · **unit-tests** pass/fail (all should pass) ·
**thottam-tests** · **run-all.sh** per-suite results + final
`N pass / M fail / K skip`. A healthy run is **0 fail** with a couple of
skips (the native-backend `compile/` suite self-skips without Zig on the
box). Call out any FAIL with its output; don't hardcode expected totals —
they grow as tests are added.

### 7. Power off (optional)

VMs are left running by default (matches "turn on"). If the user wants it
shut down afterward:

```bash
/Applications/UTM.app/Contents/MacOS/utmctl stop "<UTM name>"   # e.g. "FreeBSD 15.1"
```

---

## Per-VM specifics

Copy the block for the chosen VM — it sets everything step 5 reads
(`CC`, `BASH`, `DEPS`, `RUNPREFIX`).

**freebsd** — base `cc`, bash/rsync/python already present; repo at `~/kaappi`.

```bash
ALIAS=freebsd; TARGET=aarch64-freebsd; SIG=FreeBSD; DEST='~/kaappi'
CC=cc; BASH=bash; DEPS='doas pkg install -y bash'; RUNPREFIX=''
```

**openbsd** — needs bash; raise the tiny default rlimits or the unit binary
OOMs (DebugAllocator never reuses freed VA). Remember the nobtcfi patch in
step 3.

```bash
ALIAS=openbsd; TARGET=aarch64-openbsd; SIG=OpenBSD; DEST='~/kaappi'
CC=cc; BASH=bash; DEPS='doas pkg_add -I bash'
RUNPREFIX='ulimit -s $(ulimit -Hs); ulimit -d $(ulimit -Hd);'
```

**netbsd** — base `cc` is GCC (fine for the FFI fixture; the native backend
needs pkgsrc clang, not exercised here). bash isn't installed by default and
the non-login PATH lacks `/usr/pkg/bin`, so pin its full path in `BASH` and
`DEPS`. Only 4 GiB RAM with no swap, so the unit suite needs a swapfile.

```bash
ALIAS=netbsd; TARGET=aarch64-netbsd; SIG=NetBSD; DEST='~/kaappi'
CC=cc; BASH=/usr/pkg/bin/bash; DEPS='doas /usr/pkg/bin/pkgin -y install bash'
RUNPREFIX='ulimit -s $(ulimit -Hs); ulimit -d $(ulimit -Hd);'
# One-time, if the unit suite is OOM-killed ("out of swap"):
#   ssh netbsd 'doas sh -c "dd if=/dev/zero of=/swapfile bs=1m count=6144 && \
#     chmod 600 /swapfile && /sbin/swapctl -a /swapfile"'
```

**alpine (s390x)** and **alpine-ppc64le** — musl static targets; bash is
present, but the FFI fixture needs a compiler from `build-base` and Alpine
ships no `cc` alias, so use `gcc`. Emulated and slow; give the unit suite
memory headroom. First run has no repo — step 4's `mkdir -p` handles it.

```bash
# s390x:
ALIAS=alpine;         TARGET=s390x-linux-musl;       SIG='IBM S/390'; DEST='~/kaappi'
# ppc64le:
ALIAS=alpine-ppc64le; TARGET=powerpc64le-linux-musl; SIG=PowerPC;     DEST='~/kaappi'
CC=gcc; BASH=bash; DEPS='sudo apk add --no-cache build-base'; RUNPREFIX=''
```

Deep detail for each port lives in `docs/dev/{freebsd,openbsd,netbsd}.md`
and `docs/dev/porting.md` (s390x/ppc64le).

---

## Windows (win11)

Windows diverges: PowerShell/cmd shell, no `doas`/`sudo`, no native build
(Zig 0.16 access-violates compiling on ARM64 Windows — #1613), and a
different staged layout. Full detail is in `docs/dev/windows.md`; the
reference-machine quirks are in the `reference-win11-vm` memory.

1. **Power on:** `bash .claude/skills/vm-test/vm-up.sh win11`.
2. **Build on the Mac:** `zig build -Dtarget=aarch64-windows`,
   `zig build lib -Dtarget=aarch64-windows`,
   `zig build test -Dtarget=aarch64-windows` (a clean compile gate anywhere).
   Select `unit-tests.exe`/`thottam-tests.exe` from `.zig-cache` **by PE
   machine type, not mtime** — an `x86_64-windows` build (see the x64 note
   below) leaves same-named PE files in the cache. Match the arch, e.g.
   `file .zig-cache/o/*/unit-tests.exe | grep -i aarch64` (use `x86-64` for
   the x64 target), newest match wins.
3. **Ship** into `C:\tmp` (must exist — tests write `/tmp/...` → `\tmp`).
   Create the staging subdir first (`tar -C` won't make it), keep PowerShell
   off the binary stdin with a `cmd` wrapper, and suppress AppleDouble files:
   ```bash
   ssh win11 'cmd /c "if not exist C:\tmp\kaappi-vm mkdir C:\tmp\kaappi-vm"'
   COPYFILE_DISABLE=1 tar czf - <files> \
     | ssh win11 'cmd /c "tar -xzf - -C C:\tmp\kaappi-vm"'
   ```
4. **Run** unit-tests.exe + R7RS + the VM-verified `.scm` suites. Shell
   (`run-all.sh`) suites run under the box's Git Bash
   (`C:\tmp\PortableGit\bin\bash.exe`) via a scp'd runner script — quoting
   three shells deep (zsh→PowerShell→bash) breaks, so always run a script by
   path, never an inline compound.

Because the Windows flow is intricate and lower-frequency, prefer to walk it
from `docs/dev/windows.md` rather than improvising. For **x86_64** Windows
coverage, cross-compile `-Dtarget=x86_64-windows` and run on the same ARM64
VM under Windows' built-in x64 emulation (staged at `C:\tmp\kx64`).

---

## Notes

- **UTM.app must be able to run.** `vm-up.sh` calls `open -ga UTM` first so a
  closed app is launched in the background; `utmctl` then controls the VMs.
- **`cmd | tail; echo $?`** reports `tail`'s status, not the command's — check
  exit codes directly (this `zsh`/`PIPESTATUS` gap has bitten before).
- **Stale binaries** are the most common failure: always rebuild for the
  target right before shipping and pick test binaries by `file` signature.
- **Host keys:** `vm-up.sh` uses `accept-new` — a first-seen key is trusted,
  a *changed* one is refused. If a VM was rebuilt and its key changed,
  clear the old entry with `ssh-keygen -R <hostname>` before retrying.
- This skill runs the same battery as the `freebsd-test` / `openbsd-test` /
  `netbsd-test` / `s390x-test` / `ppc64le-test` / `windows-arm-test` CI jobs,
  but on the real reference hardware instead of a CI VM.
