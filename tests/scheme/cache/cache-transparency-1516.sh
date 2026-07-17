#!/bin/bash
# Regression test for #1516: cache transparency — `kaappi cache status|clear`
# over the central ~/.kaappi/cache store, plus HIT-after-MISS behavior.
#
# Hermetic: KAAPPI_HOME points at a throwaway dir so the real user cache is
# never read or written. An import-free program is used because the run-cache
# is (pre-existing behavior) skipped for programs that import.
#
# Usage: bash tests/scheme/cache/cache-transparency-1516.sh [path-to-kaappi]

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${1:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

HOMEDIR="$(mktemp -d)"
PROGDIR="$(mktemp -d)"
trap 'rm -rf "$HOMEDIR" "$PROGDIR"' EXIT
export KAAPPI_HOME="$HOMEDIR"

PROG="$PROGDIR/square.scm"
cat > "$PROG" <<'SCM'
(define (square x) (* x x))
(square 9)
SCM

check() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  expected to contain: $expected"
        echo "  actual: $actual"
        FAIL=$((FAIL + 1))
    fi
}

check_exit() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $actual"
        FAIL=$((FAIL + 1))
    fi
}

# 1. Fresh status: empty cache.
out="$("$KAAPPI" cache status)"
check "status on empty cache reports 0 entries" "0 entries" "$out"

# 2. Run the program (MISS → populates the cache).
run1="$("$KAAPPI" "$PROG")"
check "program runs (MISS)" "81" "$run1"

# 3. status now lists one current entry naming the source. The recorded
# path is the native spelling (on Windows C:/..., not the shell's /tmp/...).
out="$("$KAAPPI" cache status)"
check "status lists 1 entry" "1 entry" "$out"
check "status names the source path" "$(native_path "$PROG")" "$out"
check "status marks the entry current" "current" "$out"

# 4. Re-run (HIT) — identical result, no crash.
run2="$("$KAAPPI" "$PROG")"
check "program runs (HIT)" "81" "$run2"
if [[ "$run1" == "$run2" ]]; then
    echo "PASS: HIT output matches MISS output"
    PASS=$((PASS + 1))
else
    echo "FAIL: HIT output ($run2) != MISS output ($run1)"
    FAIL=$((FAIL + 1))
fi

# 5. clear removes the entry.
out="$("$KAAPPI" cache clear)"
check "clear reports 1 entry cleared" "Cleared 1 entry" "$out"

# 6. status is empty again.
out="$("$KAAPPI" cache status)"
check "status empty after clear" "0 entries" "$out"

# 7. Usage errors: bare `cache` and an unknown subcommand exit non-zero.
set +e
"$KAAPPI" cache > /dev/null 2>&1
check_exit "bare 'cache' is a usage error" 2 $?
"$KAAPPI" cache frobnicate > /dev/null 2>&1
check_exit "unknown 'cache' subcommand is a usage error" 2 $?
set -e

echo ""
echo "$PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
