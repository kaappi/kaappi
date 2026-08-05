#!/bin/bash
# kaappi#2224: TAB after a comma-command prefix appended instead of replacing.
#
# `completionCallback` in src/repl.zig used to call `ic.addCompletion`
# directly for comma-commands, bypassing `ic.completeWord`. isocline's
# `ic_add_completion` defaults `delete_before` to 0 — it only deletes the
# already-typed prefix when routed through `ic_complete_word`, which computes
# the word boundary itself. Typing `,h` then TAB spliced the full replacement
# in at the cursor without deleting `,h` first, producing `,h,help`. This
# needs a real terminal (isocline's completion menu, not a piped stdin), so
# it runs under a pty like `repl-structural-editing-2216.sh`.

set -eu

KAAPPI="${KAAPPI:-${1:-zig-out/bin/kaappi}}"

. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "no pty; isocline drives the Windows console API directly"

command -v python3 >/dev/null 2>&1 || {
    echo "SKIP: python3 is needed to allocate a pty"
    exit 77
}

case "$KAAPPI" in
    */*) kaappi_abs="$(cd "$(dirname "$KAAPPI")" 2>/dev/null && pwd)/$(basename "$KAAPPI")" ;;
    *)   kaappi_abs="$(command -v "$KAAPPI" || true)" ;;
esac
if [ ! -x "$kaappi_abs" ]; then
    echo "FAIL: $KAAPPI is not an executable file (build first: zig build)"
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

driver="$work/drive.py"
cat > "$driver" <<'PY'
import fcntl, os, pty, re, select, struct, sys, termios, time

kaappi = sys.argv[1]
ansi = re.compile(rb'\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][B0]|\x1b[=>]|\r')

pid, fd = pty.fork()
if pid == 0:
    try:
        os.environ['TERM'] = 'xterm'
        os.environ['NO_COLOR'] = '1'
        os.execv(kaappi, [kaappi])
    except BaseException:
        pass
    os._exit(127)

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 200, 0, 0))

buf = b''
eof = False
deadline = time.time() + 60

def pump(timeout):
    global buf, eof
    try:
        r, _, _ = select.select([fd], [], [], timeout)
    except OSError:
        eof = True
        return False
    if not r:
        return False
    try:
        chunk = os.read(fd, 65536)
    except OSError:
        eof = True
        return False
    if not chunk:
        eof = True
        return False
    buf += chunk
    return True

def seen(mark=0):
    return ansi.sub(b'', buf[mark:])

def wait_for(needle, mark=0, timeout=20):
    end = min(time.time() + timeout, deadline)
    while time.time() < end:
        if needle in seen(mark):
            return True
        if eof:
            break
        pump(0.2)
    return needle in seen(mark)

def idle(quiet=0.5, limit=5.0):
    end = time.time() + limit
    while time.time() < end:
        if not pump(quiet):
            return

def send(data):
    os.write(fd, data)
    time.sleep(0.05)

if not wait_for(b'kaappi> ', 0, 25):
    if not buf:
        sys.stdout.write('the REPL produced no output at all; it did not start\n')
        sys.exit(1)
    sys.stdout.write('no prompt in:\n%r\n' % seen())
    sys.exit(77)
idle()

failures = []

# Case 1: unique prefix (",h" -> only ",help" matches) completes in place —
# the buggy version left ",h,help" on the line.
mark = len(buf)
send(b',h')
if not wait_for(b',h', mark, 20):
    failures.append(('unique-prefix: no echo', seen(mark)))
else:
    idle(0.3)
    send(b'\t')
    idle(0.3)
    produced = seen(mark)
    if b',h,help' in produced:
        failures.append(('unique-prefix: appended instead of replaced', produced))
    elif b',help' not in produced:
        failures.append(('unique-prefix: did not complete to ,help', produced))
send(b'\x15')  # ctrl-u: clear the line before the next case
idle(0.3)

# Case 2: multi-candidate prefix (",d" -> ,dis / ,delete / ,describe) must
# still offer the menu without corrupting the typed text either.
mark = len(buf)
send(b',d')
if not wait_for(b',d', mark, 20):
    failures.append(('multi-candidate: no echo', seen(mark)))
else:
    idle(0.3)
    send(b'\t')
    idle(0.3)
    produced = seen(mark)
    if b',d,d' in produced:
        failures.append(('multi-candidate: line corrupted', produced))
    for cmd in (b',dis', b',delete', b',describe'):
        if cmd not in produced:
            failures.append(('multi-candidate: menu missing %r' % cmd, produced))
send(b'\x15')
idle(0.3)

send(b',quit\r')
while pump(1.0):
    pass

# Bounded reap: a hung `,quit` must fail the test, not hang the process
# (and the CI worker after it, since the outer shell timeout only kills this
# script's own pid, not a grandchild it never waited for).
shutdown_deadline = time.time() + 10
exit_status = None
while time.time() < shutdown_deadline:
    try:
        reaped, exit_status = os.waitpid(pid, os.WNOHANG)
    except OSError:
        reaped = pid  # already reaped
    if reaped == pid:
        break
    time.sleep(0.1)
else:
    failures.append(('shutdown: REPL did not exit after ,quit', seen()))
    try:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    except OSError:
        pass

if exit_status is not None and os.WIFEXITED(exit_status) and os.WEXITSTATUS(exit_status) != 0:
    failures.append(('shutdown: REPL exited with status %d' % os.WEXITSTATUS(exit_status), b''))

try:
    os.close(fd)
except OSError:
    pass

for label, produced in failures:
    sys.stdout.write('FAIL %s:\n%r\n\n' % (label, produced))
sys.exit(1 if failures else 0)
PY

set +e
KAAPPI_HOME="$work/home" python3 "$driver" "$kaappi_abs"
status=$?
set -e

case $status in
    0)  echo "PASS: comma-command TAB completion replaces the typed prefix"; exit 0 ;;
    77) echo "SKIP: no usable pty for the REPL here"; exit 77 ;;
    *)  echo "FAIL: comma-command TAB completion corrupted the line"; exit 1 ;;
esac
