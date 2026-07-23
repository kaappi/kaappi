#!/bin/bash
# Regression test: %script-path (kaappi sysinfo, backing SRFI 59/193) must
# lexically normalize an absolute path's "."/".." segments, not just an
# already-clean one. resolveScriptPath (main.zig) special-cased the absolute
# branch to `dupe` the raw argv path unchanged, so "/tmp/x/../x/app.scm"
# reported itself as "/tmp/x/../x/app.scm" instead of "/tmp/x/app.scm" --
# the relative branch (which always joins against cwd via
# std.fs.path.resolve) never had this bug, only the absolute one did.
#
# Compares kaappi's own output for a clean path against a "../"-laden path
# to the same file, rather than asserting a hardcoded expected string:
# kaappi prints native paths (see tests/scheme/CLAUDE.md), so on Windows
# that's a backslash-separated, `write`-escaped path under a Git-Bash-
# translated temp directory -- not the "/tmp/..." this script's own $tmpdir
# spells things as. Asking kaappi for both and requiring equality sidesteps
# needing to predict its exact spelling on any given host.
#
# Only the first output line is compared: a Debug build's DebugAllocator
# reports pre-existing, unrelated leaks in main.zig's lib_paths
# auto-discovery (present on plain `kaappi trivial.scm` at the current main
# tip too -- not introduced by this test) to stderr at process exit, well
# after the script's own (write ...) line -- captured here via 2>&1 like
# every other shell test in this suite, so it must not affect the compare.

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

clean_output_raw=$("$KAAPPI" "$tmpdir/app.scm" 2>&1)
clean_output="${clean_output_raw%%$'\n'*}"

# Sanity check: the clean invocation must report a real, non-empty path
# (not #f or an error) before comparing it against the "../" invocation
# below -- otherwise both sides could vacuously agree on garbage.
case "$clean_output" in
    \"*app.scm\") ;;
    *)
        echo "FAIL: clean invocation did not report a path -- got $clean_output"
        FAIL=$((FAIL + 1))
        ;;
esac

# An absolute path containing "..": resolveScriptPath must collapse it to
# the exact same value the clean invocation above reported.
dotdot_path="$tmpdir/../$(basename "$tmpdir")/app.scm"
dotdot_output_raw=$("$KAAPPI" "$dotdot_path" 2>&1)
dotdot_output="${dotdot_output_raw%%$'\n'*}"
if [ "$dotdot_output" = "$clean_output" ]; then
    echo "PASS: absolute path with .. is lexically normalized"
    PASS=$((PASS + 1))
else
    echo "FAIL: expected $clean_output, got $dotdot_output"
    FAIL=$((FAIL + 1))
fi

echo
echo "Passed: $PASS / $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
