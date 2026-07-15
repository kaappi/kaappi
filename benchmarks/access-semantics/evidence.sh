#!/usr/bin/env bash
# Vectorization-evidence pass for the P1 access-semantics experiment
# (memo §9.1 "baseline validity first"). For every (kernel, encoding) it
# compiles the kernel .ll through Kaappi's exact `zig cc -w -O2` pipeline and
# classifies kernel_run's machine code as VECTOR / LIBCALL(memset|memcpy) /
# SCALAR from the disassembly (the authoritative evidence -- generated IR has no
# source locations, so positive `-Rpass=loop-vectorize` remarks are suppressed;
# the negative `-Rpass-missed` "loop not vectorized" line is captured as
# corroboration for the atomic encodings).
#
# A kernel is "ceiling-validated" (memo §9.1) iff its PLAIN build is VECTOR or
# LIBCALL -- i.e. the pipeline actually found a fast path for the baseline. Only
# ceiling-validated kernels carry the pre-registered <10% criterion.
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-zig cc}"
OUTDIR="${1:-results}"
mkdir -p "$OUTDIR" obj

# Prefer llvm-objdump (uniform across both reference machines); fall back to
# system objdump. -dr annotates call relocations with the target symbol, so a
# memset/memcpy libcall is visible by name even in an unlinked .o.
OBJDUMP=""
for cand in llvm-objdump /opt/homebrew/opt/llvm/bin/llvm-objdump objdump; do
  if command -v "$cand" >/dev/null 2>&1; then OBJDUMP="$cand"; break; fi
done
[ -n "$OBJDUMP" ] || { echo "no objdump found" >&2; exit 1; }

arch="$(uname -m)"
# The genuine-vectorization signal is *lane-suffixed arithmetic* or a *vector
# store* -- NOT a bare vector load. A strict f64 reduction (f64_sum) uses vector
# loads (`ldp q`) to fetch 4 doubles at a time but adds them with scalar `fadd
# d0` in source order; that is the memo §9.2 "drops out" case and must classify
# SCALAR, so vector loads deliberately do not count. On x86 scalar f64 uses
# `movsd`/`movss` (xmm), so only *packed* moves (`movup[sd]`/`movdq[ua]`) and
# 256/512-bit `ymm`/`zmm` count -- bare `%xmm` alone does not.
case "$arch" in
  arm64|aarch64)
    VEC_RE='((add|sub|mul|fadd|fsub|fmul|fmla|fmls|fdiv|addp|uaddlp|saddlp)\.[0-9]+(d|s|h|b)\b|\bstp[[:space:]]+q|\bstr[[:space:]]+q|\bst[1-4][[:space:]])';;
  x86_64|amd64)
    VEC_RE='(padd[bwdq]?|psub[bwdq]?|pmull?[wdq]?|addp[sd]|subp[sd]|mulp[sd]|divp[sd]|vpadd|vaddp[sd]|vsubp[sd]|vmulp[sd]|vfmadd|vfmsub|%ymm|%zmm|movup[sd]|movap[sd]|movdq[ua]|vmovup[sd]|vmovap[sd]|vmovdq[ua])';;
  *) VEC_RE='(\.2d|\.4s|%ymm|%zmm|movup[sd])';;
esac

out_csv="$OUTDIR/evidence-$(uname -s | tr '[:upper:]' '[:lower:]')-${arch}.csv"
echo "kernel,encoding,class,vector_ops,libcall" > "$out_csv"
report="$OUTDIR/evidence-$(uname -s | tr '[:upper:]' '[:lower:]')-${arch}.txt"
: > "$report"

python3 gen_kernels.py >/dev/null

classify() {
  local ll="$1" base="$2"
  $CC -w -O2 -c "$ll" -o "obj/${base}.ev.o"
  # Each kernel object holds exactly one function (kernel_run), so classify the
  # whole disassembly. -dr annotates call relocations with their target symbol,
  # so a memset/memcpy/memset_pattern libcall is named even in an unlinked .o.
  local dis; dis="$($OBJDUMP -dr "obj/${base}.ev.o" 2>/dev/null)"
  local libcall=""
  if printf '%s\n' "$dis" | grep -qiE 'memset|memset_pattern'; then libcall="memset"; fi
  if printf '%s\n' "$dis" | grep -qiE 'memcpy|memmove'; then libcall="${libcall:+$libcall+}memcpy"; fi
  local vops; vops="$(printf '%s\n' "$dis" | grep -icE "$VEC_RE" || true)"
  local class
  if [ -n "$libcall" ]; then class="LIBCALL"
  elif [ "$vops" -gt 0 ]; then class="VECTOR"
  else class="SCALAR"; fi
  echo "$class|$vops|$libcall"
}

for name in f64_fill f64_map f64_sum i64_checksum u8_fill u8_copy; do
  for enc in plain unordered monotonic; do
    base="${name}_${enc}"
    res="$(classify "kernels/${base}.ll" "$base")"
    class="${res%%|*}"; rest="${res#*|}"; vops="${rest%%|*}"; libcall="${rest#*|}"
    echo "${name},${enc},${class},${vops},${libcall}" >> "$out_csv"
    {
      echo "### ${name} / ${enc}: ${class} (vector_ops=${vops}${libcall:+, libcall=$libcall})"
      $CC -w -O2 -Rpass-missed=loop-vectorize -c "kernels/${base}.ll" -o /dev/null 2>&1 \
        | grep -i 'not vectorized' | head -1 | sed 's/^/    remark: /' || true
      echo
    } >> "$report"
  done
done

echo "== evidence ($arch) =="
column -s, -t "$out_csv"
echo
echo "wrote $out_csv and $report"
