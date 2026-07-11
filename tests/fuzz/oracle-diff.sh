#!/usr/bin/env bash
# Differential harness: Kaappi vs an external reference Scheme (issue #1396).
#
# For each seed this generates a portable-subset program (kaappi-fuzz-gen
# --portable; see src/fuzz_gen_portable.zig for the fully-specified-subset
# rules), runs it through Kaappi (kaappi prog.scm) and through the pinned
# oracle (chibi-scheme prog.scm), and compares stdout and exit class.
# Divergent programs are copied into RESULTS_DIR (with the oracle version
# recorded alongside) and the script exits non-zero.
#
# The oracle is Chibi Scheme under its default invocation: the generated
# programs open with an explicit (import (scheme base) (scheme char)
# (scheme lazy) (scheme write)), so no dialect flags are needed — unlike,
# say, Guile, which would need R7RS mode selected explicitly. Install it
# with `brew install chibi-scheme` (or build from source — Ubuntu noble's
# apt ships 0.9.1 which is too old, #1429), or point CHIBI at a specific
# binary to pin a version exactly.
#
# Usage: bash tests/fuzz/oracle-diff.sh [N] [SEED_BASE]
#   N          number of programs (default 100)
#   SEED_BASE  first seed (default 0); seeds are BASE..BASE+N-1, and the
#              same seed always yields the same program
#
# Environment:
#   RESULTS_DIR  where divergences are written (default: ./oracle-diff-results)
#   CHIBI        oracle binary (default: chibi-scheme from PATH)
#
# Comparison rules (rationale in docs/dev/fuzzing.md):
#   both exit 0             -> stdout must match byte-for-byte (programs
#                              print every observable explicitly with
#                              `write`, so stdout IS the normalized value)
#   both exit 1..127        -> "raises" class match; stdout is NOT compared
#                              (Kaappi reports a top-level error and
#                              continues with the next form, Chibi stops at
#                              the first error, so post-error output
#                              legitimately differs). Error message text is
#                              never compared. Portable programs are total
#                              by construction, so any error at all is
#                              worth a look even when the classes match.
#   any exit >= 128         -> divergence: 128+N is death by signal N
#                              (segfault, abort, ...), never an ordinary
#                              Scheme error on either side
#   exit classes differ     -> divergence ("raises" vs "returns")
#   either side timed out   -> pair skipped (incomparable)
#
# Triage protocol — a divergence is one of:
#   (a) a Kaappi bug: minimise the program (keep re-checking both sides),
#       write the expected behavior from the R7RS spec
#       (docs/errata-corrected-r7rs.pdf), and file it with the program,
#       both outputs, and the recorded oracle version;
#   (b) an oracle (Chibi) bug: verify against the spec text first, then a
#       third implementation (e.g. Gauche) as a tie-breaker; report
#       upstream and, if it recurs, exclude the triggering form from the
#       portable generator with a comment naming the Chibi issue;
#   (c) the generator leaking unspecified behavior (evaluation order,
#       exactness, non-ASCII, library boundaries, printing edges): fix
#       src/fuzz_gen_portable.zig — its module doc lists the rule each
#       construct must satisfy.
# Check the spec BEFORE filing: both implementations being self-consistent
# but different usually means (c).
#
# Each input is generate + two interpreter runs (fast; no linking), but it
# still shells out per program — run it as a scheduled batch (fuzz.yml), not
# as a std.testing.fuzz target.

set -u

N="${1:-100}"
BASE="${2:-0}"
RESULTS_DIR="${RESULTS_DIR:-oracle-diff-results}"
CHIBI="${CHIBI:-chibi-scheme}"

cd "$(dirname "$0")/../.." || exit 1

KAAPPI=zig-out/bin/kaappi
GEN=zig-out/bin/kaappi-fuzz-gen

[ -x "$KAAPPI" ] || zig build || exit 1
[ -x "$GEN" ] || zig build fuzz-gen || exit 1

if ! command -v "$CHIBI" >/dev/null 2>&1; then
  echo "oracle-diff: oracle '$CHIBI' not found on PATH" >&2
  echo "oracle-diff: install it (apt-get install chibi-scheme | brew install chibi-scheme) or set CHIBI" >&2
  exit 2
