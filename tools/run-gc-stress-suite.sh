#!/usr/bin/env bash
# Run the Scheme corpus against a `-Dgc-stress=true` build, in one command.
#
#     bash tools/run-gc-stress-suite.sh [path/to/kaappi]
#
# WHY THIS EXISTS. `-Dgc-stress=true` attempts a collection at every
# allocation. It is the only configuration that turns a GC rooting bug -- a
# heap value held in a Zig local across an allocation without `gc.pushRoot`
# -- from rare, unattributable corruption into a deterministic failure at the
# site that caused it (`.claude/rules/gc-safety.md`, kaappi#1401, #1687).
#
# Until audit v2 Phase 7E it gated nothing on a pull request (kaappi#1898),
# and the *Scheme* corpus had run against a stress build exactly once ever --
# by hand, on a droplet, in Phase 5F. The unit suite is the other half and is
# run directly by `ci.yml`'s `gc-stress` job (`zig build test
# -Dgc-stress=true`); this script is the Scheme half, and it is not
# redundant with it: these files drive the library loader, the expander and
# all 178 SRFIs at a scale no Zig unit test reaches, and
# `src/tests_gc_root_boundary.zig`'s own OOM sweeps find leaks only in the
# expander.
#
# Deliberately NOT wired into run-all.sh: run-all.sh already runs every file
# below against whatever `zig-out/bin/kaappi` happens to be, and several of
# its shell suites fork `zig build` *without* the flag. This is the entry
# point for a run whose entire point is the binary's build configuration --
# which is why the first thing it does is make the binary prove it.
#
# Exit status is 0 only if every file exits 0 and the R7RS suite reports no
# failed assertions. Each corpus file is an `(srfi 64)` suite with the
# exit-on-fail epilogue, so a failed assertion is a nonzero exit; the R7RS
# suite is the documented exception and is handled separately below.

set -u

