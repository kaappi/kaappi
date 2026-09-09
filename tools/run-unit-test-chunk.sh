#!/usr/bin/env bash
# Run one named chunk of the Zig unit suite, so a hang names its chunk.
#
#     bash tools/run-unit-test-chunk.sh <process|concurrency|rest> [zig build args...]
#     bash tools/run-unit-test-chunk.sh --list <chunk>      # print the filters, run nothing
#     KAAPPI_TEST_TIMEOUT=90s bash tools/run-unit-test-chunk.sh <chunk>   # per-test bound
#     KAAPPI_CHUNK_BUDGET=1320 bash tools/run-unit-test-chunk.sh <chunk>  # wall budget, seconds
#
# WHY THIS EXISTS. `riscv64-test` runs the whole unit suite under QEMU
# user-mode as ONE `zig build test` step that prints nothing until it
# finishes. When a test hangs there, the only evidence is a 45-minute log
# with a single line in it and an `unit-tests` orphan at the end (kaappi#2488
# -- roughly one run in four since 2026-09-02). Splitting the suite into a
# few chunks, each its own workflow step with its own `timeout-minutes`,
# makes the next hang say WHICH chunk it was in. Chunking is a diagnostic,
# not a fix; the chunks exist to be narrowed, not to grow.
#
# THE PER-TEST TIMEOUT. `zig build test` talks to the test binary over the
# binary's stdin/stdout (`--listen=-`): it asks for one test at a time and,
# by default, waits for that test's result FOREVER -- which is the whole
# 43-minute silence above. Zig 0.16's `--test-timeout <duration>` bounds
# that wait per test: a test that overruns it is reported by NAME
# ("'<file>.test.<title>' timed out after 8m"), its process is killed, and
# the runner respawns the binary and carries on from the next test, so one
# hang costs the timeout, names its test, and still leaves every other
# test's verdict in the log. The same bound covers the other way a run can
# go silent: a test that writes to fd 1 corrupts the IPC stream (the build
# runner reads the stray bytes as a message header and waits for a body
# that never comes), and the runner now gives up on that test too instead
# of on the whole step.
#
# WHY THE PER-TEST NAME DID NOT SURVIVE CI KILLS (kaappi#2560). `zig build`
# buffers its ENTIRE console output -- summaries and per-test timeout
# messages alike -- until the process exits. Verified on Zig 0.16.0: piped
# through `tee`, redirected to a file, or run under a pty, a test that
# times out is killed and named at the moment the bound fires, yet zero
# bytes leave `zig build` until it exits; SIGTERM does not flush the buffer
# either. So on a step killed at its `timeout-minutes` cap, every name the
# per-test bound had already recorded died inside the buffer -- which is
# exactly the silent >24m kill of kaappi#2560, and it defeats #2491's
# naming on every capped step, not just this chunk. The name survives only
# when `zig build` exits on its own -- which is why the wall budget below
# is sized to outlive one per-test bound: one hung test is still named by
# zig itself, and it is only the second hang (or a wedge the runner cannot
# see) that falls through to bisection.
#
# THE WALL BUDGET AND BISECTION. This script prints its own lines to the
# live log as it goes (bash `echo` is unbuffered), so they survive any kill:
# a heartbeat while the chunk runs, a loud line when the wall budget
# expires, and one line per bisection level naming the filter subset in
# flight. Bisection re-runs `zig build test` on halves of the chunk's
# filter list with a TIGHT per-test bound (`KAAPPI_BISECT_TEST_TIMEOUT`,
# default 90s -- bisection is localisation, not adjudication). A half that
# cannot finish in its level budget holds a process-level wedge; the
# descent follows those halves down to a single filter, confirmed by a
# solo run. A half that finishes never exonerates slow TESTS -- the tight
# bound kills those mid-level and zig flushes their names when the level
# exits, which the script echoes as NOTE lines; if no level ever wedged,
# the whole chunk is re-run under the tight bound (the same filter set as
# the chunk run, so its compile is cached whenever that run got past
# compiling) so every per-test culprit is named in full context. The last
# line before any kill therefore names the filter, the
# narrowed subset, or the slow test -- the reopen criterion of #2488. Each
# level costs at most one test-binary compile for its fresh filter set
# (~1.5m cold on the CI host, cache-warm objects after phase 1), so levels
# are binary-searched, never swept, and the whole phase runs inside
# KAAPPI_BISECT_BUDGET (default 1080s). The pot funds FULL level
# estimates; a level whose allowance the pot could only clip is run anyway
# but its timeout is reported INCONCLUSIVE and never narrows the descent
# (its completion still exonerates). When the pot empties, the suspects
# list is printed as-is and a human can re-run with a bigger pot. At the
# kill itself the script also reports the tree's phase -- compiling vs
# running tests, read from the process tree -- so every "did not finish"
# line says what it was doing instead of asserting a wedge it cannot see.
# Caveat, stated plainly: a wedge that is order- or load-dependent may
# reproduce under none of these treatments; the log then says so instead
# of guessing.
#
# Knobs (unset means the old behaviour -- no watchdog, no bisection):
#   KAAPPI_TEST_TIMEOUT            per-test bound for the chunk run (Zig
#                                  duration; default 8m, see below)
#   KAAPPI_CHUNK_BUDGET            wall budget for the chunk run, SECONDS;
#                                  0/unset disables the watchdog
#   KAAPPI_BISECT_BUDGET           total bisection pot, SECONDS (default 1080)
#   KAAPPI_BISECT_TEST_TIMEOUT     per-test bound during bisection levels
#                                  (Zig duration; default 90s)
#   KAAPPI_BISECT_LEVEL_BASE_SECS        level-funding estimate base,
#                                        SECONDS (default 120; see the
#                                        constants below)
#   KAAPPI_BISECT_LEVEL_PER_TEST_TENTHS  ...and per-TEST term, tenths of
#                                        a second (default 12 = 1.2s/test)
#   KAAPPI_HEARTBEAT_SECS          heartbeat cadence, SECONDS (default 60)
#   KAAPPI_ZIG                     zig binary to drive (default `zig`); for
#                                  the shim-driven regression test
#
# The chunk run exits 124 when the wall budget fired (the `timeout(1)`
# convention), so CI fails loudly while the log carries the localisation.
#
# $KAAPPI_TEST_TIMEOUT's default is sized from the slowest chunk under
# QEMU: the fuzz chunk's 20 tests (the fixed-seed generator gates among
# them) take about 4.5m TOGETHER, so no single test is anywhere near 8m,
# and under emulation a legitimately slow test must never be mistaken for
# a hang.
#
# HOW THE CHUNKS ARE CUT. `-Dtest-filter` is a substring match on a test's
# qualified name, `<file basename>.test.<title>` (build.zig; repeatable).
# Anchoring every filter as `<basename>.test.` selects exactly the tests
# declared in that file: `ffi.test.` also matches `tests_ffi.test.…`, but a
# test is included ONCE however many filters match it (the filter prunes
# `builtin.test_functions` at compile time), so overlap costs nothing and
# every filter is emitted unconditionally. The one consequence across
# chunks: a listed file whose basename ENDS with an unlisted file's basename
# also runs in `rest` (`native_compiler` ends with `compiler`, so its five
# tests run in both `native` and `rest`). That is a few seconds of
# duplicated work, never a dropped test, and the exact per-chunk counts are
# in the PR that introduced each chunk.
#
#   process      the KEP-0022 subprocess tests: every child they spawn is a
#                whole /bin/sh emulated through binfmt on the QEMU legs
#   concurrency  fibers, reactor, scheduler, channels, SRFI-18 threads --
#                the parking and timing paths
#   io           ports and the reactor-driven reads behind them: file and
#                string ports, transcoded ports (SRFI 181), the incremental
#                reader, the filesystem primitives (SRFI 170)
#   fuzz         the fuzz generators and their wall-clock/instruction-bounded
#                harness (#1573 was this family flaking under QEMU)
#   gc           the collector: tracing, runtime stress, root-boundary OOM
#                sweeps, deep copy, and the robustness edge-case suite
#   native       the LLVM native tier (skips almost entirely on the
#                interpreter-tier QEMU legs, so this chunk is cheap there)
#   tooling      the CLI surface and its subcommands (check, fmt, doctor,
#                explain, features, the `kaappi test` runner -- whose worker
#                processes are emulated children on the QEMU legs), the
#                bytecode/library caches, the REPL, and thottam (this is
#                where the `thottam-tests` binary runs its full suite)
#   rest         EVERY OTHER `src/*.zig` file that declares a `test "…"`,
#                derived from the tree, so a new test file lands here
#                automatically and cannot be silently dropped
#
# The first split (process / concurrency / rest) localised kaappi#2488's
# first recurrence to `rest`, which was 1646 tests wide; the io / fuzz / gc /
# native chunks are the second cut, along the seams in that remainder with
# QEMU-sensitive behaviour. Add a chunk by adding a list and a case below;
# `rest` shrinks by itself because it is derived from what is NOT listed.
#
# Two things keep the split honest. A name in the explicit lists that matches
# no file FAILS the run (a list cannot rot into a silent no-op -- the same
# rule `KAAPPI_GC_STRESS_SKIP` follows). And every chunk asserts it ran more
# tests than the unnamed `test { _ = @import(…); }` reference blocks, which
# a filtered build keeps regardless of filter (five of them in the unit
# binary today; they are why N chunk totals sum to the unfiltered total
# plus 5*(N-1), before the duplicate noted above). A chunk whose filters
# matched nothing therefore fails instead of passing vacuously.
#
# The `thottam-tests` binary takes the same filters (build.zig hands both
# test steps the same list): it runs its full 88 in `tooling`, which lists
# the thottam files, and only its own unnamed block in every other chunk.
#
# Works for any target: pass `-Dtarget=riscv64-linux` (or nothing, for the
# host) after the chunk name. Exit status is `zig build test`'s, 124 when
# the wall budget fired, or 2 for a misuse this script detected itself.

