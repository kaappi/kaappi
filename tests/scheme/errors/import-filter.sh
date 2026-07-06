#!/bin/bash
# Import filter validation tests (#1174)
# R7RS §5.2: only/except/rename must error on identifiers not found in exports.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

assert_exit_code() {
    local label="$1"
    local expected="$2"
    shift 2
    local status=0
    "$@" > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $status"
        FAIL=$((FAIL + 1))
    fi
}

# --- only: bogus identifier ---
echo '(import (only (scheme base) totally-bogus-name))' > "$TMPDIR_TESTS/only-bogus.scm"
assert_exit_code "only: unknown identifier errors" 1 "$KAAPPI" "$TMPDIR_TESTS/only-bogus.scm"

# --- only: valid + bogus ---
echo '(import (only (scheme base) car totally-bogus-name))' > "$TMPDIR_TESTS/only-mixed.scm"
assert_exit_code "only: valid + unknown identifier errors" 1 "$KAAPPI" "$TMPDIR_TESTS/only-mixed.scm"

# --- only: all valid succeeds ---
echo '(import (only (scheme base) car cdr cons))' > "$TMPDIR_TESTS/only-valid.scm"
assert_exit_code "only: all valid identifiers succeeds" 0 "$KAAPPI" "$TMPDIR_TESTS/only-valid.scm"

# --- except: bogus identifier ---
echo '(import (except (scheme base) totally-bogus-name))' > "$TMPDIR_TESTS/except-bogus.scm"
assert_exit_code "except: unknown identifier errors" 1 "$KAAPPI" "$TMPDIR_TESTS/except-bogus.scm"

# --- except: valid succeeds ---
echo '(import (except (scheme base) car cdr))' > "$TMPDIR_TESTS/except-valid.scm"
assert_exit_code "except: valid identifiers succeeds" 0 "$KAAPPI" "$TMPDIR_TESTS/except-valid.scm"

# --- rename: bogus old name ---
echo '(import (rename (scheme base) (totally-bogus-name tbn)))' > "$TMPDIR_TESTS/rename-bogus.scm"
assert_exit_code "rename: unknown old name errors" 1 "$KAAPPI" "$TMPDIR_TESTS/rename-bogus.scm"

# --- rename: valid succeeds ---
echo '(import (rename (scheme base) (car my-car)))' > "$TMPDIR_TESTS/rename-valid.scm"
echo '(display (my-car (list 1 2)))' >> "$TMPDIR_TESTS/rename-valid.scm"
assert_exit_code "rename: valid rename succeeds" 0 "$KAAPPI" "$TMPDIR_TESTS/rename-valid.scm"

# --- only on SRFI library ---
echo '(import (only (srfi 1) totally-bogus-name))' > "$TMPDIR_TESTS/only-srfi-bogus.scm"
assert_exit_code "only on SRFI: unknown identifier errors" 1 "$KAAPPI" "$TMPDIR_TESTS/only-srfi-bogus.scm"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then exit 1; fi
