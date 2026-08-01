#!/bin/bash
# run-differential.sh — execution-tier differential harness (audit v2, Phase 4B)
#
# The interpreter is the oracle.  For every corpus file this runs the program
# three ways and requires them to agree:
#
#   base   kaappi F                  cold cache      <- the oracle
#   warm   kaappi F                  warm cache      <- tier (d)
#   nopt   kaappi --no-ir-opt F      cache bypassed  <- tier (b)
#
# Pass criterion, per tier: byte-identical stdout, identical exit code, and
# identical stderr after normalisation.  Any mismatch names the tier and the
# file.  Tier (c), the LLVM native backend, is deliberately NOT here — it needs
# `zig build lib` and a C compiler, and lives in its own unit.
#
#   Usage:  bash tests/scheme/differential/run-differential.sh [path-to-kaappi]
#
#   KAAPPI_DIFF_FULL=1      sweep continuations/, hygiene/ and srfi/ as well
#                           (default corpus is probes + smoke + compliance +
#                           audit; see "Corpus" below for the runtime numbers
#                           behind that split)
#   KAAPPI_DIFF_TIMEOUT=N   per-run timeout in seconds (default 60)
#   KAAPPI_DIFF_VERBOSE=1   print a line per file instead of only diffs
#   KAAPPI_DIFF_KEEP=1      keep the temp tree of captured outputs on exit
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE TRUSTING A GREEN RUN
# ---------------------------------------------------------------------------
# A green tier-(b) sweep over the *existing* corpora is a WEAK negative, not
# evidence that the IR optimiser is correct.
#
# MEASURED 2026-07-31, over all 550 pre-existing corpus files (smoke,
# compliance, audit, continuations, hygiene, srfi): `kaappi ir F` and
# `kaappi ir --no-opt F` produce BYTE-IDENTICAL output on 547 of them.  Only
# THREE files in the whole tree make the optimiser do anything —
#   tests/scheme/smoke/global-redefine-fold.scm
#   tests/scheme/smoke/identity-elim-typecheck.scm
#   tests/scheme/smoke/zero-pred-type-error.scm
# — and all three are purpose-built optimiser regression tests.  Across
# compliance/, audit/, continuations/, hygiene/ and srfi/ — 288 files — the
# count is ZERO.
#
# The reason is structural: every `define`/`lambda` body lowers to an opaque
# `passthrough` IR node, so the five optimisation passes (constant folding,
# dead branch elimination, boolean simplification, identity elimination, begin
# simplification) only ever reach TOP-LEVEL EXPRESSION position.  Practically
# every test in the tree wraps its work in procedures, so for 99.5% of the
# corpus `--no-ir-opt` compiles exactly the same bytecode as the default
# pipeline and the comparison is vacuous.
#
# Two things follow:
#
#   1. `probes/` exists for this reason.  Those files put the optimisable
#      shapes at top level on purpose, and 6 of the 7 are verified non-vacuous
#      (`kaappi ir` differs from `kaappi ir --no-opt`); the seventh,
#      cache-error-location.scm, is a tier-(d) probe.  They roughly TRIPLE the
#      number of files in the corpus that exercise the optimiser at all.
#   2. This script MEASURES the vacuity rather than leaving it to be assumed.
#      The summary reports "IR differs under --no-opt: N / M files".  If that
#      number is small, the tier-(b) result is correspondingly weak, and it
#      says so.  If a future change makes it drop to zero, that is visible
#      instead of silent.
#
# The honest reading of a green tier (b), then: it shows the optimiser does not
# break the handful of shapes it can reach, and says nothing whatever about the
# ~99% of the corpus it never sees.  Widening it means writing more probes, not
# adding more corpus directories — KAAPPI_DIFF_FULL=1 adds 227 files and
# exactly zero additional optimiser coverage.
#
# The same discipline applies to tier (d): only a program that does NOT
# `import` populates the bytecode cache at all (docs/dev/cache.md) — measured
# 40 of 330 files on the default corpus, 47 of 557 on the full one.  The
# summary reports how many files actually created an `.sbc` entry, so a
# regression that silently disables caching shows up as that count collapsing
# rather than as a vacuously green run.
#
# ---------------------------------------------------------------------------
# Exclusions
# ---------------------------------------------------------------------------
# Two mechanisms, deliberately:
#
# (a) A static SKIP list (see SKIP_PATTERNS below) for whole directories and
#     for named files whose output is nondeterministic BY CONSTRUCTION:
#       - `bench/` and `coverage/` — not part of any correctness corpus; the
#         first prints timings, the second exists for `zig build
#         coverage-scheme`.  They are excluded by never being in CORPUS_DIRS.
#       - gensym / `generate-symbol` / `generate-uninterned-symbol` counters —
#         the name embeds a process-global counter and 128 bits of OS entropy,
#         so no two runs agree.
#       - `current-time`, `current-second`, `current-jiffy`, and anything that
#         prints elapsed wall time.
#       - hash-table iteration order — `hash-table-keys`/`-values`/`-walk`
#         have no specified order.
#       - thread and fiber scheduling — interleaved output from SRFI 18
#         threads or `(kaappi fibers)` is not reproducible.
#       - `--timings` output (never passed here, but named for completeness).
#       - absolute paths in output (handled by normalisation, below).
#
# (b) Dynamic nondeterminism controls.  A static list guesses; these measure,
#     which is what keeps the list from having to be exhaustive.  All three
#     are paid only once something already looks wrong, so a green run costs
#     nothing extra.  In order of how conclusive they are:
#
#       1. STRUCTURAL.  If the file wrote no `.sbc` entry it is never cached,
#          so the "warm" run is the same configuration as the cold one and a
#          tier-(d) mismatch CANNOT be a cache effect.  Reported as NONDET.
#          This one is not a heuristic — it is a fact about the file.
#       2. SELF-AGREEMENT.  Re-run the baseline in a second fresh cold home.
#          If the two baselines already disagree, no tier is implicated.
#       3. REPRODUCIBILITY.  Replay the offending tier against a fresh
#          baseline and drop the finding unless it disagrees a second time.
#
#     Controls 2 and 3 exist because control 2 alone can pass by luck: a
#     fiber/timing test that hangs once under load
#     (smoke/nested-wait-under-sleep-dirty-snapshot-1490.scm) got through it
#     and was reported as a cache divergence until control 1 was added.
#
# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------
# stdout and the exit code are compared BYTE-EXACTLY — no normalisation, ever.
# Only stderr is normalised, and only for absolute paths and line/column
# numbers, because a naive diff surfaces pure harness noise (`(eval):7` vs
# `(eval):8`) on files that would otherwise agree.
#
# Normalisation can only HIDE a difference, never manufacture one, so the
# harness reports the raw-stderr comparison too: a file whose stderr matches
# normalised but differs raw is reported as a "cosmetic" note (e.g. the
# optimiser losing a source location) instead of being silently swallowed.
#
# Regex portability: `sed -E` / `grep -E` only, plain POSIX ERE.  GNU BRE
# extensions (`\?`, `\|`, `\+`) pass on macOS/Linux/FreeBSD/NetBSD and match
# NOTHING on OpenBSD (kaappi#1862).
#
# ---------------------------------------------------------------------------
# Corpus and runtime (measured on macOS aarch64, ReleaseSafe, 2026-07-31)
# ---------------------------------------------------------------------------
# Default (probes + smoke + compliance + audit):  330 files, 113s
# KAAPPI_DIFF_FULL=1 (adds continuations + hygiene + srfi):  557 files, 210s
#
# Both fit inside run-all.sh's 300s shell-suite budget
# (KAAPPI_SHELL_TEST_TIMEOUT) on an idle machine, but the default is the
# smaller set, for two measured reasons rather than one:
#
#   - 210s against a 300s budget is only a 1.4x margin, and these numbers come
#     from a laptop, not from CI.  A Debug build alone is 10-20x slower
#     (kaappi#1748), which blows the budget either way, but the 1.4x margin
#     leaves nothing for ordinary load.
#   - the extra 227 files buy NO additional tier coverage: 0 of them change the
#     IR under --no-ir-opt, and they add 7 cached files (40 -> 47).  Paying
#     +97s for zero signal is the wrong default.
#
# So: gate on the default set, sweep the full one on demand.
#
# `tests/scheme/srfi/slow/` no longer exists: audit v2 Phase 3.10 found its
# quarantine obsolete (the two full SRFI 257 reference suites now run in ~0.4s
# each, not the minutes that put them there) and moved both files up into
# `tests/scheme/srfi/`, so they are now in the opt-in KAAPPI_DIFF_FULL corpus
# along with the rest of srfi/.