set -u
set -o pipefail

PROCESS_FILES="tests_process tests_process_run tests_process_win"
CONCURRENCY_FILES="tests_fibers tests_reactor tests_reactor_parity tests_scheduler
                   tests_shared_channel tests_shared_channel_rendezvous tests_srfi18
                   tests_waitforfd"
IO_FILES="tests_io tests_port_io tests_random_port tests_srfi181
          tests_reader_incremental tests_filesystem primitives_io"
FUZZ_FILES="tests_fuzz fuzz_gen fuzz_gen_native fuzz_gen_portable"
GC_FILES="tests_gc_tracing tests_gc_runtime_stress tests_gc_root_boundary
          tests_deepcopy tests_robustness memory"
NATIVE_FILES="tests_native tests_native_dispatch tests_native_gate
              native_compiler llvm_emit"
TOOLING_FILES="cli cli_spec completions config check_lint tests_check doctor
               explain features fmt tests_fmt kaappi_paths lsp_diagnostic
               test_runner test_selection timings crash repl disassembler
               tests_diagnostics bytecode_file cache tests_bytecode_cache
               tests_vm_library_cache thottam thottam_fs thottam_proc
               thottam_semver thottam_state tests_thottam"
# Every explicitly listed file, for the `rest` derivation and the existence
# check. Extend this when adding a list.
LISTED_FILES="$PROCESS_FILES $CONCURRENCY_FILES $IO_FILES $FUZZ_FILES $GC_FILES $NATIVE_FILES $TOOLING_FILES"
CHUNK_NAMES="process|concurrency|io|fuzz|gc|native|tooling|rest"

