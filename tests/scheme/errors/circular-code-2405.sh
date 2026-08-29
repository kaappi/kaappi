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

# <name> <source> [code] — asserts exit 1 plus the circular-form diagnosis
# under the expected code (KP2002 default). The regression class this file
# pins includes compiler hangs, so every invocation is bounded: a hung run
# reports as a failed case instead of stalling the suite until an external
# timeout (CodeRabbit on PR #2413). No `timeout` on macOS — a background run
# + bounded wait instead.
check_circular() {
    local name="$1" src="$2" code="${3:-KP2002}"
    printf '%s' "$src" > "$TMPDIR_TESTS/$name.scm"

    local output status
    "$KAAPPI" "$TMPDIR_TESTS/$name.scm" > "$TMPDIR_TESTS/$name.out" 2>&1 &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if (( waited >= 10 )); then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            echo "FAIL: $name: HUNG (killed after 10s) — the cycle guard regressed"
            FAIL=$((FAIL + 1))
            return
        fi
        sleep 1
        waited=$((waited + 1))
    done
    status=0
    wait "$pid" || status=$?
    output="$(cat "$TMPDIR_TESTS/$name.out")"

    if [[ "$status" -ne 1 ]]; then
        echo "FAIL: $name: expected exit 1 (diagnosed compile error), got $status — abort, hang-kill, or silent success?"
        echo "output: $output"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! grep -qF "$code" <<< "$output"; then
        echo "FAIL: $name: expected the diagnostic code $code in output:"
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
    echo "PASS: $name: exit 1, $code, circular-form diagnosis"
    PASS=$((PASS + 1))
}

# Top-level handlers that fire DURING execution (vm_eval's begin splicer and
# define-values formals walk) report through the runtime reporter, which maps
# a VM CompileError to error[KP2001] — same message, different code than the
# compile-time members' syntax-error[KP2002]. Pinned with the expected code
# so neither condition can drift unnoticed (baijum, review of PR #2420).
check_circular_runtime() {
    check_circular "$1" "$2" KP2001
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
# CodeRabbit on PR #2413: the SRFI-17 generalized set! target spine hung.
check_circular family-setbang '(set! #0=(f 1 . #0#) 3)'
# A cyclic improper tail after if's alternate: detection-only, extra
# non-cyclic forms stay accepted.
check_circular family-if-tail '#0=(if #t 1 . #0#)'
# baijum's review of PR #2413: cycles crossing the lower/emit re-entry
# boundary (a fresh IR per sub-form) aborted or reported KP9001; the guard
# now spans the boundary on the Compiler, through the child-compiler chain.
check_circular reentry-let '(display #0=(let ((x #0#)) x))'
check_circular reentry-lambda '(display ((lambda () #0=(lambda () . #0#))))'
check_circular reentry-let-values '(display #0=(let-values (((a) #0#)) a))'
check_circular reentry-qq-splice '(display `#0=(x ,@(list 1) #0#))'
# Round-2 shapes (CodeRabbit re-review), pinned here so a guard regression
# FAILS as a hang-kill instead of stalling the unbounded unit suite.
check_circular round2-case "(case 1 (#0=(1 . #0#) 'a))"
check_circular round2-syntax-rules '(define-syntax m (syntax-rules #0=((). #0#) ((_ x) x)))'

# The top-level begin and define-values paths report through the RUNTIME
# reporter (they fire during execution, not compilation), which maps a VM
# CompileError to error[KP2001] — same message, different code than every
# compile-time member's syntax-error[KP2002]. Pinned with the expected code
# so a future grep -F KP2002 cannot quietly miss them.
check_circular_runtime round2-toplevel-begin '(begin . #0=(1 . #0#))'
check_circular_runtime round3-define-values '(define-values #0=(a . #0#) (values 1))'
# Round-3 (baijum review of PR #2420): parameterize bindings and cyclic
# syntax-rules TEMPLATES (the template SIGBUS was the abort class #2405 was
# filed for, from a define-syntax never used).
check_circular round3-parameterize '(parameterize #0=((p 1) . #0#) 1)'
check_circular round3-template-begin '(define-syntax m (syntax-rules () ((_ x) #0=(begin . #0#))))'
check_circular round3-template-car '(define-syntax m (syntax-rules () ((_ x) #0=(f #0#))))'

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

# `set -e` note (review of PR #2413): a plain `out=$(...)` assignment would
# abort the script on a non-zero child before the FAIL branch could run, so
# the status is captured with the guarded idiom everywhere.
control_status=0
control_output=$("$KAAPPI" "$CONTROL" 2>&1) || control_status=$?
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
