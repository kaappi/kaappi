#!/bin/bash
# kaappi#2273: `,load` must not round-trip the path through the reader's
# string escapes.
#
# The command used to splice the path into a `(load "...")` string literal,
# so a path containing `"` or `\` broke: a quote ended the string (reader
# syntax error), a backslash started an escape (`\s` is an invalid escape;
# `\t` decodes to a TAB and loads a *different* file). It now builds the
# form as Values and hands the raw path bytes to `load`, which is also why
# the regression is a pty test: `,load` only exists in the interactive REPL,
# and only a pty can drive it (like the other repl-*.sh tests).

set -eu

KAAPPI="${KAAPPI:-${1:-zig-out/bin/kaappi}}"

. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "no pty; isocline drives the Windows console API directly"

command -v python3 >/dev/null 2>&1 || {
    echo "SKIP: python3 is needed to allocate a pty"
    exit 77
}

# Resolve to an absolute path for the driver, which execs it directly. A value
# with no slash is a PATH lookup; anything else is a path as given. A binary
# that cannot be executed is a *failure*, not a skip.
case "$KAAPPI" in
    */*) kaappi_abs="$(cd "$(dirname "$KAAPPI")" 2>/dev/null && pwd)/$(basename "$KAAPPI")" ;;
    *)   kaappi_abs="$(command -v "$KAAPPI" || true)" ;;
esac
if [ ! -x "$kaappi_abs" ]; then
    echo "FAIL: $KAAPPI is not an executable file (build first: zig build)"
    exit 1
fi

# Isolate history and config: the REPL reads ~/.kaappi, and a developer's own
# `repl.prompt` would move the sentinel this script waits for.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Files whose names trip the reader escapes `,load` used to splice into a
# string literal: a double quote ends the literal, a backslash starts an
# escape. Backslashes and quotes are legal filename characters on POSIX.
printf '(display "NORMAL")(newline)\n' > "$work/normal.scm"
printf '(display "QUOTE")(newline)\n' > "$work/a\"b.scm"
printf '(display "BACKSLASH")(newline)\n' > "$work/back\\slash.scm"
printf '(display "TAB")(newline)\n' > "$work/tab\\tfile.scm"

driver="$work/drive.py"
cat > "$driver" <<'PY'
import fcntl, os, pty, re, select, struct, sys, termios, time

kaappi = sys.argv[1]
# argv[2..] are path/marker pairs: the file at `path` displays `marker` when
# loaded, so the marker's presence proves the file was opened at exactly the
# path that was typed (a mangled path loads nothing, or a *different* file).
cases = []
i = 2
while i + 1 < len(sys.argv):
    cases.append((sys.argv[i].encode(), sys.argv[i + 1].encode()))
    i += 2

ansi = re.compile(rb'\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][B0]|\x1b[=>]|\r')

pid, fd = pty.fork()
if pid == 0:
    # The child must exec or die: `pty.fork` gives it the parent's code, so a
    # raising execv would otherwise let a traceback land in the pty slave and
    # muddy the buffer the parent is matching against.
    try:
        os.environ['TERM'] = 'xterm'
        os.environ['NO_COLOR'] = '1'
        os.execv(kaappi, [kaappi])
    except BaseException:
        pass
    os._exit(127)

# A pty starts out 0x0, which gives the editor no room to render in.
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 200, 0, 0))

buf = b''
eof = False
deadline = time.time() + 90

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
    """Everything the child has written since *raw* byte `mark`, escapes
    stripped. The mark indexes `buf`, not the stripped text, because stripped
    indices are not stable: a read that ends mid-escape-sequence leaves bytes
    the regex cannot match yet, and they disappear once the rest arrives."""
    return ansi.sub(b'', buf[mark:])

def wait_for(needle, mark=0, timeout=20):
    """Wait for `needle` in output written *after* `mark`."""
    end = min(time.time() + timeout, deadline)
    while time.time() < end:
        if needle in seen(mark):
            return True
        if eof:
            break          # the child is gone; no more output is coming
        pump(0.2)
    return needle in seen(mark)

def idle(quiet=0.5, limit=5.0):
    """Drain until the child has been silent for `quiet` seconds. Typing into
    a REPL that has not finished evaluating lands in the tty's canonical
    buffer instead of the editor, so every step waits for quiet first."""
    end = time.time() + limit
    while time.time() < end:
        if not pump(quiet):
            return

def send(data):
    os.write(fd, data)
    time.sleep(0.05)

if not wait_for(b'kaappi> ', 0, 25):
    # Two very different things look alike here, and conflating them is how a
    # test goes quietly green: a REPL that wrote *nothing at all* did not run,
    # which is a failure; a REPL that wrote something but never prompted has no
    # usable terminal, which is a skip.
    if not buf:
        sys.stdout.write('the REPL produced no output at all; it did not start\n')
        sys.exit(1)
    sys.stdout.write('no prompt in:\n%r\n' % seen())
    sys.exit(77)
idle()

failures = []
for path, marker in cases:
    mark = len(buf)
    send(b',load ' + path + b'\r')
    # The marker is printed by the loaded file itself, scoped to after this
    # send; nothing else prints it. An "error[" line means the load failed
    # or the path was mangled into a different file.
    ok = wait_for(marker + b'\n', mark, 20)
    idle()
    produced = seen(mark)
    if not ok or b'error[' in produced:
        failures.append((path, marker, produced))

send(b',quit\r')
while pump(1.0):
    pass
try:
    os.close(fd)
    os.waitpid(pid, 0)
except OSError:
    pass

for path, marker, produced in failures:
    sys.stdout.write('FAIL %r: expected marker %r in\n%r\n\n' % (path, marker, produced))
sys.exit(1 if failures else 0)
PY

set +e
KAAPPI_HOME="$work/home" python3 "$driver" "$kaappi_abs" \
    "$work/normal.scm" NORMAL \
    "$work/a\"b.scm" QUOTE \
    "$work/back\\slash.scm" BACKSLASH \
    "$work/tab\\tfile.scm" TAB
status=$?
set -e

case $status in
    0)  echo "PASS: ,load opens paths containing quotes and backslashes"; exit 0 ;;
    77) echo "SKIP: no usable pty for the REPL here"; exit 77 ;;
    *)  echo "FAIL: ,load mangled a path with a quote or backslash"; exit 1 ;;
esac
