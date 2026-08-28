#!/bin/bash
# Regression test for #2405 (native tier): a circular datum in CODE position
# must terminate on every tier. On `main` the three repros from the issue
# aborted (SIGBUS in ir.tryFoldFromAST) or hung (compileSyntaxBody, the IR
# arg-spine walks) inside the interpreter; a natively compiled program
# embedding one of them aborted or hung the same way at run time, because the
# rejected form is compiled as an eval-fallback whose runtime eval walks the
# form with the very same passes.
#
# After the fix: `kaappi compile` still succeeds for these forms (they are
# eval-fallback forms, not rejected programs), and the produced binary
# terminates at run time with a non-zero status — the embedded eval reports
# the compile error instead of aborting or spinning. The interpreter (the
# oracle) exits 1 with the KP2002 circular-form diagnosis.
#
# Usage: bash tests/scheme/compile/native-circular-code-2405.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
KAAPPI="${1:-$REPO_DIR/zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

FAIL=0

# Portable bounded run: no `timeout` on macOS. Runs "$@" with stdout/stderr
# captured, returns 124 on expiry, else the command's status.
run_bounded() {
    local out_file="$1"; shift
    "$@" > "$out_file" 2>&1 &
    local pid=$!
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if (( waited >= 15 )); then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 1
        waited=$((waited + 1))
    done
    wait "$pid"
}

check_native_terminates() {
    local name="$1" src_text="$2"
    local src="$DIR/$name.scm" bin="$DIR/$name.bin"
    printf '%s' "$src_text" > "$src"

    local compile_out compile_status=0
    compile_out="$(cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" 2>&1)" || compile_status=$?
    if [[ $compile_status -ne 0 || ! -x "$bin" ]]; then
        echo "FAIL: $name: kaappi compile exited $compile_status: $compile_out"
        FAIL=$((FAIL + 1))
        return
    fi

    # Interpreter is the oracle: exit 1 with the named diagnosis.
    local interp_out interp_status=0
    interp_out="$("$KAAPPI_ABS" "$src" 2>&1)" || interp_status=$?
    if [[ "$interp_status" -ne 1 ]] || ! grep -qF "circular form in code position" <<< "$interp_out"; then
        echo "FAIL: $name: interpreter oracle wrong (exit $interp_status): $interp_out"
        FAIL=$((FAIL + 1))
        return
    fi

    # The binary must terminate (no hang => 124, no abort => status > 128)
    # and must not succeed silently either.
    local run_out run_status=0
    run_bounded "$DIR/$name.out" "$bin" || run_status=$?
    if [[ "$run_status" -eq 124 ]]; then
        echo "FAIL: $name: compiled binary HUNG (killed after 15s)"
        FAIL=$((FAIL + 1))
        return
    fi
    if [[ "$run_status" -gt 128 ]]; then
        echo "FAIL: $name: compiled binary ABORTED (signal $((run_status - 128))): $(cat "$DIR/$name.out")"
        FAIL=$((FAIL + 1))
        return
    fi
    if [[ "$run_status" -eq 0 ]]; then
        echo "FAIL: $name: compiled binary succeeded silently — the cycle was compiled away"
        FAIL=$((FAIL + 1))
        return
    fi
    echo "PASS: $name: interpreter diagnoses (exit 1, KP2002), compiled binary terminates (exit $run_status)"
}

check_native_terminates repro-a '(display #1=(p #1# q))'
check_native_terminates repro-b '#0=(display 1 . #0#)'
check_native_terminates repro-c '#0=(let-syntax () . #0#)'

echo
echo "=== Results ==="
if [ "$FAIL" -gt 0 ]; then
    echo "Failed: $FAIL"
    echo "CIRCULAR CODE NATIVE REGRESSION DETECTED"
    exit 1
fi

echo "All circular-code native-tier tests pass."
exit 0
