#!/bin/bash
# Regression test for #2097: an untracked file must not mark the git build id
# `-dirty`. The build id (build.zig gitBuildId) folds into the .sbc compiler
# hash, so a dirty flip silently invalidates every `.sbc` and bundled binary
# built moments earlier — an untracked test file did exactly that, and the
# -Dbundle tests failed with "invalid embedded bytecode" (kaappi#1930).
#
# The contract is observed end-to-end, through `kaappi features --json` on
# freshly built binaries, in three phases:
#   A  pristine tree          -> build id "<hash>"
#   B  + an untracked file    -> build id still "<hash>"        (the regression)
#   C  + that file staged     -> build id "<hash>-dirty"
#
# Each build goes into its own isolated prefix, never touching zig-out/ (the
# binary under test, kaappi#2163). Requires a pristine tree: with any tracked
# or untracked change already present the three phases are indistinguishable,
# so the script skips rather than assert garbage.
#
# This lives in the cache suite, not compile/, on purpose: phase C stages a
# file in the shared working tree, which flips the build id for any OTHER
# concurrent builder — exactly the kaappi#1930 mismatch class. run-all.sh
# runs the shell suites sequentially, Cache after Compile, so here it runs
# alone (the two cache-suite siblings never rebuild) with the ReleaseSafe
# units the compile suite just warmed; in compile/ it raced the -Dbundle
# scripts and 2156's interp-then-bundler builds (and timed out 700/703).
#
# Usage: bash tests/scheme/cache/build-id-untracked-2097.sh [path-to-kaappi]

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "rebuilds the interpreter on this machine (kaappi#1613)"
skip_without_zig "rebuilds the interpreter on this machine"

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
PROBE="$REPO_DIR/.kaappi-buildid-probe-2097"

git -C "$REPO_DIR" rev-parse --short HEAD > /dev/null 2>&1 \
    || { echo "SKIP: not a git checkout — build id is always \"unknown\" here"; exit 77; }
if [[ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null || true)" ]]; then
    echo "SKIP: working tree is not pristine — build-id dirty-state isolation is unobservable"
    exit 77
fi

DIR=$(mktemp -d)
cleanup() {
    # Unstage and remove the probe so a failed run leaves no trace.
    git -C "$REPO_DIR" reset -q -- "$PROBE" 2>/dev/null || true
    rm -f "$PROBE"
    rm -rf "$DIR"
}
trap cleanup EXIT INT TERM

# build_id <prefix>: the git build id baked into the binary at that prefix.
build_id() {
    ( "$1/bin/kaappi" features --json 2>/dev/null \
        | sed -n 's/.*"build_id":"\([^"]*\)".*/\1/p' ) || true
}

fail() {
    echo "FAIL: $1" >&2
    shift
    for line in "$@"; do echo "  $line"; done
    exit 1
}

# A: pristine tree — a clean build id, no -dirty suffix.
(cd "$REPO_DIR" && zig build -Doptimize=ReleaseSafe --prefix "$DIR/a") > /dev/null 2>&1 \
    || fail "zig build failed (phase A)"
ID_A=$(build_id "$DIR/a")
[[ -n "$ID_A" ]] || fail "phase A produced no build id" "is the binary executable?"
[[ "$ID_A" != *-dirty ]] || fail "pristine tree build id is unexpectedly dirty" "got '$ID_A'"

# B: an untracked file appears — must NOT flip the id (the kaappi#2097 bug:
# git status --porcelain counted it, so the id silently became <hash>-dirty).
echo probe > "$PROBE"
(cd "$REPO_DIR" && zig build -Doptimize=ReleaseSafe --prefix "$DIR/b") > /dev/null 2>&1 \
    || fail "zig build failed (phase B)"
ID_B=$(build_id "$DIR/b")
[[ "$ID_B" == "$ID_A" ]] \
    || fail "untracked file changed the build id: '$ID_A' -> '$ID_B'" \
            "an untracked file must not mark the tree dirty (kaappi#2097)"

# C: staging the same file IS a tracked change — the id must flip to -dirty.
git -C "$REPO_DIR" add -- "$PROBE"
(cd "$REPO_DIR" && zig build -Doptimize=ReleaseSafe --prefix "$DIR/c") > /dev/null 2>&1 \
    || fail "zig build failed (phase C)"
ID_C=$(build_id "$DIR/c")
[[ "$ID_C" == "${ID_A}-dirty" ]] \
    || fail "staged file did not mark the build id dirty" \
            "expected '${ID_A}-dirty', got '$ID_C'"

echo "PASS: untracked file keeps build id '$ID_A'; staging it flips to '$ID_C'"