set -uo pipefail

# shellcheck source=tests/scheme/shell-common.sh
. "$(dirname "$0")/../shell-common.sh"

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

KAAPPI="${1:-${KAAPPI:-zig-out/bin/kaappi}}"
case "$KAAPPI" in
    /* | ?:[/\\]*) ;;                     # already absolute (POSIX or C:/...)
    *) KAAPPI="$PWD/$KAAPPI" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

if [ ! -x "$KAAPPI" ]; then
    echo "FAIL: no kaappi binary at $KAAPPI (run 'zig build' first)"
    exit 1
fi

TIMEOUT="${KAAPPI_DIFF_TIMEOUT:-60}"
VERBOSE="${KAAPPI_DIFF_VERBOSE:-0}"

# Portable timeout: GNU coreutils `timeout` is absent on stock macOS, and the
# perl fallback is the only thing guaranteed present on the BSD reference
# boxes.  Same ladder as tests/scheme/audit-baseline.sh.
if command -v timeout > /dev/null 2>&1; then
    run_timeout() { timeout "$@"; }
elif command -v gtimeout > /dev/null 2>&1; then
    run_timeout() { gtimeout "$@"; }
else
    run_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }
fi
# GNU timeout reports 124 on expiry.  The perl fallback is killed by a signal:
# 142 (128+SIGALRM) normally, but 143 (128+SIGTERM) has been observed too,
# depending on how the shell reaps the exec'd child.  Treat all three as
# "the timeout fired", never as a real exit status to compare.
timed_out() { [ "$1" -eq 124 ] || [ "$1" -eq 142 ] || [ "$1" -eq 143 ]; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/kaappi-diff-XXXXXX")"
if [ "${KAAPPI_DIFF_KEEP:-0}" = "1" ]; then
    trap 'echo "kept: $TMPROOT"' EXIT
else
    trap 'rm -rf "$TMPROOT"' EXIT
fi

# ---------------------------------------------------------------------------
# Corpus
# ---------------------------------------------------------------------------

CORPUS_DIRS="tests/scheme/differential/probes
tests/scheme/smoke
tests/scheme/compliance
tests/scheme/audit"

if [ "${KAAPPI_DIFF_FULL:-0}" = "1" ]; then
    CORPUS_DIRS="$CORPUS_DIRS
tests/scheme/continuations
tests/scheme/hygiene
tests/scheme/srfi"
fi

# A Debug build runs the whole pipeline unoptimised and is ~500x slower on
# allocation-heavy work (see CLAUDE.md).  Three runs per file over 331 files is
# ~1000 interpreter invocations, which blew through run-all.sh's 300s
# SHELL_TIMEOUT on CI's Debug leg while finishing in ~2 minutes on ReleaseSafe.
#
# Reduce to probes/ there rather than skipping or raising the budget.  That is
# a principled reduction, not a cop-out: probes/ is where essentially all the
# tier-(b) signal lives (see the census above — 9 of 331 corpus files make the
# optimiser do anything, and 6 of those 9 ARE the probes), so the Debug leg
# keeps the coverage that discriminates and drops the ~322 files whose
# comparison is vacuous by construction.
#
# Detected from the binary, not from an env var, so it is right whether the
# build came from CI, `zig build -Doptimize=Debug`, or a stale zig-out.
BUILD_MODE=$("$KAAPPI" features --json 2>/dev/null |
    sed -n 's/.*"build_mode":"\([^"]*\)".*/\1/p')
