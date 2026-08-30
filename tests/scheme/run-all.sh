#!/bin/bash
# Run all Kaappi Scheme test suites.
# Usage: bash tests/scheme/run-all.sh
#
# This is the legacy runner: it spawns `kaappi <file>` per suite and scrapes the
# printed pass/fail counts. The first-class runner is `kaappi test` (kaappi#1509,
# see docs/dev/test-runner.md), which aggregates results from the SRFI-64 runner
# itself and offers `--json`/`--seed`. This script is kept for its broader reach
# — it also drives the chibi-test R7RS suite and the shell-based error/compile
# suites, which are outside `kaappi test`'s SRFI-64 scope.

set -euo pipefail

KAAPPI=zig-out/bin/kaappi

# This script used to run a bare `zig build` when the binary was missing. That
# convenience dates from when it was the only runner, and it silently
# substituted a DEFAULT build for whatever configuration the caller meant to
# measure (kaappi#2163). The natural two-command sequence for "run everything
# under gc-stress" is the worst case:
#
#     zig build test -Dgc-stress=true      # stresses the unit suite...
#     bash tests/scheme/run-all.sh         # ...and this built a PLAIN kaappi
#
# because `zig build test` installs no executable. The result was a full green
# Scheme suite that stressed nothing, with nothing in the output naming the
# configuration it actually ran. The same applies to -Doptimize=,
# -Dmax-registers= and -Dgc-threshold=. Every CI caller builds first, so
# refusing costs them nothing and costs a developer one command.
if [[ ! -x "$KAAPPI" ]]; then
    echo "run-all.sh: no executable at $KAAPPI." >&2
    echo "  Build it first, with the options you want the suite run under:" >&2
    echo "    zig build                        # default" >&2
    echo "    zig build -Dgc-stress=true       # collection on every allocation" >&2
    echo "    zig build -Doptimize=Debug       # ..." >&2
    echo "  (This script deliberately does not build for you: a bare 'zig build'" >&2
    echo "   here would silently run the corpus against a differently-configured" >&2
    echo "   binary than you asked for -- kaappi#2163.)" >&2
    exit 2
fi

# Isolate ~/.kaappi so the suite is hermetic: plain `kaappi <file>` runs write a
# bytecode cache under $KAAPPI_HOME/cache (kaappi#1516), and we don't want the
# suite reading or polluting the developer's real cache (or history/config).
#
# The fresh (empty) home is also what keeps the suite exercising THIS working
# tree's `.sld` libraries rather than a stale install: the library search order
# is (1) the script's own dir, (2) $KAAPPI_HOME/lib, (3) the exe-relative
# <exe>/../lib (= zig-out/lib, which `zig build` populates from the checkout).
# Step 2 is checked before step 3 by design, so a from-source binary never
# shadows a real install (kaappi#1523) — but that means a developer's own
# ~/.kaappi/lib would silently shadow their checkout edits (kaappi#2352). A
# throwaway home has no lib/, so step 3 wins and the corpus runs against the
# tree under test. Do NOT narrow this to a cache-only isolation.
#
# Tests that need their own HOME (e.g. exe-relative-lib-1523) override this.
KAAPPI_HOME_TMP=$(mktemp -d /tmp/kaappi-test-home-XXXXXX)
export KAAPPI_HOME="$KAAPPI_HOME_TMP"

R7RS_COUNTS=$(mktemp /tmp/kaappi-r7rs-counts-XXXXXX)
trap 'rm -f "$R7RS_COUNTS"; rm -rf "$KAAPPI_HOME_TMP"' EXIT

TIMEOUT="${KAAPPI_TEST_TIMEOUT:-60}"
# Shell-suite tests do real work (native compiles, sometimes a `zig build`) so
# they legitimately run longer than a single .scm file — a few minutes, not
# seconds — but with no bound at all a genuine hang silently burns the whole
# job's timeout with no indication of which file was stuck (kaappi#1748: a
# 3M-iteration test took 7+ minutes under a Debug build and ate the rest of a
# 40-minute CI job before anyone could tell which file was responsible).
SHELL_TIMEOUT="${KAAPPI_SHELL_TEST_TIMEOUT:-300}"

