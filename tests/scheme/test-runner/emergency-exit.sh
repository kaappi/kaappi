#!/bin/bash
# kaappi#2521 — `(emergency-exit ...)` must honor the `kaappi test` worker's
# suppress_exit contract.
#
# `exit` consults `vm.suppress_exit`, so a worker turns a file's `(exit 1)`
# failure epilogue into a recorded no-op and still emits its one JSON result.
# `emergency-exit` did not — it called std.process.exit directly, killing the
# worker before it could emit, and the orchestrator reported
# `ERROR <file> (worker produced no result)`, losing every SRFI-64 count the
# file had already collected. A passing suite ending in `(emergency-exit 0)`
# was red under `kaappi test` and green under `tests/scheme/run-all.sh`.
#
# Now `emergency-exit` records the request the same way `exit` does, so a
# requested emergency exit code weighs into the file's verdict exactly like a
# requested `(exit N)` — the worker reaches emitResult and the verdict rules
# certified by runner-agreement.sh apply unchanged.
#
# Each fixture runs BOTH ways, as in runner-agreement.sh: a plain
# `kaappi <file>` (whose exit status is what run-all.sh reads) and
# `kaappi test <file>`; the two must agree AND land on the expected verdict.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
KAAPPI="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
PASS=0
FAIL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export KAAPPI_HOME="$WORK/home"
mkdir -p "$KAAPPI_HOME"
# Run from the temp dir: a plain `kaappi <file>` run's SRFI-64 runner drops a
# `<suite>.log` in the cwd. Keep those out of the repo.
cd "$WORK"

# --- the two runners' verdict rules (as in runner-agreement.sh) --------------

verdict_run_all() {
    local file="$1" status=0
    "$KAAPPI" "$file" > "$WORK/out.txt" 2>&1 || status=$?
    if [[ $status -ne 0 ]]; then
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

# The absence twin: the crash flavor this script exists to bury.
assert_kt_lacks() {
    local label="$1" needle="$2"
    local body
    body=$(cat "$WORK/kt.txt")
    if grep -qF "$needle" <<< "$body"; then
        echo "FAIL: $label — transcript mentions '$needle'"
        sed 's/^/      | /' "$WORK/kt.txt"
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $label"
        PASS=$((PASS + 1))
    fi
}

# --- fixtures ---------------------------------------------------------------

# A wholly green suite ending in (emergency-exit 0): a plain run exits 0, and
# the worker must reach emitResult with its counts, not die mid-file. This is
# the exact shape that used to report `worker produced no result` (#2521).
cat > ee-pass.scm <<'EOF'
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "ee-pass")
(test-equal "an ordinary passing assertion" 1 1)
(test-end "ee-pass")
(emergency-exit 0)
EOF

# The failure-epilogue shape: a failing assertion plus (emergency-exit 1). The
# nonzero request is redundant with the counts, so `kaappi test` must report a
# FAIL carrying the assertion detail, not an opaque file error.
cat > ee-fail-epilogue.scm <<'EOF'
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "ee-fail-epilogue")
(test-equal "a genuinely failing assertion" 1 2)
(test-end "ee-fail-epilogue")
(emergency-exit 1)
EOF

# A bare (emergency-exit 1) with nothing in the counts to explain it: a plain
# run exits 1, so the file's own verdict is the only signal there is and it
# must not be discarded — or crash-flavored into a missing result.
cat > ee-bare.scm <<'EOF'
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "ee-bare")
(test-equal "an ordinary passing assertion" 1 1)
(test-end "ee-bare")
(emergency-exit 1)
EOF

# --- the matrix -------------------------------------------------------------

assert_agree "(emergency-exit 0) over a passing suite stays green in both runners (#2521)" ee-pass.scm PASS
assert_kt_mentions "the passing suite's counts survive the suppressed emergency exit" "(1 tests"
assert_kt_lacks "a suppressed emergency exit is not a missing worker result" "worker produced no result"

assert_agree "(emergency-exit 1) over a failing suite is a failure in both runners" ee-fail-epilogue.scm FAIL
assert_kt_mentions "the failing assertion keeps its detail" "a genuinely failing assertion"
assert_kt_lacks "the failure epilogue is not a missing worker result" "worker produced no result"

assert_agree "a bare (emergency-exit 1) with nothing failing is a failure in both runners" ee-bare.scm FAIL
assert_kt_mentions "the file's own verdict is on the transcript, not lost to a crash" \
    "file requested a nonzero exit with no failing test to explain it"

echo ""
echo "emergency-exit: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