# Bisection level funding, seconds. A level's ESTIMATE is the plausible
# worst case for a CLEAN level: a fresh compile for the subset (~90s on
# the CI host) plus runtime per TEST in it. The term is per test, not per
# filter, because the `rest` chunk's filters are skewed 2.4-4.7x in test
# count (tests_ir carries 94 against a ~20-per-file average) and a
# per-filter term underestimates the heavy windows enough to misread a
# clean level as wedged -- worst at the solo confirm, which would print
# LOCALISED AND CONFIRMED for a merely-heavy file. The default term is 12
# tenths of a second (~2x the ~0.6s/test the #2560 numbers give for
# `rest` under QEMU: 907 tests in ~9.5m after the ~1.5m compile). A level
# run at its full estimate therefore separates the outcomes: finishing
# exonerates its half, and only not-finishing implicates it. The pot
# funds FULL estimates -- deliberately no fractional share, because a
# clipped level's TIMEOUT is not evidence (a clean level can simply be
# slower than a clipped allowance): an under-funded timeout is reported
# INCONCLUSIVE and never narrows the descent, while an under-funded
# COMPLETION still exonerates (finishing is finishing whatever the
# allowance was). Below MIN (BASE/3: a fraction of even the compile) a
# level cannot decide anything and is not started. Natively everything
# finishes far under the estimate; the constants are env-overridable for
# fast hosts and for the shim-driven regression test (which zeroes the
# per-test term so an estimate is the base alone).
BISECT_LEVEL_BASE_SECS="${KAAPPI_BISECT_LEVEL_BASE_SECS:-120}"
BISECT_LEVEL_PER_TEST_TENTHS="${KAAPPI_BISECT_LEVEL_PER_TEST_TENTHS:-12}"
BISECT_LEVEL_MIN_SECS=$((BISECT_LEVEL_BASE_SECS / 3))
[ "$BISECT_LEVEL_MIN_SECS" -ge 1 ] || BISECT_LEVEL_MIN_SECS=1

