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
#   both exit 0             -> stdout must match byte-for-byte
#   both exit 1..127        -> ordinary-error match; stdout is NOT compared
#                              (the VM reports a top-level error and
#                              continues, the native binary exits at the
#                              first error, so post-error output
#                              legitimately differs)
#   any exit >= 128         -> divergence: 128+N is death by signal N
#                              (segfault, abort, ...), never an ordinary
#                              Scheme error on either side
#   exit classes differ     -> divergence (error on one side only)
#   compile fails/times out -> divergence (generated programs must compile)
#   either side timed out   -> pair skipped (incomparable)
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
# Compilation gets a longer budget than execution: it forks the system
# linker, and a hang there would otherwise stall the whole batch.
TIMEOUT_BIN=""
for c in timeout gtimeout; do
  if command -v "$c" >/dev/null 2>&1; then
    TIMEOUT_BIN="$c"
    break
  fi
done
RUN_TIMEOUT="${TIMEOUT_BIN:+$TIMEOUT_BIN 10}"
COMPILE_TIMEOUT="${TIMEOUT_BIN:+$TIMEOUT_BIN 60}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/native-diff.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Fail fast when the native toolchain is unavailable: probe with a trivial
# program and check that the output binary actually appears (`kaappi compile`
# exits non-zero on link/toolchain errors, but the binary check also guards
# against a compile that lies about success). The probe also warms the
# linker's compiler-rt cache, so per-seed compiles fit the tighter
# COMPILE_TIMEOUT; its own budget is generous for a cold cache.
printf '(write 42)\n(newline)\n' > "$WORK/probe.scm"
${TIMEOUT_BIN:+$TIMEOUT_BIN 300} "$KAAPPI" compile "$WORK/probe.scm" -o "$WORK/probe.bin" > "$WORK/probe.log" 2>&1
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
  # Clear per-seed transients so save_divergence can never attach a stale
  # file from an earlier seed (nat.out/nat.err are only written when the
  # compile succeeds).
  rm -f "$WORK/vm.out" "$WORK/vm.err" "$WORK/nat.out" "$WORK/nat.err" "$WORK/compile.log"
  "$GEN" "$seed" --native > "$prog" || {
    echo "native-diff: generator failed for seed $seed" >&2
    exit 1
  }

  $RUN_TIMEOUT "$KAAPPI" "$prog" > "$WORK/vm.out" 2> "$WORK/vm.err"
  vm_exit=$?

  bin="$WORK/seed-$seed.bin"
  rm -f "$bin"
  $COMPILE_TIMEOUT "$KAAPPI" compile "$prog" -o "$bin" > "$WORK/compile.log" 2>&1
  compile_exit=$?
  if [ ! -x "$bin" ]; then
    if [ -n "$TIMEOUT_BIN" ] && { [ "$compile_exit" -eq 124 ] || [ "$compile_exit" -eq 137 ]; }; then
      echo "seed $seed: DIVERGENCE — native compilation timed out" >&2
    else
      echo "seed $seed: DIVERGENCE — native compilation failed (generated programs must always compile)" >&2
    fi
    save_divergence
    divergent=$((divergent + 1))
    continue
  fi

  $RUN_TIMEOUT "$bin" > "$WORK/nat.out" 2> "$WORK/nat.err"
  nat_exit=$?

  # 124 = timeout(1) expiry, 137 = SIGKILL after expiry: incomparable pair.
  if [ -n "$TIMEOUT_BIN" ] && { [ "$vm_exit" -eq 124 ] || [ "$vm_exit" -eq 137 ] ||
    [ "$nat_exit" -eq 124 ] || [ "$nat_exit" -eq 137 ]; }; then
    skipped=$((skipped + 1))
    rm -f "$bin" "$prog" "${prog%.scm}.sbc"
    continue
  fi

  mismatch=""
  if [ "$vm_exit" -eq 0 ] && [ "$nat_exit" -eq 0 ]; then
    cmp -s "$WORK/vm.out" "$WORK/nat.out" || mismatch="stdout differs (both exited 0)"
  elif [ "$vm_exit" -ge 128 ] || [ "$nat_exit" -ge 128 ]; then
    # 128+N = killed by signal N. A segfault/abort is a crash finding even
    # when the other side also errored, so it must never be absorbed into
    # the ordinary-error match below.
    mismatch="signal-terminated exit (vm=$vm_exit native=$nat_exit)"
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
