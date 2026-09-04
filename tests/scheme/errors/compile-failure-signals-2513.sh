#!/bin/bash
# Regression test for #2513: a failed --compile must leave no artifact and
# print no success line.
#
# The compile driver recovers from errors (an import evaluated at compile time
# that fails, a read error, a compile error) and keeps compiling, so the run
# used to fall out the bottom with a partial function list, write the .sbc
# anyway, and print `Compiled X -> Y` — on a run that exits 1. Both halves are
# traps: anything reading stdout is told the build worked, and the write
# replaced a previous good artifact at the -o target with the broken one (or
# silently left a stale one there when nothing was written at all).
#
# Now: no `Compiled` line, and NO file at the exact -o / derived-.sbc target —
# a failed compile leaves no file rather than a partial or stale one.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

# A program whose import fails at compile time while its remaining forms
# compile fine — exactly the shape that used to produce a partial bundle.
cat > "$TMPDIR_TESTS/bad.scm" << 'EOF'
(import (nonexistent-library-2513))
(display "this form still compiles")
EOF

cat > "$TMPDIR_TESTS/good.scm" << 'EOF'
(import (scheme base))
(display "fine")
EOF

# check <label> <expected-status> <expected-file> <present|gone> <kaappi...>
# Asserts the exit status, the expected presence of the artifact file, and —
# for a failing run — that stdout carries no `Compiled ...` line.
check() {
    local label="$1" expected_status="$2" expected_file="$3" want="$4"
    shift 4
    local status=0
    "$@" > "$TMPDIR_TESTS/stdout.txt" 2> "$TMPDIR_TESTS/stderr.txt" || status=$?
    if [[ "$status" -ne "$expected_status" ]]; then
        echo "FAIL: $label — expected exit $expected_status, got $status"
        FAIL=$((FAIL + 1))
        return
    fi
    if [[ "$expected_status" -ne 0 ]] && grep -q '^Compiled ' "$TMPDIR_TESTS/stdout.txt"; then
        echo "FAIL: $label — stdout carries a 'Compiled ...' line on a failed run"
        FAIL=$((FAIL + 1))
        return
    fi
    if [[ "$want" == present && ! -e "$expected_file" ]] || [[ "$want" == gone && -e "$expected_file" ]]; then
        echo "FAIL: $label — expected '$expected_file' $want, found otherwise"
        FAIL=$((FAIL + 1))
        return
    fi
    echo "PASS: $label"
    PASS=$((PASS + 1))
}

OUT="$TMPDIR_TESTS/out.sbc"

# 1. Fresh failed compile: exit 1, no Compiled line, no artifact at the -o
#    target.
check "failed --compile exits 1, no Compiled line, no artifact (#2513)" 1 "$OUT" gone \
    "$KAAPPI" --compile -o "$OUT" "$TMPDIR_TESTS/bad.scm"

# 2. A stale artifact from a previous good build at the same -o target must be
#    removed, not silently kept looking current.
check "good --compile to -o target exits 0 and writes the artifact" 0 "$OUT" present \
    "$KAAPPI" --compile -o "$OUT" "$TMPDIR_TESTS/good.scm"
check "failed --compile removes the stale artifact at the -o target (#2513)" 1 "$OUT" gone \
    "$KAAPPI" --compile -o "$OUT" "$TMPDIR_TESTS/bad.scm"

# 3. The derived .sbc target (no -o): same rule — the previous build's file
#    next to the source does not survive a failed recompile.
cp "$TMPDIR_TESTS/good.scm" "$TMPDIR_TESTS/derived.scm"
check "good --compile with derived target writes derived.sbc" 0 "$TMPDIR_TESTS/derived.sbc" present \
    "$KAAPPI" --compile "$TMPDIR_TESTS/derived.scm"
cp "$TMPDIR_TESTS/bad.scm" "$TMPDIR_TESTS/derived.scm"
check "failed --compile removes the stale derived .sbc (#2513)" 1 "$TMPDIR_TESTS/derived.sbc" gone \
    "$KAAPPI" --compile "$TMPDIR_TESTS/derived.scm"

# 4. A read error (not an import failure) fails the same way and leaves the
#    target clean.
check "good --compile rebuilds the -o artifact" 0 "$OUT" present \
    "$KAAPPI" --compile -o "$OUT" "$TMPDIR_TESTS/good.scm"
printf '(+ 1\n' > "$TMPDIR_TESTS/unbal.scm"
check "read-error --compile removes the stale artifact at the -o target (#2513)" 1 "$OUT" gone \
    "$KAAPPI" --compile -o "$OUT" "$TMPDIR_TESTS/unbal.scm"

echo ""
echo "compile-failure-signals: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
