#!/bin/bash
# Crash-reporting panic handler tests (kaappi#1514, part of epic #1503).
#
# `--panic-test[=<stage>]` is an internal, undocumented hook that deliberately
# panics. It exists so CI can verify the crash banner the *shipped* build prints
# in front of the standard Zig panic — the whole reason it is not Debug-gated is
# that this suite runs against the default ReleaseSafe binary (the build mode the
# banner names), which is exactly the path a real user hits.
#
# We assert: the identity line, the version/target/build-mode line, the pipeline
# breadcrumb (and that it tracks the stage), the report URL, that the standard
# panic message + stack trace still follow the banner, and that the process dies
# by signal (abort), not a clean exit.

set -uo pipefail   # NOT -e: --panic-test aborts (nonzero) by design.

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

pass=0
fail=0
# check "label" <0-if-ok-else-nonzero>
check() {
    if [[ "$2" -eq 0 ]]; then
        echo "PASS: $1"; pass=$((pass + 1))
    else
        echo "FAIL: $1"; fail=$((fail + 1))
    fi
}
ok() { [[ "$1" -eq 0 ]] && echo 0 || echo 1; }

# ── Default (executing) stage ────────────────────────────────────────────
out="$("$KAAPPI" --panic-test 2>&1)"
status=$?

# abort() dies by signal → shell status is 128+signo (134 for SIGABRT). Assert
# "died by signal" rather than a specific number so it stays portable.
check "aborts (died by signal, not a clean exit)" "$(ok "$([[ $status -ge 128 ]] && echo 0 || echo 1)")"

grep -qF "kaappi internal error — this is a bug in kaappi, not in your program." <<<"$out"
check "banner identity line" $?

grep -qE "^  version: v[0-9]+\.[0-9]+\.[0-9]+ \(.+-.+, (Debug|ReleaseSafe|ReleaseFast|ReleaseSmall)\)$" <<<"$out"
check "version/target/build-mode line" $?

grep -qE "^  while:   executing <panic-test>$" <<<"$out"
check "breadcrumb while line (default = executing)" $?

grep -qF "report:  https://github.com/kaappi/kaappi/issues/new" <<<"$out"
check "report URL line" $?

# The standard panic message + trace must survive in front of which the banner is
# printed — the trace is the valuable part and must not be swallowed.
grep -qF "panic: deliberate panic" <<<"$out"
check "standard panic message retained" $?

grep -qE "0x[0-9a-fA-F]+" <<<"$out"
check "stack trace addresses retained" $?

# Ordering: banner (identity) must come before the panic message + trace.
banner_line=$(grep -n "internal error" <<<"$out" | head -1 | cut -d: -f1)
trace_line=$(grep -n "panic: deliberate" <<<"$out" | head -1 | cut -d: -f1)
check "banner precedes the stack trace" \
    "$(ok "$([[ -n $banner_line && -n $trace_line && $banner_line -lt $trace_line ]] && echo 0 || echo 1)")"

# ── The breadcrumb tracks the stage selector ─────────────────────────────
# Proves the while: line renders from the live breadcrumb, not a fixed string —
# the same mechanism the pipeline drives at reading/expanding/compiling/executing.
for stage in reading expanding compiling executing; do
    out="$("$KAAPPI" --panic-test="$stage" 2>&1)"
    grep -qE "^  while:   $stage <panic-test>$" <<<"$out"
    check "breadcrumb reflects stage=$stage" $?
done

# An unknown stage selector falls back to executing (never crashes the parser).
out="$("$KAAPPI" --panic-test=bogus 2>&1)"
grep -qE "^  while:   executing <panic-test>$" <<<"$out"
check "unknown stage falls back to executing" $?

# ── Summary ──────────────────────────────────────────────────────────────
echo
echo "Passed: $pass"
echo "Failed: $fail"
[[ $fail -eq 0 ]]
