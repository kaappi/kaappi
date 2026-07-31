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

# Use pre-built binary if available, otherwise build once.
if [[ ! -x zig-out/bin/kaappi ]]; then
    zig build
fi
KAAPPI=zig-out/bin/kaappi

# Isolate ~/.kaappi so the suite is hermetic: plain `kaappi <file>` runs write a
# bytecode cache under $KAAPPI_HOME/cache (kaappi#1516), and we don't want the
# suite reading or polluting the developer's real cache (or history/config).
# Tests that need their own HOME (e.g. exe-relative-lib-1523) override this.
KAAPPI_HOME_TMP=$(mktemp -d /tmp/kaappi-test-home-XXXXXX)
export KAAPPI_HOME="$KAAPPI_HOME_TMP"

TMPOUT=$(mktemp /tmp/kaappi-test-XXXXXX)
TMPSTDOUT=$(mktemp /tmp/kaappi-r7rs-stdout-XXXXXX)
TMPSTDERR=$(mktemp /tmp/kaappi-r7rs-stderr-XXXXXX)
trap 'rm -f "$TMPOUT" "$TMPSTDOUT" "$TMPSTDERR"; rm -rf "$KAAPPI_HOME_TMP"' EXIT

TIMEOUT="${KAAPPI_TEST_TIMEOUT:-60}"
# Shell-suite tests do real work (native compiles, sometimes a `zig build`) so
# they legitimately run longer than a single .scm file — a few minutes, not
# seconds — but with no bound at all a genuine hang silently burns the whole
# job's timeout with no indication of which file was stuck (kaappi#1748: a
# 3M-iteration test took 7+ minutes under a Debug build and ate the rest of a
# 40-minute CI job before anyone could tell which file was responsible).
SHELL_TIMEOUT="${KAAPPI_SHELL_TEST_TIMEOUT:-300}"

# How many .scm files to run at once. Each file is a fresh interpreter with no
# shared state (see tests/scheme/CLAUDE.md), so they parallelise cleanly — the
# suite's own audit found no cross-file collisions on fixed paths or ports.
# Shell suites stay sequential: they do native compiles and `zig build` into a
# shared .zig-cache, which is a different (unaudited) contention story.
# KAAPPI_TEST_JOBS=1 restores the old strictly-sequential behaviour.
detect_jobs() {
    local n=""
    n=$(getconf _NPROCESSORS_ONLN 2>/dev/null) \
        || n=$(sysctl -n hw.ncpu 2>/dev/null) \
        || n=$(nproc 2>/dev/null) \
        || n=""
    case "$n" in
        ''|*[!0-9]*) echo 4 ;;
        *) echo "$n" ;;
    esac
}
JOBS="${KAAPPI_TEST_JOBS:-$(detect_jobs)}"

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
    local pid status
    "$KAAPPI" "$file" > "$slot.out" 2>&1 &
    pid=$!
    if wait_with_timeout "$pid" "$TIMEOUT"; then
        status=0
        wait "$pid" || status=$?
    else
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        echo "TIMEOUT" > "$slot.rec"
        return 0
    fi
    if [[ $status -eq 0 ]]; then
        # SRFI-64 files rely on their own exit-on-fail epilogue, and a file
        # that forgets it (or a stray chibi-test file — the shim exits 0
        # even when assertions fail) would otherwise slip through. Trust
        # the printed counts, not just the exit code.
        if grep -Eq '(^|[^0-9])[1-9][0-9]* fail|unexpected (failures|errors) +[1-9]' "$slot.out"; then
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
        TIMEOUT)
            echo "  TIMEOUT  $file  (killed after ${TIMEOUT}s)"
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

run_shell_suite() {
    local title="$1" dir="$2"
    local matched=0 pid status
    echo "=== $title ==="
    for test_script in "$dir"/*.sh; do
        [[ -e "$test_script" ]] || continue
        if [[ ! -x "$test_script" ]]; then
            echo "  FAIL  $test_script  (not executable)"
            FAIL=$((FAIL + 1))
            continue
        fi
        matched=1
        KAAPPI="$KAAPPI" bash "$test_script" "$KAAPPI" > "$TMPOUT" 2>&1 &
        pid=$!
        if wait_with_timeout "$pid" "$SHELL_TIMEOUT"; then
            status=0
            wait "$pid" || status=$?
        else
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            echo "  TIMEOUT  $test_script  (killed after ${SHELL_TIMEOUT}s)"
            cat "$TMPOUT"
            TIMEDOUT=$((TIMEDOUT + 1))
            continue
        fi
        if [[ $status -eq 0 ]]; then
            echo "  PASS  $test_script"
            PASS=$((PASS + 1))
        elif [[ $status -eq 77 ]]; then
            # Exit 77 = SKIP (shell-common.sh skip_on_windows/skip_without_zig/
            # skip_on_debug_build): the script's premise cannot hold here.
            echo "  SKIP  $test_script"
            SKIPPED=$((SKIPPED + 1))
        else
            echo "  FAIL  $test_script"
            cat "$TMPOUT"
            FAIL=$((FAIL + 1))
        fi
    done
    if [[ $matched -eq 0 ]]; then
        echo "  (no tests matched)"
    fi
    echo ""
}

echo "Running .scm suites with $JOBS parallel job(s) (override: KAAPPI_TEST_JOBS)."
echo ""

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

echo "=== R7RS test suite ==="
set +e
"$KAAPPI" tests/scheme/r7rs/r7rs-tests.scm > "$TMPSTDOUT" 2> "$TMPSTDERR"
R7RS_STATUS=$?
R7RS_OUTPUT="$(cat "$TMPSTDOUT" "$TMPSTDERR")"
set -e

R7RS_PASS=$(printf "%s\n" "$R7RS_OUTPUT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "pass") s += $i }} END {print s + 0}')
R7RS_FAIL=$(printf "%s\n" "$R7RS_OUTPUT" | awk '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == "fail") s += $i }} END {print s + 0}')
echo "  $R7RS_PASS pass, $R7RS_FAIL fail"
if [[ $R7RS_STATUS -ne 0 ]]; then
    echo "  FAIL  tests/scheme/r7rs/r7rs-tests.scm (exit $R7RS_STATUS)"
    echo "--- stderr output ---"
    cat "$TMPSTDERR" 2>/dev/null || true
    echo "--- last 20 lines stdout ---"
    tail -20 "$TMPSTDOUT" 2>/dev/null || true
    echo "--- end crash context ---"
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
