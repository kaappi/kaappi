#!/bin/bash
# `kaappi test --jobs N` parallel execution.
#
# Every test file is already its own worker process, so running several at once
# is a scheduling change, not a semantic one. That is exactly what this test
# pins down: for the same fixture set, `--jobs 1` and `--jobs 4` must produce
# byte-identical output once the timing fields are normalised away — same
# verdicts, same per-file ordering, same summary counts.
#
# Ordering is the interesting half. Workers finish out of order (the fixtures
# below are deliberately staggered so they do), and the orchestrator reports the
# completed prefix in file order rather than in completion order. A regression
# that reported files as they landed would still produce correct totals, so
# totals alone would not catch it — the full transcript comparison would.
#
# Fixtures live in a temp dir so an intentionally-failing suite never pollutes a
# plain `kaappi test ./tests` run of the repo.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
KAAPPI="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# Keep the workers off the developer's real bytecode cache and history.
export KAAPPI_HOME="$FIX/home"
mkdir -p "$KAAPPI_HOME"

# Six suites with staggered work, so completion order will not match file order
# under any concurrency > 1. `a` is the slowest and sorts first, which is the
# case that catches a reporter that emits in completion order.
make_suite() {
    local name="$1" spin="$2" extra="$3"
    cat > "$FIX/$name.scm" <<EOF
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "$name")
(test-equal "identity" 1 1)
;; Burn a little time so the suites finish out of order.
(test-assert "spin" (let loop ((i 0) (acc 0))
                      (if (>= i $spin) #t (loop (+ i 1) (+ acc i)))))
$extra
(let ((r (test-runner-current)))
  (test-end "$name")
  (when (> (test-runner-fail-count r) 0) (exit 1)))
EOF
}

make_suite a 400000 ''
make_suite b 1000   ''
make_suite c 1000   ''
make_suite d 200000 ''
make_suite e 1000   ''
# One genuinely failing suite: the failure path must survive parallelism too,
# and must be attributed to the right file.
make_suite f 1000 '(test-equal "deliberate failure" 1 2)'

# Normalise the two things that legitimately differ run to run: per-file and
# total durations. Everything else must match exactly.
normalise() {
    sed -E 's/[0-9]+(\.[0-9]+)?ms/DURms/g' "$1"
}

run_jobs() {
    local n="$1" out="$2"
    set +e
    "$KAAPPI" test --jobs "$n" --seed 7 "$FIX" > "$out" 2>"$out.err"
    echo $? > "$out.rc"
    set -e
}

run_jobs 1 "$FIX/j1"
run_jobs 4 "$FIX/j4"

rc1="$(cat "$FIX/j1.rc")"
rc4="$(cat "$FIX/j4.rc")"

# The fixture set contains a failing suite, so a correct run exits nonzero.
if [[ "$rc1" == "0" ]]; then
    echo "FAIL: expected nonzero exit with a failing suite present (--jobs 1)"
    cat "$FIX/j1"
    exit 1
fi
if [[ "$rc1" != "$rc4" ]]; then
    echo "FAIL: exit status differs by job count: --jobs 1 => $rc1, --jobs 4 => $rc4"
    exit 1
fi

normalise "$FIX/j1" > "$FIX/j1.norm"
normalise "$FIX/j4" > "$FIX/j4.norm"

if ! diff -u "$FIX/j1.norm" "$FIX/j4.norm" > "$FIX/diff"; then
    echo "FAIL: --jobs 4 output differs from --jobs 1 (verdicts or ordering changed)"
    cat "$FIX/diff"
    exit 1
fi

# Guard the guard: if the transcript ever stops naming files, the diff above
# would compare two equally empty things and pass vacuously.
for suite in a b c d e f; do
    if ! grep -q "$suite.scm" "$FIX/j1.norm"; then
        echo "FAIL: transcript does not mention $suite.scm — comparison would be vacuous"
        cat "$FIX/j1.norm"
        exit 1
    fi
done

# The failing suite must be reported as the failure, under both job counts.
if ! grep -E "^  FAIL  .*/f\.scm" "$FIX/j4.norm" > /dev/null; then
    echo "FAIL: f.scm not reported as the failing file under --jobs 4"
    cat "$FIX/j4.norm"
    exit 1
fi

# Files must appear in sorted order, not completion order. `a` is the slowest,
# so under concurrency it finishes last while still having to print first.
order="$(grep -oE '[a-f]\.scm' "$FIX/j4.norm" | sed 's/\.scm$//' | tr -d '\n')"
if [[ "$order" != "abcdef" ]]; then
    echo "FAIL: files reported in '$order', expected sorted order 'abcdef'"
    cat "$FIX/j4.norm"
    exit 1
fi

# --jobs must validate its argument rather than silently defaulting.
set +e
"$KAAPPI" test --jobs 0 "$FIX" > "$FIX/bad" 2>&1
bad_rc=$?
set -e
if [[ $bad_rc -eq 0 ]]; then
    echo "FAIL: --jobs 0 was accepted"
    exit 1
fi
if ! grep -q "positive integer" "$FIX/bad"; then
    echo "FAIL: --jobs 0 did not explain itself: $(cat "$FIX/bad")"
    exit 1
fi

echo "PASS: kaappi test --jobs produces identical results and ordering"
