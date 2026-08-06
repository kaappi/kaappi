#!/bin/bash
# run-wasm-differential.sh — WASM cross-tier differential (audit v2, Phase 4D)
#
# Sibling of run-differential.sh, which covers tier (b) --no-ir-opt and tier
# (d) cold-vs-warm cache.  This one covers the WASM tier:
#
#   base   kaappi F                              <- the oracle (interpreter)
#   wasm   wasmtime run --dir=. kaappi.wasm F    <- tier (e)
#
# Pass criterion: byte-identical stdout, identical exit status, and identical
# stderr after the same normalisation the sibling uses.
#
#   Usage:  bash tests/scheme/differential/run-wasm-differential.sh [path-to-kaappi]
#
#   KAAPPI_WASM=<path>         the .wasm module (default zig-out/bin/kaappi.wasm)
#   KAAPPI_WASM_DIFF_FULL=1    add continuations/, hygiene/ and srfi/
#   KAAPPI_WASM_DIFF_TIMEOUT=N per-run timeout in seconds (default 60)
#   KAAPPI_WASM_DIFF_VERBOSE=1 print a line per file instead of only diffs
#   KAAPPI_WASM_DIFF_KEEP=1    keep the temp tree of captured outputs
#
# Exits 77 (SKIP) when there is no WASM runtime or no module to run — most
# dev boxes have neither, and CI's `wasm` job has both.
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE TRUSTING A GREEN RUN
# ---------------------------------------------------------------------------
# Most of the corpus cannot run on this tier at all, and the reason is a bug,
# not a property of WASM.
#
# MEASURED 2026-08-01 over 591 corpus files (smoke, compliance, audit,
# continuations, hygiene, srfi, probes): **401 of them fail on WASM with
# nothing but `KP2001 library not found`**, because no file-backed `.sld` is
# importable there even when the host mounts the directory (kaappi#2108 —
# `platform.openRead` has no WASI branch, so `resolveLibraryPath`'s existence
# probe fails for every candidate path).  Only registry built-ins and the two
# `embedded_libraries` entries resolve.
#
# So the comparison is structurally narrow: ~184 of 591 files actually execute
# on both tiers.  This script REPORTS that number rather than leaving it to be
# assumed — the summary prints "excluded (no .sld on WASM)" — for the same
# reason the sibling reports its optimiser-vacuity meter.  When kaappi#2108 is
# fixed, that count should collapse and the compared count should jump; if it
# does not, something else has broken.
#
# The honest reading of a green run today: the ~184 files that CAN run agree
# byte-for-byte, and the other ~400 are untested on this tier.
#
# ---------------------------------------------------------------------------
# Exclusions
# ---------------------------------------------------------------------------
# Three buckets, all measured rather than guessed, all reported:
#
# (a) LIBDIFF — the wasm run's only complaint is `library not found` and the
#     native run has none.  kaappi#2108.  Counted, not a failure.
#
# (b) PLATFORM — the wasm run hit a degradation the engine reports
#     deliberately and CLAUDE.md documents: no filesystem access (the
#     `(scheme file)` gates from kaappi#1972/#2016) or no FFI.  These are
#     matched on the engine's OWN message text, not on a file list, so a
#     degradation that stops being reported cleanly shows up as a DIFF
#     instead of being silently swallowed.
#
# (c) KNOWN_DIFFS — real, filed, unfixed divergences, one `basename` per line
#     with its issue number.  As in the sibling, an entry that stops
#     diverging is reported as STALE (a note, not a failure).
#
# Nondeterminism is handled the same way the sibling handles it: a candidate
# divergence is replayed against a second native baseline, and dropped unless
# it reproduces.  Paid only when something already looks wrong.
#
# WHY THE `agree` COUNT DROPPED IN kaappi#2116.  Converting the corpus's 56
# verdictless files to the SRFI-64 exit-on-fail shape gave each of them an
# `(import (srfi 64))`, and `(srfi 64)` is a file-backed `.sld`, which wasm32
# cannot load (kaappi#2108).  Measured on macOS aarch64 at e62b90eb: `agree`
# 176 -> 124 and LIBDIFF 179 -> 231, 52 files moving from compared to excluded.
# That is a real, temporary reduction in this harness's reach, and it reverses
# entirely when #2108 lands — it is not a sign that those files stopped
# working.  Three files were deliberately left free of file-backed `.sld`
# imports for exactly this reason and carry a hand-rolled `(exit 1)` instead,
# because LIBDIFF would have destroyed what they exist to measure --
# `deep-nesting-print.scm` and
# `large-index-bounds-1912.scm` (the latter's KNOWN_DIFFS entry for #1912 was
# deleted when the fix made the tiers agree again -- it remains the cross-tier
# large-index probe) and `deep-nesting-print-tier-margin.scm` (the positive
# control that keeps #2107's margin under watch).  Do not "tidy" those three
# into SRFI-64.
# They are three of the FOUR hand-rolled-verdict files; the fourth,
# `continuations/coroutine-repl-echo.scm`, is exempt for an unrelated reason and
# is not a tier probe.  tests/scheme/CLAUDE.md holds the single inventory table.
# `deep-nesting-print-tier-margin.scm` does import `(scheme process-context)`
# for `exit` -- a BUILT-IN library, not a `.sld`, so it stays out of LIBDIFF;
# verified under wasmtime that its output and exit status are unchanged.
#
# Unrelated pre-existing observation from that measurement, recorded so it is
# not re-derived: `deep-nesting-print.scm`'s KNOWN_DIFFS entry is reported
# STALE at e62b90eb with the file unmodified, i.e. #2107 no longer reproduces
# for it on the current wasmtime.  Left in place for #2107's owner to judge.
#
# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------
# stdout and the exit status are compared BYTE-EXACTLY.  Only stderr is
# normalised, for absolute paths and line/column numbers.
#
# Regex portability: `sed -E` / `grep -E` only, plain POSIX ERE — GNU BRE
# extensions match nothing on OpenBSD (kaappi#1862).  No `grep -q` on the
# right of a pipe under `pipefail` (kaappi#1926).
#
# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
# wasmtime only, deliberately.  It is what CI installs and what this harness
# was validated against (46.0.0).  Adding another runtime means adding a
# `wasm_run` implementation below and verifying its `--dir`-equivalent
# actually pre-opens the repo root; an unverified invocation would report
# every file as broken, which is worse than skipping.

