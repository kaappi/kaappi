#!/bin/bash
# kaappi#2005: `(load "file.scm")` where file.scm begins with a top-level
# `import` must route that import through the same machinery a script or the
# REPL uses — not evaluate it as an ordinary application.
#
# Before the fix, the loaded `(import (scheme base) ...)` was compiled as a
# call: `(scheme base)` was applied and `base` looked up as a variable, so the
# load failed with an "undefined variable 'base'" error — and the error was
# attributed to the LOADER's file and line, because the loaded thunk carried no
# source name of its own. Both halves are checked here: that the import-bearing
# file loads and runs (prints "inner ok", exit 0), and that a genuinely broken
# loaded file reports the error against the LOADED file, not the loader.

set -euo pipefail

KAAPPI="${KAAPPI:-${1:-zig-out/bin/kaappi}}"

. "$(dirname "$0")/../shell-common.sh"

# `load` opens a relative path against the current working directory, so the
# test runs kaappi from inside the fixture directory. Resolve the binary to an
# absolute path first, since KAAPPI is typically relative to the repo root.
case "$KAAPPI" in
    */*) kaappi_abs="$(cd "$(dirname "$KAAPPI")" 2>/dev/null && pwd)/$(basename "$KAAPPI")" ;;
    *)   kaappi_abs="$(command -v "$KAAPPI" || true)" ;;
esac
if [ ! -x "$kaappi_abs" ]; then
    echo "FAIL: $KAAPPI is not an executable file (build first: zig build)"
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

PASS=0
FAIL=0

# --- Case 1: a loaded file whose first form is a top-level import ----------
cat > "$work/inner.scm" <<'SCM'
(import (scheme base) (scheme write))
(display "inner ok")
(newline)
SCM
cat > "$work/loader.scm" <<'SCM'
(import (scheme base) (scheme load))
(load "inner.scm")
SCM

set +e
out=$(cd "$work" && "$kaappi_abs" loader.scm 2>&1)
status=$?
set -e

if [ "$status" -eq 0 ] && printf '%s' "$out" | grep -q 'inner ok'; then
    echo "PASS: load of an import-bearing file runs it"
    PASS=$((PASS + 1))
else
    echo "FAIL: expected 'inner ok' and exit 0, got exit $status:"
    printf '%s\n' "$out"
    FAIL=$((FAIL + 1))
fi

# --- Case 2: a genuinely broken loaded file — error names the loaded file --
# The loaded file is named so that its basename is NOT a substring of the
# driver's ("bad.scm" vs "driver.scm"): before the attribution fix the error
# was reported against the driver, and a grep that also matched the driver's
# name would pass vacuously. The `(car 7)` on line 2 is the error; its import
# on line 1 must itself succeed (the same fix), so the reported line is 2.
cat > "$work/bad.scm" <<'SCM'
(import (scheme base))
(car 7)
SCM
cat > "$work/driver.scm" <<'SCM'
(import (scheme base) (scheme load))
(load "bad.scm")
SCM

set +e
berr=$(cd "$work" && "$kaappi_abs" driver.scm 2>&1)
bstatus=$?
set -e

if [ "$bstatus" -ne 0 ] && printf '%s' "$berr" | grep -q 'bad.scm:2:'; then
    echo "PASS: a broken loaded file reports its own file:line"
    PASS=$((PASS + 1))
else
    echo "FAIL: expected an error naming bad.scm:2 and non-zero exit, got exit $bstatus:"
    printf '%s\n' "$berr"
    FAIL=$((FAIL + 1))
fi

echo
echo "Passed: $PASS / $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
