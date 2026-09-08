#!/bin/bash
# The shell suites' per-script timeout override (kaappi#2555).
#
# bundle-cpu-baseline-2515.sh does three full -Doptimize=ReleaseSafe builds
# when the Zig cache is cold, and the flat KAAPPI_SHELL_TEST_TIMEOUT cap
# (600s on the Release legs) killed it on the v0.27.0 tag push — a commit
# whose only code change was a version string — cancelling the release
# ci-gate. The fix was not a smaller test but a per-script budget: the shell
# workers consult PER_SCRIPT_TIMEOUTS exactly the way the .scm workers
# consult PER_FILE_TIMEOUTS.
#
# This pins the mechanism by driving run-all.sh's own dispatch functions
# against fixture scripts that only sleep, with both budgets dialed down to
# seconds. The functions are extracted from run-all.sh with sed rather than
# copied here, so the shipping code is what runs — the same technique
# runner-agreement.sh uses to keep its verdict regex honest.
#
# No kaappi binary and no zig are needed, so this runs on every leg that can
# run bash, including the ones with no toolchain.

set -euo pipefail

RUN_ALL="$(cd "$(dirname "$0")/.." && pwd)/run-all.sh"
if [[ ! -f "$RUN_ALL" ]]; then
    echo "FAIL: cannot find run-all.sh next to this suite" >&2
    exit 1
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# The table entry itself is part of the fix. Without this check the behaviour
# assertions below could pass against a PER_SCRIPT_TIMEOUTS the test set
# itself, and the override for the script that motivated it could be dropped
# silently.
if ! grep -q '^PER_SCRIPT_TIMEOUTS="bundle-cpu-baseline-2515.sh:' "$RUN_ALL"; then
    echo "FAIL: run-all.sh has no PER_SCRIPT_TIMEOUTS entry for bundle-cpu-baseline-2515.sh" >&2
    exit 1
fi

# Extract the dispatch path's functions. Ranges are anchored on each
# definition and its column-0 closing brace, the shape every function in
# run-all.sh already has.
sed -n -e '/^wait_with_timeout() {/,/^}/p' \
       -e '/^shell_timeout_for() {/,/^}/p' \
       -e '/^run_shell_worker() {/,/^}/p' \
       -e '/^report_shell_result() {/,/^}/p' \
       "$RUN_ALL" > "$DIR/functions.sh"

# Guard the guard: an extraction that silently missed a function would make
# everything after it fail for the wrong reason.
for fn in wait_with_timeout shell_timeout_for run_shell_worker report_shell_result; do
    if ! grep -q "^$fn() {" "$DIR/functions.sh"; then
        echo "FAIL: could not extract '$fn' from run-all.sh" >&2
        exit 1
    fi
done

. "$DIR/functions.sh"

# The globals the extracted functions read. run-all.sh sets these at top
# level, outside any function, so the sed ranges above do not carry them;
# here they are the second-scale stand-ins: the budget every other script
# gets, and the override the listed script gets instead.
SHELL_TIMEOUT=2
PER_SCRIPT_TIMEOUTS="bundle-cpu-baseline-2515.sh:6"
TICKS_PER_SEC=20
sleep 0.05 2>/dev/null || TICKS_PER_SEC=1
export KAAPPI=/bin/true

# --- the lookup --------------------------------------------------------------
# Basename-matched, so the dispatch that passes full paths still finds the
# entry; an unlisted script (and a near-miss name) falls back to the global.
if [[ "$(shell_timeout_for "$DIR/bundle-cpu-baseline-2515.sh")" != "6" ]]; then
    echo "FAIL: listed script did not get its PER_SCRIPT_TIMEOUTS budget" >&2
    exit 1
fi
if [[ "$(shell_timeout_for "$DIR/unlisted-script.sh")" != "2" ]]; then
    echo "FAIL: unlisted script did not fall back to SHELL_TIMEOUT" >&2
    exit 1
