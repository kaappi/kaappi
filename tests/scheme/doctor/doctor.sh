#!/bin/bash
# `kaappi doctor` — installation and environment self-check (kaappi#1513).
#
# Covers the exit-code contract (nonzero only on FAIL-level findings), the human
# and --json output shapes, and a deliberately broken environment: an explicit
# KAAPPI_LIB_DIR that does not resolve is the one FAIL doctor emits.

set -uo pipefail

KAAPPI="${1:-${KAAPPI:-zig-out/bin/kaappi}}"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# assert_exit <label> <expected> <cmd...> — run cmd, compare its exit status.
assert_exit() {
    local label="$1" expected="$2"
    shift 2
    local status=0
    "$@" > "$TMP/out" 2> "$TMP/err" || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        pass "$label"
    else
        fail "$label" "expected exit $expected, got $status"
        cat "$TMP/out" "$TMP/err"
    fi
}

# assert_contains <label> <needle> <cmd...> — run cmd, grep combined output.
assert_contains() {
    local label="$1" needle="$2"
    shift 2
    "$@" > "$TMP/out" 2> "$TMP/err"
    if grep -qF -- "$needle" "$TMP/out" "$TMP/err"; then
        pass "$label"
    else
        fail "$label" "output missing: $needle"
        cat "$TMP/out" "$TMP/err"
    fi
}

# The healthy environment must never FAIL: WARN-level findings (a missing
# ~/.kaappi/lib or libkaappi_rt.a) are usable-but-degraded and keep exit 0.
# KAAPPI_LIB_DIR is unset so the one FAIL condition can't fire.
assert_exit    "healthy env exits 0"           0 env -u KAAPPI_LIB_DIR "$KAAPPI" doctor
assert_contains "human output has a header"    "kaappi doctor" env -u KAAPPI_LIB_DIR "$KAAPPI" doctor
assert_contains "human output has a summary"   "Summary:"      env -u KAAPPI_LIB_DIR "$KAAPPI" doctor
assert_contains "reports every check group"    "native-backend" env -u KAAPPI_LIB_DIR "$KAAPPI" doctor

# --json output shape.
assert_exit    "json healthy exits 0"          0 env -u KAAPPI_LIB_DIR "$KAAPPI" doctor --json
assert_contains "json has meta version"        '"version":'  env -u KAAPPI_LIB_DIR "$KAAPPI" doctor --json
assert_contains "json has target triple"       '"target":'   env -u KAAPPI_LIB_DIR "$KAAPPI" doctor --json
assert_contains "json has checks array"        '"checks":['  env -u KAAPPI_LIB_DIR "$KAAPPI" doctor --json
assert_contains "json healthy is ok:true"      '"ok":true'   env -u KAAPPI_LIB_DIR "$KAAPPI" doctor --json

# Deliberately broken environment: KAAPPI_LIB_DIR pointing at a nonexistent
# directory. This is a definite misconfiguration, so it is FAIL → exit 1.
BOGUS="$TMP/nonexistent-lib-dir"
assert_exit    "bogus KAAPPI_LIB_DIR exits 1"  1 env KAAPPI_LIB_DIR="$BOGUS" "$KAAPPI" doctor
assert_contains "bogus dir names the check"    "KAAPPI_LIB_DIR" env KAAPPI_LIB_DIR="$BOGUS" "$KAAPPI" doctor
assert_contains "bogus dir reports FAIL"       "FAIL" env KAAPPI_LIB_DIR="$BOGUS" "$KAAPPI" doctor
assert_contains "bogus json is ok:false"       '"ok":false'      env KAAPPI_LIB_DIR="$BOGUS" "$KAAPPI" doctor --json
assert_contains "bogus json status is fail"    '"status":"fail"' env KAAPPI_LIB_DIR="$BOGUS" "$KAAPPI" doctor --json

# A directory that exists but has no libkaappi_rt.a is equally a FAIL: the
# explicit override resolves to a place with no runtime library.
EMPTY="$TMP/empty-lib-dir"
mkdir -p "$EMPTY"
assert_exit    "empty KAAPPI_LIB_DIR exits 1"  1 env KAAPPI_LIB_DIR="$EMPTY" "$KAAPPI" doctor
assert_contains "empty dir suggests a fix"     "libkaappi_rt.a" env KAAPPI_LIB_DIR="$EMPTY" "$KAAPPI" doctor

# Usage handling.
assert_exit    "--help exits 0"                0 "$KAAPPI" doctor --help
assert_contains "--help prints usage"          "Usage: kaappi doctor" "$KAAPPI" doctor --help
assert_exit    "unknown option exits 2"        2 "$KAAPPI" doctor --bogus-flag
assert_exit    "unexpected argument exits 2"   2 "$KAAPPI" doctor stray-arg

echo ""
echo "$PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
