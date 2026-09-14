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
# level the pot could only clip, the unbudgeted heartbeat (which died
# on an unbound variable under bash >= 4 before the fix), and the level
# estimates on both of depth 2's windows (kaappi#2596) -- without ever
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
# A copy of sleep under the name `zig`: as a GRANDCHILD of the shim its
# comm is "zig", which pins phase_of's compiling branch (the test binary
# and the QEMU wrapper hold the same position with a different name).
mkdir -p "$work/bin"
cp "$(command -v sleep)" "$work/bin/zig"
# macOS AMFI kills a copied system binary that carries no valid signature,
# so re-sign the copy ad hoc; Linux and the BSDs enforce nothing here.
if [ "$(uname -s)" = "Darwin" ]; then
    codesign --force -s - "$work/bin/zig" > /dev/null 2>&1 || true
fi
cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
set -u
# hang_tree: hang with a GRANDCHILD whose executable name decides what
# the script's phase_of reports -- `sleep` (default) reads as a spawned
# test binary ("running tests"); the sleep copy named zig
# (SHIM_WEDGE_STYLE=compile + SHIM_FAKE_ZIG) reads as the compiler.
hang_tree() {
    case "${SHIM_WEDGE_STYLE:-}" in
        compile) bash -c '"$SHIM_FAKE_ZIG" 9999 & wait' ;;
        *)       bash -c 'sleep 9999 & wait' ;;
    esac
}
if [ -n "${SHIM_WEDGE_ONCE:-}" ] && [ ! -f "${SHIM_WEDGE_ONCE}" ]; then
    : > "${SHIM_WEDGE_ONCE}"
    hang_tree
fi
if [ -n "${SHIM_HANG_FIRST:-}" ]; then
    count=0
    [ -f "${SHIM_HANG_FIRST}" ] && count=$(cat "${SHIM_HANG_FIRST}")
    if [ "$count" -gt 0 ]; then
        echo $((count - 1)) > "${SHIM_HANG_FIRST}"
        hang_tree
    fi
fi
if [ -n "${SHIM_WEDGE_FILTER:-}" ]; then
    for a in "$@"; do
        case "$a" in
            -Dtest-filter=*"$SHIM_WEDGE_FILTER"*) hang_tree ;;
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
base_env="$base_env KAAPPI_BISECT_LEVEL_BASE_SECS=2 KAAPPI_BISECT_LEVEL_PER_TEST_TENTHS=0"
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
# The pot must clear the level floor (BASE/3 = 10s here) by more than a
# second: pot_start and depth 1's now-stamp straddle a clock-tick boundary
# whenever a second flips between them, and a pot equal to the floor then
# reads as one second short and the level is refused as "too shallow"
# instead of run clipped -- a low-single-digit-percent flake per run.
# 12 leaves that tick of slack while still clipping 12 < 30.
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env KAAPPI_CHUNK_BUDGET=3 KAAPPI_BISECT_BUDGET=12 \
    KAAPPI_BISECT_LEVEL_BASE_SECS=30 \
    SHIM_HANG_FIRST="$work/count" \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || fail "case 4 (clipped level): wall-budget overrun must exit 124 (got $rc)"
grep -q "INCONCLUSIVE" "$out" || fail "case 4: a clipped-allowance timeout was not reported INCONCLUSIVE"
grep -q "descending into this half" "$out" && fail "case 4: an inconclusive level must not descend"
grep -q "RESULT: inconclusive -- the pot could not fund decisive levels" "$out" ||
    fail "case 4: no pot-too-small verdict line"

# Case 5: the kill-time phase report, running-tests branch. The shim's
# default hang_tree leaves a `sleep` grandchild, which phase_of must read
# as a spawned test binary. A dry pot keeps the case to the kill itself.
rc=0
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env KAAPPI_CHUNK_BUDGET=3 KAAPPI_BISECT_BUDGET=0 \
    SHIM_WEDGE_ONCE="$work/once5" \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || fail "case 5 (phase, tests): wall-budget overrun must exit 124 (got $rc)"