set -uo pipefail

# shellcheck source=tests/scheme/shell-common.sh
. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${1:-${KAAPPI:-zig-out/bin/kaappi}}"
case "$KAAPPI" in
    /* | ?:[/\\]*) ;;
    *) KAAPPI="$PWD/$KAAPPI" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

WASM="${KAAPPI_WASM:-zig-out/bin/kaappi.wasm}"

if [ ! -x "$KAAPPI" ]; then
    echo "FAIL: no kaappi binary at $KAAPPI (run 'zig build' first)"
    exit 1
fi
if ! command -v wasmtime > /dev/null 2>&1; then
    echo "SKIP: no wasmtime on PATH (see the Runtime note in this script)"
    exit 77
fi
if [ ! -f "$WASM" ]; then
    echo "SKIP: no wasm module at $WASM (run 'zig build wasm' first)"
    exit 77
fi

TIMEOUT="${KAAPPI_WASM_DIFF_TIMEOUT:-60}"
VERBOSE="${KAAPPI_WASM_DIFF_VERBOSE:-0}"

# Portable timeout: stock macOS has no GNU `timeout`; the perl fallback is the
# only thing guaranteed on the BSD reference boxes.  Same ladder as
# tools/audit-baseline.sh and the sibling script.
if command -v timeout > /dev/null 2>&1; then
    run_timeout() { timeout "$@"; }
elif command -v gtimeout > /dev/null 2>&1; then
    run_timeout() { gtimeout "$@"; }
else
    run_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }
fi
timed_out() { [ "$1" -eq 124 ] || [ "$1" -eq 142 ] || [ "$1" -eq 143 ]; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/kaappi-wasmdiff-XXXXXX")"
if [ "${KAAPPI_WASM_DIFF_KEEP:-0}" = "1" ]; then
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

if [ "${KAAPPI_WASM_DIFF_FULL:-0}" = "1" ]; then
    CORPUS_DIRS="$CORPUS_DIRS
tests/scheme/continuations
tests/scheme/hygiene
tests/scheme/srfi"
fi

# Real, filed, unfixed divergences.  `basename` per line; the comment carries
# the issue.  A listed file that stops diverging is reported as STALE.
#
# deep-nesting-print.scm      kaappi#2107 — write/display of a car-nested
#   structure deeper than 847 aborts the module (shadow-stack underflow);
#   MAX_PRINT_DEPTH's 1024 guard is unreachable on wasm32.  This file nests
#   200000 deep, so it aborts where native truncates and passes.
# command-line-o-flag.scm     kaappi#2109 — (command-line) is '() on WASM
#   because main.zig's WASM entry returns before vm.command_line_args is set.
# condexpand-include-lib-868-879.scm  kaappi#2108 — cond-expand (library …)
#   over a file-backed .sld, the same resolver failure as the LIBDIFF bucket,
#   but reported through cond-expand rather than a KP2001, so it does not
#   match that bucket's signature.
# large-index-bounds-1912.scm kaappi#1912 -- FIXED: index arguments are now
#   bounds-checked in u64 before any narrowing to usize (usize = u32 on
#   wasm32), so 2^32+1 raises instead of aliasing element 1.  The KNOWN_DIFFS
#   entry was deleted when the tiers agreed; the file remains in the corpus as
#   the cross-tier large-index regression probe.
KNOWN_DIFFS="
deep-nesting-print.scm
command-line-o-flag.scm
condexpand-include-lib-868-879.scm
"

is_known_diff() {
    local line base
    base="$(basename "$1")"
    # shellcheck disable=SC2086  # deliberate word splitting over the entry list
    for line in $KNOWN_DIFFS; do
        [ "$line" = "$base" ] && return 0
    done
    return 1
}

# note_stale <file>: record that a KNOWN_DIFFS file did NOT produce the
# divergence it is listed for.
#
# Called from every terminal bucket except KNOWN itself and NONDET — not just
# from the agreeing path.  A listed file that starts agreeing is the obvious
# case, but one that shifts into LIBDIFF or PLATFORM is equally stale: the
# recorded divergence is no longer what happens, and leaving the entry in
# place would keep suppressing a bucket nobody reviewed.  NONDET is excluded
# deliberately, since a flaky run would otherwise report a perfectly good
# entry as stale.
note_stale() {
    if is_known_diff "$1"; then
        STALE="$STALE
  $(basename "$1")"
    fi
}

# ---------------------------------------------------------------------------
# Run helpers
# ---------------------------------------------------------------------------

# run_native <home> <out> <err> <file>
run_native() {
    local home="$1" out="$2" err="$3" f="$4"
    export KAAPPI_HOME="$home"
    run_timeout "$TIMEOUT" "$KAAPPI" "$f" > "$out" 2> "$err"
}

# run_wasm <out> <err> <file>
# Paths stay RELATIVE to the repo root: wasmtime pre-opens "." there, and a
# host absolute path is not resolvable inside the guest.
run_wasm() {
    local out="$1" err="$2" f="$3"
    run_timeout "$TIMEOUT" wasmtime run --dir=. "$WASM" "$f" > "$out" 2> "$err"
}

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

# wasm_only_match <pattern> <native-err> <wasm-err>: the wasm run reports it
# and the native run does not.  Both greps read files directly — never the
# right-hand side of a pipe, so `pipefail` has no pipeline to misjudge.
wasm_only_match() {
    grep -Eq "$1" "$3" 2> /dev/null && ! grep -Eq "$1" "$2" 2> /dev/null
}

LIB_SIGNATURE='KP2001|library not found'
# The engine's own platform-gate wording (kaappi#1972/#2016) plus the FFI
# names that are simply not registered on this target.  Matching the message
# rather than a file list is what keeps a *degraded* gate from being confused
# with a *working* one: if these stop being reported cleanly, the file lands
# in DIFF instead of here.
PLATFORM_SIGNATURE='this WebAssembly build has no filesystem access|undefined variable .(ffi-open|ffi-fn|ffi-close|ffi-callback|fd->port).'

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------

TOTAL=0
COMPARED=0
AGREE=0
LIBDIFF=0
PLATFORM=0
KNOWN=0
DIFF=0
NONDET=0
BASE_TIMEOUT=0
WASM_TIMEOUT=0
COSMETIC=0
FAILED_FILES=""
STALE=""

report_diff() {   # report_diff <file> <what> <expected> <actual>
    echo "  DIFF  $1 — $2"
    diff -u "$3" "$4" 2> /dev/null | sed -e '1,2d' -e 's/^/        /' | head -30
}

# ---------------------------------------------------------------------------
# Per-file differential
# ---------------------------------------------------------------------------

check_file() {
    local f="$1"
    local d="$TMPROOT/work"
    rm -rf "$d"
    mkdir -p "$d/home1" "$d/home2"

    local rc_base rc_wasm

    run_native "$d/home1" "$d/base.out" "$d/base.err" "$f"
    rc_base=$?
    if timed_out $rc_base; then
        echo "  TIMEOUT  $f  (native baseline, ${TIMEOUT}s) — not a tier finding; see run-all.sh"
        BASE_TIMEOUT=$((BASE_TIMEOUT + 1))
        return 0
    fi

    run_wasm "$d/wasm.out" "$d/wasm.err" "$f"
    rc_wasm=$?
    # A hang is a finding (audit v2 protocol): the WASM reactor degrades to
    # CLOCK-only poll_oneoff waits, so a fd wait that can never be ready is
    # exactly the shape that hangs here and not natively.
    if timed_out $rc_wasm; then
        echo "  HANG  $f  (wasm, ${TIMEOUT}s) — native completed in time"
        WASM_TIMEOUT=$((WASM_TIMEOUT + 1))
        FAILED_FILES="$FAILED_FILES
  [wasm hang] $f"
        return 0
    fi

    COMPARED=$((COMPARED + 1))

    normalise "$d/base.err" > "$d/base.nerr"
    normalise "$d/wasm.err" > "$d/wasm.nerr"

    local bad=0 cosmetic=0
    [ "$rc_wasm" != "$rc_base" ] && bad=1
    cmp -s "$d/base.out" "$d/wasm.out" || bad=1
    if ! cmp -s "$d/base.nerr" "$d/wasm.nerr"; then
        bad=1
    elif ! cmp -s "$d/base.err" "$d/wasm.err"; then
        cosmetic=1
    fi

    if [ $bad -eq 0 ]; then
        AGREE=$((AGREE + 1))
        [ $cosmetic -eq 1 ] && {
            COSMETIC=$((COSMETIC + 1))
            echo "  NOTE  $f — stderr differs only in paths/line numbers"
        }
        note_stale "$f"
        [ "$VERBOSE" = "1" ] && echo "  ok    $f"
        return 0
    fi

    # --- bucket the mismatch ---------------------------------------------
    # Order matters: the library failure is checked first because a file that
    # cannot import its library never reaches whatever else it would have hit.
    if wasm_only_match "$LIB_SIGNATURE" "$d/base.err" "$d/wasm.err"; then
        LIBDIFF=$((LIBDIFF + 1))
        note_stale "$f"
        [ "$VERBOSE" = "1" ] && echo "  LIBDIFF  $f  (no .sld on WASM — kaappi#2108)"
        return 0
    fi
    if wasm_only_match "$PLATFORM_SIGNATURE" "$d/base.err" "$d/wasm.err"; then
        PLATFORM=$((PLATFORM + 1))
        note_stale "$f"
        [ "$VERBOSE" = "1" ] && echo "  PLATFORM  $f  (documented WASM degradation, reported cleanly)"
        return 0
    fi

    # --- discriminating control ------------------------------------------
    # Does the native side agree with ITSELF?  A second baseline in a fresh
    # home; if the two disagree, the file is nondeterministic and no tier is
    # implicated.  Paid only once something already looks wrong.
    local rc_ctl
    run_native "$d/home2" "$d/ctl.out" "$d/ctl.err" "$f"
    rc_ctl=$?
    normalise "$d/ctl.err" > "$d/ctl.nerr"
    if [ "$rc_ctl" != "$rc_base" ] ||
        ! cmp -s "$d/base.out" "$d/ctl.out" ||
        ! cmp -s "$d/base.nerr" "$d/ctl.nerr"; then
        echo "  NONDET  $f  (two native baseline runs disagree — excluded, not a tier finding)"
        NONDET=$((NONDET + 1))
        return 0
    fi

    # Require the divergence to REPRODUCE — the control above can pass by
    # luck on an intermittently flaky file.
    local rc_w2
    run_wasm "$d/w2.out" "$d/w2.err" "$f"
    rc_w2=$?
    normalise "$d/w2.err" > "$d/w2.nerr"
    if [ "$rc_w2" = "$rc_base" ] && cmp -s "$d/base.out" "$d/w2.out" &&
        cmp -s "$d/base.nerr" "$d/w2.nerr"; then
        echo "  NONDET  $f  (divergence did not reproduce — flaky, not a finding)"
        NONDET=$((NONDET + 1))
        return 0
    fi

    if is_known_diff "$f"; then
        KNOWN=$((KNOWN + 1))
        echo "  KNOWN  $f  (see KNOWN_DIFFS)"
        return 0
    fi

    DIFF=$((DIFF + 1))
    FAILED_FILES="$FAILED_FILES
  [wasm] $f"
    echo "  DIFF  $f  (exit $rc_base native vs $rc_wasm wasm)"
    cmp -s "$d/base.out" "$d/wasm.out" || report_diff "$f" stdout "$d/base.out" "$d/wasm.out"
    cmp -s "$d/base.nerr" "$d/wasm.nerr" || report_diff "$f" stderr "$d/base.nerr" "$d/wasm.nerr"
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== differential: WASM tier vs interpreter oracle ==="
echo "native:  $KAAPPI ($("$KAAPPI" --version 2> /dev/null | head -1))"
echo "wasm:    $WASM"
echo "runtime: $(wasmtime --version 2> /dev/null | head -1)"
printf 'corpus: '
# shellcheck disable=SC2086  # deliberate word splitting over the dir list
printf '%s ' $CORPUS_DIRS
echo ""
echo ""

START=$(date +%s)
# shellcheck disable=SC2086  # deliberate word splitting over the dir list
for dir in $CORPUS_DIRS; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.scm; do
        [ -e "$f" ] || continue
        TOTAL=$((TOTAL + 1))
        check_file "$f"
    done
done
ELAPSED=$(($(date +%s) - START))

echo ""
echo "=== summary ==="
echo "  corpus files:                    $TOTAL"
echo "  skipped (native timeout):        $BASE_TIMEOUT"
echo "  compared:                        $COMPARED"
echo ""
echo "  agree (stdout+exit+stderr):      $AGREE"
echo "  excluded, no .sld on WASM:       $LIBDIFF  (kaappi#2108)"
echo "  excluded, documented degradation:$PLATFORM"
echo "  nondeterministic (excluded):     $NONDET"
echo "  known divergences hit:           $KNOWN (suppressed; see KNOWN_DIFFS)"
echo "  stderr cosmetic-only notes:      $COSMETIC"
echo ""
echo "  DIVERGENCES:                     $DIFF"
echo "  wasm hangs:                      $WASM_TIMEOUT"

if [ "$COMPARED" -gt 0 ] && [ "$LIBDIFF" -gt $((COMPARED / 2)) ]; then
    echo ""
    echo "  NOTE: over half the corpus could not run on this tier at all"
    echo "        (kaappi#2108).  A green result here covers $AGREE files, not $COMPARED."
fi
if [ -n "$STALE" ]; then
    echo ""
    echo "  STALE: these KNOWN_DIFFS entries no longer diverge — delete them"
    echo "         from run-wasm-differential.sh (not a failure):$STALE"
fi
echo ""
echo "  elapsed: ${ELAPSED}s"

if [ $((DIFF + WASM_TIMEOUT)) -gt 0 ]; then
    echo ""
    echo "FAIL: $((DIFF + WASM_TIMEOUT)) WASM tier divergence(s):$FAILED_FILES"
    exit 1
fi
echo ""
echo "PASS: no unknown WASM tier divergence across $COMPARED files"
exit 0
