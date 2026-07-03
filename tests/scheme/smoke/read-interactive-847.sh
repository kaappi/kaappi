#!/usr/bin/env bash
# Regression test for #847: (read) blocks forever on interactive terminals.
#
# The root cause was that readDatumFn drained the fd to EOF before parsing.
# We test the fix by feeding input through a pipe — if (read) still drains
# to EOF before parsing, the tests will produce wrong results or hang (caught
# by kaappi --timeout).
set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
TMPSCM=$(mktemp /tmp/kaappi-read-847-XXXXXX.scm)
trap 'rm -f "$TMPSCM"' EXIT

# --- Test 1: read returns a complete datum without waiting for EOF ---
cat > "$TMPSCM" <<'SCM'
(import (scheme base) (scheme read) (scheme write))
(display (read))
SCM
result=$(echo '42' | "$KAAPPI" --timeout 10000 "$TMPSCM")
if [ "$result" != "42" ]; then
  echo "FAIL test 1: expected '42', got '$result'"
  exit 1
fi

# --- Test 2: read returns a list datum ---
result=$(echo '(a b c)' | "$KAAPPI" --timeout 10000 "$TMPSCM")
if [ "$result" != "(a b c)" ]; then
  echo "FAIL test 2: expected '(a b c)', got '$result'"
  exit 1
fi

# --- Test 3: read returns multiple datums sequentially ---
cat > "$TMPSCM" <<'SCM'
(import (scheme base) (scheme read) (scheme write))
(display (+ (read) (read)))
SCM
result=$(printf '1\n2\n' | "$KAAPPI" --timeout 10000 "$TMPSCM")
if [ "$result" != "3" ]; then
  echo "FAIL test 3: expected '3', got '$result'"
  exit 1
fi

# --- Test 4: read returns EOF after all datums consumed ---
cat > "$TMPSCM" <<'SCM'
(import (scheme base) (scheme read) (scheme write))
(let ((v (read)))
  (display (list v (eof-object? (read)))))
SCM
result=$(echo '42' | "$KAAPPI" --timeout 10000 "$TMPSCM")
if [ "$result" != "(42 #t)" ]; then
  echo "FAIL test 4: expected '(42 #t)', got '$result'"
  exit 1
fi

# --- Test 5: whitespace before datum is skipped ---
cat > "$TMPSCM" <<'SCM'
(import (scheme base) (scheme read) (scheme write))
(display (read))
SCM
result=$(printf '   42\n' | "$KAAPPI" --timeout 10000 "$TMPSCM")
if [ "$result" != "42" ]; then
  echo "FAIL test 5: expected '42', got '$result'"
  exit 1
fi

echo "All read-interactive-847 tests passed."
