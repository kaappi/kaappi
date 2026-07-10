#!/usr/bin/env bash
# Differential harness: bytecode VM vs LLVM native backend (issue #1395).
#
# For each seed this generates a native-subset program (kaappi-fuzz-gen
# --native; see src/fuzz_gen_native.zig for why the subset matters), runs it
# through the interpreter (kaappi prog.scm) and through the native backend
# (kaappi compile prog.scm -o prog.bin && ./prog.bin), and compares stdout
# and exit class. Divergent programs are copied into RESULTS_DIR and the
# script exits non-zero.
#
# Usage: bash tests/fuzz/native-diff.sh [N] [SEED_BASE]
#   N          number of programs (default 100)
#   SEED_BASE  first seed (default 0); seeds are BASE..BASE+N-1, and the
#              same seed always yields the same program
#
# Environment:
#   RESULTS_DIR  where divergences are written (default: ./native-diff-results)
#
# Comparison rules (rationale in docs/dev/fuzzing.md):
#   both exit 0          -> stdout must match byte-for-byte
#   both exit non-zero   -> error classes match; stdout is NOT compared (the
#                           VM reports a top-level error and continues, the
#                           native binary exits at the first error, so
#                           post-error output legitimately differs)
#   exit classes differ  -> divergence
#   either side timed out-> pair skipped (incomparable)
#
# This is process-spawn + link per input — orders of magnitude slower than
# in-process fuzzing — so it runs as a scheduled batch in CI (fuzz.yml), not
# as a std.testing.fuzz target.

set -u

N="${1:-100}"
BASE="${2:-0}"
RESULTS_DIR="${RESULTS_DIR:-native-diff-results}"

cd "$(dirname "$0")/../.." || exit 1

KAAPPI=zig-out/bin/kaappi
GEN=zig-out/bin/kaappi-fuzz-gen

[ -x "$KAAPPI" ] || zig build || exit 1
[ -f zig-out/lib/libkaappi_rt.a ] || zig build lib || exit 1
[ -x "$GEN" ] || zig build fuzz-gen || exit 1

# GNU timeout when available (Linux/CI); on macOS without coreutils the
# programs are bounded by construction, so running without one is acceptable.
TIMEOUT_CMD=""
for c in timeout gtimeout; do
  if command -v "$c" >/dev/null 2>&1; then
    TIMEOUT_CMD="$c 10"
    break
  fi
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/native-diff.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Fail fast when the native toolchain is unavailable: `kaappi compile`
# reports link/toolchain errors on stderr but still exits 0, so probe with a
# trivial program and check that the output binary actually appears.
printf '(write 42)\n(newline)\n' > "$WORK/probe.scm"
"$KAAPPI" compile "$WORK/probe.scm" -o "$WORK/probe.bin" > "$WORK/probe.log" 2>&1
if [ ! -x "$WORK/probe.bin" ]; then
  echo "native-diff: 'kaappi compile' cannot produce binaries here:" >&2
  cat "$WORK/probe.log" >&2
  exit 1
fi

divergent=0
skipped=0
compared=0

echo "native-diff: seeds $BASE..$((BASE + N - 1))"

save_divergence() {
  mkdir -p "$RESULTS_DIR"
  cp "$prog" "$RESULTS_DIR/"
  for f in vm.out vm.err nat.out nat.err compile.log; do
    [ -f "$WORK/$f" ] && cp "$WORK/$f" "$RESULTS_DIR/seed-$seed.$f"
  done
}

i=0
while [ "$i" -lt "$N" ]; do
  seed=$((BASE + i))
  i=$((i + 1))
  prog="$WORK/seed-$seed.scm"
  "$GEN" "$seed" --native > "$prog" || {
    echo "native-diff: generator failed for seed $seed" >&2
    exit 1
  }

  $TIMEOUT_CMD "$KAAPPI" "$prog" > "$WORK/vm.out" 2> "$WORK/vm.err"
  vm_exit=$?

  bin="$WORK/seed-$seed.bin"
  rm -f "$bin"
  "$KAAPPI" compile "$prog" -o "$bin" > "$WORK/compile.log" 2>&1
  if [ ! -x "$bin" ]; then
    echo "seed $seed: DIVERGENCE — native compilation failed (generated programs must always compile)" >&2
    save_divergence
    divergent=$((divergent + 1))
    continue
  fi

  $TIMEOUT_CMD "$bin" > "$WORK/nat.out" 2> "$WORK/nat.err"
  nat_exit=$?

  # 124 = timeout(1) expiry, 137 = SIGKILL after expiry: incomparable pair.
  if [ -n "$TIMEOUT_CMD" ] && { [ "$vm_exit" -eq 124 ] || [ "$vm_exit" -eq 137 ] ||
    [ "$nat_exit" -eq 124 ] || [ "$nat_exit" -eq 137 ]; }; then
    skipped=$((skipped + 1))
    rm -f "$bin" "$prog" "${prog%.scm}.sbc"
    continue
  fi

  mismatch=""
  if [ "$vm_exit" -eq 0 ] && [ "$nat_exit" -eq 0 ]; then
    cmp -s "$WORK/vm.out" "$WORK/nat.out" || mismatch="stdout differs (both exited 0)"
  elif [ "$vm_exit" -eq 0 ] || [ "$nat_exit" -eq 0 ]; then
    mismatch="exit class differs (vm=$vm_exit native=$nat_exit)"
  fi
  compared=$((compared + 1))

  if [ -n "$mismatch" ]; then
    echo "seed $seed: DIVERGENCE — $mismatch" >&2
    save_divergence
    divergent=$((divergent + 1))
  fi
  rm -f "$bin" "$prog" "${prog%.scm}.sbc"
done

echo "native-diff: $compared compared, $skipped skipped, $divergent divergent"
if [ "$divergent" -gt 0 ]; then
  echo "native-diff: divergent programs saved in $RESULTS_DIR/" >&2
  exit 1
fi