fi
# Pinning is per-version + per-invocation: record what actually ran so a
# divergence artifact is reproducible even after the host upgrades Chibi.
CHIBI_VERSION=$("$CHIBI" -V 2>/dev/null | head -n 1)
echo "oracle-diff: oracle: $CHIBI_VERSION"

# GNU timeout when available (Linux/CI); on macOS without coreutils the
# programs are bounded by construction, so running without one is acceptable.
TIMEOUT_BIN=""
for c in timeout gtimeout; do
  if command -v "$c" >/dev/null 2>&1; then
    TIMEOUT_BIN="$c"
    break
  fi
done
RUN_TIMEOUT="${TIMEOUT_BIN:+$TIMEOUT_BIN 10}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/oracle-diff.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

divergent=0
skipped=0
compared=0

echo "oracle-diff: seeds $BASE..$((BASE + N - 1))"

save_divergence() {
  mkdir -p "$RESULTS_DIR"
  printf '%s\n' "$CHIBI_VERSION" > "$RESULTS_DIR/oracle-version.txt"
  cp "$prog" "$RESULTS_DIR/"
  for f in kaappi.out kaappi.err chibi.out chibi.err; do
    [ -f "$WORK/$f" ] && cp "$WORK/$f" "$RESULTS_DIR/seed-$seed.$f"
  done
}

i=0
while [ "$i" -lt "$N" ]; do
  seed=$((BASE + i))
  i=$((i + 1))
  prog="$WORK/seed-$seed.scm"
  # Clear per-seed transients so save_divergence can never attach a stale
  # file from an earlier seed.
  rm -f "$WORK/kaappi.out" "$WORK/kaappi.err" "$WORK/chibi.out" "$WORK/chibi.err"
  "$GEN" "$seed" --portable > "$prog" || {
    echo "oracle-diff: generator failed for seed $seed" >&2
    exit 1
  }

  $RUN_TIMEOUT "$KAAPPI" "$prog" > "$WORK/kaappi.out" 2> "$WORK/kaappi.err"
  k_exit=$?
  $RUN_TIMEOUT "$CHIBI" "$prog" > "$WORK/chibi.out" 2> "$WORK/chibi.err"
  c_exit=$?

  # 124 = timeout(1) expiry, 137 = SIGKILL after expiry: incomparable pair.
  if [ -n "$TIMEOUT_BIN" ] && { [ "$k_exit" -eq 124 ] || [ "$k_exit" -eq 137 ] ||
    [ "$c_exit" -eq 124 ] || [ "$c_exit" -eq 137 ]; }; then
    skipped=$((skipped + 1))
    rm -f "$prog" "${prog%.scm}.sbc"
    continue
  fi

  mismatch=""
  if [ "$k_exit" -eq 0 ] && [ "$c_exit" -eq 0 ]; then
    cmp -s "$WORK/kaappi.out" "$WORK/chibi.out" || mismatch="stdout differs (both exited 0)"
  elif [ "$k_exit" -ge 128 ] || [ "$c_exit" -ge 128 ]; then
    # 128+N = killed by signal N. A segfault/abort is a crash finding even
    # when the other side also errored, so it must never be absorbed into
    # the raises-class match below.
    mismatch="signal-terminated exit (kaappi=$k_exit chibi=$c_exit)"
  elif [ "$k_exit" -eq 0 ] || [ "$c_exit" -eq 0 ]; then
    mismatch="exit class differs (kaappi=$k_exit chibi=$c_exit): one raises, one returns"
  fi
  compared=$((compared + 1))

  if [ -n "$mismatch" ]; then
    echo "seed $seed: DIVERGENCE — $mismatch" >&2
    save_divergence
    divergent=$((divergent + 1))
  fi
  rm -f "$prog" "${prog%.scm}.sbc"
done

echo "oracle-diff: $compared compared, $skipped skipped, $divergent divergent"
if [ "$divergent" -gt 0 ]; then
  echo "oracle-diff: divergent programs saved in $RESULTS_DIR/ — see the triage protocol in this script's header" >&2
  exit 1
fi