usage() {
    echo "usage: $0 [--list] <$CHUNK_NAMES> [zig build args...]" >&2
    exit 2
}

# fname <-Dtest-filter=NAME.test.>: the bare file name, for display and for
# building the reproduce command (which re-adds the `.test.` anchor).
fname() {
    local s="$1"
    s="${s#-Dtest-filter=}"
    printf '%s' "${s%.test.}"
}

list_only=0
if [ "${1:-}" = "--list" ]; then
    list_only=1
    shift
fi
chunk="${1:-}"
[ -n "$chunk" ] || usage
shift

# Resolve paths against the repo root so the script works from any cwd.
cd "$(dirname "$0")/.." || exit 2

# Every explicitly listed name must be a real test file, or the list has
# rotted and the chunk would quietly shrink.
for name in $LISTED_FILES; do
    if [ ! -f "src/$name.zig" ]; then
        echo "$0: '$name' names no src/$name.zig -- update the chunk lists" >&2
        exit 2
    fi
done

in_list() { # in_list <name> <list...>
    local needle="$1"; shift
    local n
    for n in "$@"; do [ "$n" = "$needle" ] && return 0; done
    return 1
}

case "$chunk" in
    process)     names="$PROCESS_FILES" ;;
    concurrency) names="$CONCURRENCY_FILES" ;;
    io)          names="$IO_FILES" ;;
    fuzz)        names="$FUZZ_FILES" ;;
    gc)          names="$GC_FILES" ;;
    native)      names="$NATIVE_FILES" ;;
    tooling)     names="$TOOLING_FILES" ;;
    rest)
        names=""
        for f in src/*.zig; do
            n="$(basename "$f" .zig)"
            # shellcheck disable=SC2086
            in_list "$n" $LISTED_FILES && continue
            grep -q '^test "' "$f" || continue
            names="$names $n"
        done
        ;;
    *) usage ;;
esac

filters=()
filter_tests=()
for n in $names; do
    filters+=("-Dtest-filter=$n.test.")
    # The bisection's level estimates are per TEST (see the constants
    # above), so carry each file's declared-test count alongside its
    # filter. grep -c prints 0 and exits 1 for a listed file with no
    # named tests; that status is harmless here because the command
    # substitution feeding an array append discards it (set -e is what
    # would mind, and this script does not set it).
    filter_tests+=("$(grep -c '^test "' "src/$n.zig" | tr -d ' ')")
done

if [ "$list_only" = 1 ]; then
    printf '%s\n' "${filters[@]}"
    exit 0
fi

# The floor a chunk must clear: the unnamed reference blocks are in every
# filtered binary, so a chunk that matched nothing still reports that many.
floor="$(grep -l '^test {' src/*.zig | wc -l | tr -d ' ')"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

test_timeout="${KAAPPI_TEST_TIMEOUT:-8m}"
budget="${KAAPPI_CHUNK_BUDGET:-0}"
bisect_pot="${KAAPPI_BISECT_BUDGET:-1080}"
bisect_timeout="${KAAPPI_BISECT_TEST_TIMEOUT:-90s}"
heartbeat_secs="${KAAPPI_HEARTBEAT_SECS:-60}"
# The zig binary to drive. KAAPPI_ZIG exists so the regression test can
# point the script at a shim that plays wedged/clean subsets in seconds;
# everything else gets the real `zig` from PATH.
zig_bin="${KAAPPI_ZIG:-zig}"

# tree_pids <pid>: the pid and its descendants, deepest first. `zig
# build`'s direct child is the cached build-runner binary, whose child is
# the (possibly emulated) test binary; none of them die with their parent
# on their own (verified: TERMing `zig build` leaves the runner orphaned
# and burning CPU), so a watchdog kill must walk the whole tree -- and the
# KILL escalation must walk a SNAPSHOT taken BEFORE the TERM: once the
# parent exits, `pgrep -P` can no longer find the re-parented survivors,
# and an escalation computed from the live tree signals nothing. pgrep -P
# exists on Linux, macOS and the BSDs; where it does not (MSYS), only the
# pid itself is captured and the caller's own process group is the net.
tree_pids() {
    local pid="$1" child
    if command -v pgrep > /dev/null 2>&1; then
        for child in $(pgrep -P "$pid" 2>/dev/null); do
            tree_pids "$child"
        done
    fi
    printf '%s\n' "$pid"
}

# phase_of <zig-pid>: what the tree was doing when the budget fired --
# "compiling" while a grandchild is the zig compiler itself, "running
# tests" once a grandchild is a spawned test binary instead (under QEMU
# that grandchild is the emulator wrapper, also not `zig`). zig prints
# nothing (see the header), so the tree's shape is the only signal, and
# the verdicts quote it as a heuristic, not a fact.
phase_of() {
    local pid="$1" child gc base verdict
    command -v pgrep > /dev/null 2>&1 || { echo "unknown"; return; }
    verdict=""
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        for gc in $(pgrep -P "$child" 2>/dev/null); do
            # Whole line, not the first word: macOS comm= is the full
            # executable path, so a checkout under a directory with a
            # space in its name would split to a non-zig first word and
            # misclassify a compile as running tests. Linux comm= is the
            # 15-char executable name, never a path; the basename is
            # identity either way.
            base=""
            read -r base < <(ps -o comm= -p "$gc" 2>/dev/null)
            base="${base##*/}"
            if [ "$base" != "zig" ] && [ -n "$base" ]; then
                echo "running tests"
                return
            fi
            verdict="compiling"
        done
    done
    if [ -n "$verdict" ]; then
        echo "$verdict"
    else
        echo "unknown"
    fi
}

