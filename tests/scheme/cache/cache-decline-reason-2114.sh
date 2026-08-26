#!/bin/bash
# Regression test for #2114 (reason naming) as changed by #1888 (what
# declines): `--timings` must name what actually kept a file out of the
# cache, and since #1888 that set shrank from "any of the eight top-level
# heads" to just compile-time registrations and compile errors.
#
# History: #2114 made `--timings` name the specific top-level head that
# disabled the cache (all eight used to be reported as `imports`). #1888 made
# every one of the eight cacheable — each becomes a positional declaration
# slot whose verbatim source span is re-dispatched on a HIT — so the only
# remaining decline reasons are `define-syntax` (a HIT would not replay the
# compile-time macro/property registration, #2112) and `compile error` (a HIT
# would run the partial program with exit 0).
#
# What this pins:
#   * each of the eight heads misses cold WITH a write and HITs warm;
#   * the rule is top-level *head position only* for the refusals too — the
#     same four non-library constructs nested inside a body leave caching
#     alive;
#   * `define-syntax` and a compile error are named as decline reasons;
#   * a plain program with none of them populates the cache and HITs.
#
# Hermetic: one isolated KAAPPI_HOME per case, so no probe can see another's
# entry (or the real user cache).
#
# Usage: bash tests/scheme/cache/cache-decline-reason-2114.sh [path-to-kaappi]

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${1:-zig-out/bin/kaappi}"
if [ ! -x "$KAAPPI" ]; then
    echo "FAIL: no kaappi binary at '$KAAPPI' — build it first (zig build)"
    exit 1
fi
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

PASS=0
FAIL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ok() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

bad() {
    echo "FAIL: $1"
    shift
    for line in "$@"; do echo "  $line"; done
    FAIL=$((FAIL + 1))
}

# cold_then_warm <label> <program-path>: the program must miss cold with a
# write and hit warm.
cold_then_warm() {
    local label="$1" prog="$2" home cold warm
    home="$(mktemp -d "$WORK/home.XXXXXX")"
    cold="$(KAAPPI_HOME="$home" "$KAAPPI_ABS" --timings "$prog" 2>&1 > /dev/null | grep '^cache:' || echo '(no cache line)')"
    warm="$(KAAPPI_HOME="$home" "$KAAPPI_ABS" --timings "$prog" 2>&1 > /dev/null | grep '^cache:' || echo '(no cache line)')"
    case "$cold" in
        "cache: MISS (wrote"*) ;;
        *) bad "$label: cold run misses with a write" "actual: $cold"
           return ;;
    esac
    case "$warm" in
        "cache: HIT"*) ok "$label: cold MISS-with-write, warm HIT" ;;
        *) bad "$label: warm run hits" "cold: $cold" "warm: $warm" ;;
    esac
}

# decline_line <program-source>: the `cache:` line of a cold `--timings` run,
# in an isolated cache home.
decline_line() {
    local home prog out
    home="$(mktemp -d "$WORK/home.XXXXXX")"
    prog="$(mktemp "$WORK/prog.XXXXXX")"
    printf '%s\n' "$1" > "$prog"
    # `|| true`: a declining program usually also fails to run, and under
    # pipefail that would fall through to the no-cache-line branch.
    out="$(KAAPPI_HOME="$home" "$KAAPPI_ABS" --timings "$prog" 2>&1 > /dev/null || true)"
    printf '%s\n' "$out" | grep '^cache:' || echo "(no cache line)"
}

prog_for() {
    local prog
    prog="$(mktemp "$WORK/prog.XXXXXX")"
    printf '%s\n' "$1" > "$prog"
    echo "$prog"
}

echo "=== each top-level head is cacheable (declaration slot, #1888) ==="
cold_then_warm "top-level import" "$(prog_for '(import (scheme base))
(display 1)(newline)')"
cold_then_warm "top-level define-library" "$(prog_for '(define-library (probe lib) (export p) (begin (define (p) 1)))
(display 1)(newline)')"
cold_then_warm "top-level define-record-type" "$(prog_for '(define-record-type <p> (mk a) p? (a p-a))
(display (p-a (mk 5)))(newline)')"
cold_then_warm "top-level define-values" "$(prog_for '(define-values (a b) (values 1 2))
(display (+ a b))(newline)')"
cold_then_warm "top-level begin" "$(prog_for '(begin (display 1))
(newline)')"
cold_then_warm "top-level cond-expand" "$(prog_for '(cond-expand (else (display 1)))
(newline)')"

# include / include-ci need a file to include; both share one fixture.
cat > "$WORK/inc-body.scm" <<'SCM'
(define included 7)
SCM
for head in include include-ci; do
    cat > "$WORK/uses-$head.scm" <<SCM
($head "inc-body.scm")
(display included)(newline)
SCM
    cold_then_warm "top-level $head" "$WORK/uses-$head.scm"
done

echo "=== the remaining refusals name themselves ==="
line="$(decline_line '(define-syntax m (syntax-rules () ((_ x) x)))
(display (m 1))(newline)')"
if [ "$line" == "cache: MISS (not cached: define-syntax)" ]; then
    ok "define-syntax is named as the reason"
else
    bad "define-syntax is named as the reason" \
        "expected: cache: MISS (not cached: define-syntax)" \
        "actual:   $line"
fi

# A runtime-undefined variable is NOT a compile error (globals resolve at
# run time), so this must be actual bad syntax.
line="$(decline_line '(lambda)')"
if [ "$line" == "cache: MISS (not cached: compile error)" ]; then
    ok "compile error is named as the reason"
else
    bad "compile error is named as the reason" \
        "expected: cache: MISS (not cached: compile error)" \
        "actual:   $line"
fi

echo "=== control: nested in a body, the same forms do not disable the cache ==="
# All four non-library heads at once, none of them at top level. If any of them
# were matched structurally rather than in head position, this would decline.
nested='(define (a) (begin 1 2 3))
(define (b) (cond-expand (else (quote chosen))))
(define (c) (define-values (x y) (values 10 20)) (+ x y))
(define (d) (define-record-type <pt> (mk x) pt? (x pt-x)) (pt-x (mk 7)))
(display (+ (a) (c) (d)))(newline)'
cold_then_warm "nested begin/cond-expand/define-values/define-record-type" "$(prog_for "$nested")"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
