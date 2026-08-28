#!/bin/bash
# #2405: a circular datum in CODE position (a plain R7RS datum-label cycle,
# no macros involved). Three one-line repros from the issue, plus the wider
# family the fix guards:
#
#   repro A  (display #1=(p #1# q))   car-side cycle  -> SIGBUS abort
#   repro B  #0=(display 1 . #0#)     spine cycle     -> KP9001 "internal error"
#   repro C  #0=(let-syntax () . #0#) body cycle      -> hang
#
# Each must instead terminate with exit 1 and the named diagnosis
# (syntax-error[KP2002] "circular form in code position"). Quoted circular
# data — the issue's Controls — must keep working everywhere.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

# <name> <source> — asserts exit 1 plus the KP2002 circular-form diagnosis.
check_circular() {
    local name="$1" src="$2"
    printf '%s' "$src" > "$TMPDIR_TESTS/$name.scm"

    local output status
    output=$("$KAAPPI" "$TMPDIR_TESTS/$name.scm" 2>&1) && status=0 || status=$?

    if [[ "$status" -ne 1 ]]; then
        echo "FAIL: $name: expected exit 1 (diagnosed compile error), got $status — abort, hang-kill, or silent success?"
        echo "output: $output"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! grep -qF "KP2002" <<< "$output"; then
        echo "FAIL: $name: expected the syntax-error code KP2002 in output:"
        echo "$output"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! grep -qF "circular form in code position" <<< "$output"; then
        echo "FAIL: $name: expected the circular-form diagnosis in output:"
        echo "$output"
        FAIL=$((FAIL + 1))
        return
    fi
    echo "PASS: $name: exit 1, KP2002, circular-form diagnosis"
    PASS=$((PASS + 1))
}

check_circular repro-a '(display #1=(p #1# q))'
check_circular repro-b '#0=(display 1 . #0#)'
check_circular repro-c '#0=(let-syntax () . #0#)'
check_circular family-and '#0=(and 1 . #0#)'
check_circular family-let '#0=(let ((x 1)) . #0#)'
check_circular family-lambda '#0=(lambda () . #0#)'
check_circular family-do '#0=(do ((i 0 (+ i 1))) ((> i 2)) . #0#)'
check_circular family-quasiquote '(display `(1 . #0=(2 . #0#)))'
check_circular family-apply-tail '#0=(apply + . #0#)'

# The issue's Controls: circular DATA is fine everywhere — quoting makes the
# datum a constant no code walk enters, and a syntax-rules macro use with a
# circular argument expands normally.
CONTROL="$TMPDIR_TESTS/controls.scm"
cat > "$CONTROL" <<'EOF'
(define x '#0=(zz . #0#))
(write x)
(newline)
(define-syntax m (syntax-rules () ((_ x) 'done)))
(display (m #0=(zz . #0#)))
(newline)
EOF

control_output=$("$KAAPPI" "$CONTROL" 2>&1)
control_status=$?
if [[ "$control_status" -eq 0 && "$control_output" == *'#0=(zz . #0#)'*done* ]]; then
    echo "PASS: controls: quoted circular datum prints, syntax-rules circular argument expands"
    PASS=$((PASS + 1))
else
    echo "FAIL: controls: expected the quoted cycle to print and 'done', got (exit $control_status):"
    echo "$control_output"
    FAIL=$((FAIL + 1))
fi

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "CIRCULAR CODE REGRESSION DETECTED"
    exit 1
fi

echo "All circular-code tests pass."
exit 0
