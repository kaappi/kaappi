#!/bin/bash
# Regression test: %script-path (kaappi sysinfo, backing SRFI 59/193) must
# lexically normalize an absolute path's "."/".." segments, not just an
# already-clean one. resolveScriptPath (main.zig) special-cased the absolute
# branch to `dupe` the raw argv path unchanged, so "/tmp/x/../x/app.scm"
# reported itself as "/tmp/x/../x/app.scm" instead of "/tmp/x/app.scm" --
# the relative branch (which always joins against cwd via
# std.fs.path.resolve) never had this bug, only the absolute one did.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/app.scm" <<'SCM'
(import (scheme base) (scheme write) (kaappi sysinfo))
(write (%script-path))
(newline)
SCM

# An absolute path containing "..": resolveScriptPath must collapse it.
dotdot_path="$tmpdir/../$(basename "$tmpdir")/app.scm"
output=$("$KAAPPI" "$dotdot_path" 2>&1)
expected="\"$tmpdir/app.scm\""
if [ "$output" = "$expected" ]; then
    echo "PASS: absolute path with .. is lexically normalized"
    PASS=$((PASS + 1))
else
    echo "FAIL: expected $expected, got $output"
    FAIL=$((FAIL + 1))
fi

# An already-clean absolute path must still round-trip unchanged.
output=$("$KAAPPI" "$tmpdir/app.scm" 2>&1)
if [ "$output" = "$expected" ]; then
    echo "PASS: an already-clean absolute path is unchanged"
    PASS=$((PASS + 1))
else
    echo "FAIL: expected $expected, got $output"
    FAIL=$((FAIL + 1))
fi

echo
echo "Passed: $PASS / $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
