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

assert_stderr_contains() {
    local label="$1"
    local pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1 >/dev/null) || true
    if echo "$output" | grep -q "$pattern"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — stderr did not contain '$pattern'"
        echo "  got: $output"
        FAIL=$((FAIL + 1))
    fi
}

# --- only: bogus identifier ---
echo '(import (only (scheme base) totally-bogus-name))' > "$TMPDIR_TESTS/only-bogus.scm"
assert_exit_code "only: unknown identifier errors" 1 "$KAAPPI" "$TMPDIR_TESTS/only-bogus.scm"
assert_stderr_contains "only: error names the identifier" "totally-bogus-name" "$KAAPPI" "$TMPDIR_TESTS/only-bogus.scm"

# --- only: valid + bogus ---
echo '(import (only (scheme base) car totally-bogus-name))' > "$TMPDIR_TESTS/only-mixed.scm"
assert_exit_code "only: valid + unknown identifier errors" 1 "$KAAPPI" "$TMPDIR_TESTS/only-mixed.scm"

# --- only: all valid succeeds ---
echo '(import (only (scheme base) car cdr cons))' > "$TMPDIR_TESTS/only-valid.scm"
assert_exit_code "only: all valid identifiers succeeds" 0 "$KAAPPI" "$TMPDIR_TESTS/only-valid.scm"

# --- only: syntax keywords accepted ---
echo '(import (only (scheme base) define car if lambda begin))' > "$TMPDIR_TESTS/only-syntax.scm"
echo '(display (car (list 1 2)))' >> "$TMPDIR_TESTS/only-syntax.scm"
assert_exit_code "only: syntax keywords accepted" 0 "$KAAPPI" "$TMPDIR_TESTS/only-syntax.scm"

echo '(import (only (scheme case-lambda) case-lambda))' > "$TMPDIR_TESTS/only-case-lambda.scm"
echo '(display "ok")' >> "$TMPDIR_TESTS/only-case-lambda.scm"
assert_exit_code "only: case-lambda keyword accepted" 0 "$KAAPPI" "$TMPDIR_TESTS/only-case-lambda.scm"

echo '(import (only (scheme lazy) delay force make-promise))' > "$TMPDIR_TESTS/only-lazy.scm"
echo '(display "ok")' >> "$TMPDIR_TESTS/only-lazy.scm"
assert_exit_code "only: delay/force syntax accepted" 0 "$KAAPPI" "$TMPDIR_TESTS/only-lazy.scm"

echo '(import (only (srfi 9) define-record-type))' > "$TMPDIR_TESTS/only-srfi9.scm"
echo '(display "ok")' >> "$TMPDIR_TESTS/only-srfi9.scm"
assert_exit_code "only: define-record-type accepted" 0 "$KAAPPI" "$TMPDIR_TESTS/only-srfi9.scm"

# --- except: bogus identifier ---
echo '(import (except (scheme base) totally-bogus-name))' > "$TMPDIR_TESTS/except-bogus.scm"
assert_exit_code "except: unknown identifier errors" 1 "$KAAPPI" "$TMPDIR_TESTS/except-bogus.scm"
assert_stderr_contains "except: error names the identifier" "totally-bogus-name" "$KAAPPI" "$TMPDIR_TESTS/except-bogus.scm"

# --- except: syntax keyword accepted ---
echo '(import (except (scheme base) when unless))' > "$TMPDIR_TESTS/except-syntax.scm"
echo '(display "ok")' >> "$TMPDIR_TESTS/except-syntax.scm"
assert_exit_code "except: syntax keywords accepted" 0 "$KAAPPI" "$TMPDIR_TESTS/except-syntax.scm"

# --- except: valid succeeds ---
echo '(import (except (scheme base) car cdr))' > "$TMPDIR_TESTS/except-valid.scm"
assert_exit_code "except: valid identifiers succeeds" 0 "$KAAPPI" "$TMPDIR_TESTS/except-valid.scm"

# --- rename: bogus old name ---
echo '(import (rename (scheme base) (totally-bogus-name tbn)))' > "$TMPDIR_TESTS/rename-bogus.scm"
assert_exit_code "rename: unknown old name errors" 1 "$KAAPPI" "$TMPDIR_TESTS/rename-bogus.scm"
assert_stderr_contains "rename: error names the identifier" "totally-bogus-name" "$KAAPPI" "$TMPDIR_TESTS/rename-bogus.scm"

# --- rename: syntax keyword accepted ---
echo '(import (rename (scheme base) (define def)))' > "$TMPDIR_TESTS/rename-syntax.scm"
echo '(display "ok")' >> "$TMPDIR_TESTS/rename-syntax.scm"
assert_exit_code "rename: syntax keyword accepted" 0 "$KAAPPI" "$TMPDIR_TESTS/rename-syntax.scm"

# --- rename: valid succeeds ---
echo '(import (rename (scheme base) (car my-car)))' > "$TMPDIR_TESTS/rename-valid.scm"
echo '(display (my-car (list 1 2)))' >> "$TMPDIR_TESTS/rename-valid.scm"
assert_exit_code "rename: valid rename succeeds" 0 "$KAAPPI" "$TMPDIR_TESTS/rename-valid.scm"

# --- only on SRFI library ---
echo '(import (only (srfi 1) totally-bogus-name))' > "$TMPDIR_TESTS/only-srfi-bogus.scm"
assert_exit_code "only on SRFI: unknown identifier errors" 1 "$KAAPPI" "$TMPDIR_TESTS/only-srfi-bogus.scm"

# --- import filter inside define-library errors ---
cat > "$TMPDIR_TESTS/lib-filter-err.scm" << 'SCHEME'
(define-library (test lib)
  (import (except (scheme base) bogus-name))
  (export greet)
  (begin (define (greet) "hello")))
(import (test lib))
(display (greet))
SCHEME
assert_exit_code "define-library: import filter error propagates" 1 "$KAAPPI" "$TMPDIR_TESTS/lib-filter-err.scm"

# --- composed sets: prefix + only ---
echo '(import (only (prefix (scheme base) b:) b:car b:cdr))' > "$TMPDIR_TESTS/prefix-only.scm"
echo '(display (b:car (b:cdr (list 1 2 3))))' >> "$TMPDIR_TESTS/prefix-only.scm"
assert_exit_code "prefix+only: valid prefixed names succeed" 0 "$KAAPPI" "$TMPDIR_TESTS/prefix-only.scm"

echo '(import (only (prefix (scheme base) b:) car))' > "$TMPDIR_TESTS/prefix-only-bad.scm"
assert_exit_code "prefix+only: unprefixed name errors" 1 "$KAAPPI" "$TMPDIR_TESTS/prefix-only-bad.scm"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then exit 1; fi
