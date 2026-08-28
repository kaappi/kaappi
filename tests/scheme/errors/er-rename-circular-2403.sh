#!/bin/bash
# #2403: `rename` on a circular macro-use datum. The five-line repro used to
# recurse until the GC root stack panicked — an uncatchable process abort.
# It must instead surface as an ordinary syntax error carrying the diagnosis
# (a transformer's own `guard` can intercept it; the uncaught case is pinned
# here), and the process must exit non-zero rather than abort or hang.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

REPRO="$TMPDIR_TESTS/circ-er.scm"
cat > "$REPRO" <<'EOF'
(import (scheme base) (srfi 211 explicit-renaming))
(define-syntax m
  (er-macro-transformer
   (lambda (form rename compare) (rename (cadr form)))))
(m #0=(zz . #0#))
EOF

output=$("$KAAPPI" "$REPRO" 2>&1 || true)

if grep -qF "rename: cannot rename a circular datum" <<< "$output"; then
    echo "PASS: uncaught circular rename reports the diagnosis"
    PASS=$((PASS + 1))
else
    echo "FAIL: expected 'rename: cannot rename a circular datum' in output:"
    echo "$output"
    FAIL=$((FAIL + 1))
fi

if grep -qF "KP2002" <<< "$output"; then
    echo "PASS: uncaught circular rename is a syntax error (KP2002)"
    PASS=$((PASS + 1))
else
    echo "FAIL: expected KP2002 in output:"
    echo "$output"
    FAIL=$((FAIL + 1))
fi

status=0
"$KAAPPI" "$REPRO" > /dev/null 2>&1 || status=$?
if [[ "$status" -ne 1 ]]; then
    echo "FAIL: expected exit 1 (uncaught syntax error), got $status — silent success, abort or signal?"
    FAIL=$((FAIL + 1))
else
    echo "PASS: exits with the ordinary uncaught-error status 1"
    PASS=$((PASS + 1))
fi

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "CIRCULAR RENAME REGRESSION DETECTED"
    exit 1
fi

echo "All circular rename tests pass."
exit 0
