#!/usr/bin/env bash
# The chunk script's wall-budget watchdog and streamed bisection (kaappi#2560).
#
# `zig build` buffers all of its console output until the process exits
# (verified on Zig 0.16.0: through a pipe, a file, or a pty; SIGTERM does
# not flush it either), so a CI step killed at its `timeout-minutes` cap
# loses even the per-test timeout names that #2491's `--test-timeout` had
# already recorded. Every capped riscv64 `rest` run therefore died
# silent -- the cap localised nothing, which is what #2560 filed.
#
# tools/run-unit-test-chunk.sh now localises with its OWN unbuffered echo
# lines, which survive any kill: a heartbeat while the chunk runs, a
# "WALL BUDGET EXCEEDED" line when the script's wall budget fires, and one
# line per bisection level naming the filter subset in flight, exiting 124
# (the timeout(1) convention) so the run fails loudly instead of just
# quietly bleeding out at a CI cap.
#
# Both cases below drive that machinery with budgets small enough that the
# initial test-binary compile itself "wedges": no real test hangs, and each
# case is bounded by its budgets (~40s and ~75s). Which side of a bisection
# level's own budget the machine lands on (cold compile vs warm objects)
# varies by host, so every assertion accepts exactly the two outcomes the
# script is allowed to print for it.

. "$(dirname "$0")/../shell-common.sh"

skip_on_windows "the watchdog kills the zig process tree via pgrep, which MSYS lacks"
skip_without_zig "the chunk script runs zig build"

cd "$(dirname "$0")/../../.." || exit 1

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Structure: --list still derives the rest chunk's filters from the tree,
# and an unknown chunk name is a usage error, not a silent success.
n=$(bash tools/run-unit-test-chunk.sh --list rest | wc -l | tr -d ' ')
[ "$n" -ge 20 ] || fail "--list rest produced only $n filters (expected the derived remainder, dozens)"
if bash tools/run-unit-test-chunk.sh --list bogus-chunk > /dev/null 2>&1; then
    fail "an unknown chunk name must exit 2"
fi

# Case 1: the wall budget fires and the bisection pot is too dry for even
# one level. The kill must still be loud, streamed, and exit 124.
out=$(mktemp)
trap 'rm -f "$out" "$out2"' EXIT
KAAPPI_CHUNK_BUDGET=12 KAAPPI_BISECT_BUDGET=20 KAAPPI_HEARTBEAT_SECS=3 \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1
status=$?

[ "$status" -eq 124 ] || fail "case 1: wall-budget overrun must exit 124 (timeout(1) convention), got $status"
grep -q "WALL BUDGET EXCEEDED" "$out" || fail "case 1: no streamed budget-exceeded line"
grep -q "still running at" "$out" || fail "case 1: no heartbeat line survived the kill"
grep -q "too shallow for depth 1" "$out" || fail "case 1: the dry pot was not reported as too shallow"
grep -q "RESULT:" "$out" || fail "case 1: no summary verdict line"

# Case 2: enough pot for one bisection level (a level gets 3/5 of the pot
# and needs >= 90s, so 180s is the smallest pot that starts one). A cold
# cache cannot compile the subset in ~108s (level watchdog fires, descent
# enters that half); a warm one runs the subset's tests (level finishes,
# half is discarded). Both are correct; both must name the subset BEFORE
# running it, and the level's outcome must be reported as a decision.
out2=$(mktemp)
KAAPPI_CHUNK_BUDGET=12 KAAPPI_BISECT_BUDGET=180 KAAPPI_HEARTBEAT_SECS=3 \
    bash tools/run-unit-test-chunk.sh rest > "$out2" 2>&1
status=$?

[ "$status" -eq 124 ] || fail "case 2: wall-budget overrun must exit 124, got $status"
grep -Eq "bisect depth 1: [0-9]+ filter\\(s\\) [a-z_0-9.]+\.\.[a-z_0-9.]+, budget [0-9]+s" "$out2" ||
    fail "case 2: no bisect level line naming its filter subset and its budget"
grep -Eq "(did NOT finish in [0-9]+s -- the wedge reproduces inside this half|finished in [0-9]+s \\(zig exit [0-9]+\\) -- no process wedge here)" "$out2" ||
    fail "case 2: the level's outcome was not reported as a bisection decision"
grep -Eq "(bisect incomplete|RESULT:)" "$out2" ||
    fail "case 2: neither an incomplete-descent suspects list nor a verdict line was printed"

echo "PASS: watchdog fired loudly, bisection streamed its subsets, exit 124"
