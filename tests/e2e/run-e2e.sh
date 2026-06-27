#!/bin/bash
# End-to-end tests for the LLVM native backend.
# Verifies: Scheme source → --emit-llvm → .ll → clang → native binary → correct output.
#
# Usage: bash tests/e2e/run-e2e.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BDD_LIB="$REPO_DIR/../kaappi-bdd/lib"
TMPDIR="${TMPDIR:-/tmp}/kaappi-e2e-$$"
PASS=0
FAIL=0

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT
mkdir -p "$TMPDIR"

cd "$REPO_DIR"

# Build kaappi and runtime library
echo "=== Building kaappi and libkaappi_rt.a ==="
zig build
zig build lib

KAAPPI="$REPO_DIR/zig-out/bin/kaappi"
LIBDIR="$REPO_DIR/zig-out/lib"

# --- Phase 1: BDD tests via interpreter ---

echo ""
echo "=== Phase 1: BDD tests (interpreter) ==="
if [[ -d "$BDD_LIB" ]]; then
    if "$KAAPPI" --lib-path "$BDD_LIB" "$SCRIPT_DIR/test-llvm-backend.scm"; then
        echo "BDD tests: PASS"
        PASS=$((PASS + 1))
    else
        echo "BDD tests: FAIL"
        FAIL=$((FAIL + 1))
    fi
else
    echo "SKIP: kaappi-bdd not found at $BDD_LIB"
fi

# --- Phase 2: Native compilation parity tests ---

echo ""
echo "=== Phase 2: Native compilation parity tests ==="

assert_native_parity() {
    local label="$1"
    local program="$2"

    local expected
    expected=$("$KAAPPI" "$program" 2>&1) || true

    local ll_file="$TMPDIR/$(basename "$program" .scm).ll"
    local native_bin="$TMPDIR/$(basename "$program" .scm)"

    if ! "$KAAPPI" --emit-llvm -o "$ll_file" "$program" 2>/dev/null; then
        echo "FAIL: $label — emit-llvm failed"
        FAIL=$((FAIL + 1))
        return
    fi

    local clang_output
    local cc="${KAAPPI_CC:-zig cc}"
    if ! clang_output=$($cc -w "$ll_file" -o "$native_bin" -L"$LIBDIR" -lkaappi_rt -lc -lm -lpthread 2>&1); then
        echo "  cc: $clang_output"
        echo "FAIL: $label — clang linking failed"
        FAIL=$((FAIL + 1))
        return
    fi

    local actual
    actual=$("$native_bin" 2>&1) || true

    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

for program in "$SCRIPT_DIR"/programs/*.scm; do
    name=$(basename "$program" .scm)
    assert_native_parity "$name" "$program"
done

# --- Summary ---

echo ""
TOTAL=$((PASS + FAIL))
echo "=== E2E Summary: $PASS/$TOTAL passed ==="
if [[ $FAIL -gt 0 ]]; then
    echo "$FAIL FAILED"
    exit 1
fi
