#!/bin/bash
# kaappi#1903 — `kaappi test` and tests/scheme/run-all.sh must reach the SAME
# verdict for a file.
#
# They read different signals. run-all.sh runs `kaappi <file>` and reads the
# process exit status (plus a grep over the printed counts, for a suite that
# forgets its epilogue). `kaappi test` runs the same file in a worker with
# `vm.suppress_exit` set, so the file's `(exit)` never happens, and derives its
# verdict from the SRFI-64 counters plus whether an uncaught top-level error was
# reported. Anywhere those two disagree, a suite is green in one runner and red
# in the other and nobody can say which is right.
#
# The shape that first exposed it was `tests/scheme/srfi/srfi150.scm`: a
# deliberate top-level error, four `test-expect-fail` annotations, and an
# `(exit 0)` epilogue. run-all.sh reported it green; `kaappi test` reported
# exit 1 with `1 errored`. This file reconstructs that shape directly — plus
# every neighbouring case — so the guarantee outlives SRFI 150's own defects
# (kaappi#2051), which will one day stop producing the top-level error at all.
#
# Each fixture is run BOTH ways and the two verdicts are required to match.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
KAAPPI="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
RUN_ALL_SH="$(cd "$(dirname "$0")/.." && pwd)/run-all.sh"
PASS=0
FAIL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export KAAPPI_HOME="$WORK/home"
mkdir -p "$KAAPPI_HOME"
# Run from the temp dir: the `kaappi test` worker installs test-runner-null and
# writes no log, but `verdict_run_all` runs a *plain* `kaappi <file>`, whose
# SRFI-64 runner drops a `<suite>.log` in the cwd. Keep those out of the repo.
cd "$WORK"

# --- the two runners' verdict rules -----------------------------------------

# run-all.sh's rule, copied from run_file_worker(): exit status first, then a
# grep over the output for a suite that reported failures but exited 0 anyway.
#
# This regex is a COPY. It gained its third alternative — a bare FAIL token —
# in kaappi#2116, and a copy that misses an update is exactly how the two
# runners would start disagreeing while this script kept saying they agree. The
# drift check below fails the run if run-all.sh no longer contains this literal
# string, so the copy cannot silently fall behind the original.
RUN_ALL_NET='(^|[^0-9])[1-9][0-9]* fail|unexpected (failures|errors) +[1-9]|(^|[^A-Za-z0-9_])FAIL([^A-Za-z0-9_]|$)'

# The drift check. `grep -F` on the literal pattern text, so this compares the
# two spellings character for character rather than trying to match one regex
# with the other. A here-string, never a pipe into `grep -q`, under pipefail
# (kaappi#1926).
if [[ -r "$RUN_ALL_SH" ]]; then
    if ! grep -Fq "$RUN_ALL_NET" "$RUN_ALL_SH"; then
        echo "runner-agreement: the run-all.sh net regex copied into this script" >&2
        echo "  no longer appears verbatim in $RUN_ALL_SH." >&2
        echo "  Re-copy it, or this script will certify an agreement that has" >&2
        echo "  already been broken. Expected to find:" >&2
        echo "    $RUN_ALL_NET" >&2
        exit 1
    fi
else
    echo "runner-agreement: cannot read $RUN_ALL_SH to check the net regex" >&2
    exit 1
fi

verdict_run_all() {
    local file="$1" status=0
    "$KAAPPI" "$file" > "$WORK/out.txt" 2>&1 || status=$?
    if [[ $status -ne 0 ]]; then
        echo "FAIL"
    elif grep -Eq "$RUN_ALL_NET" "$WORK/out.txt"; then
        echo "FAIL"
    else
        echo "PASS"
    fi
}

# `kaappi test`'s rule, read off its own exit status — nonzero iff a test
# failed, unexpectedly passed, or a file errored.
verdict_kaappi_test() {
    local file="$1" status=0
    "$KAAPPI" test "$file" > "$WORK/kt.txt" 2>&1 || status=$?
    if [[ $status -ne 0 ]]; then echo "FAIL"; else echo "PASS"; fi
}

# --- the assertion ----------------------------------------------------------

# Both runners must agree, and both must reach `expected`. Requiring only
# agreement would be satisfied by two runners that are wrong together.
assert_agree() {
    local label="$1" file="$2" expected="$3"
    local a b
    a=$(verdict_run_all "$file")
    b=$(verdict_kaappi_test "$file")
    if [[ "$a" == "$b" && "$a" == "$expected" ]]; then
        echo "PASS: $label ($expected in both runners)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — run-all.sh=$a kaappi-test=$b, expected $expected in both"
        sed 's/^/      | /' "$WORK/kt.txt"
        FAIL=$((FAIL + 1))
    fi
}

