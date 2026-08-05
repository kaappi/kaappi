#!/bin/bash
# kaappi#2226: pasting a block with more than one top-level form into the
# REPL dropped everything after the first form.
#
# Many terminal emulators deliver a pasted newline as a literal CR ('\r') —
# the same byte a real Enter keypress sends. `ic_editline` (isocline) wraps
# every `ic_readline` call in `tty_start_raw()`/`tty_end_raw()`
# (vendor/isocline/src/tty.c), and both used `tcsetattr(..., TCSAFLUSH, ...)`.
# TCSAFLUSH discards any input the kernel has already received but the
# process has not yet read(2) — so the moment the first pasted form's CR
# submits it (that line alone is already complete) and `ic_editline` returns,
# `tty_end_raw()`'s flush throws away the rest of the still-unread paste
# before the REPL ever asks for it. This needs a real terminal (isocline's
# raw-mode reads, not a piped stdin), so it runs under a pty like
# `repl-structural-editing-2216.sh`.

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

if not wait_for(b'kaappi> ', 0, 25):
    # Two very different things look alike here, and conflating them is how a
    # test goes quietly green: a REPL that wrote *nothing at all* did not run,
    # which is a failure; a REPL that wrote something but never prompted has no
    # usable terminal, which is a skip (the alternative is a flake on every
    # emulated CI leg).
    if not buf:
        sys.stdout.write('the REPL produced no output at all; it did not start\n')
        sys.exit(1)
    sys.stdout.write('no prompt in:\n%r\n' % seen())
    sys.exit(77)
idle()

failures = []

# Paste three separate, individually-complete top-level forms as ONE write(2)
# — the way a terminal delivers a clipboard paste, not one line at a time.
# Newlines arrive as CR ('\r'), matching how terminals commonly translate a
# pasted newline into the same byte a real Enter keypress sends: the buggy
# version submitted the first form on its CR and then discarded the rest of
# the still-unread paste when isocline dropped back out of raw mode.
mark = len(buf)
paste = b'(define x 1)\r(define y 2)\r(display (+ x y))\r'
os.write(fd, paste)
if not wait_for(b'kaappi> ', mark, 20):
    failures.append(('paste: no prompt returned after pasted block', seen(mark)))
idle(0.3)

produced = seen(mark)
if b'3' not in produced:
    failures.append(('paste: (display (+ x y)) did not print 3 — later forms were lost', produced))

# Confirm `y` actually landed as a binding (not just that "3" appeared
# somewhere incidentally) by asking for it directly.
mark = len(buf)
send = lambda data: (os.write(fd, data), time.sleep(0.05))
send(b'y\r')
wait_for(b'kaappi> ', mark, 10)
idle(0.3)
produced = seen(mark)
if b'undefined variable' in produced:
    failures.append(("paste: 'y' was never defined — the second form was dropped", produced))
elif b'2' not in produced:
    failures.append(("paste: 'y' did not evaluate to 2", produced))

send(b',quit\r')
while pump(1.0):
    pass

# Bounded reap: a hung `,quit` must fail the test, not hang the process (and
# the CI worker after it, since the outer shell timeout only kills this
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
elif exit_status is not None and os.WIFSIGNALED(exit_status):
    failures.append(('shutdown: REPL was killed by signal %d' % os.WTERMSIG(exit_status), b''))

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
    0)  echo "PASS: pasting multiple top-level forms evaluates all of them"; exit 0 ;;
    77) echo "SKIP: no usable pty for the REPL here"; exit 77 ;;
    *)  echo "FAIL: pasting multiple top-level forms lost input after the first"; exit 1 ;;
esac
