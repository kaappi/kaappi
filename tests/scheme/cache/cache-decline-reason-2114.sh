#!/bin/bash
# Regression test for #2114: `--timings` must name the top-level head that
# actually disabled the `.sbc` cache.
#
# The documented rule named one construct, `import`. The implemented rule is
# every head `vm_eval.handleTopLevelForm` claims — all eight of them, listed in
# `vm_eval.TopLevelHead` — and `--timings` reported all eight as `imports`, so a
# file containing no `import` at all was told its cache miss was caused by one.
#
# What this pins:
#   * each of the eight heads is named for itself in the "not cached: ..." line;
#   * the rule is top-level *head position only* — the same four non-library
#     constructs nested inside a body leave caching alive, which is what makes
#     this `handleTopLevelForm`'s dispatch set rather than "these forms are
#     unserialisable";
#   * a plain program with none of them still populates the cache and HITs.
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

# cache_line <program-source>: the `cache:` line of a cold `--timings` run, in
# an isolated cache home.
cache_line() {
    local home prog
    home="$(mktemp -d "$WORK/home.XXXXXX")"
    prog="$(mktemp "$WORK/prog.XXXXXX")"
    printf '%s\n' "$1" > "$prog"
    KAAPPI_HOME="$home" "$KAAPPI_ABS" --timings "$prog" 2>&1 > /dev/null |
        grep '^cache:' || echo "(no cache line)"
}

# expect_reason <head-name> <program-source>
expect_reason() {
    local head="$1" line
    line="$(cache_line "$2")"
    if [ "$line" == "cache: MISS (not cached: top-level $head)" ]; then
        ok "top-level $head is named as the reason"
    else
        bad "top-level $head is named as the reason" \
            "expected: cache: MISS (not cached: top-level $head)" \
            "actual:   $line"
    fi
}

echo "=== each top-level head names itself ==="
expect_reason import '(import (scheme base))
(display 1)(newline)'
expect_reason define-library '(define-library (probe lib) (export p) (begin (define (p) 1)))
(display 1)(newline)'
expect_reason define-record-type '(define-record-type <p> (mk a) p? (a p-a))
(display (p-a (mk 5)))(newline)'
expect_reason define-values '(define-values (a b) (values 1 2))
(display (+ a b))(newline)'
expect_reason begin '(begin (display 1))
(newline)'
expect_reason cond-expand '(cond-expand (else (display 1)))
(newline)'

# include / include-ci need a file to include; both share one fixture.
cat > "$WORK/inc-body.scm" <<'SCM'
(define included 7)
SCM
for head in include include-ci; do
    home="$(mktemp -d "$WORK/home.XXXXXX")"
    cat > "$WORK/uses-$head.scm" <<SCM
($head "inc-body.scm")
(display included)(newline)
SCM
    line="$(KAAPPI_HOME="$home" "$KAAPPI_ABS" --timings "$WORK/uses-$head.scm" 2>&1 > /dev/null |
        grep '^cache:' || echo "(no cache line)")"
    if [ "$line" == "cache: MISS (not cached: top-level $head)" ]; then
        ok "top-level $head is named as the reason"
    else
        bad "top-level $head is named as the reason" \
            "expected: cache: MISS (not cached: top-level $head)" \
            "actual:   $line"
    fi
done

echo "=== control: nested in a body, the same forms do not disable the cache ==="
# All four non-library heads at once, none of them at top level. If any of them
# were matched structurally rather than in head position, this would miss.
nested='(define (a) (begin 1 2 3))
(define (b) (cond-expand (else (quote chosen))))
(define (c) (define-values (x y) (values 10 20)) (+ x y))
(define (d) (define-record-type <pt> (mk x) pt? (x pt-x)) (pt-x (mk 7)))
(display (+ (a) (c) (d)))(newline)'
line="$(cache_line "$nested")"
case "$line" in
    "cache: MISS"*"not cached"*)
        bad "nested begin/cond-expand/define-values/define-record-type still cache" \
            "actual: $line" ;;
    "cache: MISS"*) ok "nested begin/cond-expand/define-values/define-record-type still cache" ;;
    *) bad "nested begin/cond-expand/define-values/define-record-type still cache" \
        "expected a plain MISS that then writes the cache" "actual: $line" ;;
esac

echo "=== control: a cacheable program misses cold, then hits warm ==="
HOME_HIT="$(mktemp -d "$WORK/home.XXXXXX")"
cat > "$WORK/plain.scm" <<'SCM'
(define (square x) (* x x))
(display (square 9))
(newline)
SCM
cold="$(KAAPPI_HOME="$HOME_HIT" "$KAAPPI_ABS" --timings "$WORK/plain.scm" 2>&1 > /dev/null | grep '^cache:')"
warm="$(KAAPPI_HOME="$HOME_HIT" "$KAAPPI_ABS" --timings "$WORK/plain.scm" 2>&1 > /dev/null | grep '^cache:')"
case "$cold" in
    "cache: MISS"*"not cached"*) bad "cold run misses without a decline reason" "actual: $cold" ;;
    "cache: MISS"*) ok "cold run misses without a decline reason" ;;
    *) bad "cold run misses without a decline reason" "actual: $cold" ;;
esac
case "$warm" in
    "cache: HIT"*) ok "warm run hits" ;;
    *) bad "warm run hits" "actual: $warm" ;;
esac

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