# Assert a substring is present in the last `kaappi test` transcript. Uses a
# here-string, never a pipe into grep -q (see tests/scheme/CLAUDE.md).
assert_kt_mentions() {
    local label="$1" needle="$2"
    local body
    body=$(cat "$WORK/kt.txt")
    if grep -qF "$needle" <<< "$body"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — transcript does not mention '$needle'"
        sed 's/^/      | /' "$WORK/kt.txt"
        FAIL=$((FAIL + 1))
    fi
}

# --- fixtures ---------------------------------------------------------------

# The srfi150.scm shape, reduced to its essentials: a top-level raise that no
# `guard` can reach, an expected-fail assertion that depends on it, and an
# epilogue that exits 0 because the SRFI-64 counters are clean.
cat > ack.scm <<'EOF'
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "ack")
(test-equal "an ordinary passing assertion" 1 1)
(error "deliberate uncaught top-level error")
(test-expect-fail "depends on the form that errored")
(test-assert "depends on the form that errored" never-defined-by-the-errored-form)
(let ((runner (test-runner-current)))
  (test-end "ack")
  (if (> (test-runner-fail-count runner) 0) (exit 1) (exit 0)))
EOF

# The same top-level error with no epilogue at all: nothing acknowledges it, so
# `kaappi <file>` exits 1 and both runners must call it a failure.
cat > unack.scm <<'EOF'
(import (scheme base) (srfi 64))
(test-begin "unack")
(test-equal "an ordinary passing assertion" 1 1)
(error "deliberate uncaught top-level error")
(test-end "unack")
EOF

# A top-level error acknowledged by (exit 0) *and* a genuinely failing
# assertion. The waiver covers the file's own error; it must not cover the
# assertion, or a suite could declare itself green by fiat.
cat > ack-but-failing.scm <<'EOF'
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "ack-but-failing")
(error "deliberate uncaught top-level error")
(test-equal "a genuinely failing assertion" 1 2)
(test-end "ack-but-failing")
(exit 0)
EOF

# The ordinary SRFI-64 failure epilogue: a failing assertion plus (exit 1).
# The nonzero exit is redundant with the counts, so `kaappi test` must report
# it as a FAIL carrying the assertion detail, not as an opaque file error.
cat > failing-epilogue.scm <<'EOF'
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "failing-epilogue")
(test-equal "a genuinely failing assertion" 1 2)
(let ((runner (test-runner-current)))
  (test-end "failing-epilogue")
  (if (> (test-runner-fail-count runner) 0) (exit 1) (exit 0)))
EOF

# A nonzero exit with nothing in the counts to explain it. run-all.sh sees
# exit 1; `kaappi test` has no failing assertion to report, so the file's own
# verdict is the only signal there is and it must not be discarded.
cat > bare-nonzero-exit.scm <<'EOF'
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "bare-nonzero-exit")
(test-equal "an ordinary passing assertion" 1 1)
(test-end "bare-nonzero-exit")
(exit 1)
EOF

# `test-expect-fail` on its own — a wrong *value*, not a raise. This is the
# case the annotation is actually for, and it must stay green in both runners.
cat > expect-fail-only.scm <<'EOF'
(import (scheme base) (srfi 64))
(test-begin "expect-fail-only")
(test-expect-fail "a known wrong answer")
(test-equal "a known wrong answer" 1 2)
(test-equal "an ordinary passing assertion" 1 1)
(test-end "expect-fail-only")
EOF

# A wholly ordinary green suite — the control that keeps the matrix honest.
cat > clean.scm <<'EOF'
(import (scheme base) (srfi 64))
(test-begin "clean")
(test-equal "an ordinary passing assertion" 1 1)
(test-end "clean")
EOF

# --- the matrix -------------------------------------------------------------

assert_agree "top-level error acknowledged by (exit 0)" ack.scm PASS
assert_kt_mentions "the acknowledged error is still on the transcript" \
    "acknowledged by an explicit (exit 0)"
assert_kt_mentions "the acknowledged error keeps its own diagnostic" \
    "deliberate uncaught top-level error"

assert_agree "top-level error with no epilogue to acknowledge it" unack.scm FAIL
assert_agree "(exit 0) does not bury a failing assertion" ack-but-failing.scm FAIL
assert_agree "ordinary failing suite with an (exit 1) epilogue" failing-epilogue.scm FAIL
assert_kt_mentions "a redundant (exit 1) keeps the assertion detail" \
    "a genuinely failing assertion"

assert_agree "nonzero exit with nothing in the counts to explain it" bare-nonzero-exit.scm FAIL
assert_agree "test-expect-fail on a wrong value, not a raise" expect-fail-only.scm PASS
assert_agree "an ordinary green suite" clean.scm PASS

echo ""
echo "runner-agreement: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