# Per-file timeout overrides for .scm files that legitimately outlive TIMEOUT.
# The official SRFI 231 conformance suite (srfi231-official.scm) runs ~150s
# cold — the isolated KAAPPI_HOME means its .sld libraries compile fresh every
# run, and the PGM convolution timing blocks dominate the rest — where the 60s
# default would kill an otherwise-green file (the same class of
# false-positive the SHELL_TIMEOUT comment above describes, at file scale).
PER_FILE_TIMEOUTS="srfi231-official.scm:${KAAPPI_SRFI231_OFFICIAL_TIMEOUT:-600}"

timeout_for() {
    local base entry
    base=$(basename "$1")
    for entry in $PER_FILE_TIMEOUTS; do
        if [[ "$base" == "${entry%%:*}" ]]; then
            echo "${entry##*:}"
            return
        fi
    done
    echo "$TIMEOUT"
}

# How many .scm files to run at once. Each file is a fresh interpreter with no
# shared state (see tests/scheme/CLAUDE.md), so they parallelise cleanly — the
# suite's own audit found no cross-file collisions on fixed paths or ports.
# The shell suites run concurrently too (kaappi#1926), at KAAPPI_SHELL_TEST_JOBS
# — their contention is over the one zig-out/ that `zig build` installs into,
# which tests/scheme/shell-common.sh now serialises with a lock. They get their
# own knob because each script can fork a whole compiler: a box that wants the
# .scm files N-wide does not necessarily want N concurrent `zig build`s.
# KAAPPI_TEST_JOBS=1 restores the old strictly-sequential behaviour for both.
detect_jobs() {
    local n=""
    n=$(getconf _NPROCESSORS_ONLN 2>/dev/null) \
        || n=$(sysctl -n hw.ncpu 2>/dev/null) \
        || n=$(nproc 2>/dev/null) \
        || n=""
    case "$n" in
        ''|*[!0-9]*|0) echo 4 ;;
        *) echo "$n" ;;
    esac
}
JOBS="${KAAPPI_TEST_JOBS:-$(detect_jobs)}"
SHELL_JOBS="${KAAPPI_SHELL_TEST_JOBS:-$JOBS}"

# Reject a bad job count loudly. `[[ $running -ge $JOBS ]]` evaluates its
# operands arithmetically, where a non-numeric value is silently 0 — so
# KAAPPI_TEST_JOBS=abc would not fail, it would just quietly serialise the run
# with a spurious `wait` per file. A typo in a CI env var should not cost a
# 4x-slower suite that still reports success.
case "$JOBS" in
    ''|*[!0-9]*|0)
        echo "run-all.sh: KAAPPI_TEST_JOBS must be a positive integer (got '${KAAPPI_TEST_JOBS:-}')" >&2
        exit 2
        ;;
esac
case "$SHELL_JOBS" in
    ''|*[!0-9]*|0)
        echo "run-all.sh: KAAPPI_SHELL_TEST_JOBS must be a positive integer (got '${KAAPPI_SHELL_TEST_JOBS:-}')" >&2
        exit 2
        ;;
esac

PASS=0
FAIL=0
TIMEDOUT=0
SKIPPED=0

# Space-separated basenames to skip (e.g. KAAPPI_TEST_SKIP="callcc-bench.scm foo.scm")
SKIP="${KAAPPI_TEST_SKIP:-}"

should_skip() {
    local base
    base=$(basename "$1")
    for s in $SKIP; do
        if [[ "$base" == "$s" ]]; then return 0; fi
    done
    return 1
}
R7RS_PASS=0
R7RS_FAIL=0
R7RS_STATUS_FAIL=0

