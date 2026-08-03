#!/usr/bin/env bash
# Run tests/scheme/r7rs/r7rs-tests.scm and turn its printed counts into an
# exit status.
#
#     bash tools/run-r7rs-suite.sh [path/to/kaappi] [extra kaappi args...]
#
# WHY THIS EXISTS. The R7RS suite is the one file in the corpus that reports
# failures WITHOUT exiting nonzero. It uses the `(chibi test)` shim, which has
# no exit-on-fail epilogue, so
#
#     kaappi tests/scheme/r7rs/r7rs-tests.scm; echo $?
#
# prints 0 with a failed assertion sitting in the log. Every other corpus file
# is an `(srfi 64)` suite whose epilogue exits 1, which is exactly why the bare
# spelling looks safe and is not.
#
# `run-all.sh` has always known this and parsed the counts. Five `ci.yml` steps
# did not -- riscv64, s390x, ppc64le and both Windows legs invoked the suite
# bare and took the process exit status as the verdict, so on those legs its
# 1,395 assertions caught a crash and never a wrong answer (kaappi#2157). That
# matters most on s390x, the project's big-endian canary (#1654), whose whole
# purpose is to catch byte-order bugs -- and a byte-order bug presents as a
# wrong answer, not a crash.
#
# This script is the single implementation all six callers now share, so they
# agree by construction rather than by three people copying the same awk.
#
# Exit status:
#   0  the suite ran and every assertion passed
#   1  the suite reported failing assertions, or the process exited nonzero
#   2  the harness could not run it at all (no binary, suite file missing, or
#      zero passing assertions -- see the floor check below)

set -u

# Resolve the binary against the CALLER's cwd first -- a relative argument
# means what the caller meant, not what it happens to mean after the cd below.
KAAPPI="${1:-zig-out/bin/kaappi}"
[[ $# -gt 0 ]] && shift
case "$KAAPPI" in
    /*) ;;
    *) KAAPPI="$PWD/$KAAPPI" ;;
esac

# Same for the caller's counts file, for the same reason.
COUNTS_OUT="${KAAPPI_R7RS_COUNTS_OUT:-}"
case "$COUNTS_OUT" in
    ''|/*) ;;
    *) COUNTS_OUT="$PWD/$COUNTS_OUT" ;;
esac

# Then run from the repo root, and hand kaappi the same REPO-RELATIVE suite
# path every caller used before this script existed. That spelling is
# load-bearing on the two Windows legs: they run a native kaappi.exe under Git
# Bash, where an MSYS-absolute argv (`/d/a/kaappi/...`) goes through path
# translation the relative one never touches. The binary path above is exempt
# because bash execs it directly rather than passing it as an argument.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
SUITE=tests/scheme/r7rs/r7rs-tests.scm

if [[ ! -e "$KAAPPI" ]]; then
    echo "run-r7rs-suite: no kaappi at '$KAAPPI'" >&2
    echo "Usage: bash tools/run-r7rs-suite.sh [path/to/kaappi] [extra kaappi args...]" >&2
    exit 2
fi
if [[ ! -f "$SUITE" ]]; then
    echo "run-r7rs-suite: suite file missing at '$REPO_ROOT/$SUITE'" >&2
    exit 2
fi

# Bare `mktemp`, not `mktemp "$TMPDIR/..."`: this runs under Git Bash on the
# Windows legs, where the shell suites' own helper (tests/scheme/shell-common.sh)
# uses the bare form for the same reason.
STDOUT_FILE="$(mktemp)"
STDERR_FILE="$(mktemp)"
trap 'rm -f "$STDOUT_FILE" "$STDERR_FILE"' EXIT

"$KAAPPI" "$@" "$SUITE" > "$STDOUT_FILE" 2> "$STDERR_FILE"
R7RS_STATUS=$?
R7RS_OUTPUT="$(cat "$STDOUT_FILE" "$STDERR_FILE")"

# The counts the shim prints, summed across every `test-begin`/`test-end`
# section: "<n> pass" and "<n> fail", tolerating a trailing comma. This awk is
# the definition of "the R7RS suite passed" and now has exactly one copy.
r7rs_count() {
    printf "%s\n" "$R7RS_OUTPUT" | awk -v want="$1" \
        '{for (i = 1; i < NF; i++) { w=$(i+1); gsub(",", "", w); if ($i ~ /^[0-9]+$/ && w == want) s += $i }} END {print s + 0}'
}
R7RS_PASS=$(r7rs_count pass)
R7RS_FAIL=$(r7rs_count fail)

echo "  $R7RS_PASS pass, $R7RS_FAIL fail (exit $R7RS_STATUS)"

# A caller that folds this suite into a larger summary (run-all.sh) reads the
# counts back from here rather than re-parsing the output, so there is still
# only one parser. Written before any of the failure exits below, so the
# numbers are available even when the run is judged a failure.
if [[ -n "$COUNTS_OUT" ]]; then
    {
        echo "R7RS_PASS=$R7RS_PASS"
        echo "R7RS_FAIL=$R7RS_FAIL"
        echo "R7RS_STATUS=$R7RS_STATUS"
    } > "$COUNTS_OUT"
fi

if [[ $R7RS_FAIL -gt 0 ]]; then
    printf '%s\n' "$R7RS_OUTPUT" | grep -E '^FAIL|^ERROR' | head -30 | sed 's/^/        /'
fi
if [[ $R7RS_STATUS -ne 0 ]]; then
    echo "  FAIL  tests/scheme/r7rs/r7rs-tests.scm (exit $R7RS_STATUS)"
    echo "--- stderr output ---"
    cat "$STDERR_FILE" 2>/dev/null || true
    echo "--- last 20 lines stdout ---"
    tail -20 "$STDOUT_FILE" 2>/dev/null || true
    echo "--- end crash context ---"
fi

# Zero passing assertions means the suite did not run -- a missing library, a
# startup abort, a shim whose output format moved. That must not read as "no
# failures", which is the same cannot-fail shape this whole script exists to
# close.
if [[ $R7RS_PASS -eq 0 ]]; then
    echo "run-r7rs-suite: the suite reported 0 passing assertions." >&2
    echo "  It did not run. Treating that as a harness failure, not a pass." >&2
    exit 2
fi

if [[ $R7RS_FAIL -gt 0 || $R7RS_STATUS -ne 0 ]]; then
    exit 1
fi
exit 0
