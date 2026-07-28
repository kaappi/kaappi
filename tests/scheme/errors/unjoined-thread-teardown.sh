#!/bin/bash
# kaappi#1792: a thread-start!ed OS thread that is never thread-join!ed must
# not corrupt the heap at process exit.
#
# thread-join! is optional in SRFI-18 — nothing raises or warns if a script
# omits it — so a background thread that outlives (or barely misses) main's
# own teardown is ordinary, reachable code. The bug: main.zig used to run
# vm.deinit()/gc.deinit() unconditionally, which frees the parent's shared
# symbol table and globals map — structures a still-running child GC/VM alias
# and may be concurrently reading or writing. Freeing them out from under the
# child is a data race that corrupted the allocator's own heap metadata
# (observed as glibc's "corrupted size vs. prev_size" + SIGABRT on Linux).
#
# Two shapes reproduced the corruption: the child already finished its thunk
# by the time main tears down, and the child still running (or mid-completion)
# at that point. Both must now exit 0, repeatedly — this is a race, so a
# single passing run proves nothing.

set -uo pipefail

. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
ITERATIONS="${UNJOINED_THREAD_ITERATIONS:-50}"

PASS=0
FAIL=0

TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

# Child finishes essentially instantly; main may well tear down before it does.
cat > "$TMPDIR_TESTS/unjoined-finished.scm" << 'EOF'
(import (scheme base) (srfi 18))
(thread-start! (make-thread (lambda () 1)))
EOF

# Child is still sleeping (i.e. still alive) when main's own code has nothing
# left to run and process teardown begins.
cat > "$TMPDIR_TESTS/unjoined-running.scm" << 'EOF'
(import (scheme base) (srfi 18))
(thread-start! (make-thread (lambda () (thread-sleep! 2) 1)))
EOF

run_many() {
    local label="$1"
    local file="$2"
    local n="$3"
    local bad=0
    local status
    for ((i = 0; i < n; i++)); do
        "$KAAPPI" "$file" > /dev/null 2>"$TMPDIR_TESTS/stderr.$i"
        status=$?
        if [[ "$status" -ne 0 ]]; then
            bad=$((bad + 1))
            echo "  run $i: exit $status"
            sed 's/^/    /' "$TMPDIR_TESTS/stderr.$i"
        fi
        rm -f "$TMPDIR_TESTS/stderr.$i"
    done
    if [[ "$bad" -eq 0 ]]; then
        echo "PASS: $label ($n/$n runs exit 0)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label ($bad/$n runs did not exit 0)"
        FAIL=$((FAIL + 1))
    fi
}

run_many "unjoined thread, child already finished at exit" "$TMPDIR_TESTS/unjoined-finished.scm" "$ITERATIONS"
run_many "unjoined thread, child still running at exit" "$TMPDIR_TESTS/unjoined-running.scm" "$ITERATIONS"

echo ""
echo "unjoined-thread-teardown: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
