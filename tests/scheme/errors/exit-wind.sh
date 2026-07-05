#!/bin/bash
# exit / emergency-exit semantics (R7RS 6.14) — audit Phase 2.14 (#1137).
# These terminate the process, so they can't be asserted from inside a
# Scheme test file (see tests/scheme/audit/primitives_r7rs-audit.scm).
#
#  - (exit obj):  runs outstanding dynamic-wind AFTER procedures, then
#    exits: fixnum → low byte, #f → 1, #t or absent → 0.
#  - (emergency-exit obj): same exit-code mapping but MUST NOT run the
#    dynamic-wind after procedures.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

check() {
    local label="$1" expected_status="$2" expected_out="$3" src="$4"
    local f="$TMPDIR_TESTS/prog.scm"
    printf '%s\n' "$src" > "$f"
    rm -f "$TMPDIR_TESTS/prog.sbc"
    local status=0 out
    out="$("$KAAPPI" "$f" 2>/dev/null)" || status=$?
    if [[ "$status" -eq "$expected_status" && "$out" == "$expected_out" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected_status out '$expected_out', got exit $status out '$out'"
        FAIL=$((FAIL + 1))
    fi
}

PRELUDE='(import (scheme base) (scheme process-context) (scheme write))'

# exit runs dynamic-wind afters
check "exit runs afters" 7 "AFTER" \
"$PRELUDE
(dynamic-wind (lambda () #f) (lambda () (exit 7)) (lambda () (display \"AFTER\")))"

# nested winds run in inside-out order
check "exit runs nested afters inside-out" 3 "INNER-OUTER-" \
"$PRELUDE
(dynamic-wind (lambda () #f)
  (lambda ()
    (dynamic-wind (lambda () #f)
      (lambda () (exit 3))
      (lambda () (display \"INNER-\"))))
  (lambda () (display \"OUTER-\")))"

# emergency-exit skips afters
check "emergency-exit skips afters" 9 "" \
"$PRELUDE
(dynamic-wind (lambda () #f) (lambda () (emergency-exit 9)) (lambda () (display \"AFTER\")))"

# exit code mapping
check "(exit) is 0" 0 "" "$PRELUDE (exit)"
check "(exit #t) is 0" 0 "" "$PRELUDE (exit #t)"
check "(exit #f) is 1" 1 "" "$PRELUDE (exit #f)"
check "(exit 5) is 5" 5 "" "$PRELUDE (exit 5)"
check "(emergency-exit #f) is 1" 1 "" "$PRELUDE (emergency-exit #f)"

echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
