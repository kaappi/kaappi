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
# Every case below drives the script through a fake `zig` (KAAPPI_ZIG): a
# shim that plays wedged or clean subsets in seconds, with real child
# processes so the watchdog's process-tree snapshot has a tree to kill.
# That makes each outcome deterministic -- the descent, the solo confirm,
# the NOTE lines for tight-bound overruns, the INCONCLUSIVE stop for a
# level the pot could only clip, and the unbudgeted heartbeat (which died
# on an unbound variable under bash >= 4 before the fix) -- without ever
# compiling the unit suite or contending for the Zig cache locks. The
# real-zig path is what the riscv64 chunk steps run eight times per CI job.

. "$(dirname "$0")/../shell-common.sh"

skip_on_windows "the watchdog kills the zig process tree via pgrep, which MSYS lacks"

cd "$(dirname "$0")/../../.." || exit 1

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/kaappi-chunk-watchdog-XXXXXX")
trap 'rm -rf "$work"' EXIT
out="$work/out"

# The fake `zig build test`: never compiles, decides from its arguments.
#   wedge (hang with two children) iff, in order:
#     - SHIM_WEDGE_ONCE is set and its stamp file is missing (first call), or
#     - SHIM_HANG_FIRST is set and fewer than that many calls have hung, or
#     - SHIM_WEDGE_FILTER is set and some -Dtest-filter= arg contains it;
#   otherwise sleep SHIM_DELAY, print SHIM_TIMEOUT_NAME as a zig per-test
#   timeout line (exercising the script's sed parser, spaces included),
#   print a summary the script's floor check accepts, exit SHIM_EXIT.
shim="$work/zig"
cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
set -u
if [ -n "${SHIM_WEDGE_ONCE:-}" ] && [ ! -f "${SHIM_WEDGE_ONCE}" ]; then
    : > "${SHIM_WEDGE_ONCE}"
    sleep 9999 & sleep 9999 & wait
fi
if [ -n "${SHIM_HANG_FIRST:-}" ]; then
    count=0
    [ -f "${SHIM_HANG_FIRST}" ] && count=$(cat "${SHIM_HANG_FIRST}")
    if [ "$count" -gt 0 ]; then
        echo $((count - 1)) > "${SHIM_HANG_FIRST}"
        sleep 9999 & sleep 9999 & wait
    fi
fi
if [ -n "${SHIM_WEDGE_FILTER:-}" ]; then
    for a in "$@"; do
        case "$a" in
            -Dtest-filter=*"$SHIM_WEDGE_FILTER"*) sleep 9999 & sleep 9999 & wait ;;
        esac
    done
fi
[ -n "${SHIM_DELAY:-}" ] && sleep "$SHIM_DELAY"
if [ -n "${SHIM_TIMEOUT_NAME:-}" ]; then
    printf "error: '%s' timed out after 90s\n" "$SHIM_TIMEOUT_NAME"
fi
printf '%s\n' \
    "test success" \
    "+- run test unit-tests 60 pass (60 total) 1s MaxRSS:1M" \
    "+- run test thottam-tests 1 pass (1 total) 1s MaxRSS:1M"
exit "${SHIM_EXIT:-0}"
SHIM
chmod +x "$shim"

# Common knobs: the pinned KAAPPI_TEST_TIMEOUT guards against a caller's
# run-all.sh KAAPPI_TEST_TIMEOUT (seconds, for Scheme tests) leaking into
# the --test-timeout grammar (a Zig duration). The level-funding constants
# are scaled down so a level's "full estimate" is seconds, not minutes.
base_env="KAAPPI_ZIG=$shim KAAPPI_TEST_TIMEOUT=8m KAAPPI_BISECT_TEST_TIMEOUT=90s"
base_env="$base_env KAAPPI_BISECT_LEVEL_BASE_SECS=2 KAAPPI_BISECT_LEVEL_PER_FILTER_SECS=1"
base_env="$base_env KAAPPI_HEARTBEAT_SECS=2"

