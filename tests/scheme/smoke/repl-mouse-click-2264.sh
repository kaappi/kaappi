#!/bin/bash
# kaappi#2264: click inside the current input to reposition the edit cursor.
#
# The mapping from an SGR mouse event to a buffer byte position is split
# across two C files and cannot be reached from Zig: the SGR decode in
# `tty_esc.c` and the anchor + click-to-position in `editline.c` (KAAPPI
# PATCH 5 in `vendor/isocline/PATCHES.md`). Driving it needs a real
# terminal, so the whole thing runs under a pty, like the structural-editing
# test.
#
# The driver plays the terminal emulator: it answers the editor's one-time
# `ESC[6n` anchor query with a fixed `ESC[4;9R` (the prompt's content starts
# at row 4, col 9 after the two banner lines and the blank), then feeds SGR
# mouse presses relative to that anchor. Everything the editor maps depends
# on the anchor and the click coordinates being consistent, which is exactly
# the absolute -> relative arithmetic this test pins down.
#
# Each case clicks, then does one editing op whose effect is only observable
# through the *evaluator*'s output, so the assertion is independent of how
# the editor redraws the line: the only way `bc` prints from `abc` is for
# the click to have moved the cursor between 'a' and 'b' before the
# backspace. A second run with mouse support off (the default) feeds the same
# SGR bytes and asserts they are safely ignored.

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
# `repl.prompt` would move the sentinel this script waits for. Mouse is on for
# the first run, off for the second (no `repl.mouse` key at all).
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

driver="$work/drive.py"
cat > "$driver" <<'PY'
import fcntl, os, pty, re, select, struct, sys, termios, time

kaappi = sys.argv[1]
mode = sys.argv[2]              # 'on'  -> repl.mouse: true;  'off' -> default
assert mode in ('on', 'off')
ansi = re.compile(rb'\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][B0]|\x1b[=>]|\r')

# The fixed DSR answer: the prompt's content starts at row 4, col 9 (two
# banner lines + one blank, prompt "kaappi> " is 8 columns). The editor maps
# a click at absolute (row, col) to editor (row - 4, col - 9).
DSR = b'\x1b[4;9R'
def click(col, row):
    return b'\x1b[<0;%d;%dM' % (col, row)   # SGR: left-button press

# (send, echo, click, edit-key, expected result, reject as a standalone
# result line). `echo` is what to wait for after sending: the editor renders
# the buffer, so a `\r` that became a newline is waited for as `3 4)` — the
# raw bytes never appear in the output. Every buffer must be a valid
# expression whose *evaluated* value distinguishes the click from a plain
# end-of-buffer edit; reject is what the same edit without the click would
# have produced.
CASES = [
    # single line: click at (9+6, 4) = editor (0, 6) -> before the '1' of
    # "(list 1 2 3)"; typing '9' gives "(list 91 2 3)" -> (91 2 3), where a
    # plain end-insert gives "(list 1 2 3 9)" -> (1 2 3 9).
    (b'(list 1 2 3)', b'(list 1 2 3)', click(15, 4), b'9', b'(91 2 3)', b'(1 2 3 9)'),
    # continuation row: click at (9+2, 4+1) = editor (1, 2) -> before the '4'
    # of "(list 1 2\n3 4)"; typing '9' gives "(list 1 2\n3 94)" ->
    # (1 2 3 94), where a plain end-insert gives (1 2 3 49).
    (b'(list 1 2\r3 4)', b'3 4)', click(11, 5), b'9', b'(1 2 3 94)', b'(1 2 3 49)'),
]
# With mouse off the click must be ignored: the '9' lands at the end, after
# the closing paren, so the buffer is "(list 1 2\n3 4)9" — two forms, whose
# first result is (1 2 3 4). Had the click repositioned, the buffer would be
# one form and (1 2 3 4) would never print.
OFF_CASE = (b'(list 1 2\r3 4)', b'3 4)', click(11, 5), b'9', b'(1 2 3 4)', b'(1 2 3 94)')

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
answered_dsr = 0                 # how many ESC[6n queries we have answered
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

def answer_dsr():
    """Answer every ESC[6n anchor query the child sent, the way a terminal
    emulator would. The child blocks ~400ms waiting, so we answer on sight."""
    global answered_dsr
    while True:
        idx = buf.find(b'\x1b[6n', answered_dsr)
        if idx < 0:
            return
        answered_dsr = idx + 4
        os.write(fd, DSR)

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
        answer_dsr()
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
        answer_dsr()
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

cases = CASES if mode == 'on' else [OFF_CASE]
failures = []
for send_bytes, echo, clk, editkey, expect, reject in cases:
    mark = len(buf)
    send(send_bytes)
    # The echoed text is proof the editor has the buffer — a plain sleep is not,
    # and typing on while the REPL is still evaluating puts the bytes in the
    # tty's canonical buffer, where the click then arrives as a literal ESC.
    if not wait_for(echo, mark, 20):
        failures.append((typed, expect, seen(mark)))
        idle()
        continue
    idle(0.3)
    send(clk)
    idle(0.3)
    send(editkey)
    idle(0.3)
    send(b'\r')
    # The result line, not the prompt: the prompt string appears in every
    # redraw of the line being typed, so it says nothing about evaluation.
    ok = wait_for(b'\n' + expect + b'\n', mark, 20)
    idle()
    # Only what this case produced, so an earlier case cannot satisfy a later
    # assertion. The reject is scoped to a standalone result line too: the
    # typed echo of `abc` contains `ab`, which would false-positive a plain
    # substring check.
    produced = seen(mark)
    if not ok or (reject is not None and (b'\n' + reject + b'\n') in produced):
        failures.append((send_bytes, expect, produced))

send(b',quit\r')
while pump(1.0):
    pass
try:
    os.close(fd)
    os.waitpid(pid, 0)
except OSError:
    pass

for typed, expect, produced in failures:
    sys.stdout.write('FAIL %r: expected %r in\n%r\n\n' % (typed, expect, produced))
sys.exit(1 if failures else 0)
PY

run_case() {  # $1 = mode ('on' | 'off')
    mkdir -p "$work/home"
    if [ "$1" = "on" ]; then
        printf 'repl.mouse: true\n' > "$work/home/config"
    else
        rm -f "$work/home/config"
    fi
    set +e
    KAAPPI_HOME="$work/home" python3 "$driver" "$kaappi_abs" "$1"
    status=$?
    set -e
    return $status
}

run_case on
status_on=$?
if [ $status_on -eq 0 ]; then
    echo "PASS: click repositions the cursor (single-line and continuation rows)"
elif [ $status_on -eq 77 ]; then
    echo "SKIP: no usable pty for the REPL here"
    exit 77
else
    echo "FAIL: click-to-position did not take effect"
    exit 1
fi

run_case off
status_off=$?
if [ $status_off -eq 0 ]; then
    echo "PASS: without repl.mouse the SGR bytes are ignored (default stays safe)"
else
    echo "FAIL: SGR bytes must be inert when repl.mouse is off"
    exit 1
fi
