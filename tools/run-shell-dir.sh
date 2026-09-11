#!/usr/bin/env bash
# Run every *.sh in one test-suite directory, with the verdicts a CI leg
# needs: a per-script timeout, SKIP (exit 77), kept transcripts, and a loud
# failure when the directory holds no scripts at all.
#
#     bash tools/run-shell-dir.sh <dir> [kaappi]
#
# WHY THIS EXISTS. The sandbox and robustness suites are the two shell-suite
# directories run-all.sh deliberately leaves to CI, so both the POSIX `test`
# legs and the two Windows "Shell suites" steps need a driver for them. Three
# hand-copied glob loops is the shape that orphaned srfi181-sandbox.sh
# (kaappi#2575): the POSIX copy named its scripts one by one, the list
# stopped at three, and only the Windows copies — which globbed — ever ran
# the fourth. One driver called from every leg cannot drift from itself.
#
# Verdicts, one line per script with the transcript preserved:
#   PASS     exit 0           transcript in a collapsed ::group:: under CI
#   SKIP     exit 77          shell-common.sh's "premise cannot hold here"
#   FAIL     any other exit   transcript printed, ::error annotation under CI
#   TIMEOUT  killed at budget partial transcript, ::error annotation
#
# A directory with no *.sh is a FAIL, not a silent pass — a moved or renamed
# suite must not leave every leg green while running nothing, which is the
# same orphan class one level up (kaappi#2575 review).
#
# The timeout counts sleep ticks rather than wall clock and kills the
# script's whole process group (`set -m`), both borrowed from run-all.sh's
# run_shell_worker (kaappi#2434, kaappi#1748): a hung script may have a
# child interpreter or `zig build` that must die with it, and neither macOS
# nor Git Bash ships a GNU `timeout`. Budget: KAAPPI_SHELL_TEST_TIMEOUT
# seconds, default 600.
#
# The optional second argument is the kaappi binary to test with — exported
# as KAAPPI and passed as argv[1], the shape the Windows legs need
# (bin/kaappi.exe). Without it the scripts' own default
# (zig-out/bin/kaappi) applies. KAAPPI_HOME isolation is the caller's
# policy, as it is for run-all.sh.

set -u

dir=${1:?usage: run-shell-dir.sh <dir> [kaappi]}
kaappi=${2:-}

SHELL_TIMEOUT="${KAAPPI_SHELL_TEST_TIMEOUT:-600}"

# ::group:: / ::error:: are GitHub workflow commands; outside a runner they
# are noise in front of the transcript.
if [ -n "${CI:-}" ]; then
    pass_group_open() { echo "::group::  PASS  $1"; }
    group_close() { echo "::endgroup::"; }
    annotate() { echo "::error file=$1::$2"; }
else
    pass_group_open() { :; }
    group_close() { :; }
    annotate() { :; }
fi

TICKS_PER_SEC=20
if ! sleep 0.05 2>/dev/null; then
    TICKS_PER_SEC=1
fi

wait_with_timeout() {
    local pid=$1 secs=$2 ticks=0
    local limit=$((secs * TICKS_PER_SEC))
    local interval=0.05
    if [ "$TICKS_PER_SEC" -eq 1 ]; then interval=1; fi
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge "$limit" ]; then return 1; fi
        sleep "$interval"
        ticks=$((ticks + 1))
    done
    return 0
}

scripts=()
for s in "$dir"/*.sh; do
    [ -e "$s" ] || continue
    scripts[${#scripts[@]}]="$s"
done

if [ ${#scripts[@]} -eq 0 ]; then
    echo "  FAIL  no *.sh found in $dir"
    exit 1
fi

out=$(mktemp "${TMPDIR:-/tmp}/run-shell-dir-XXXXXX")
trap 'rm -f "$out"' EXIT

fail=0
for s in "${scripts[@]}"; do
    # `set -m` for the launch only, so the script leads its own process
    # group (pgid == pid) and a timeout can signal its children too; `set +m`
    # before wait keeps the async job-control notices off (run-all.sh).
    set -m
    if [ -n "$kaappi" ]; then
        KAAPPI="$kaappi" bash "$s" "$kaappi" > "$out" 2>&1 &
    else
        bash "$s" > "$out" 2>&1 &
    fi
    pid=$!
    set +m
    status=0
    if wait_with_timeout "$pid" "$SHELL_TIMEOUT"; then
        wait "$pid" || status=$?
    else
        kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        echo "  TIMEOUT  $s  (killed after ${SHELL_TIMEOUT}s)"
        cat "$out"
        annotate "$s" "$s timed out after ${SHELL_TIMEOUT}s"
        fail=1
        continue
    fi
    case $status in
        0)
            echo "  PASS  $s"
            pass_group_open "$s"
            cat "$out"
            group_close
            ;;
        77)
            echo "  SKIP  $s"
            ;;
        *)
            echo "  FAIL  $s (exit $status)"
            cat "$out"
            annotate "$s" "$s failed (exit $status)"
            fail=1
            ;;
    esac
done
exit $fail