# run_supervised <budget-secs> <label> <zig args...>
#
# Runs `zig build test <args...> --summary all`, teeing its output to the
# live log as it appears (in practice once, at exit -- see the header) and
# to "$log", while printing a heartbeat every $heartbeat_secs and enforcing
# the wall budget. The zig pid is tracked directly (output goes to a file
# the script forwards, not through a pipeline, so `$!` is zig and killing it
# orphans nothing but its own tree). Sets on return: zig_status,
# watchdog_fired (1 = budget expired and the tree was killed), ran_secs.
run_supervised() {
    local budget="$1" label="$2"; shift 2
    local start now next_beat sent size grace doomed p
    # Empty by default: a heartbeat must expand it on the unbudgeted path
    # too, and `local x` alone is UNSET under `set -u` on bash >= 4 (bash
    # 3.2 leaves it set-but-empty, which is why macOS hid the bug).
    local budget_note=""
    : > "$log"
    "$zig_bin" build test "$@" --summary all > "$log" 2>&1 &
    zig_pid=$!
    start=$(date +%s)
    next_beat=$((start + heartbeat_secs))
    sent=0
    watchdog_fired=0
    if [ "$budget" -gt 0 ]; then
        budget_note=" of a ${budget}s budget"
    fi
    while kill -0 "$zig_pid" 2> /dev/null; do
        sleep 5
        now=$(date +%s)
        size=$(wc -c < "$log" | tr -d ' ')
        if [ "$size" -gt "$sent" ]; then
            tail -c +$((sent + 1)) "$log"
            sent=$size
        fi
        # Re-check liveness after the sleep: a run that FINISHED during
        # the poll interval must not be heartbeat-reported as running or
        # watchdog-killed as overran, which a bare elapsed >= budget test
        # would do whenever the budget is under the poll interval.
        if kill -0 "$zig_pid" 2> /dev/null; then
            if [ "$now" -ge "$next_beat" ]; then
                echo "== $label: still running at $((now - start))s${budget_note} (zig pid $zig_pid; zig buffers its output until exit, so silence here is normal)"
                next_beat=$((now + heartbeat_secs))
            fi
            if [ "$budget" -gt 0 ] && [ $((now - start)) -ge "$budget" ]; then
                watchdog_fired=1
                kill_phase=$(phase_of "$zig_pid")
                doomed=$(tree_pids "$zig_pid")
                echo "== $label: WALL BUDGET EXCEEDED after $((now - start))s ($kill_phase) -- killing the zig build tree (its buffered output dies with it)"
                for p in $doomed; do kill -TERM "$p" 2> /dev/null || true; done
                grace=0
                while [ "$grace" -lt 10 ] && kill -0 "$zig_pid" 2> /dev/null; do
                    sleep 1
                    grace=$((grace + 1))
                done
                # KILL the SNAPSHOT, not the live tree: TERM may have
                # already reaped zig itself, and survivors are unfindable
                # afterwards.
                for p in $doomed; do kill -KILL "$p" 2> /dev/null || true; done
                break
            fi
        fi
    done
    wait "$zig_pid" 2> /dev/null
    zig_status=$?
    # Final drain: zig's whole buffered output lands in the file at exit.
    size=$(wc -c < "$log" | tr -d ' ')
    if [ "$size" -gt "$sent" ]; then
        tail -c +$((sent + 1)) "$log"
    fi
    ran_secs=$(( $(date +%s) - start ))
}

