#!/bin/bash
# Regression test for #1523: a from-source build (`zig build`, no installer,
# no ~/.kaappi/lib) must resolve portable SRFI .sld libraries when the
# binary is invoked from a directory unrelated to the source checkout, with
# no --lib-path. build.zig installs lib/ into zig-out/lib/ next to the exe,
# and main.zig adds <exe_dir>/../lib as a fallback search path
# (kaappi_paths.getExeRelativeLibDir) so the two line up.
#
# The cwd must actually change to an unrelated directory (not just point
# the script argument elsewhere) — resolveLibraryPath's cwd-relative "" and
# "lib/" prefixes are checked before any search path, and this repo's own
# checkout has a lib/srfi/151.sld that would otherwise mask a broken fix.

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

# Runs the isolated binary with cwd = $TMPDIR_TESTS/elsewhere, a fake empty
# HOME, and no --lib-path.
run_isolated() {
    (cd "$TMPDIR_TESTS/elsewhere" && \
        env -u KAAPPI_HOME -u KAAPPI_LIB_DIR HOME="$TMPDIR_TESTS/emptyhome" \
        "$TMPDIR_TESTS/dist/bin/kaappi" portable-srfi.scm)
}

assert_isolated_exit() {
    local label="$1" expected="$2"
    local status=0
    run_isolated > "$TMPDIR_TESTS/out.txt" 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $status"
        cat "$TMPDIR_TESTS/out.txt"
        FAIL=$((FAIL + 1))
    fi
}

KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
SRC_LIB_DIR="$(dirname "$KAAPPI_ABS")/../lib"

if [[ ! -f "$SRC_LIB_DIR/srfi/151.sld" ]]; then
    echo "SKIP: exe-relative-lib-1523 (no $SRC_LIB_DIR/srfi/151.sld — rebuild with 'zig build')"
    exit 0
fi

# Isolated distribution layout: <dist>/bin/kaappi + <dist>/lib/... , mirroring
# both a `zig build` tree and an installed release.
mkdir -p "$TMPDIR_TESTS/dist/bin" "$TMPDIR_TESTS/elsewhere" "$TMPDIR_TESTS/emptyhome"
cp "$KAAPPI_ABS" "$TMPDIR_TESTS/dist/bin/kaappi"
cp -r "$SRC_LIB_DIR" "$TMPDIR_TESTS/dist/lib"

cat > "$TMPDIR_TESTS/elsewhere/portable-srfi.scm" <<'SCM'
(import (scheme base) (scheme write) (srfi 151))
(display (bitwise-ior 1 2))
(newline)
SCM

# The exact repro from #1523: cwd outside the checkout, HOME pointed at an
# empty directory (so ~/.kaappi/lib can't mask the failure), no --lib-path.
assert_isolated_exit "portable SRFI resolves via exe-relative lib/ with no --lib-path" 0

if grep -q "^3$" "$TMPDIR_TESTS/out.txt"; then
    echo "PASS: (bitwise-ior 1 2) prints 3"
    PASS=$((PASS + 1))
else
    echo "FAIL: unexpected output for (bitwise-ior 1 2)"
    cat "$TMPDIR_TESTS/out.txt"
    FAIL=$((FAIL + 1))
fi

# Negative control: the same isolated binary with no sibling lib/ at all
# must fail the same way the bug report did, proving the positive case above
# actually exercises the exe-relative fallback rather than some other path.
# The .sbc bytecode cache from the run above would otherwise let this load
# straight from cached bytecode without re-resolving the library — delete it
# first so the negative control genuinely re-imports (srfi 151).
rm -rf "$TMPDIR_TESTS/dist/lib"
rm -f "$TMPDIR_TESTS/elsewhere/portable-srfi.sbc"
assert_isolated_exit "portable SRFI import fails without a sibling lib/" 1

echo ""
echo "$PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