if [ "$BUILD_MODE" = "Debug" ] && [ "${KAAPPI_DIFF_FULL:-0}" != "1" ]; then
    CORPUS_DIRS="tests/scheme/differential/probes"
    DEBUG_REDUCED=1
fi

# Basename globs whose output is nondeterministic BY CONSTRUCTION, so that
# comparing two runs of them says nothing about any tier.  Space-separated.
#
# Keep this list SHORT and justified: the dynamic control below catches
# anything missed, whereas a file listed here stops being checked at all.  It
# is empty today because the measured sweep found nothing that needed it — the
# corpus is deterministic, and the categories the audit plan calls out
# (gensym/generate-symbol counters, current-time/current-jiffy, hash-table
# iteration order, thread and fiber scheduling) either do not reach stdout in
# these files or are already normalised away.  Add an entry only with a reason.
SKIP_PATTERNS=""

is_skipped() {
    local base pat
    base="$(basename "$1")"
    # shellcheck disable=SC2086  # deliberate word splitting over the pattern list
    for pat in $SKIP_PATTERNS; do
        # shellcheck disable=SC2254  # $pat is intentionally a glob
        case "$base" in $pat) return 0 ;; esac
    done
    return 1
}

# Divergences that are REAL, filed, and not yet fixed.  One `tier:basename` per
# line.  A listed pair is reported as KNOWN and does not fail the run — the
# shell analogue of the `;; FAIL: #1234` marker convention in
# docs/audit-strategy.md's session protocol, so `run-all.sh` stays green while
# the bug is open.
#
# Unlike that convention this list does not rot silently: when a listed pair
# stops diverging the summary prints a STALE line telling you to delete the
# entry.  That is deliberately a NOTE and not a failure — a gate that goes red
# the moment someone FIXES a bug teaches people to distrust it.
#
# d:cache-error-location.scm
#   A cache HIT loses a runtime error's source line and snippet when the error
#   is located by `Function.source_line` rather than by the line table:
#   `toplevel_driver.vmErrorLocation`'s `fallback_line` is a hardcoded 0 on the
#   cache-HIT path (src/main.zig:732) where the fresh-compile path passes the
#   top-level datum's line (src/main.zig:815).  stdout and the exit code agree;
#   only the diagnostic degrades.  Found by this harness (audit v2, Phase 4B);
#   see the header of probes/cache-error-location.scm for the full repro and
#   its discriminating control.  Tracked as kaappi#1922 -- delete this entry
#   when that is fixed, and the STALE check below will confirm it.
KNOWN_DIFFS="
d:cache-error-location.scm
"