# bisect_chunk <zig args...>: binary-search the filter list for the wedge,
# spending at most $bisect_pot seconds in total. Prints one line per level
# BEFORE running it, so a kill anywhere leaves the in-flight subset named.
#
# Four honest outcomes, because a wedge has three shapes and the pot can
# run out:
#   * a PROCESS-level wedge (emulation or runner stuck) also wedges every
#     bisection level that contains it; the descent follows the wedged
#     halves and ends on one filter, confirmed by a solo run;
#   * PER-TEST hangs never wedge a level -- the tight per-test bound kills
#     each one mid-level and the level completes -- so the descent cannot
#     follow them; instead every name the tight bound flushes is echoed as
#     a NOTE line, and if NO level ever wedged, the whole chunk is re-run
#     under the tight bound (same filter set as the chunk run, so its
#     compile is cached whenever that run got past compiling) to name
#     every per-test culprit in full context;
#   * a wedge that reproduces under neither treatment is order- or
#     load-dependent, and the log says so instead of guessing;
#   * a level the pot could only fund below its estimate never narrows on
#     a timeout -- that is INCONCLUSIVE, not evidence -- though its
#     completion still exonerates (finishing is finishing).
bisect_chunk() {
    local lo=0 hi=${#filters[@]} depth=0 mid n est allow remaining now subset_tests
    local pot_start first last f i tn
    local wedged_seen=0 full_rerun_wedged=0 inconclusive_seen=0 bisect_slow_notes=""
    pot_start=$(date +%s)
    echo "== bisect: ${#filters[@]} filter(s), per-test timeout $bisect_timeout, total budget ${bisect_pot}s"
    while [ $((hi - lo)) -gt 1 ]; do
        depth=$((depth + 1))
        now=$(date +%s)
        remaining=$((bisect_pot - (now - pot_start)))
        mid=$(((lo + hi) / 2))
        n=$((mid - lo))
        subset_tests=0
        i=$lo
        while [ "$i" -lt "$mid" ]; do
            subset_tests=$((subset_tests + filter_tests[i]))
            i=$((i + 1))
        done
        est=$((BISECT_LEVEL_BASE_SECS + (BISECT_LEVEL_PER_TEST_TENTHS * subset_tests) / 10))
        allow=$est
        [ "$allow" -gt "$remaining" ] && allow=$remaining
        if [ "$allow" -lt "$BISECT_LEVEL_MIN_SECS" ]; then
            echo "== bisect: remaining pot (${remaining}s) is too shallow for depth $depth (a level needs >= ${BISECT_LEVEL_MIN_SECS}s to tell wedged from clean)"
            break
        fi
        first=$(fname "${filters[lo]}")
        last=$(fname "${filters[mid - 1]}")
        echo "== bisect depth $depth: $n filter(s) $first..$last, budget ${allow}s of a ${est}s estimate"
        run_supervised "$allow" "bisect depth $depth ($first..$last)" "${filters[@]:lo:n}" "$@" --test-timeout "$bisect_timeout"
        if [ "$watchdog_fired" = 1 ]; then
            if [ "$allow" -lt "$est" ]; then
                inconclusive_seen=1
                echo "== bisect depth $depth: $first..$last did NOT finish in ${allow}s, but that allowance was clipped below the ${est}s estimate -- INCONCLUSIVE (a clean level of this size can be slower than a clipped allowance); not descending"
                break
            fi
            wedged_seen=1
            echo "== bisect depth $depth: $first..$last did NOT finish in ${allow}s at its full estimated allowance ($kill_phase at kill time) -- descending into this half"
            hi=$mid
        else
            echo "== bisect depth $depth: $first..$last finished in ${ran_secs}s (zig exit $zig_status) -- no process wedge here, discarding this half"
            # A completed level can still carry the phase-1 culprit: a test
            # that is merely SLOW (not wedged) survives phase 1's 8m bound
            # long enough to blow the wall budget but not the tight one, and
            # zig flushes its name when the level exits. Surface it.
            # Whole lines, not word-split: a test TITLE can contain spaces
            # ('synthetic wedge 2560'), and a shattered name localises
            # nothing. Collected once per test, not once per sighting.
            while IFS= read -r tn; do
                [ -n "$tn" ] || continue
                echo "== bisect depth $depth: NOTE: '$tn' exceeded the tight $bisect_timeout bound -- a phase-1 suspect"
                case "$bisect_slow_notes" in
                    *"'$tn'"*) ;;
                    *) bisect_slow_notes="$bisect_slow_notes '$tn'" ;;
                esac
            done < <(sed -n "s/^error: '\([^']*\)' timed out after.*/\1/p" "$log")
            lo=$mid
        fi
    done

    now=$(date +%s)
    remaining=$((bisect_pot - (now - pot_start)))

    if [ "$wedged_seen" = 0 ]; then
        # No level wedged, so the descent proves nothing about filters: the
        # phase-1 overrun was per-test (hangs or slowness the runner can
        # bound) or it does not reproduce at all. The tight-bound full
        # re-run names the former; the log's honesty covers the latter.
        if [ "$remaining" -ge "$BISECT_LEVEL_MIN_SECS" ]; then
            echo "== bisect: no level wedged -- re-running the whole chunk under the tight $bisect_timeout bound (same filter set as the chunk run; its compile is cached whenever that run got past compiling) to name per-test culprits in full context, budget ${remaining}s"
            run_supervised "$remaining" "bisect full re-run" "${filters[@]}" "$@" --test-timeout "$bisect_timeout"
            if [ "$watchdog_fired" = 1 ]; then
                full_rerun_wedged=1
                echo "== the full chunk did not finish the re-run in ${ran_secs}s ($kill_phase at kill time) -- if the tests were in flight that is an order- or interaction-dependent wedge; if it was still compiling, the pot was simply too small to conclude anything"
            else
                echo "== the full re-run finished (zig exit $zig_status): any 'timed out after' name above is a phase-1 suspect"
                while IFS= read -r tn; do
                    [ -n "$tn" ] || continue
                    case "$bisect_slow_notes" in
                        *"'$tn'"*) ;;
                        *) bisect_slow_notes="$bisect_slow_notes '$tn'" ;;
                    esac
                done < <(sed -n "s/^error: '\([^']*\)' timed out after.*/\1/p" "$log")
            fi
        else
            echo "== bisect: budget pot too dry for the tight-bound full re-run"
        fi
        if [ "$full_rerun_wedged" = 1 ]; then
            echo "== RESULT: inconclusive -- the full-chunk re-run did not finish ($kill_phase); nothing is narrowed"
        elif [ "$inconclusive_seen" = 1 ]; then
            echo "== RESULT: inconclusive -- the pot could not fund decisive levels (see the INCONCLUSIVE line above); re-run with a larger KAAPPI_BISECT_BUDGET"
        elif [ -n "$bisect_slow_notes" ]; then
            echo "== RESULT: no level wedged; per-test suspect(s) named by the tight bound:$bisect_slow_notes"
        else
            echo "== RESULT: nothing reproduced under bisection -- the phase-1 overrun was order- or load-dependent, or slower than every budget here"
        fi
        return 0
    fi

    if [ $((hi - lo)) -eq 1 ]; then
        f=$(fname "${filters[lo]}")
        if [ "$remaining" -ge "$BISECT_LEVEL_MIN_SECS" ]; then
            est=$((BISECT_LEVEL_BASE_SECS + (BISECT_LEVEL_PER_TEST_TENTHS * filter_tests[lo]) / 10))
            allow=$est
            [ "$allow" -gt "$remaining" ] && allow=$remaining
            echo "== bisect: confirming the single suspect $f alone (budget ${allow}s)"
            run_supervised "$allow" "bisect confirm ($f)" "${filters[lo]}" "$@" --test-timeout "$bisect_timeout"
            if [ "$watchdog_fired" = 1 ] && [ "$allow" -ge "$est" ]; then
                echo "== LOCALISED AND CONFIRMED: filter '$f.test.' alone did not finish at its full estimated allowance ($kill_phase at kill time)"
            elif [ "$watchdog_fired" = 1 ]; then
                echo "== LOCALISED (unconfirmed): filter '$f.test.' did not finish its solo run, but on a clipped allowance -- a clean solo run can be slower than that"
            else
                echo "== NARROWED BUT NOT CONFIRMED: '$f.test.' completed alone in ${ran_secs}s -- the wedge is order- or load-dependent; this is the last unexonerated filter"
            fi
        else
            echo "== LOCALISED: filter '$f.test.' is the only suspect left (budget pot too dry to confirm it alone)"
        fi
        if [ -n "$bisect_slow_notes" ]; then
            echo "== additionally, these tests exceeded the tight bound during the descent:$bisect_slow_notes"
        fi
        echo "== reproduce/narrow on any host with:"
        echo "==   zig build test -Dtest-filter=$f.test. --test-timeout $bisect_timeout $*"
    else
        echo "== bisect incomplete: $((hi - lo)) suspect filter(s) remain:"
        i=$lo
        while [ "$i" -lt "$hi" ]; do
            echo "==   $(fname "${filters[i]}")"
            i=$((i + 1))
        done
        echo "== re-run the step with a larger KAAPPI_BISECT_BUDGET to finish the descent"
    fi
}