# Run one .scm file to completion in the background, recording its verdict in
# "$slot.rec" and its combined output in "$slot.out". Runs in a subshell, so it
# cannot touch the PASS/FAIL counters — the parent tallies those later from the
# records, which is also what keeps the printed order deterministic regardless
# of the order files actually finish in.
run_file_worker() {
    local file="$1" slot="$2"
    local pid status tmo
    tmo=$(timeout_for "$file")
    "$KAAPPI" "$file" > "$slot.out" 2>&1 &
    pid=$!
    if wait_with_timeout "$pid" "$tmo"; then
        status=0
        wait "$pid" || status=$?
    else
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        echo "TIMEOUT ${tmo}s" > "$slot.rec"
        return 0
    fi
    if [[ $status -eq 0 ]]; then
        # SRFI-64 files rely on their own exit-on-fail epilogue, and a file
        # that forgets it (or a stray chibi-test file — the shim exits 0
        # even when assertions fail) would otherwise slip through. Trust
        # the printed counts, not just the exit code.
        #
        # The third alternative is a bare FAIL token, added by kaappi#2116:
        # the two count-shaped patterns before it require a failure COUNT,
        # which the hand-rolled `(display "FAIL: ...")` style has none of, so
        # 16 files printing exactly that were reported PASS. The token is
        # anchored on both sides against word characters so it cannot fire on
        # `FAILURES` or on a sentence mentioning failure in lower case, and
        # the corpus was swept for a file that prints it as expected output —
        # none does.
        if grep -Eq '(^|[^0-9])[1-9][0-9]* fail|unexpected (failures|errors) +[1-9]|(^|[^A-Za-z0-9_])FAIL([^A-Za-z0-9_]|$)' "$slot.out"; then
            echo "FAIL_ASSERT" > "$slot.rec"
        else
            echo "PASS" > "$slot.rec"
        fi
    else
        echo "FAIL" > "$slot.rec"
    fi
    return 0
}

# Print one worker's verdict and fold it into the counters. Parent shell only.
report_file_result() {
    local file="$1" slot="$2"
    local kind=""
    [[ -f "$slot.rec" ]] && kind=$(cat "$slot.rec")
    case "$kind" in
        PASS)
            echo "  PASS  $file"
            PASS=$((PASS + 1))
            ;;
        TIMEOUT*)
            echo "  TIMEOUT  $file  (killed after ${kind#TIMEOUT })"
            [[ -f "$slot.out" ]] && cat "$slot.out"
            TIMEDOUT=$((TIMEDOUT + 1))
            ;;
        FAIL_ASSERT)
            echo "  FAIL  $file  (failing assertions reported despite exit 0)"
            [[ -f "$slot.out" ]] && cat "$slot.out"
            FAIL=$((FAIL + 1))
            ;;
        *)
            # Empty record = the worker itself died before writing a verdict.
            echo "  FAIL  $file"
            [[ -f "$slot.out" ]] && cat "$slot.out"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

# `wait -n` (return as soon as the *next* job finishes) keeps the pool full with
# no polling at all, but it arrived in bash 4.3 and macOS still ships 3.2. There
# we fall back to draining the whole batch before starting the next one, which
# costs a little at each batch boundary but needs no polling either — polling
# here meant a `$(jobs -r | wc -l)` subshell every few milliseconds, which on a
# box already saturated by workers is pure overhead.
HAVE_WAIT_N=0
if (( ${BASH_VERSINFO[0]:-0} > 4 || (${BASH_VERSINFO[0]:-0} == 4 && ${BASH_VERSINFO[1]:-0} >= 3) )); then
    HAVE_WAIT_N=1
fi

# Poll a child to completion, giving up after $secs.
#
# The tick is 0.05s, not 1s: at one-second granularity every spawned unit cost a
# full second of wall clock no matter how fast it really was, and 381 of the 566
# .scm files finish in under 50ms. That single sleep accounted for ~93% of this
# script's runtime (668s total for ~53s of actual work). Ticks are counted in
# 20ths of a second so the $secs timeout keeps its exact meaning.
#
# Fractional sleep is not POSIX, but every platform this suite runs on (GNU
# coreutils, macOS/BSD, busybox) accepts it; the fallback keeps a stubborn
# `sleep` from spinning the CPU.
TICKS_PER_SEC=20
if ! sleep 0.05 2>/dev/null; then
    TICKS_PER_SEC=1
