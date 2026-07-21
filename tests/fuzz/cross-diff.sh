#!/usr/bin/env bash
# Cross-architecture differential harness: the SAME Kaappi build on two CPU
# architectures.
#
# For each seed this generates a portable-subset program (kaappi-fuzz-gen
# --portable; see src/fuzz_gen_portable.zig for the fully-specified-subset
# rules), runs it through a HOST kaappi (native) and a TARGET kaappi (a
# different CPU arch, executed transparently via QEMU binfmt), and compares
# exit code and stdout. Divergent programs are copied into RESULTS_DIR and the
# script exits non-zero.
#
# WHY A BINARY DIFFERENTIAL AND NOT `--fuzz`: Zig 0.16's coverage-guided fuzzer
# cannot instrument a cross-compiled target — `zig build test --fuzz
# -Dtarget=s390x-linux` fails with "no fuzz tests found" — so the in-process
# targets in src/tests_fuzz.zig only ever run on the host arch (see
# docs/dev/fuzzing.md, "Cross-architecture coverage"). This harness needs only
# the `kaappi` binary to run under QEMU, which it does, so it is the portable
# way to reach non-host architectures — above all the big-endian s390x canary.
#
# WHY THIS IS A CLEAN ORACLE: both sides are the same interpreter, and the
# portable subset is deterministic and fully specified (no time/random/IO
# ordering, `eq?` only on interned symbols, no identity- or address-dependent
# output). So the two runs MUST agree byte-for-byte on stdout and agree on exit
# code; any difference is an architecture-specific bug — endianness, alignment,
# pointer width, or codegen — never unspecified behavior. This is strictly
# tighter than oracle-diff.sh's Kaappi-vs-Chibi comparison, which must tolerate
# dialect differences; here there are none to tolerate.
#
# Usage: bash tests/fuzz/cross-diff.sh [N] [SEED_BASE]
#   N          number of programs (default 100)
#   SEED_BASE  first seed (default 0); seeds are BASE..BASE+N-1, and the same
#              seed always yields the same program
#
# Environment:
#   HOST_KAAPPI    native kaappi binary  (default: zig-out/bin/kaappi-host)
#   TARGET_KAAPPI  foreign-arch kaappi   (default: zig-out/bin/kaappi; run via binfmt)
#   GEN            portable generator    (default: zig-out/bin/kaappi-fuzz-gen; HOST arch)
#   TARGET_LABEL   arch name for logs + arch.txt  (default: target)
#   RESULTS_DIR    where divergences are written (default: ./cross-diff-results)
#
# Comparison rules (both sides are the same interpreter, so this is strict):
#   any exit >= 128 on either side -> divergence: 128+N is death by signal N
#                                     (segfault, abort, ...) — an arch crash
#   exit codes differ              -> divergence (same program, same interpreter)
#   exit codes equal               -> stdout must match byte-for-byte
#   either side timed out          -> pair skipped (incomparable); the target
#                                     runs under emulation and is much slower,
#                                     so it gets a longer bound than the host
#
# Triage: a divergence is (a) an architecture-specific Kaappi bug — the common
# case, and on s390x almost always endianness (the `.sbc` codec and any
# serialization/hashing that reads multi-byte values); minimise the program
# (re-check both arches at each step), then file it with the program and both
# outputs; or (b) the generator leaking non-portable behavior — fix
# src/fuzz_gen_portable.zig. Two self-consistent-but-different arches is (a):
# the same code produced different observable output, which is the bug.

set -u

N="${1:-100}"
BASE="${2:-0}"
RESULTS_DIR="${RESULTS_DIR:-cross-diff-results}"
TARGET_LABEL="${TARGET_LABEL:-target}"

cd "$(dirname "$0")/../.." || exit 1

HOST_KAAPPI="${HOST_KAAPPI:-zig-out/bin/kaappi-host}"
TARGET_KAAPPI="${TARGET_KAAPPI:-zig-out/bin/kaappi}"
GEN="${GEN:-zig-out/bin/kaappi-fuzz-gen}"

# The generator is a host tool; build it if absent. The two kaappi binaries are
# built by the caller (the target one needs -Dtarget=, which only the workflow
# knows), so a missing binary is a setup error, not something to auto-build.
[ -x "$GEN" ] || zig build fuzz-gen || exit 1
if [ ! -x "$HOST_KAAPPI" ]; then
  echo "cross-diff: host kaappi '$HOST_KAAPPI' not found or not executable" >&2
  echo "cross-diff: build it first: zig build && cp zig-out/bin/kaappi zig-out/bin/kaappi-host" >&2
  exit 2
