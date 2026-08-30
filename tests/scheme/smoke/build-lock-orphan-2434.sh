#!/usr/bin/env bash
# Regression test for kaappi#2434:
#
# build_lock (tests/scheme/shell-common.sh) steals a lock whose recorded holder
# pid is dead, treating "the launcher is gone" as "no work is in flight." That
# is false when the holder was KILLED rather than exiting: the `zig build` it
# forked can be orphaned and keep installing into the shared fixture prefix. A
# next writer that stole on the dead launcher pid alone would then interleave
# its own install with the orphan's -- a half-written interpreter that surfaces
# as an unrelated-looking flake in whichever script loses.
#
# The fix makes the steal group-aware: run-all.sh runs each shell script as its
# own process-group leader and signals the whole group on SHELL_TIMEOUT, and
# build_lock refuses to steal while any process is still alive in the recorded
# holder's process group. So a build orphaned into that group blocks the steal.
#
# This is a deterministic simulation of the race -- no real build, no real
# overrun. We plant a lock whose pid file names a process that has already
# exited, while a marker process it spawned survives in that same process
# group (standing in for the orphaned build), then assert a second writer does
# NOT steal the lock. Without the fix it steals at once (equating dead pid with
# no work); with the fix it keeps waiting until the group is genuinely empty.
set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"

# Signalling a whole process group (`kill -- -PGID`) and the leader==group
# invariant this leans on are POSIX process-group semantics that Git Bash does
# not emulate reliably; the production fix's group-kill has the same premise.
skip_on_windows "process-group liveness (kill -- -PGID) is not reliable under Git Bash/MSYS"

REPO=$(mktemp -d)
PIDFILE=$(mktemp)
ACQFILE="$REPO/acquired"
ORPHAN=""
BLPID=""

cleanup() {
    [ -n "$BLPID" ] && kill "$BLPID" 2> /dev/null || true
    [ -n "$ORPHAN" ] && kill "$ORPHAN" 2> /dev/null || true
    rm -rf "$REPO" "$PIDFILE"
}
trap cleanup EXIT

# --- build the simulated orphan -----------------------------------------
#
# Under `set -m` the `bash -c` below leads its own process group (pgid == its
# pid). It forks a long-lived marker (the orphan/in-flight-build stand-in),
# records both pids, then exits -- leaving the marker alive but its group
# leaderless, exactly the state a killed script leaves its forked build in.
set -m
bash -c 'sleep 60 & printf "%s %s\n" "$$" "$!" > "'"$PIDFILE"'"' &
set +m

# Wait for the leader to record its pids and exit.
LEADER=""
waited=0
while :; do
    read -r LEADER ORPHAN < "$PIDFILE" 2> /dev/null || true
    if [ -n "${LEADER:-}" ] && [ -n "${ORPHAN:-}" ] && ! kill -0 "$LEADER" 2> /dev/null; then
        break
    fi
    sleep 0.1
    waited=$((waited + 1))
    if [ "$waited" -ge 100 ]; then
        echo "FAIL: simulated leader never exited" >&2
        exit 1
    fi
done

# Precondition for the simulation to mean anything: the leader must be dead
# while its process group is still alive (the orphan). If this platform does
# not give us that -- the orphan landed in a different group -- we cannot
# construct the race, so skip rather than report a spurious pass/fail.
if kill -0 "$LEADER" 2> /dev/null; then
    echo "SKIP: could not kill the simulated leader while its group survives"
    exit 77
fi
if ! kill -0 -- "-$LEADER" 2> /dev/null; then
    echo "SKIP: marker did not survive in the leader's process group (no group semantics)"
    exit 77
fi

# --- plant the lock the dead leader "held" ------------------------------
LOCK=$(build_lock_dir "$REPO" orphan-2434)
mkdir -p "$(dirname "$LOCK")"
mkdir "$LOCK"
echo "$LEADER" > "$LOCK/pid"

# --- a second writer must NOT steal it while the group is alive ----------
( build_lock "$REPO" orphan-2434 && : > "$ACQFILE" ) &
BLPID=$!

# The steal check runs at the top of build_lock's loop, before its 1s sleep, so
# a broken build_lock acquires in well under a second. Two seconds is a wide
# margin without dragging the suite.
sleep 2
if [ -f "$ACQFILE" ]; then
    echo "FAIL: build_lock stole a lock whose holder is dead but whose forked" >&2
    echo "      work is still alive -- the kaappi#2434 race." >&2
    exit 1
fi

# --- once the work really ends, the steal must proceed -------------------
# Kill the marker: now the leader pid AND its group are both gone, which is the
# genuine "no work in flight" state the steal is meant to detect.
kill "$ORPHAN" 2> /dev/null || true
ORPHAN=""

waited=0
while [ ! -f "$ACQFILE" ]; do
    sleep 0.2
    waited=$((waited + 1))
    if [ "$waited" -ge 50 ]; then
        echo "FAIL: build_lock never stole the lock after the group emptied" >&2
        exit 1
    fi
done

echo "PASS: build_lock holds while an orphaned build survives, steals once it exits"