is_known_diff() {   # is_known_diff <tier> <file>
    local key line
    key="$1:$(basename "$2")"
    # shellcheck disable=SC2086  # deliberate word splitting over the entry list
    for line in $KNOWN_DIFFS; do
        [ "$line" = "$key" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Run + compare helpers
# ---------------------------------------------------------------------------

# run_kaappi <home> <stdout-file> <stderr-file> <args...> -> exit status
# KAAPPI_HOME is exported (not prefixed onto the call): a variable assignment
# prefixing a *function* invocation leaks into the caller's environment in
# bash's default mode, which would silently make the next run non-hermetic.
run_kaappi() {
    local home="$1" out="$2" err="$3"
    shift 3
    export KAAPPI_HOME="$home"
    run_timeout "$TIMEOUT" "$KAAPPI" "$@" > "$out" 2> "$err"
}

# normalise <stderr-file>: absolute paths and line/column numbers only.
normalise() {
    sed -E \
        -e "s|${TMPROOT}[A-Za-z0-9._/-]*|<tmp>|g" \
        -e "s|${REPO_ROOT}|<repo>|g" \
        -e 's|/private/var/folders/[A-Za-z0-9._/+-]*|<tmp>|g' \
        -e 's|/var/folders/[A-Za-z0-9._/+-]*|<tmp>|g' \
        -e 's|/tmp/[A-Za-z0-9._/+-]*|<tmp>|g' \
        -e 's|:[0-9]+:[0-9]+|:<line>:<col>|g' \
        -e 's|\(eval\):[0-9]+|(eval):<line>|g' \
        -e 's|\.scm:[0-9]+|.scm:<line>|g' \
        -e 's|line [0-9]+|line <n>|g' \
        "$1"
}

# sbc_count <home>: how many bytecode-cache entries the home holds.
sbc_count() {
    local d="$1/cache" n
    [ -d "$d" ] || { echo 0; return; }
    n=$(find "$d" -name '*.sbc' -type f 2>/dev/null | wc -l)
    echo "$((n))"
}

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------

TOTAL=0
COMPARED=0
SKIPPED=0
BASE_TIMEOUT=0
NONDET=0
DIFF_B=0
DIFF_D=0
COSMETIC_B=0
COSMETIC_D=0
CACHE_USED=0
IR_DIFFERS=0
IR_SAME=0
IR_UNKNOWN=0
KNOWN=0
FAILED_FILES=""
STALE=""

report_diff() {   # report_diff <tier> <file> <what> <expected-file> <actual-file>
    echo "  DIFF  [$1] $2 — $3"
    diff -u "$4" "$5" 2> /dev/null | sed -e '1,2d' -e 's/^/        /' | head -30
}

# ---------------------------------------------------------------------------
# Per-file differential
# ---------------------------------------------------------------------------

check_file() {
    local f="$1"
    local d="$TMPROOT/work"
    rm -rf "$d"
    mkdir -p "$d/home1" "$d/home2"

    local rc_base rc_warm rc_nopt entries

    # --- run 1: cold cache.  This is the oracle for both tiers. ----------
    run_kaappi "$d/home1" "$d/base.out" "$d/base.err" "$f"
    rc_base=$?
    if timed_out $rc_base; then
        echo "  TIMEOUT  $f  (baseline, ${TIMEOUT}s) — not a tier finding; see run-all.sh"
        BASE_TIMEOUT=$((BASE_TIMEOUT + 1))
        return 0
    fi

    # Did this file populate the cache at all?  Programs that `import` do not
    # (docs/dev/cache.md), so tier (d) is a no-op for most of the corpus and
    # we count how often it is not.
    entries=$(sbc_count "$d/home1")
    [ "$entries" -gt 0 ] && CACHE_USED=$((CACHE_USED + 1))

    # --- run 2: warm cache, same home.  Tier (d). ------------------------
    run_kaappi "$d/home1" "$d/warm.out" "$d/warm.err" "$f"
    rc_warm=$?

    # --- run 3: --no-ir-opt.  Tier (b).  Bypasses the cache in both
    # directions, so it cannot perturb runs 1-2 whatever order it runs in.
    run_kaappi "$d/home1" "$d/nopt.out" "$d/nopt.err" --no-ir-opt "$f"
    rc_nopt=$?

    COMPARED=$((COMPARED + 1))

    normalise "$d/base.err" > "$d/base.nerr"
    normalise "$d/warm.err" > "$d/warm.nerr"
    normalise "$d/nopt.err" > "$d/nopt.nerr"

    local bad_b=0 bad_d=0 cos_b=0 cos_d=0

    # tier (d): cold vs warm
    [ "$rc_warm" != "$rc_base" ] && bad_d=1
    cmp -s "$d/base.out" "$d/warm.out" || bad_d=1
    if ! cmp -s "$d/base.nerr" "$d/warm.nerr"; then
        bad_d=1
    elif ! cmp -s "$d/base.err" "$d/warm.err"; then
        cos_d=1
    fi

    # tier (b): default vs --no-ir-opt
    [ "$rc_nopt" != "$rc_base" ] && bad_b=1
    cmp -s "$d/base.out" "$d/nopt.out" || bad_b=1
    if ! cmp -s "$d/base.nerr" "$d/nopt.nerr"; then
        bad_b=1
    elif ! cmp -s "$d/base.err" "$d/nopt.err"; then
        cos_b=1
    fi

    # --- discriminating controls -----------------------------------------
    # Three, applied in order of how conclusive they are.  All are paid only
    # when something already looks wrong, so the green path costs nothing.

    # Control 1 (structural, and the strongest).  A program that `import`s is
    # never cached (docs/dev/cache.md), so it wrote no .sbc entry and the
    # "warm" run is BIT-FOR-BIT the same configuration as the cold one.  A
    # mismatch there cannot be a cache effect — there is no cache — so it is
    # nondeterminism in the file, by construction.  Without this rule a flaky
    # fiber/timing test reads as a tier-(d) finding, which is exactly what
    # tests/scheme/smoke/nested-wait-under-sleep-dirty-snapshot-1490.scm did
    # (it hung once under load and was reported as a cache divergence).
    local nondet_seen=0
    if [ $bad_d -eq 1 ] && [ "$entries" -eq 0 ]; then
        echo "  NONDET  $f  (tier d: file is never cached, so cold == warm — flaky, not a cache divergence)"
        NONDET=$((NONDET + 1))
        nondet_seen=1
        bad_d=0
        cos_d=0
    fi

    # Control 2.  Does the file agree with ITSELF?  A second cold baseline in
    # a fresh home; if that already disagrees, no tier is implicated.
    if [ $bad_b -eq 1 ] || [ $bad_d -eq 1 ]; then
        local rc_ctl
        run_kaappi "$d/home2" "$d/ctl.out" "$d/ctl.err" "$f"
        rc_ctl=$?
        normalise "$d/ctl.err" > "$d/ctl.nerr"
        if [ "$rc_ctl" != "$rc_base" ] ||
            ! cmp -s "$d/base.out" "$d/ctl.out" ||
            ! cmp -s "$d/base.nerr" "$d/ctl.nerr"; then
            echo "  NONDET  $f  (two cold baseline runs disagree — excluded, not a tier finding)"
            if [ "$VERBOSE" = "1" ]; then
                diff -u "$d/base.out" "$d/ctl.out" 2> /dev/null | sed -e '1,2d' -e 's/^/        /' | head -10
            fi
            NONDET=$((NONDET + 1))
            return 0
        fi
    fi

    # Control 3.  Require the divergence to REPRODUCE.  Control 2 can pass by
    # luck on an intermittently flaky file, so replay the offending tier once
    # more against a fresh baseline and drop it unless it disagrees again.
    if [ $bad_d -eq 1 ]; then
        rm -rf "$d/home3"
        mkdir -p "$d/home3"
        run_kaappi "$d/home3" "$d/r1.out" "$d/r1.err" "$f"
        local rc_r1=$?
        run_kaappi "$d/home3" "$d/r2.out" "$d/r2.err" "$f"
        local rc_r2=$?
        normalise "$d/r1.err" > "$d/r1.nerr"
        normalise "$d/r2.err" > "$d/r2.nerr"
        if [ "$rc_r1" = "$rc_r2" ] && cmp -s "$d/r1.out" "$d/r2.out" &&
            cmp -s "$d/r1.nerr" "$d/r2.nerr"; then
            echo "  NONDET  $f  (tier d divergence did not reproduce — flaky, not a finding)"
            NONDET=$((NONDET + 1))
            nondet_seen=1
            bad_d=0
        fi
    fi
    if [ $bad_b -eq 1 ]; then
        rm -rf "$d/home4"
        mkdir -p "$d/home4"
        run_kaappi "$d/home4" "$d/s1.out" "$d/s1.err" "$f"
        local rc_s1=$?
        run_kaappi "$d/home4" "$d/s2.out" "$d/s2.err" --no-ir-opt "$f"
        local rc_s2=$?
        normalise "$d/s1.err" > "$d/s1.nerr"
        normalise "$d/s2.err" > "$d/s2.nerr"
        if [ "$rc_s1" = "$rc_s2" ] && cmp -s "$d/s1.out" "$d/s2.out" &&
            cmp -s "$d/s1.nerr" "$d/s2.nerr"; then
            echo "  NONDET  $f  (tier b divergence did not reproduce — flaky, not a finding)"
            NONDET=$((NONDET + 1))
            nondet_seen=1
            bad_b=0
        fi
    fi

    if [ $bad_d -eq 1 ]; then
        if is_known_diff d "$f"; then
            KNOWN=$((KNOWN + 1))
            echo "  KNOWN [d cold-vs-warm cache] $f  (see KNOWN_DIFFS)"
        else
            DIFF_D=$((DIFF_D + 1))
            FAILED_FILES="$FAILED_FILES
  [d cold/warm cache] $f"
            echo "  DIFF  [d cold-vs-warm cache] $f  (exit $rc_base vs $rc_warm)"
            cmp -s "$d/base.out" "$d/warm.out" || report_diff d "$f" stdout "$d/base.out" "$d/warm.out"
            cmp -s "$d/base.nerr" "$d/warm.nerr" || report_diff d "$f" stderr "$d/base.nerr" "$d/warm.nerr"
        fi
    elif [ $nondet_seen -eq 0 ] && is_known_diff d "$f"; then
        STALE="$STALE
  d:$(basename "$f")"
    fi
    if [ $bad_b -eq 1 ]; then
        if is_known_diff b "$f"; then
            KNOWN=$((KNOWN + 1))
            echo "  KNOWN [b --no-ir-opt] $f  (see KNOWN_DIFFS)"
        else
            DIFF_B=$((DIFF_B + 1))
            FAILED_FILES="$FAILED_FILES
  [b --no-ir-opt] $f"
            echo "  DIFF  [b --no-ir-opt] $f  (exit $rc_base vs $rc_nopt)"
            cmp -s "$d/base.out" "$d/nopt.out" || report_diff b "$f" stdout "$d/base.out" "$d/nopt.out"
            cmp -s "$d/base.nerr" "$d/nopt.nerr" || report_diff b "$f" stderr "$d/base.nerr" "$d/nopt.nerr"
        fi
    elif [ $nondet_seen -eq 0 ] && is_known_diff b "$f"; then
        STALE="$STALE
  b:$(basename "$f")"
    fi
    [ $cos_d -eq 1 ] && {
        COSMETIC_D=$((COSMETIC_D + 1))
        echo "  NOTE  [d] $f — stderr differs only in paths/line numbers"
    }
    [ $cos_b -eq 1 ] && {
        COSMETIC_B=$((COSMETIC_B + 1))
        echo "  NOTE  [b] $f — stderr differs only in paths/line numbers"
    }

    # --- vacuity meter for tier (b) --------------------------------------
    # Does the optimiser change this file's IR at all?  `kaappi ir` executes
    # nothing, so this is cheap; it is what turns "no diff" into "no diff, and
    # here is how much of the corpus the passes even touch".
    if run_kaappi "$d/home1" "$d/ir.opt" "$d/ir.opt.err" ir "$f" &&
        run_kaappi "$d/home1" "$d/ir.noopt" "$d/ir.noopt.err" ir --no-opt "$f"; then
        if cmp -s "$d/ir.opt" "$d/ir.noopt"; then
            IR_SAME=$((IR_SAME + 1))
        else
            IR_DIFFERS=$((IR_DIFFERS + 1))
        fi
    else
        IR_UNKNOWN=$((IR_UNKNOWN + 1))
    fi

    if [ "$VERBOSE" = "1" ] && [ $bad_b -eq 0 ] && [ $bad_d -eq 0 ]; then
        echo "  ok    $f  (cache entries: $entries)"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== differential: tier (b) --no-ir-opt, tier (d) cold-vs-warm cache ==="
echo "binary:  $KAAPPI ($("$KAAPPI" --version 2> /dev/null | head -1))"
printf 'corpus: '
# shellcheck disable=SC2086  # deliberate word splitting over the dir list
printf '%s ' $CORPUS_DIRS
echo ""
if [ "${DEBUG_REDUCED:-0}" = "1" ]; then
    echo "        (Debug build detected -- reduced to probes/, which carry 6 of"
    echo "         the 9 optimiser-reaching files.  KAAPPI_DIFF_FULL=1 overrides.)"
fi
echo ""

START=$(date +%s)
# shellcheck disable=SC2086  # deliberate word splitting over the dir list
for dir in $CORPUS_DIRS; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.scm; do
        [ -e "$f" ] || continue
        TOTAL=$((TOTAL + 1))
        if is_skipped "$f"; then
            SKIPPED=$((SKIPPED + 1))
            [ "$VERBOSE" = "1" ] && echo "  SKIP  $f"
            continue
        fi
        check_file "$f"
    done
done
ELAPSED=$(($(date +%s) - START))

IR_TOTAL=$((IR_SAME + IR_DIFFERS))
echo ""
echo "=== summary ==="
echo "  corpus files:                 $TOTAL"
echo "  skipped (static list):        $SKIPPED"
echo "  skipped (baseline timeout):   $BASE_TIMEOUT"
echo "  nondeterministic (excluded):  $NONDET"
echo "  compared:                     $COMPARED"
echo ""
echo "  tier (b) --no-ir-opt:         $((COMPARED - DIFF_B)) agree, $DIFF_B differ"
echo "  tier (d) cold-vs-warm cache:  $((COMPARED - DIFF_D)) agree, $DIFF_D differ"
echo "  known divergences hit:        $KNOWN (suppressed; see KNOWN_DIFFS)"
echo "  stderr cosmetic-only notes:   b=$COSMETIC_B d=$COSMETIC_D"
echo ""
echo "  cache exercised:              $CACHE_USED / $COMPARED files wrote an .sbc entry"
echo "  IR differs under --no-ir-opt: $IR_DIFFERS / $IR_TOTAL files ($IR_UNKNOWN undetermined)"
if [ "$IR_DIFFERS" -eq 0 ] && [ "$IR_TOTAL" -gt 0 ]; then
    echo "  WARNING: the optimiser changed NO file's IR — tier (b) is fully vacuous here."
fi
if [ "$CACHE_USED" -eq 0 ] && [ "$COMPARED" -gt 0 ]; then
    echo "  WARNING: no file populated the cache — tier (d) is fully vacuous here."
fi
if [ -n "$STALE" ]; then
    echo ""
    echo "  STALE: these KNOWN_DIFFS entries no longer diverge — delete them"
    echo "         from run-differential.sh (not a failure):$STALE"
fi
echo ""
echo "  elapsed: ${ELAPSED}s"

if [ $((DIFF_B + DIFF_D)) -gt 0 ]; then
    echo ""
    echo "FAIL: $((DIFF_B + DIFF_D)) tier divergence(s):$FAILED_FILES"
    exit 1
fi
echo ""
echo "PASS: no tier divergence across $COMPARED files"
exit 0