fi
if [ ! -x "$TARGET_KAAPPI" ]; then
  echo "cross-diff: target kaappi '$TARGET_KAAPPI' not found or not executable" >&2
  echo "cross-diff: build it first: zig build -Dtarget=<arch>-linux (and register QEMU binfmt)" >&2
  exit 2
fi

# Smoke-check that the target binary actually runs here (binfmt registered): a
# trivial program whose output is known. A target that cannot execute would
# make every seed a false "divergence", so fail loudly and early instead.
probe="$(mktemp "${TMPDIR:-/tmp}/cross-diff-probe.XXXXXX.scm")"
printf '(write (+ 1 2))(newline)\n' > "$probe"
probe_out="$("$TARGET_KAAPPI" "$probe" 2>/dev/null)"
rm -f "$probe" "${probe%.scm}.sbc"
if [ "$probe_out" != "3" ]; then
  echo "cross-diff: target kaappi '$TARGET_KAAPPI' did not run (probe printed '$probe_out', expected '3')" >&2
  echo "cross-diff: is QEMU binfmt registered for $TARGET_LABEL? (docker/setup-qemu-action)" >&2
  exit 2
fi
echo "cross-diff: host=$HOST_KAAPPI target=$TARGET_KAAPPI ($TARGET_LABEL)"

# GNU timeout when available (Linux/CI). The target runs under emulation, so it
# gets a much longer bound than the host; the portable programs are bounded by
# construction, so running without `timeout` at all is acceptable too.
TIMEOUT_BIN=""
for c in timeout gtimeout; do
  if command -v "$c" >/dev/null 2>&1; then TIMEOUT_BIN="$c"; break; fi
done
HOST_TIMEOUT="${TIMEOUT_BIN:+$TIMEOUT_BIN 10}"
TARGET_TIMEOUT="${TIMEOUT_BIN:+$TIMEOUT_BIN 120}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/cross-diff.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

divergent=0
skipped=0
compared=0

echo "cross-diff: seeds $BASE..$((BASE + N - 1))"

save_divergence() {
  mkdir -p "$RESULTS_DIR"
  printf '%s\n' "$TARGET_LABEL" > "$RESULTS_DIR/arch.txt"
  cp "$prog" "$RESULTS_DIR/"
  for f in host.out host.err target.out target.err; do
    [ -f "$WORK/$f" ] && cp "$WORK/$f" "$RESULTS_DIR/seed-$seed.$f"
  done
}

i=0
while [ "$i" -lt "$N" ]; do
  seed=$((BASE + i))
  i=$((i + 1))
  prog="$WORK/seed-$seed.scm"
  # Clear per-seed transients so save_divergence can never attach a stale file.
  rm -f "$WORK/host.out" "$WORK/host.err" "$WORK/target.out" "$WORK/target.err"
  "$GEN" "$seed" --portable > "$prog" || {
    echo "cross-diff: generator failed for seed $seed" >&2
    exit 1
  }

  $HOST_TIMEOUT "$HOST_KAAPPI" "$prog" > "$WORK/host.out" 2> "$WORK/host.err"
  h_exit=$?
  $TARGET_TIMEOUT "$TARGET_KAAPPI" "$prog" > "$WORK/target.out" 2> "$WORK/target.err"
  t_exit=$?

  # 124 = timeout(1) expiry, 137 = SIGKILL after expiry: incomparable pair.
  if [ -n "$TIMEOUT_BIN" ] && { [ "$h_exit" -eq 124 ] || [ "$h_exit" -eq 137 ] ||
    [ "$t_exit" -eq 124 ] || [ "$t_exit" -eq 137 ]; }; then
    skipped=$((skipped + 1))
    rm -f "$prog" "${prog%.scm}.sbc"
    continue
  fi

  mismatch=""
  if [ "$h_exit" -ge 128 ] || [ "$t_exit" -ge 128 ]; then
    # 128+N = killed by signal N. A segfault/abort on one arch is the finding.
    mismatch="signal-terminated exit (host=$h_exit target=$t_exit)"
  elif [ "$h_exit" -ne "$t_exit" ]; then
    mismatch="exit code differs (host=$h_exit target=$t_exit)"
  else
    cmp -s "$WORK/host.out" "$WORK/target.out" || mismatch="stdout differs (exit $h_exit on both)"
  fi
  compared=$((compared + 1))

  if [ -n "$mismatch" ]; then
    echo "seed $seed: DIVERGENCE — $mismatch" >&2
    save_divergence
    divergent=$((divergent + 1))
  fi
  rm -f "$prog" "${prog%.scm}.sbc"
done

echo "cross-diff: $compared compared, $skipped skipped, $divergent divergent"
if [ "$divergent" -gt 0 ]; then
  echo "cross-diff: divergent programs saved in $RESULTS_DIR/ ($TARGET_LABEL vs host)" >&2
  exit 1
fi
