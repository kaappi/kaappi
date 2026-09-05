#!/bin/bash
# kaappi#2525 — `(exit …)` / `(emergency-exit …)` from a SRFI-18 child thread
# must honor the `kaappi test` worker's suppress_exit contract too.
#
# `vm_instance` is threadlocal, so a child thread's `exit` consults ITS VM's
# flag. `VM.initForThread` did not inherit `suppress_exit`, so a thread's
# `(exit 0)` was a real std.process.exit: the worker died before emitting its
# one JSON result and the orchestrator reported
# `ERROR <file> (worker produced no result)` — the same crash-flavoured
# outcome kaappi#2521 removed for the main thread — losing every SRFI-64
# count the file had collected. A plain `kaappi <file>` exited 0, so the two
# runners disagreed (kaappi#1903).
#
# Now the flag is inherited and the request lands on the ROOT VM (the only
# one the worker's emitResult reads), so a thread's requested exit code
# weighs into the verdict exactly like a main-thread `(exit N)`.
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
    if [[ $status -ne 0 ]]; then echo "FAIL"; else echo "PASS"; fi
}

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

# The absence twin: the crash flavour this script exists to bury.
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

# A green suite whose joined child thread calls (exit 0): a plain run exits 0
# (the thread's exit IS the process exit), and the worker must reach
# emitResult with its counts. This is the exact shape that reported
# `worker produced no result` (#2525).
cat > te-pass.scm <<'SCM'
(import (scheme base) (scheme process-context) (srfi 18) (srfi 64))
(test-begin "te-pass")
(test-equal "an ordinary passing assertion" 1 1)
(thread-join! (thread-start! (make-thread (lambda () (exit 0)))))
(test-end "te-pass")
SCM

# Same, via emergency-exit.
cat > te-emergency-pass.scm <<'SCM'
(import (scheme base) (scheme process-context) (srfi 18) (srfi 64))
(test-begin "te-emergency-pass")
(test-equal "an ordinary passing assertion" 1 1)
(thread-join! (thread-start! (make-thread (lambda () (emergency-exit 0)))))
(test-end "te-emergency-pass")
SCM

# A thread's bare (exit 1) with nothing in the counts to explain it: a plain
# run exits 1, so the request must reach the ROOT VM's record — a request
# left on the child VM is one the worker never reads, and the file would
# come back green under `kaappi test`.
cat > te-bare.scm <<'SCM'
(import (scheme base) (scheme process-context) (srfi 18) (srfi 64))
(test-begin "te-bare")
(test-equal "an ordinary passing assertion" 1 1)
(thread-join! (thread-start! (make-thread (lambda () (exit 1)))))
(test-end "te-bare")
SCM

# --- the matrix -------------------------------------------------------------

assert_agree "a child thread's (exit 0) over a passing suite stays green in both runners (#2525)" te-pass.scm PASS
assert_kt_mentions "the passing suite's counts survive the thread's suppressed exit" "(1 tests"
assert_kt_lacks "a thread's suppressed exit is not a missing worker result" "worker produced no result"

assert_agree "a child thread's (emergency-exit 0) over a passing suite stays green in both runners" te-emergency-pass.scm PASS
assert_kt_lacks "a thread's suppressed emergency exit is not a missing worker result" "worker produced no result"

assert_agree "a child thread's bare (exit 1) with nothing failing is a failure in both runners" te-bare.scm FAIL
assert_kt_mentions "the thread's request reached the root VM's verdict, not a child's unread record" \
    "file requested a nonzero exit with no failing test to explain it"

echo ""
echo "thread-exit: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
