#!/bin/bash
# Regression test for #2510: a .sld that fails to read (a stray ")" after a
# well-formed define-library) must fail EVERY import in the process — not
# just the first. The loader dispatched the define-library form — which
# registers the library — before the reader reached the stray datum, so the
# second import's registry short-circuit used to serve the half-loaded
# library as a success. A test file that imported the library twice could
# therefore pass while every single-import consumer failed.
#
# The fix rolls the registration back on a failed load, so both attempts now
# report the same KP2001. A clean library must keep importing fine (twice),
# and a GOOD dependency nested inside the broken file stays committed — the
# rollback removes only what the failed load itself registered.
#
# The .sld fixtures are generated into a temp dir rather than committed next
# to this script: the broken ones are intentionally unparseable, and the fmt
# corpus test (tests/scheme/fmt/fmt.sh) walks every .scm/.sld under
# tests/scheme — a committed stray paren would fail it. This is the same
# convention fmt.sh and the reader-error suites use for malformed sources.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
KAAPPI_HOME_OWN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS" "$KAAPPI_HOME_OWN"' EXIT

# Hermetic home (kaappi#2352): an installed ~/.kaappi/lib must not shadow
# the fixture dir — the test must always resolve it via --lib-path.
export KAAPPI_HOME="$KAAPPI_HOME_OWN"

# The fixture root: libraries live under lib/rollback2510/*.sld so their
# (rollback2510 <name>) names map onto the sub-path the loader builds.
FIXTURES="$TMPDIR_TESTS/lib"
mkdir -p "$FIXTURES/rollback2510"

# Well-formed library + one stray trailing paren: the define-library dispatch
# (and its registration) happens before the reader reaches the extra ")".
cat > "$FIXTURES/rollback2510/broken.sld" << 'EOF'
(define-library (rollback2510 broken)
  (import (scheme base))
  (export answer)
  (begin (define (answer) 42)))
)
EOF

cat > "$FIXTURES/rollback2510/good.sld" << 'EOF'
(define-library (rollback2510 good)
  (import (scheme base))
  (export good-answer)
  (begin (define (good-answer) 42)))
EOF

# Broken file that first imports the good one: the nested load succeeds and
# must stay committed even though the outer file then fails to read.
cat > "$FIXTURES/rollback2510/broken-with-dep.sld" << 'EOF'
(define-library (rollback2510 broken-with-dep)
  (import (scheme base) (rollback2510 good))
  (export answer)
  (begin (define (answer) (good-answer))))
)
EOF

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

# Assert a program exits non-zero, reports the LibrarySourceReadError flavor
# of KP2001 exactly `want` times (one per failed import — a "library not
# found" KP2001 would mean the fixture was not even reached), and never
# printed `forbidden` (the value the half-loaded library used to leak).
assert_fails_with() {
    local label="$1" file="$2" want="$3" forbidden="$4"
    local out status=0
    out=$("$KAAPPI" --lib-path "$FIXTURES" "$file" 2>&1) || status=$?
    local kp_count=0
    kp_count=$(grep -c "LibrarySourceReadError" <<< "$out" || true)
    if [[ "$status" -eq 0 ]]; then
        fail "$label — exited 0, expected non-zero; output: $out"
        return
    fi
    if [[ "$kp_count" -ne "$want" ]]; then
        fail "$label — got $kp_count LibrarySourceReadError report(s), want exactly $want (one per failed import); output: $out"
        return
    fi
    if grep -q "library not found" <<< "$out"; then
        fail "$label — fixture did not resolve (library not found); output: $out"
        return
    fi
    if [[ -n "$forbidden" ]] && grep -q "$forbidden" <<< "$out"; then
        fail "$label — output contains '$forbidden' (partial library leaked); output: $out"
        return
    fi
    pass "$label"
}

# Assert a program exits 0 and printed the expected text.
assert_succeeds_printing() {
    local label="$1" file="$2" expected="$3"
    local out status=0
    out=$("$KAAPPI" --lib-path "$FIXTURES" "$file" 2>&1) || status=$?
    if [[ "$status" -ne 0 ]]; then
        fail "$label — exited $status, expected 0; output: $out"
        return
    fi
    if ! grep -q "$expected" <<< "$out"; then
        fail "$label — output does not contain '$expected'; output: $out"
        return
    fi
    pass "$label"
}

# --- single import of the broken library: one failure ---
cat > "$TMPDIR_TESTS/broken-once.scm" << 'EOF'
(import (rollback2510 broken))
(display "answer = ") (display (answer)) (newline)
EOF
assert_fails_with "broken .sld, single import: KP2001, non-zero exit" \
    "$TMPDIR_TESTS/broken-once.scm" 1 "42"

# --- the regression itself: double import must fail IDENTICALLY ---
# Before the fix the second import succeeded via the registry short-circuit
# and the program printed "answer = 42" after the error.
cat > "$TMPDIR_TESTS/broken-twice.scm" << 'EOF'
(import (rollback2510 broken))
(import (rollback2510 broken))
(display "answer = ") (display (answer)) (newline)
EOF
assert_fails_with "broken .sld, double import: both attempts fail KP2001" \
    "$TMPDIR_TESTS/broken-twice.scm" 2 "42"

# --- clean library: the rollback must never fire on successful loads ---
cat > "$TMPDIR_TESTS/good-twice.scm" << 'EOF'
(import (rollback2510 good))
(import (rollback2510 good))
(display "answer = ") (display (good-answer)) (newline)
EOF
assert_succeeds_printing "clean .sld, double import still works" \
    "$TMPDIR_TESTS/good-twice.scm" "answer = 42"

# --- a good dependency nested in the broken file stays committed ---
# The nested (rollback2510 good) load succeeded inside the failed outer load;
# it must remain importable afterwards (rollback is scoped to what the failed
# load itself registered). The program still exits non-zero because the first
# import's error is real and uncaught. ONE run serves both assertions —
# stderr carries the single KP2001 report, stdout the dependency's answer
# (#2518 review: previously a second run checked stdout alone).
cat > "$TMPDIR_TESTS/broken-with-dep.scm" << 'EOF'
(import (rollback2510 broken-with-dep))
(import (rollback2510 good))
(display "dep answer = ") (display (good-answer)) (newline)
EOF
dep_status=0
dep_out=$("$KAAPPI" --lib-path "$FIXTURES" "$TMPDIR_TESTS/broken-with-dep.scm" \
    2>"$TMPDIR_TESTS/broken-with-dep.err") || dep_status=$?
dep_err=$(<"$TMPDIR_TESTS/broken-with-dep.err")
dep_kp_count=0
dep_kp_count=$(grep -c "LibrarySourceReadError" <<< "$dep_err" || true)
if [[ "$dep_status" -ne 0 && "$dep_kp_count" -eq 1 ]] \
    && ! grep -q "library not found" <<< "$dep_err"; then
    pass "nested good dependency survives the failed outer load"
else
    fail "nested good dependency survives the failed outer load — exit $dep_status, $dep_kp_count KP2001 report(s); stderr: $dep_err"
fi
if grep -q "dep answer = 42" <<< "$dep_out"; then
    pass "good dependency usable after sibling rollback"
else
    fail "good dependency usable after sibling rollback — stdout: $dep_out"
fi

echo ""
echo "Library load rollback (#2510): $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
