#!/usr/bin/env bash
# Run every Scheme suite that carries a byte-order assertion, in one command.
#
#     bash tools/run-endian-suite.sh [path/to/kaappi]
#
# WHY THIS EXISTS. s390x is the project's only big-endian target and exists
# precisely to catch byte-order bugs (kaappi#1654), but `ci.yml`'s `s390x-test`
# job runs exactly three steps -- the cross-compile, `zig build test
# -Dtarget=s390x-linux`, and `tests/scheme/r7rs/r7rs-tests.scm`. It does not
# run `tests/scheme/run-all.sh`, so until this script every file below had
# executed only on little-endian hosts, where a byte-order assertion cannot
# fail. `r7rs-tests.scm` imports no SRFI with a byte-order-sensitive surface.
#
# The Zig unit suite DOES run on that leg, which is why `src/tests_endian.zig`
# holds the two pins Scheme cannot express: `%host-big-endian?` against an
# actual memory probe, and the `.sbc` codec's canonical little-endian scalars.
# This script is the Scheme half.
#
# Deliberately NOT wired into run-all.sh: every file listed here is already
# reached by run-all.sh's own suite globs, so doing both would run them twice.
# This is the entry point for hosts where run-all.sh is too heavy to run --
# which today means the three QEMU legs.
#
# Exit status is 0 only if every file exits 0. Each file is an (srfi 64) suite
# with the exit-on-fail epilogue, so a failed assertion is a nonzero exit.

set -u

# Resolve the binary against the CALLER's cwd first -- a relative argument
# means what the caller meant, not what it happens to mean after the cd below.
KAAPPI="${1:-zig-out/bin/kaappi}"
case "$KAAPPI" in
    /*) ;;
    *) KAAPPI="$PWD/$KAAPPI" ;;
esac

# Then run from the repo root regardless of where we were invoked: every path
# below is repo-relative, and so is the --lib-path passed to each run.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

if [[ ! -x "$KAAPPI" ]]; then
    echo "run-endian-suite: no executable kaappi at '$KAAPPI'" >&2
    echo "Usage: bash tools/run-endian-suite.sh [path/to/kaappi]" >&2
    exit 2
fi

# Keep the cache out of the invoking user's real KAAPPI_HOME: this script is
# also run by hand during audits, and `run-all.sh` isolates for the same reason.
if [[ -z "${KAAPPI_HOME:-}" ]]; then
    KAAPPI_HOME="$(mktemp -d)"
    export KAAPPI_HOME
    trap 'rm -rf "$KAAPPI_HOME"' EXIT
fi

# The hub written for this purpose comes first; the rest are pre-existing
# suites that carry endian-relevant assertions and had never run big-endian.
#   srfi74            blobs: explicit big/little layouts, native selection
#   srfi160/srfi4     numeric vectors: host-native element storage
#   primitives_srfi160-audit
#                     the encoder-vs-ref-vs-printer cross-decoder probe
#   srfi66/srfi63     u8vector and prototype-typed arrays over SRFI 160
#   srfi135           UTF-16BE/LE conversions
#   srfi178           bit order (spec-defined, asserted not to drift)
#   internal-primitives-audit
#                     %host-big-endian? reachability and arity
FILES=(
    tests/scheme/audit/endianness-audit.scm
    tests/scheme/srfi/srfi74.scm
    tests/scheme/srfi/srfi160.scm
    tests/scheme/srfi/srfi4.scm
    tests/scheme/srfi/srfi66.scm
    tests/scheme/srfi/srfi63.scm
    tests/scheme/srfi/srfi135.scm
    tests/scheme/srfi/srfi178-audit.scm
    tests/scheme/audit/primitives_srfi160-audit.scm
    tests/scheme/audit/internal-primitives-audit.scm
)

PASS=0
FAIL=0
MISSING=0

echo "=== Endian-sensitive Scheme suites ==="
echo "kaappi: $KAAPPI"
echo ""

for f in "${FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        # A renamed or deleted file must be loud: silently running nine of ten
        # files is exactly how tests/scheme/srfi/slow/ went unnoticed for
        # eleven days (kaappi#1900).
        echo "  MISSING  $f"
        MISSING=$((MISSING + 1))
        continue
    fi
    # --lib-path is explicit rather than relying on the exe-relative default
    # (<exe_dir>/../lib): that default reads /proc/self/exe on Linux, and the
    # QEMU legs this script exists for run the binary through binfmt_misc,
    # where that path's meaning is the emulator's business rather than ours.
    # Naming ./lib costs nothing and removes the question.
    out="$("$KAAPPI" --lib-path lib "$f" 2>&1)"
    status=$?
    if [[ $status -eq 0 ]]; then
        echo "  PASS  $f"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $f (exit $status)"
        echo "$out" | sed 's/^/        /'
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Summary: $PASS passed, $FAIL failed, $MISSING missing ==="

if [[ $FAIL -gt 0 || $MISSING -gt 0 ]]; then
    exit 1
fi
exit 0
