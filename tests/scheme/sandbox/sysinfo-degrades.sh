#!/bin/bash
# Systematic audit v2, Phase 2.11 — audit dimension D7 for
# src/primitives_sysinfo.zig: the `--sandbox` gate is a PER-NAME decision,
# and until this script nobody had asserted the set as a whole.
#
# `primitives.Lib.sandboxAllowed` returns true for `.kaappi_sysinfo`, so the
# library itself stays importable under --sandbox; the four
# filesystem-path-revealing specs opt out individually via `.sandbox = false`
# (primitives_sysinfo.zig), and `registerSandboxed` then never registers them
# at all — a sandboxed program sees "undefined variable", not a stub.
#
# The split is deliberate and its rationale is in primitives.zig's own
# comment: static build info (version, OS, CPU) leaks nothing about the host
# filesystem, while script/lib/exe paths do. This script pins BOTH halves.
# Losing the gate on any of the four is a sandbox escape; adding a gate to
# any of the three would silently break `(srfi 112)`-style logging in
# sandboxed code.
#
# It also pins the two claims the comment makes about the surrounding
# system: that every portable SRFI layered on `(kaappi sysinfo)` (59, 112,
# 193) is unreachable under --sandbox anyway because it is a file-backed
# `.sld`, and that `(scheme process-context)`'s `command-line` — the obvious
# alternative route to the script path — is blocked too, so gating
# `%script-path` is not defeated one import away.
#
# Exit 0 = the gate matches its documented set. Any failure = exit 1.

set -euo pipefail

KAAPPI="${KAAPPI:-${1:-zig-out/bin/kaappi}}"
PASS=0
FAIL=0

# Runs `expr` under --sandbox and requires the output to be exactly `expected`.
assert_sandbox_output() {
    local label="$1" expr="$2" expected="$3" output
    output=$(printf '%s\n' "$expr" | "$KAAPPI" --sandbox 2>&1 || true)
    if [ "$output" = "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected', got: $output"
        FAIL=$((FAIL + 1))
    fi
}

# Requires the name to be absent from a sandboxed VM's globals entirely.
assert_undefined_under_sandbox() {
    local label="$1" name="$2" output
    output=$(printf '(%s)\n' "$name" | "$KAAPPI" --sandbox 2>&1 || true)
    if grep -qE "undefined variable" <<< "$output"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected 'undefined variable', got: $output"
        FAIL=$((FAIL + 1))
    fi
}

# Requires the name to be BOUND when NOT sandboxed — the control that proves
# the sandbox result above is the gate talking and not a typo in the name.
# The value is deliberately not asserted: %script-path and %current-lib-dir
# are legitimately #f when the program arrives on stdin rather than as a
# script file, which is exactly how this script feeds them.
assert_present_unsandboxed() {
    local label="$1" name="$2" output
    output=$(printf '(let ((v (%s))) (display (or (string? v) (not v))))\n' "$name" | "$KAAPPI" 2>&1 || true)
    if [ "$output" = "#t" ]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '#t', got: $output"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== (kaappi sysinfo) --sandbox gate (audit D7) ==="
echo

echo "--- the four path-revealing specs are gated (.sandbox = false) ---"
for name in %script-path %current-lib-dir %kaappi-lib-dir %implementation-dir; do
    assert_undefined_under_sandbox "$name is unavailable under --sandbox" "$name"
done

echo
echo "--- control: all four exist and answer in an unsandboxed VM ---"
assert_present_unsandboxed "%script-path answers unsandboxed" "%script-path"
assert_present_unsandboxed "%current-lib-dir answers unsandboxed" "%current-lib-dir"
assert_present_unsandboxed "%kaappi-lib-dir answers unsandboxed" "%kaappi-lib-dir"
assert_present_unsandboxed "%implementation-dir answers unsandboxed" "%implementation-dir"

echo
echo "--- the three static-build-info specs are NOT gated ---"
assert_sandbox_output "%implementation-version answers under --sandbox" \
    '(display (string? (%implementation-version)))' '#t'
assert_sandbox_output "%os-name answers under --sandbox" \
    '(display (string? (%os-name)))' '#t'
assert_sandbox_output "%cpu-architecture answers under --sandbox" \
    '(display (string? (%cpu-architecture)))' '#t'

echo
echo "--- the library itself stays importable (Lib.sandboxAllowed) ---"
assert_sandbox_output "(kaappi sysinfo) imports under --sandbox" \
    '(import (scheme base) (kaappi sysinfo)) (display (string? (%os-name)))' '#t'
assert_sandbox_output "the gated names stay unbound even after importing the library" \
    '(import (scheme base) (kaappi sysinfo))
     (display (call-with-current-continuation
       (lambda (k) (with-exception-handler (lambda (e) (k "gated"))
                     (lambda () (%script-path))))))' 'gated'

echo
echo "--- the portable SRFIs layered on it are file-backed, so blocked ---"
for srfi in 59 112 193; do
    out=$(printf '(import (scheme base) (srfi %s))\n' "$srfi" | "$KAAPPI" --sandbox 2>&1 || true)
    if grep -qE "cannot load library from file" <<< "$out"; then
        echo "PASS: (srfi $srfi) cannot load under --sandbox"
        PASS=$((PASS + 1))
    else
        echo "FAIL: (srfi $srfi) loaded under --sandbox — got: $out"
        FAIL=$((FAIL + 1))
    fi
done

echo
echo "--- the obvious alternative route to the script path is blocked too ---"
assert_undefined_under_sandbox "command-line is unavailable under --sandbox" "command-line"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "(kaappi sysinfo)'s --sandbox gate does not match its documented set."
    exit 1
fi
echo "(kaappi sysinfo) degrades correctly under --sandbox."
exit 0