# Resolve the binary against the CALLER's cwd first -- a relative argument
# means what the caller meant, not what it happens to mean after the cd below.
KAAPPI="${1:-zig-out/bin/kaappi}"
case "$KAAPPI" in
    /*) ;;
    *) KAAPPI="$PWD/$KAAPPI" ;;
esac

# Then run from the repo root regardless of where we were invoked: every path
# below is repo-relative, and so is the --lib-path passed to each run.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

if [[ ! -x "$KAAPPI" ]]; then
    echo "run-gc-stress-suite: no executable kaappi at '$KAAPPI'" >&2
    echo "Usage: bash tools/run-gc-stress-suite.sh [path/to/kaappi]" >&2
    exit 2
fi

# THE POINT OF THIS CHECK. Nothing about running a .scm file reveals which
# build options produced the binary, so a plain build would sail through
# every assertion below and the run would report success -- a green log for a
# stress suite that was never stressed. `kaappi features --json` reports the
# comptime `build_options.gc_stress` directly (src/features.zig), so refusing
# here is the difference between a gate and a decoration.
if ! "$KAAPPI" features --json 2>/dev/null | grep -q '"gc_stress":true'; then
    echo "run-gc-stress-suite: '$KAAPPI' is NOT a -Dgc-stress=true build." >&2
    echo "  kaappi features --json reports:" >&2
    "$KAAPPI" features --json 2>/dev/null \
        | tr ',' '\n' | grep -i 'gc_stress\|version' >&2 || true
    echo "  Rebuild with: zig build -Dgc-stress=true" >&2
    exit 2
fi

# One EXIT trap, set once. bash replaces a trap rather than adding to it, so
# a second `trap ... EXIT` later in the file would silently drop this one and
# leak the temp home on every run.
SCRATCH_DIRS=()
# shellcheck disable=SC2329  # invoked indirectly, by the EXIT trap below
cleanup() {
    # The length guard is not cosmetic: `"${arr[@]}"` on an empty array is an
    # unbound-variable error under `set -u` in bash 3.2, which is what macOS
    # ships and what a developer running this by hand will use.
    if [[ ${#SCRATCH_DIRS[@]} -gt 0 ]]; then
        rm -rf "${SCRATCH_DIRS[@]}"
    fi
}
trap cleanup EXIT

# Keep the cache out of the invoking user's real KAAPPI_HOME: plain
# `kaappi <file>` runs write a bytecode cache under $KAAPPI_HOME/cache
# (kaappi#1516), and run-all.sh isolates for the same reason.
if [[ -z "${KAAPPI_HOME:-}" ]]; then
    KAAPPI_HOME="$(mktemp -d)"
    export KAAPPI_HOME
    SCRATCH_DIRS+=("$KAAPPI_HOME")
fi

# The same list run-all.sh globs (its SCM_SUITE_DIRS). Kept as directories
# rather than a curated file list so a new test file joins this run by
# existing, with no second place to update -- but see the floor check below,
# because a glob that silently matches nothing is the failure mode a curated
# list does not have.
SCM_SUITE_DIRS="smoke compliance continuations hygiene srfi ffi audit"

# A file that legitimately takes minutes under stress collection is fine; a
# file that HANGS must not silently consume the whole CI job's budget with no
# indication of which one it was (the kaappi#1748 shape). macOS ships no
# `timeout`, so fall back to running unbounded there rather than failing.
#
# 900 s is set from measurement, not taste. Stress collection costs roughly
# O(live heap) per allocation, so a file that builds a large heap is
# superlinear, and the corpus has a long tail of exactly those. Measured on
# macOS aarch64 (12 cores, 12-way, load average 8-13 from concurrent work):
#
#   tests/scheme/smoke/trampoline-polish-1375.scm   ~13 min
#   tests/scheme/srfi/srfi14.scm                    ~10 min
#   tests/scheme/srfi/srfi264.scm                   ~9 min
#
# while the other 602 files finished inside 11 min *in aggregate*. A tighter
# bound would not catch a hang any sooner -- it would just turn the three
# slowest legitimate files red, which is the worse failure by far: a red gate
# that is right about nothing trains people to ignore it.
TIMEOUT_SECS="${KAAPPI_GC_STRESS_TIMEOUT:-900}"
if command -v timeout > /dev/null 2>&1; then
    RUN_TIMEOUT=(timeout "$TIMEOUT_SECS")
elif command -v gtimeout > /dev/null 2>&1; then
    RUN_TIMEOUT=(gtimeout "$TIMEOUT_SECS")
else
    RUN_TIMEOUT=()
fi

# Build the FFI fixture when a compiler is around so uint64-range.scm
# exercises real code instead of skipping -- the same non-fatal step, and the
# same reason, as run-all.sh's.
FIXTURE_SRC=tests/scheme/ffi/fixtures/u64test.c
if command -v zig > /dev/null 2>&1; then
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

# Stress collection makes each file 10-20x slower, which is what makes the
# parallelism load-bearing here rather than a nicety: sequentially this run
# is ~19 min where run-all.sh's own .scm half is ~1. Each file is a fresh
# interpreter with no shared state (tests/scheme/CLAUDE.md), which is the
# same property run-all.sh relies on for its own JOBS knob.
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
JOBS="${KAAPPI_GC_STRESS_JOBS:-$(detect_jobs)}"
case "$JOBS" in
    ''|*[!0-9]*|0)
        echo "run-gc-stress-suite: KAAPPI_GC_STRESS_JOBS must be a positive integer (got '${KAAPPI_GC_STRESS_JOBS:-}')" >&2
        exit 2
        ;;
esac

echo "=== Scheme corpus under -Dgc-stress=true ==="
echo "kaappi: $KAAPPI"
"$KAAPPI" --version
echo "jobs:   $JOBS (override: KAAPPI_GC_STRESS_JOBS)"
echo ""

# Space-separated BASENAMES to skip, same spelling and semantics as
# run-all.sh's KAAPPI_TEST_SKIP -- and set for the same kind of reason
# ci.yml already sets that one on the Debug leg: a build configuration
# 10-20x slower than the default makes a handful of files pathological
# without making them interesting. Deliberately empty by default, so the
# exclusion lives next to the job that needs it and is visible in the diff
# that adds it rather than buried here.
SKIP="${KAAPPI_GC_STRESS_SKIP:-}"
skipped_file() {
    local base
    base="$(basename "$1")"
    for s in $SKIP; do
        [[ "$base" == "$s" ]] && return 0
    done
    return 1
}

FILES=()
SKIPPED=0
SKIPPED_NAMES=()
for dir in $SCM_SUITE_DIRS; do
    for f in tests/scheme/"$dir"/*.scm; do
        [[ -e "$f" ]] || continue
        if skipped_file "$f"; then
            SKIPPED=$((SKIPPED + 1))
            SKIPPED_NAMES+=("$f")
            continue
        fi
        FILES+=("$f")
    done
done

# A skip that is not printed is coverage silently lost. Name them.
if [[ $SKIPPED -gt 0 ]]; then
    echo "  Skipping $SKIPPED file(s) via KAAPPI_GC_STRESS_SKIP:"
    printf '    %s\n' "${SKIPPED_NAMES[@]}"
    echo ""
fi

# A name in SKIP that matches nothing is a typo or a renamed file, and it
# would silently mean "no exclusion" -- the same shape as a glob matching
# nothing. Fail rather than run a differently-scoped suite than was asked for.
SKIP_COUNT=0
for s in $SKIP; do SKIP_COUNT=$((SKIP_COUNT + 1)); done
if [[ $SKIP_COUNT -ne $SKIPPED ]]; then
    echo "run-gc-stress-suite: KAAPPI_GC_STRESS_SKIP names $SKIP_COUNT file(s) but $SKIPPED matched." >&2
    echo "  A skip entry that matches nothing has silently stopped excluding anything." >&2
    exit 2
fi

# One marker file per failure, written by the worker, counted after the pool
# drains: a subshell in a pipeline cannot increment the parent's counter, and
# a failure that only ever incremented a lost variable is the same
# cannot-fail shape the checks above exist to avoid.
FAILDIR="$(mktemp -d)"
SCRATCH_DIRS+=("$FAILDIR")
# NOT `export KAAPPI`, however natural that name looks for the binary under
# test: tests/scheme/audit/primitives_filesystem-audit.scm asserts that an
# environment variable literally named KAAPPI is *unset*, so exporting it
# turns three of its assertions red for reasons that have nothing to do with
# the GC. Found the hard way -- the first run of this script reported those
# three as gc-stress failures (kaappi#2162).
export GC_STRESS_KAAPPI_BIN="$KAAPPI"
export FAILDIR
export RUN_TIMEOUT_CMD="${RUN_TIMEOUT[*]:-}"

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "run-gc-stress-suite: no .scm files matched under tests/scheme/{$SCM_SUITE_DIRS}." >&2
    exit 2
fi

# shellcheck disable=SC2016  # the worker body must expand in the CHILD, not here
printf '%s\0' "${FILES[@]}" | xargs -0 -P "$JOBS" -I{} bash -c '
    f="$1"
    # shellcheck disable=SC2086  # RUN_TIMEOUT_CMD is a command prefix or empty
    out="$($RUN_TIMEOUT_CMD "$GC_STRESS_KAAPPI_BIN" --lib-path lib "$f" 2>&1)"
    status=$?
    if [[ $status -ne 0 ]]; then
        { echo "  FAIL  $f (exit $status)"
          printf "%s\n" "$out" | tail -30 | sed "s/^/        /"
        } > "$FAILDIR/$(echo "$f" | tr / _)"
    fi
' _ {}

FAIL=$(find "$FAILDIR" -type f | wc -l | tr -d ' ')
PASS=$(( ${#FILES[@]} - FAIL ))
if [[ $FAIL -gt 0 ]]; then
    cat "$FAILDIR"/*
fi

# A glob that matches nothing exits 0 for every file it did not run. Eleven
# days of tests/scheme/srfi/slow/ going unnoticed (kaappi#1900) is what that
# costs, and here it would additionally read as "gc-stress found nothing".
# The floor is deliberately well below the current count (605 as of writing)
# so it needs no maintenance as files are added, but well above zero.
FLOOR="${KAAPPI_GC_STRESS_FLOOR:-500}"
if [[ $((PASS + FAIL)) -lt $FLOOR ]]; then
    echo ""
    echo "run-gc-stress-suite: only $((PASS + FAIL)) files ran, expected at least $FLOOR." >&2
    echo "  A suite directory was renamed or the globs stopped matching." >&2
    exit 2
fi

# The R7RS suite is the one file that reports failures WITHOUT exiting
# nonzero: it uses the (chibi test) shim, which has no exit-on-fail epilogue,
# so `kaappi tests/scheme/r7rs/r7rs-tests.scm; echo $?` prints 0 with a failed
# assertion in the log. This block used to carry its own copy of run-all.sh's
# count-parsing awk; both now call tools/run-r7rs-suite.sh, which is also what
# the five ci.yml steps that used to invoke the suite bare now use
# (kaappi#2157). One implementation, so the callers agree by construction.
echo ""
echo "=== R7RS suite under -Dgc-stress=true ==="
R7RS_COUNTS="$(mktemp)"
SCRATCH_DIRS+=("$R7RS_COUNTS")
# `${arr[@]+"${arr[@]}"}`, not `"${arr[@]}"`: RUN_TIMEOUT is empty whenever
# neither `timeout` nor `gtimeout` is on PATH (the macOS default), and an empty
# array under `set -u` is an unbound-variable error in bash 3.2 — which is what
# macOS ships and what a developer running this by hand will use.
KAAPPI_R7RS_COUNTS_OUT="$R7RS_COUNTS" \
    ${RUN_TIMEOUT[@]+"${RUN_TIMEOUT[@]}"} bash tools/run-r7rs-suite.sh "$KAAPPI" --lib-path lib
R7RS_RUNNER_STATUS=$?
R7RS_PASS=0
R7RS_FAIL=0
if [[ -s "$R7RS_COUNTS" ]]; then
    # shellcheck disable=SC1090  # generated by tools/run-r7rs-suite.sh
    . "$R7RS_COUNTS"
fi

echo ""
echo "=== Summary: $PASS files passed, $FAIL failed, $SKIPPED skipped; R7RS $R7RS_PASS pass, $R7RS_FAIL fail ==="

if [[ $FAIL -gt 0 || $R7RS_RUNNER_STATUS -ne 0 ]]; then
    exit 1
fi
exit 0