fi
if [[ "$(shell_timeout_for "$DIR/bundle-cpu-baseline-2515.sh2")" != "2" ]]; then
    echo "FAIL: near-miss basename was matched instead of falling back" >&2
    exit 1
fi

# --- the worker, end to end --------------------------------------------------
# Fixtures only sleep, so the verdicts below are decided purely by the
# budgets. run_shell_worker is backgrounded exactly as run_shell_suite
# backgrounds it (it relies on its own `set -m` window).
mk_fixture() { # <path-under-$DIR> <seconds-to-sleep>
    printf '#!/bin/bash\nsleep %s\n' "$2" > "$DIR/$1.sh"
    chmod +x "$DIR/$1.sh"
}

run_fixture() { # <slot-label> <script-path> — prints the recorded verdict
    local slot="$DIR/slot-$1"
    rm -f "$slot.rec" "$slot.out"
    run_shell_worker "$2" "$slot" &
    local pid=$!
    wait "$pid"
    cat "$slot.rec"
}

# The regression this file exists for, in miniature: a script that outlives
# the global budget but fits its own override must PASS. Under the old flat
# timeout this is killed at 2s and reported TIMEOUT — the v0.27.0 ci-gate
# cancellation, at 1/300th scale.
mk_fixture bundle-cpu-baseline-2515 3
if [[ "$(run_fixture listed "$DIR/bundle-cpu-baseline-2515.sh")" != "PASS" ]]; then
    echo "FAIL: script killed inside its per-script budget (was the worker wired to shell_timeout_for?)" >&2
    exit 1
fi

# The override is a budget, not a waiver: past it, the listed script dies too.
# A second copy under slow/ so both basename matches can exist at once.
mkdir -p "$DIR/slow"
mk_fixture slow/bundle-cpu-baseline-2515 8
if [[ "$(run_fixture listed-slow "$DIR/slow/bundle-cpu-baseline-2515.sh")" != "TIMEOUT 6s" ]]; then
    echo "FAIL: listed script was not killed (and recorded) at its own budget" >&2
    exit 1
fi

# Every other script still lives under the global budget...
mk_fixture unlisted-slow 4
if [[ "$(run_fixture unlisted-slow "$DIR/unlisted-slow.sh")" != "TIMEOUT 2s" ]]; then
    echo "FAIL: unlisted script was not killed at SHELL_TIMEOUT" >&2
    exit 1
fi
# ...and is not broken by it.
mk_fixture unlisted-fast 1
if [[ "$(run_fixture unlisted-fast "$DIR/unlisted-fast.sh")" != "PASS" ]]; then
    echo "FAIL: unlisted fast script did not pass under SHELL_TIMEOUT" >&2
    exit 1
fi

# --- the report --------------------------------------------------------------
# The printed kill time must be the budget that actually applied — it used to
# hardcode SHELL_TIMEOUT, which would misreport an overridden script.
PASS=0 FAIL=0 TIMEDOUT=0 SKIPPED=0
report_shell_result "$DIR/slow/bundle-cpu-baseline-2515.sh" "$DIR/slot-listed-slow" > "$DIR/report.txt" 2>&1
if ! grep -q 'TIMEOUT  .*(killed after 6s)' "$DIR/report.txt"; then
    echo "FAIL: TIMEOUT report did not name the per-script budget: $(cat "$DIR/report.txt")" >&2
    exit 1
fi
report_shell_result "$DIR/unlisted-slow.sh" "$DIR/slot-unlisted-slow" > "$DIR/report2.txt" 2>&1
if ! grep -q 'TIMEOUT  .*(killed after 2s)' "$DIR/report2.txt"; then
    echo "FAIL: TIMEOUT report did not name the global budget: $(cat "$DIR/report2.txt")" >&2
    exit 1
fi

echo "PASS: shell-suite per-script timeout override routes, bounds, and reports correctly"