grep -q "WALL BUDGET EXCEEDED after .*s (running tests)" "$out" ||
    fail "case 5: a sleep grandchild must be reported as tests in flight"

# Case 6: the compiling branch -- same shape, but the grandchild is the
# sleep copy named zig, which phase_of must read as the compiler itself.
rc=0
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env KAAPPI_CHUNK_BUDGET=3 KAAPPI_BISECT_BUDGET=0 \
    SHIM_WEDGE_ONCE="$work/once6" SHIM_WEDGE_STYLE=compile \
    SHIM_FAKE_ZIG="$work/bin/zig" \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || fail "case 6 (phase, compile): wall-budget overrun must exit 124 (got $rc)"
grep -q "WALL BUDGET EXCEEDED after .*s (compiling)" "$out" ||
    fail "case 6: a zig-named grandchild must be reported as compiling"

# Case 7: the per-TEST funding term, with the term nonzero. The depth-1
# and depth-2 lines must carry estimates computed from each subset's own
# declared-test count (the test derives them independently, from the same
# grep of the same files), so a regression back to a flat or per-filter
# estimate changes the printed numbers and fails here. The probe windows
# are derived from --list with the same mid arithmetic the script uses
# (lo=0, hi=count, mid=(lo+hi)/2 per level), so a new test file landing
# in the derived rest chunk moves them with it instead of failing the
# case: depth 1 is the first half, and depth 1 completing (the wedge-once
# stamp was consumed in phase 1) puts depth 2 just past it.
#
# Depth 1 completing is the usual path, not a certainty: it runs an
# instant shim under its full ~44s allowance, and on a loaded VM leg that
# allowance has still expired first (netbsd-test, kaappi#2596). The
# script then reads the overrun as a wedge and DESCENDS, so depth 2 is
# the first half's first half (hi=mid1, so mid=mid1/2) with that window's
# own estimate. Both windows are accepted -- matched by filter count,
# first..last names AND estimate -- the descent one only behind the
# script's own "descending into this half" line for depth 1, so a flat or
# per-filter estimate still fails either way; and every failure prints
# the bisect lines actually seen, so the next flake says which path ran
# without a re-run. Case 8 forces the descent path so its matcher is
# exercised on every run, not just on a stalled VM.
#
# The pot is sized for the descent path: depth 1's full estimate, a poll
# tick and the kill grace, then the alternate depth 2 (15s today), with
# room. On the usual path the pot never binds -- every level completes in
# one poll tick -- so the printed allowances there are the full estimates
# whatever the pot.
est_of() { # est_of <tenths> <start-1-based> <count>: 2s base + tenths x the slice's tests
    local tenths="$1" start="$2" n="$3" total=0 f c
    for f in $(bash tools/run-unit-test-chunk.sh --list rest \
               | sed -n "${start},$((start + n - 1))p" \
               | sed 's/^-Dtest-filter=//; s/\.test\.$//'); do
        c=$(grep -c '^test "' "src/$f.zig" | tr -d ' ')
        total=$((total + c))
    done
    echo $(( 2 + (tenths * total) / 10 ))
}
window_of() { # window_of <start-1-based> <count>: the level line's first..last file names
    local start="$1" n="$2" first last
    first=$(bash tools/run-unit-test-chunk.sh --list rest | sed -n "${start}p")
    last=$(bash tools/run-unit-test-chunk.sh --list rest | sed -n "$((start + n - 1))p")
    first=${first#-Dtest-filter=}; last=${last#-Dtest-filter=}
    echo "${first%.test.}..${last%.test.}"
}
fail_bisect() { # fail_bisect <message>: fail, after showing the bisect lines the script printed
    echo "bisect lines seen (kaappi#2596):" >&2
    grep -e 'WALL BUDGET EXCEEDED' -e '== bisect' "$out" >&2 || echo "  (none)" >&2
    fail "$1"
}
total=$(bash tools/run-unit-test-chunk.sh --list rest | wc -l | tr -d ' ')
mid1=$((total / 2))             # depth 1: filters 1..mid1
mid2=$(((mid1 + total) / 2))    # depth 2 after depth 1 completes: mid1+1..mid2
alt2=$((mid1 / 2))              # depth 2 after depth 1 overruns: 1..alt2
n1=$mid1
n2=$((mid2 - mid1))
n2alt=$alt2
w1=$(window_of 1 "$n1")
w2=$(window_of $((mid1 + 1)) "$n2")
w2alt=$(window_of 1 "$n2alt")
check_level_estimates() { # check_level_estimates <case label> <tenths>: depth 1, then depth 2 on whichever path ran
    local label="$1" tenths="$2" e1 want_n want_w want_e
    e1=$(est_of "$tenths" 1 "$n1")
    grep -q "bisect depth 1: ${n1} filter(s) ${w1}, budget .*s of a ${e1}s estimate" "$out" ||
        fail_bisect "$label: depth 1 is not ${n1} filters ${w1} at a ${e1}s estimate from its subset's test count"
    if grep -q "bisect depth 1: .* did NOT finish in .* -- descending into this half" "$out"; then
        echo "$label: depth 1 overran its allowance, so depth 2 is the descent window (filters 1..${n2alt})"
        want_n=$n2alt; want_w=$w2alt; want_e=$(est_of "$tenths" 1 "$n2alt")
    else
        want_n=$n2; want_w=$w2; want_e=$(est_of "$tenths" $((mid1 + 1)) "$n2")
    fi
    grep -q "bisect depth 2: ${want_n} filter(s) ${want_w}, budget .*s of a ${want_e}s estimate" "$out" ||
        fail_bisect "$label: depth 2 is not ${want_n} filters ${want_w} at a ${want_e}s estimate from its subset's test count"
}
e1=$(est_of 1 1 "$n1")
e2=$(est_of 1 $((mid1 + 1)) "$n2")
e2alt=$(est_of 1 1 "$n2alt")
[ "$e1" -ne "$e2" ] || fail "case 7 setup: the depth-1 and just-past windows estimate equal; pick denser windows"
[ "$e1" -ne "$e2alt" ] || fail "case 7 setup: the depth-1 and descent windows estimate equal; pick denser windows"
rc=0
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env KAAPPI_CHUNK_BUDGET=3 KAAPPI_BISECT_BUDGET=90 \
    KAAPPI_BISECT_LEVEL_PER_TEST_TENTHS=1 \
    SHIM_WEDGE_ONCE="$work/once7" \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || fail_bisect "case 7 (per-test funding): wall-budget overrun must exit 124 (got $rc)"
check_level_estimates "case 7" 1

# Case 8: case 7's descent path, forced. The counter seeds two hangs -- the
# chunk run and depth 1 -- so depth 1 times out at its full estimated
# allowance exactly as a stalled VM makes it, the script descends, and
# depth 2 must be the descent window: the branch of check_level_estimates
# a healthy host never takes. The per-test term is zeroed here so the
# overrun costs one poll tick, not case 7's whole ~44s depth-1 allowance
# (the estimate arithmetic itself is case 7's business); the window is
# still pinned by count and names. A 20s pot lets the descent print two
# or three levels and then dry up, which keeps the case short.
echo 2 > "$work/count8"
rc=0
# shellcheck disable=SC2086  # base_env is a deliberate VAR=val word list for env
env $base_env KAAPPI_CHUNK_BUDGET=3 KAAPPI_BISECT_BUDGET=20 \
    SHIM_HANG_FIRST="$work/count8" \
    bash tools/run-unit-test-chunk.sh rest > "$out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || fail_bisect "case 8 (forced depth-1 overrun): wall-budget overrun must exit 124 (got $rc)"
grep -q "bisect depth 1: .* did NOT finish in [0-9]*s at its full estimated allowance .* -- descending into this half" "$out" ||
    fail_bisect "case 8: the seeded depth-1 hang did not overrun at its full allowance and descend"
check_level_estimates "case 8" 0

echo "PASS: watchdog, heartbeat, decisive descent, per-test NOTEs, the"
echo "PASS: clipped-level INCONCLUSIVE stop, both kill-time phase reads,"
echo "PASS: level estimates that follow the subset's own test count, on"
echo "PASS: both the just-past and the descent depth-2 windows"
