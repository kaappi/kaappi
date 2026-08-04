#!/bin/bash
# kaappi#2216: structural s-expression editing at the REPL.
#
# The transforms themselves are unit-tested in `src/repl_sexp.zig`. What this
# covers is the half that lives in C and cannot be reached from Zig: isocline's
# key dispatch, the buffer replacement, and the cursor clamp — KAAPPI PATCH 3
# in `vendor/isocline/PATCHES.md`. Driving it needs a real terminal, so the
# whole thing runs under a pty.
#
# Each case types a form, moves the cursor inside it, presses one structural
# key, submits, and asserts on what the *evaluator* printed. That keeps the
# check independent of how the editor redraws the line: the only way to print
# `(1 2)` from `(list 1 2 3)` is for barf to have moved the paren.

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
# that cannot be executed is a *failure*, not a skip — the skip below exists
# for platforms with no usable terminal, and letting a missing build take that
# exit would make this test silently green.
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

driver="$work/drive.py"
cat > "$driver" <<'PY'
import fcntl, os, pty, re, select, struct, sys, termios, time

kaappi = sys.argv[1]
ansi = re.compile(rb'\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][B0]|\x1b[=>]|\r')

# typed form, ctrl-b presses to get the cursor inside, key, what the evaluator
# must print, and what it must NOT print (the unedited form's own answer).
CASES = [
    (b'(list 1 2 3)',       1, b'\x1bB', b'(1 2)',   b'(1 2 3)'),   # barf
    (b'(list 1 2) 3',       3, b'\x1bS', b'(1 2 3)', None),         # slurp
    (b'(list 1 (list 2 3))', 2, b'\x1bR', b'(1 3)',  b'(1 (2 3))'), # raise
    (b'(list 1 2 3)',       1, b'\x1by', b'(2 3 1)', b'(1 2 3)'),   # rotate
]

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
    the regex cannot match yet, and they disappear once the rest arrives —
    shifting every index taken before that."""
    return ansi.sub(b'', buf[mark:])

def wait_for(needle, mark=0, timeout=20):
    """Wait for `needle` in output written *after* `mark`. The mark matters:
    every prompt looks alike, so searching the whole buffer would match the
    previous one and return before this step had produced anything."""
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
    # usable terminal, which is a skip (the alternative is a flake on every
    # emulated CI leg).
    if not buf:
        sys.stdout.write('the REPL produced no output at all; it did not start\n')
        sys.exit(1)
    sys.stdout.write('no prompt in:\n%r\n' % seen())
    sys.exit(77)
idle()

failures = []
for typed, lefts, key, expect, reject in CASES:
    mark = len(buf)
    send(typed)
    # The echoed text is proof the editor has the buffer — a plain sleep is not,
    # and typing on while the REPL is still evaluating puts the bytes in the
    # tty's canonical buffer, where ctrl-b arrives as a literal ^B.
    if not wait_for(typed, mark, 20):
        failures.append((key, typed, seen(mark)))
        idle()
        continue
    for _ in range(lefts):
        send(b'\x02')          # ctrl-b: one character left
    idle(0.3)
    send(key)
    idle(0.3)
    send(b'\r')
    # The result line, not the prompt: the prompt string appears in every
    # redraw of the line being typed, so it says nothing about evaluation.
    ok = wait_for(b'\n' + expect + b'\n', mark, 20)
    idle()
    # Only what this case produced, so an earlier case cannot satisfy a later
    # assertion.
    produced = seen(mark)
    if not ok or (reject is not None and reject in produced):
        failures.append((key, expect, produced))

send(b',quit\r')
while pump(1.0):
    pass
try:
    os.close(fd)
    os.waitpid(pid, 0)
except OSError:
    pass

for key, expect, produced in failures:
    sys.stdout.write('FAIL %r: expected %r in\n%r\n\n' % (key, expect, produced))
sys.exit(1 if failures else 0)
PY

set +e
KAAPPI_HOME="$work/home" python3 "$driver" "$kaappi_abs"
status=$?
set -e

case $status in
    0)  echo "PASS: barf, slurp, raise and rotate all edit the buffer"; exit 0 ;;
    77) echo "SKIP: no usable pty for the REPL here"; exit 77 ;;
    *)  echo "FAIL: structural editing did not take effect"; exit 1 ;;
esac