fi

wait_with_timeout() {
    local pid=$1 secs=$2 ticks=0
    local limit=$((secs * TICKS_PER_SEC))
    local interval=0.05
    if [[ $TICKS_PER_SEC -eq 1 ]]; then interval=1; fi
    while kill -0 "$pid" 2>/dev/null; do
        if [[ $ticks -ge $limit ]]; then return 1; fi
        sleep "$interval"
        ticks=$((ticks + 1))
    done
    return 0
}

run_suite() {
    local title="$1"
    shift
    local matched=0
    echo "=== $title ==="

    # Collect first, so the run can be dispatched $JOBS-at-a-time and still be
    # reported in a stable, glob-sorted order.
    local files=()
    local pattern file
    for pattern in "$@"; do
        for file in $pattern; do
            if [[ -e "$file" ]]; then
                matched=1
                if should_skip "$file"; then
                    echo "  SKIP  $file"
                    SKIPPED=$((SKIPPED + 1))
                    continue
                fi
                files[${#files[@]}]="$file"
            fi
        done
    done

    if [[ $matched -eq 0 ]]; then
        echo "  (no tests matched)"
        echo ""
        return
    fi
    if [[ ${#files[@]} -eq 0 ]]; then
        echo ""
        return
    fi

    local slotdir
    slotdir=$(mktemp -d "${TMPDIR:-/tmp}/kaappi-suite-XXXXXX")

    local i=0 running=0
    while [[ $i -lt ${#files[@]} ]]; do
        if [[ $running -ge $JOBS ]]; then
            if [[ $HAVE_WAIT_N -eq 1 ]]; then
                wait -n 2>/dev/null || true
                running=$((running - 1))
            else
                wait || true
                running=0
            fi
        fi
        run_file_worker "${files[$i]}" "$slotdir/$i" &
        running=$((running + 1))
        i=$((i + 1))
    done
    wait || true

    i=0
    while [[ $i -lt ${#files[@]} ]]; do
        report_file_result "${files[$i]}" "$slotdir/$i"
        i=$((i + 1))
    done

    rm -rf "$slotdir"
    echo ""
}

# Same shape as run_file_worker: record the verdict, never touch the counters.
run_shell_worker() {
    local script="$1" slot="$2"
    local pid status
    KAAPPI="$KAAPPI" bash "$script" "$KAAPPI" > "$slot.out" 2>&1 &
    pid=$!
    if wait_with_timeout "$pid" "$SHELL_TIMEOUT"; then
        status=0
        wait "$pid" || status=$?
    else
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        echo "TIMEOUT" > "$slot.rec"
        return 0
    fi
    case $status in
        0) echo "PASS" > "$slot.rec" ;;
        # Exit 77 = SKIP (shell-common.sh skip_on_windows/skip_without_zig/
        # skip_on_debug_build): the script's premise cannot hold here.
        77) echo "SKIP" > "$slot.rec" ;;
        *) echo "FAIL" > "$slot.rec" ;;
    esac
    return 0
}

report_shell_result() {
    local script="$1" slot="$2"
    local kind=""
    [[ -f "$slot.rec" ]] && kind=$(cat "$slot.rec")
    case "$kind" in
        PASS)
            echo "  PASS  $script"
            PASS=$((PASS + 1))
            ;;
        SKIP)
            echo "  SKIP  $script"
            SKIPPED=$((SKIPPED + 1))
            ;;
        TIMEOUT)
            echo "  TIMEOUT  $script  (killed after ${SHELL_TIMEOUT}s)"
            [[ -f "$slot.out" ]] && cat "$slot.out"
            TIMEDOUT=$((TIMEDOUT + 1))
            ;;
        NOTEXEC)
            echo "  FAIL  $script  (not executable)"
            FAIL=$((FAIL + 1))
            ;;
        *)
            echo "  FAIL  $script"
            [[ -f "$slot.out" ]] && cat "$slot.out"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

# A script that rebuilds the whole interpreter takes minutes, where every other
# script takes seconds. With a pool of N, when those start matters far more than
# N does, so they go first. Derived by grep rather than a hand-kept list of
# names, so a future rebuild-shaped script sorts itself; a wrong answer here
# costs makespan, never a verdict. All three spellings count: a script that
# runs the build itself, and one that goes through either of shell-common.sh's
# shared builders (where only the first caller pays, but which one that is
# isn't known here).
is_slow_shell_test() {
    # `^[^#]*`: skip comment lines, several of which mention the build they
    # deliberately do not run.
    grep -Eq '^[^#]*(zig build -D|bundle_fixture_binary|fixture_interpreter)' "$1" 2>/dev/null
}

run_shell_suite() {
    local title="$1" dir="$2"
    echo "=== $title ==="

    # Collect first, so the run can be dispatched $SHELL_JOBS-at-a-time and
    # still be reported in a stable, glob-sorted order.
    local scripts=()
    local test_script
    for test_script in "$dir"/*.sh; do
        [[ -e "$test_script" ]] || continue
        scripts[${#scripts[@]}]="$test_script"
    done

    if [[ ${#scripts[@]} -eq 0 ]]; then
        echo "  (no tests matched)"
        echo ""
        return
    fi

    local slotdir
    slotdir=$(mktemp -d "${TMPDIR:-/tmp}/kaappi-shell-XXXXXX")

    # Dispatch order is a list of indices into $scripts, slow ones first; the
    # report below still walks 0..n-1, so the printed order never moves.
    local order=() i=0
    while [[ $i -lt ${#scripts[@]} ]]; do
        if [[ ! -x "${scripts[$i]}" ]]; then
            echo "NOTEXEC" > "$slotdir/$i.rec"
        elif is_slow_shell_test "${scripts[$i]}"; then
            order[${#order[@]}]=$i
        fi
        i=$((i + 1))
    done
    i=0
    while [[ $i -lt ${#scripts[@]} ]]; do
        if [[ -x "${scripts[$i]}" ]] && ! is_slow_shell_test "${scripts[$i]}"; then
            order[${#order[@]}]=$i
        fi
        i=$((i + 1))
    done

    local running=0 idx
    i=0
    while [[ $i -lt ${#order[@]} ]]; do
        if [[ $running -ge $SHELL_JOBS ]]; then
            if [[ $HAVE_WAIT_N -eq 1 ]]; then
                wait -n 2>/dev/null || true
                running=$((running - 1))
            else
                wait || true
                running=0
            fi
        fi
        idx=${order[$i]}
        run_shell_worker "${scripts[$idx]}" "$slotdir/$idx" &
        running=$((running + 1))
        i=$((i + 1))
    done
    wait || true

    i=0
    while [[ $i -lt ${#scripts[@]} ]]; do
        report_shell_result "${scripts[$i]}" "$slotdir/$i"
        i=$((i + 1))
    done

    rm -rf "$slotdir"
    echo ""
}

# The .scm suite globs below are non-recursive (srfi/*.scm, not **), so a test
# file dropped into a subdirectory of a suite is silently never run by anything.
# tests/scheme/srfi/slow/ was exactly that for eleven days, holding the two full
# SRFI 257 reference suites (kaappi#1900) — the quarantine that put them there
# was obsoleted by #1804 a week later and nobody re-measured, because nothing
# ever reported them as missing.
#
# Fixtures legitimately live in subdirectories (tests/scheme/CLAUDE.md requires
# it), so the discriminator is `test-begin`: a fixture is a library or an
# included fragment and never opens a SRFI-64 suite, while every real suite
# file does. Verified against the whole tree — 11 fixture .scm files under
# suite subdirectories, none containing `test-begin`, and no false positives.
SCM_SUITE_DIRS="smoke compliance continuations hygiene srfi ffi audit"

check_unreachable_tests() {
    echo "=== Reachability check ==="
    local found=0 dir f listing
    listing=$(mktemp "${TMPDIR:-/tmp}/kaappi-reach-XXXXXX")
    for dir in $SCM_SUITE_DIRS; do
        [[ -d "tests/scheme/$dir" ]] || continue
        find "tests/scheme/$dir" -type f -name '*.scm' > "$listing" 2>/dev/null || true
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            # Top-level files are covered by the globs below; only look deeper.
            [[ "$(dirname "$f")" = "tests/scheme/$dir" ]] && continue
            if grep -Fq 'test-begin' "$f"; then
                echo "  UNREACHABLE  $f"
                found=$((found + 1))
            fi
        done < "$listing"
    done
    rm -f "$listing"
    if [[ $found -gt 0 ]]; then
        echo ""
        echo "  $found test file(s) sit in a suite subdirectory, where this script's"
        echo "  non-recursive globs cannot see them. Move each into its suite directory,"
        echo "  or wire the subdirectory into a run_suite glob below."
        echo "  See tests/scheme/CLAUDE.md (Directory layout)."
        FAIL=$((FAIL + found))
    else
        echo "  PASS  no test files hidden in suite subdirectories"
    fi
    echo ""
}

# The sibling of the check above, and the same class of bug one level down: a
# file the globs DO see, which has no way to report a failure (kaappi#2116).
# 56 files printed their answers and exited 0 whatever those answers were —
# `tests/scheme/smoke/thread-sleep-876.scm` was demonstrably green under the
# very regression it was written to catch, and the stdout net in
# run_file_worker cannot help, because a file that prints `#f` or a bare
# `FAIL:` line has no failure COUNT for it to match.
#
# A file must carry at least one of the four things that can turn a wrong
# answer into a nonzero exit: a SRFI-64 suite (`test-begin`, whose epilogue
# exits), an explicit `(exit`, an `(error`, or an `(assert`. This is a
# heuristic and knows it: `(error` inside a `guard` being TESTED is not a
# verdict channel, so a determined file can still slip through. What it does
# guarantee is that the count cannot grow back silently from zero, which is
# what let 55 accumulate.
#
# `test-begin` is deliberately not made mandatory: four files carry a bare
# `(exit 1)` instead and say so in their own headers — three are cross-tier
# probes that must keep their top-level forms bare to run identically on every
# tier, and coroutine-repl-echo.scm must leave its top-level forms bare. See
# the inventory table in tests/scheme/CLAUDE.md.
check_verdictless_tests() {
    echo "=== Verdict-channel check ==="
    local found=0 dir f
    for dir in $SCM_SUITE_DIRS; do
        for f in tests/scheme/"$dir"/*.scm; do
            [[ -e "$f" ]] || continue
            if ! grep -Eq 'test-begin|\(exit|\(error|\(assert' "$f"; then
                echo "  NO-VERDICT  $f"
                found=$((found + 1))
            fi
        done
    done
    if [[ $found -gt 0 ]]; then
        echo ""
        echo "  $found test file(s) have no way to signal failure: whatever they compute,"
        echo "  they exit 0 and both runners report them as passing. Give each one the"
        echo "  SRFI-64 shape (test-begin ... test-end + the exit-on-fail epilogue)."
        echo "  See tests/scheme/CLAUDE.md (Adding a test)."
        FAIL=$((FAIL + found))
    else
        echo "  PASS  every globbed test file can report a failure"
    fi
    echo ""
}

# Name the binary that produced the counts below. Nothing about running a .scm
# file reveals which build options compiled the interpreter, so a log without
# this cannot distinguish a gc-stress run from a plain one, or a Debug leg from
# a ReleaseFast one (kaappi#2163). `kaappi features --json` reports the
# comptime options directly (src/features.zig); the sed is deliberately dumb so
# a missing field degrades to a blank rather than failing the run.
describe_binary() {
    local json field
    json=$("$KAAPPI" features --json 2>/dev/null) || return 0
    for field in version build_id target build_mode gc_stress; do
        printf '  %-11s %s\n' "$field" \
            "$(printf '%s' "$json" | tr ',' '\n' | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\"}]*\)\"\{0,1\}.*/\1/p" | head -1)"
    done
}
echo "Binary under test: $KAAPPI"
describe_binary
echo ""
echo "Running .scm suites with $JOBS parallel job(s) (override: KAAPPI_TEST_JOBS)."
echo "Running shell suites with $SHELL_JOBS parallel job(s) (override: KAAPPI_SHELL_TEST_JOBS)."

# Build the native runtime archive once, up front. 18 scripts in the compile
# suite need it and each used to run `zig build lib` itself — 18 redundant
# builds installing into one zig-out/lib, which is exactly the race that kept
# the shell suites sequential (kaappi#1926). Doing it here and exporting the
# marker turns every one of those into a no-op. The marker is advisory: a
# script that does not see it builds its own archive as before, which is what
# the Windows CI legs (they invoke each script directly) rely on.
if command -v zig > /dev/null 2>&1; then
    # Says so out loud: cold, this is a minute of silence before the first
    # suite prints anything.
    echo "Building the native runtime archive (zig build lib) once, up front."
    if zig build lib > /dev/null 2>&1; then
        export KAAPPI_RT_LIB_READY=1
    else
        echo "  WARN  zig build lib failed; compile scripts will each retry it"
    fi
fi

# The WASM differential compares this tree's interpreter against
# zig-out/bin/kaappi.wasm, but nothing else on this path rebuilds that module —
# so without this step a local run-all.sh would measure today's interpreter
# against whatever stale .wasm happens to be in zig-out/, producing confident
# FALSE divergences (or, worse, a clean PASS that tested nothing) against a
# module from another commit (kaappi#2197). CI's `wasm` job builds it first; do
# the same here. Gated on wasmtime too, since without it the differential SKIPs
# regardless and the build would be wasted. Best-effort: run-wasm-differential.sh
# has its own freshness guard, so if this is skipped or fails the leg degrades to
# a clear SKIP rather than a false FAIL.
if command -v zig > /dev/null 2>&1 && command -v wasmtime > /dev/null 2>&1; then
    echo "Building the WebAssembly module (zig build wasm) for the WASM differential."
    if ! zig build wasm > /dev/null 2>&1; then
        echo "  WARN  zig build wasm failed; the WASM differential will SKIP (stale/missing module)"
    fi
fi
echo ""

check_unreachable_tests
check_verdictless_tests

run_suite "Smoke tests" tests/scheme/smoke/*.scm
run_shell_suite "Smoke shell tests" tests/scheme/smoke
run_suite "Compliance tests" tests/scheme/compliance/*.scm
run_suite "Continuation tests" tests/scheme/continuations/*.scm
run_suite "Hygiene tests" tests/scheme/hygiene/*.scm
run_suite "SRFI tests" tests/scheme/srfi/*.scm

# Build the FFI fixture library when a compiler is around so uint64-range.scm
# exercises real code instead of skipping. Non-fatal: without a fixture the
# test degrades to its documented SKIP.
FIXTURE_SRC=tests/scheme/ffi/fixtures/u64test.c
if command -v zig >/dev/null 2>&1; then
    case "$(uname)" in
        Darwin) FIXTURE_LIB=tests/scheme/ffi/fixtures/libu64test.dylib
                FIXTURE_FLAGS="-dynamiclib" ;;
        *)      FIXTURE_LIB=tests/scheme/ffi/fixtures/libu64test.so
                FIXTURE_FLAGS="-shared -fPIC" ;;
    esac
    if [[ ! -e "$FIXTURE_LIB" || "$FIXTURE_SRC" -nt "$FIXTURE_LIB" ]]; then
        # shellcheck disable=SC2086  # FIXTURE_FLAGS is a flag list
        zig cc $FIXTURE_FLAGS "$FIXTURE_SRC" -o "$FIXTURE_LIB" \
            || echo "  WARN  could not build $FIXTURE_LIB (uint64-range.scm will skip)"
    fi
fi
run_suite "FFI tests" tests/scheme/ffi/*.scm
run_suite "Audit tests" tests/scheme/audit/*.scm
run_shell_suite "Error tests" tests/scheme/errors
run_shell_suite "Compile tests" tests/scheme/compile
run_shell_suite "Test runner" tests/scheme/test-runner
run_shell_suite "Pipeline dumps" tests/scheme/pipeline
run_shell_suite "Doctor" tests/scheme/doctor
run_shell_suite "Formatter" tests/scheme/fmt
run_shell_suite "Cache" tests/scheme/cache
run_shell_suite "Timings" tests/scheme/timings
run_shell_suite "Shell completions" tests/scheme/completions
run_shell_suite "Language server" tests/scheme/lsp
run_shell_suite "Package manager" tests/scheme/thottam
# Execution-tier differential: every corpus file must give the same answer with
# the IR optimiser off and from a warm bytecode cache as it does from a cold
# one. Defaults to the smoke+compliance+audit corpus plus its own probes
# (330 files, ~115s, inside SHELL_TIMEOUT); KAAPPI_DIFF_FULL=1 adds
# continuations/, hygiene/ and srfi/ (557 files, ~210s) — opt-in because those
# 227 extra files add no tier coverage, only runtime.
run_shell_suite "Differential tiers" tests/scheme/differential

# The R7RS suite is the one corpus file that reports failures without exiting
# nonzero — the `(chibi test)` shim has no exit-on-fail epilogue — so its
# verdict comes from its printed counts. That parsing used to live here; it now
# lives in tools/run-r7rs-suite.sh, shared with the five ci.yml steps that used
# to invoke the suite bare and therefore could not fail on a wrong answer
# (kaappi#2157). The counts come back through a file rather than by re-parsing
# the runner's own output, so there is still exactly one parser.
echo "=== R7RS test suite ==="
set +e
KAAPPI_R7RS_COUNTS_OUT="$R7RS_COUNTS" bash tools/run-r7rs-suite.sh "$KAAPPI"
R7RS_RUNNER_STATUS=$?
set -e

if [[ -s "$R7RS_COUNTS" ]]; then
    # shellcheck disable=SC1090  # generated by tools/run-r7rs-suite.sh
    . "$R7RS_COUNTS"
elif [[ $R7RS_RUNNER_STATUS -ne 0 ]]; then
    # The runner bailed before it had counts to report (no binary, missing
    # suite file). Nothing to fold into the summary but the failure itself.
    R7RS_STATUS_FAIL=1
fi
# Any nonzero status from the runner fails the run. `-ne 0` rather than the
# three separate conditions it replaces (`-eq 2`, a nonzero sourced
# `R7RS_STATUS`, and `R7RS_FAIL -gt 0` in the summary below): each of those is
# individually correct, but relying on three of them to cover the runner's two
# failure exits means a fourth exit code added later is covered by none.
# tools/run-gc-stress-suite.sh already gates on the status alone.
#
# `R7RS_FAIL -gt 0` stays in the summary condition as an independent second
# signal — it is what makes the *counts* load-bearing rather than decorative.
if [[ $R7RS_RUNNER_STATUS -ne 0 ]]; then
    R7RS_STATUS_FAIL=1
fi

echo ""
echo "=== Summary ==="
echo "  Scheme files: $PASS pass, $FAIL fail, $TIMEDOUT timeout, $SKIPPED skipped"
echo "  R7RS suite:   $R7RS_PASS pass, $R7RS_FAIL fail"
echo "  Total:        $((PASS + R7RS_PASS)) pass, $((FAIL + R7RS_FAIL + R7RS_STATUS_FAIL + TIMEDOUT)) fail ($TIMEDOUT from timeouts, $SKIPPED skipped)"

if [[ $FAIL -gt 0 || $TIMEDOUT -gt 0 || $R7RS_FAIL -gt 0 || $R7RS_STATUS_FAIL -gt 0 ]]; then
    exit 1
fi
