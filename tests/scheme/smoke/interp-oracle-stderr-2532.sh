#!/usr/bin/env bash
# Regression test for kaappi#2532:
#
# interp_stdout (tests/scheme/shell-common.sh) discarded the interpreter's
# stderr outright, so when a CI leg's oracle run aborted (exit 134, SIGABRT)
# the harness had the exit status but not the panic text: stdout to a pipe is
# block-buffered and its buffer is lost on abort, and stderr had gone to
# /dev/null by design. The ubuntu-Debug recurrence could not be localized
# between "abort in a race path" and "exit-time allocator report" purely for
# want of that text.
#
# The fix: interp_stdout takes an optional errfile, and show_interp_stderr
# prints it on the caller's unexpected-failure branch. This is a
# deterministic simulation of the CI failure -- no real kaappi, no real
# abort. A stub "interpreter" writes a marker to stderr, nothing to stdout,
# and exits 134; the test asserts the stdout capture and exit-status
# propagation are unchanged, that the stderr text lands in the errfile and is
# surfaced by show_interp_stderr, that the 3-arg form still buries stderr
# (with the NOISY stub, so a redirect regression cannot pass silently), and
# that a clean run stays silent.
#
# It tests the harness, not the interpreter: the oracle scripts in compile/
# are the consumers, and their FAIL branches are what must carry the captured
# stderr into the CI log.
set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# The aborting "interpreter": the CI failure's shape -- a panic line on
# stderr, no stdout, exit 134.
cat > "$DIR/aborting-kaappi" << 'EOF'
#!/bin/sh
echo "stub panic: simulated allocator/panic report" >&2
exit 134
EOF
chmod +x "$DIR/aborting-kaappi"

ERR="$DIR/oracle.interp.err"

status=0
out=$(interp_stdout "$DIR/aborting-kaappi" "$DIR" "prog.scm" "$ERR") || status=$?

# The observable oracle facts are unchanged: empty stdout, status 134.
if [ -n "$out" ]; then
    echo "FAIL: interp_stdout leaked stderr text into stdout: '$out'" >&2
    exit 1
fi
if [ "$status" -ne 134 ]; then
    echo "FAIL: interp_stdout returned $status, expected 134" >&2
    exit 1
fi

# The point of the fix: the stderr text survives in the errfile... (-s keeps
# the red path, where the old shell-common.sh never creates the file, down to
# the one FAIL line that matters.)
if ! grep -qs "stub panic" "$ERR"; then
    echo "FAIL: interp_stdout dropped the interpreter's stderr (kaappi#2532)" >&2
    exit 1
fi
# ...and show_interp_stderr surfaces it on the failure branch, under the
# header that tells a merged CI log what the text is.
shown=$(show_interp_stderr "$ERR" 2>&1)
if ! grep -qs "stub panic" <<< "$shown" \
    || ! grep -qsF -- "--- interpreter stderr ---" <<< "$shown"; then
    echo "FAIL: show_interp_stderr did not surface the captured stderr" >&2
    show_interp_stderr "$ERR"
    exit 1
fi

# The 3-arg form must keep sending stderr to /dev/null. Prove it with the
# NOISY stub -- a quiet one could not tell a redirect regression from
# silence -- by capturing what reaches the CALLER's stderr: nothing may.
leak="$DIR/three-arg.stderr"
status=0
out=$(interp_stdout "$DIR/aborting-kaappi" "$DIR" "prog.scm" 2> "$leak") || status=$?
if [ -n "$out" ] || [ "$status" -ne 134 ] || [ -s "$leak" ]; then
    echo "FAIL: 3-arg form must hide stderr: stdout '$out' status $status, leaked:" >&2
    cat "$leak" >&2
    exit 1
fi

# A quiet run stays quiet on both forms.
cat > "$DIR/quiet-kaappi" << 'EOF'
#!/bin/sh
echo "42"
exit 0
EOF
chmod +x "$DIR/quiet-kaappi"

status=0
out=$(interp_stdout "$DIR/quiet-kaappi" "$DIR" "prog.scm") || status=$?
if [ "$out" != "42" ] || [ "$status" -ne 0 ]; then
    echo "FAIL: interp_stdout 3-arg form: stdout '$out' status $status" >&2
    exit 1
fi

QERR="$DIR/quiet.interp.err"
status=0
out=$(interp_stdout "$DIR/quiet-kaappi" "$DIR" "prog.scm" "$QERR") || status=$?
if [ "$out" != "42" ] || [ "$status" -ne 0 ]; then
    echo "FAIL: interp_stdout with errfile: stdout '$out' status $status" >&2
    exit 1
fi
if [ -s "$QERR" ]; then
    echo "FAIL: a clean oracle run left a non-empty stderr capture" >&2
    exit 1
fi
if [ -n "$(show_interp_stderr "$QERR" 2>&1)" ]; then
    echo "FAIL: show_interp_stderr was noisy for an empty capture" >&2
    exit 1
fi

echo "PASS: interp_stdout captures oracle stderr; show_interp_stderr surfaces it on failure"