budget_note="no wall budget (KAAPPI_CHUNK_BUDGET unset)"
[ "$budget" -gt 0 ] && budget_note="wall budget ${budget}s"
echo "== unit-test chunk '$chunk': ${#filters[@]} filter(s), per-test timeout $test_timeout, $budget_note, extra args: $*"
run_supervised "$budget" "unit-test chunk '$chunk'" "${filters[@]}" "$@" --test-timeout "$test_timeout"
status=$zig_status

if [ "$watchdog_fired" = 1 ]; then
    # The chunk did not finish inside its wall budget. zig's own summary --
    # and any per-test name it had already collected -- is lost with its
    # buffer, so localise with the script's own streamed lines instead.
    bisect_chunk "$@"
    exit 124
fi
[ "$status" = 0 ] || exit "$status"

# `--summary all` prints one line per test binary, e.g.
#   +- run test unit-tests 54 pass, 12 skip (66 total) 15s MaxRSS:1G
total="$(sed -n 's/.*run test unit-tests .*(\([0-9][0-9]*\) total).*/\1/p' "$log" | head -1)"
if [ -z "$total" ]; then
    echo "$0: could not find the unit-tests total in the build summary" >&2
    exit 2
fi
if [ "$total" -le "$floor" ]; then
    echo "$0: chunk '$chunk' ran only $total test(s), no more than the $floor unnamed reference block(s) -- its filters matched nothing" >&2
    exit 2
fi
echo "== unit-test chunk '$chunk': $total tests (floor $floor)"
