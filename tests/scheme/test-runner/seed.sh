#!/bin/bash
# `kaappi test --seed` reproducibility tests (kaappi#1509).
#
# --seed N seeds SRFI-27's default random source deterministically, so the same
# seed reproduces the same draws; the effective seed is printed on every run so
# any failure can be replayed. We observe the drawn value *through the JSON*: a
# fixture forces a failure whose `actual` field is the number it drew, so same
# seed => same actual, different seed => (almost surely) different actual.

# No `set -e`: the draw fixture fails on purpose, so `kaappi test` exits nonzero
# by design — we read its JSON, we don't treat the exit as a script error.
set -u

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required to validate kaappi test --seed output"
    exit 1
fi

KAAPPI="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# The test always fails; its `actual` value is the random number drawn, so the
# JSON exposes the draw for comparison across runs.
cat > "$FIX/draw.scm" <<'EOF'
(import (scheme base) (srfi 27) (srfi 64))
(test-begin "draw-suite")
(test-equal "draw" 'sentinel (random-integer 1000000000))
(test-end "draw-suite")
EOF

# actual-of SEED  ->  the drawn value from the single failure's `actual` field
actual_of() {
    local seed="$1"
    "$KAAPPI" test --json --seed "$seed" "$FIX" 2>/dev/null | python3 -c '
import json, sys
for line in sys.stdin:
    if not line.strip(): continue
    o = json.loads(line)
    if o.get("type") == "file" and o.get("failures"):
        print(o["failures"][0]["actual"]); break
'
}

PASS=0
FAIL=0
check() { # cond label
    if [[ "$1" == "ok" ]]; then echo "PASS: $2"; PASS=$((PASS+1)); else echo "FAIL: $2"; FAIL=$((FAIL+1)); fi
}

A1="$(actual_of 12345)"
A2="$(actual_of 12345)"
B1="$(actual_of 67890)"

[[ -n "$A1" ]] && check ok "seeded run produces a draw" || check no "seeded run produces a draw ($A1)"
[[ "$A1" == "$A2" ]] && check ok "same seed => same draw ($A1)" || check no "same seed => same draw ($A1 vs $A2)"
[[ "$A1" != "$B1" ]] && check ok "different seed => different draw ($A1 vs $B1)" || check no "different seed => different draw (both $A1)"

# The effective seed must be printed on every run (to stderr), pinned or not.
SEED_LINE="$("$KAAPPI" test --seed 12345 "$FIX" 2>&1 1>/dev/null | grep -c 'seed 12345' || true)"
[[ "$SEED_LINE" -ge 1 ]] && check ok "pinned seed echoed on stderr" || check no "pinned seed echoed on stderr"

DEFAULT_SEED="$("$KAAPPI" test "$FIX" 2>&1 1>/dev/null | grep -Ec 'seed [0-9]+' || true)"
[[ "$DEFAULT_SEED" -ge 1 ]] && check ok "auto seed echoed on stderr (default run)" || check no "auto seed echoed on stderr"

echo ""
echo "Passed: $PASS"
echo "Failed: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
echo "All kaappi test --seed tests pass."
