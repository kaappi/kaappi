#!/bin/bash
# `kaappi test --lib-path` forwarding (kaappi#1509).
#
# The ecosystem-repo criterion: `kaappi test --lib-path <dir>` must forward the
# search path to each worker so a suite's `(import (some-lib))` resolves against
# that dir, exactly as `kaappi --lib-path <dir> tests/x.scm` does. We put the lib
# in a *non-standard* dir (`deps/`, not the cwd-relative `lib/` that kaappi
# searches by default) so a pass here proves the forwarding, not ambient
# resolution.

set -u

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
KAAPPI="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required"
    exit 1
fi

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
mkdir -p "$REPO/deps" "$REPO/tests"

cat > "$REPO/deps/widget.sld" <<'EOF'
(define-library (widget)
  (import (scheme base))
  (export widget-double)
  (begin (define (widget-double x) (* 2 x))))
EOF

cat > "$REPO/tests/test-widget.scm" <<'EOF'
(import (scheme base) (srfi 64) (widget))
(test-begin "widget")
(test-equal "double 21" 42 (widget-double 21))
(test-end "widget")
EOF

PASS=0
FAIL=0
check() { if [[ "$1" == ok ]]; then echo "PASS: $2"; PASS=$((PASS+1)); else echo "FAIL: $2"; FAIL=$((FAIL+1)); fi; }

field() { # json-stream -> "<pass> <error>" of the first file object
    python3 -c '
import json, sys
for line in sys.stdin:
    if not line.strip(): continue
    o = json.loads(line)
    if o.get("type") == "file":
        print(o.get("pass"), o.get("error")); break
'
}

cd "$REPO"

# With forwarding: (widget) resolves from deps/, the suite passes, exit 0.
OUT="$("$KAAPPI" test --lib-path ./deps --json 2>/dev/null)"; status=$?
got="$(printf '%s\n' "$OUT" | field)"
[[ "$got" == "1 False" ]] && check ok "forwarded --lib-path resolves the import (pass=1, no error)" \
    || check no "forwarded --lib-path resolves the import (got: '$got')"
[[ "$status" -eq 0 ]] && check ok "exit 0 when the forwarded suite passes" \
    || check no "exit 0 when the forwarded suite passes (status=$status)"

# Without forwarding: deps/ is not a default prefix, so (widget) is unresolved,
# the file errors, and the run exits nonzero.
OUT2="$("$KAAPPI" test ./tests --json 2>/dev/null)"; status2=$?
got2="$(printf '%s\n' "$OUT2" | field)"
[[ "$got2" == *"True" ]] && check ok "without --lib-path the import is unresolved (error=true)" \
    || check no "without --lib-path the import is unresolved (got: '$got2')"
[[ "$status2" -ne 0 ]] && check ok "exit nonzero when a file errors" \
    || check no "exit nonzero when a file errors (status=$status2)"

echo ""
echo "Passed: $PASS"
echo "Failed: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
echo "All kaappi test --lib-path tests pass."