# Structure: --list still derives the rest chunk's filters from the tree,
# and an unknown chunk name is a usage error, not a silent success.
n=$(bash tools/run-unit-test-chunk.sh --list rest | wc -l | tr -d ' ')
[ "$n" -ge 20 ] || fail "--list rest produced only $n filters (expected the derived remainder, dozens)"
if bash tools/run-unit-test-chunk.sh --list bogus-chunk > /dev/null 2>&1; then
    fail "an unknown chunk name must exit 2"
fi

# Case 1: NO wall budget (the header's primary invocation). The heartbeat
# must fire on this path too -- before the budget_note fix it died on an
# unbound variable under bash >= 4 and orphaned the zig tree it supervised
# -- and a clean finish must still reach the floor-checked summary.
rc=0
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env SHIM_DELAY=8 bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "case 1 (no budget): a clean unbudgeted run must exit 0 (got $rc)"
grep -q "still running at" "$out" || fail "case 1: no heartbeat on the unbudgeted path"
grep -q "== unit-test chunk 'rest': 60 tests (floor " "$out" ||
    fail "case 1: no floor-checked summary line after a clean finish"

# Case 2: the descent. The shim wedges exactly when the subset contains
# tests_printer, so every half holding it times out at its FULL estimate
# (decisive), every other half completes, and the descent must end on the
# single filter, confirmed by its solo run.
rc=0
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env KAAPPI_CHUNK_BUDGET=3 KAAPPI_BISECT_BUDGET=120 \
    SHIM_WEDGE_FILTER="tests_printer.test." \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || fail "case 2 (descent): wall-budget overrun must exit 124 (got $rc)"
grep -q "WALL BUDGET EXCEEDED" "$out" || fail "case 2: no streamed budget-exceeded line"
grep -q "descending into this half" "$out" || fail "case 2: no decisive-timeout descent line"
grep -q "LOCALISED AND CONFIRMED: filter 'tests_printer.test.'" "$out" ||
    fail "case 2: the descent did not end confirmed on tests_printer"
grep -q "zig build test -Dtest-filter=tests_printer.test." "$out" ||
    fail "case 2: no reproduce command for the confirmed filter"

# Case 3: the per-test reading. Only the FIRST invocation (the chunk run
# itself) wedges; every level then completes while printing a zig per-test
# timeout line with SPACES in the name, which must surface whole as a NOTE
# and exactly once in the RESULT (the level and the full re-run both see
# it; the collection dedups).
rc=0
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env KAAPPI_CHUNK_BUDGET=3 KAAPPI_BISECT_BUDGET=120 \
    SHIM_WEDGE_ONCE="$work/once" SHIM_TIMEOUT_NAME="tests_fake.test.slow one" \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || fail "case 3 (per-test): wall-budget overrun must exit 124 (got $rc)"
grep -q "NOTE: 'tests_fake.test.slow one' exceeded the tight 90s bound" "$out" ||
    fail "case 3: no NOTE line carrying the whole space-containing name"
[ "$(grep -c "^== RESULT: no level wedged; per-test suspect(s) named by the tight bound: 'tests_fake.test.slow one'$" "$out")" -eq 1 ] ||
    fail "case 3: the RESULT must name the suspect exactly once"

# Case 4: a level the pot can only clip. The chunk run and depth 1 both
# hang (the counter file seeds two hangs), and the pot funds 10s of a 25s
# estimate: the timeout must be reported INCONCLUSIVE and must NOT narrow
# the descent.
echo 2 > "$work/count"
rc=0
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env KAAPPI_CHUNK_BUDGET=3 KAAPPI_BISECT_BUDGET=10 \
    SHIM_HANG_FIRST="$work/count" \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || fail "case 4 (clipped level): wall-budget overrun must exit 124 (got $rc)"
grep -q "INCONCLUSIVE" "$out" || fail "case 4: a clipped-allowance timeout was not reported INCONCLUSIVE"
grep -q "descending into this half" "$out" && fail "case 4: an inconclusive level must not descend"
grep -q "RESULT: inconclusive -- the pot could not fund decisive levels" "$out" ||
    fail "case 4: no pot-too-small verdict line"

echo "PASS: watchdog, heartbeat, decisive descent, per-test NOTEs, and the"
echo "PASS: clipped-level INCONCLUSIVE stop all behave and are all streamed"
