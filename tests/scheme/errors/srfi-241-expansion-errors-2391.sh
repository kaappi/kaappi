#!/bin/bash
# Expansion-stage diagnostics of the SRFI 241 er-macro port (kaappi#2391).
#
# The match transformer and the %match-qq quasiquote transformer validate
# pattern/template shape while they EXPAND, so every diagnostic here is
# raised at compile time (syntax-error[KP2002]) — a runtime `guard` in the
# SRFI-64 suite can never observe them, which is why they get a shell suite:
# one malformed form per diagnostic, asserting a nonzero exit AND the
# diagnostic text (a generic "invalid syntax" with the message lost would
# fail here).
#
# The positive behavior of the same code paths lives in
# tests/scheme/srfi/srfi241.scm.
#
# Usage: bash tests/scheme/errors/srfi-241-expansion-errors-2391.sh [path-to-kaappi]

set -euo pipefail

KAAPPI="${1:-${KAAPPI:-zig-out/bin/kaappi}}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

# Hermetic: a throwaway KAAPPI_HOME (an installed ~/.kaappi/lib must not
# shadow the working tree, kaappi#2352) and the checkout's own lib/ so the
# .sld under test is the one in the tree, not a stale zig-out/lib copy.
KAAPPI_HOME="$(mktemp -d)"
export KAAPPI_HOME
DIR=$(mktemp -d)
trap 'rm -rf "$DIR" "$KAAPPI_HOME"' EXIT

PASS=0
FAIL=0

# check_expansion_error <name> <expected-diagnostic-substring> <program>
check_expansion_error() {
    local name="$1" expect="$2" src="$3"
    printf '%s\n' "$src" > "$DIR/$name.scm"

    local status=0 out
    out=$("$KAAPPI_ABS" --lib-path "$REPO_DIR/lib" "$DIR/$name.scm" 2>&1) \
        || status=$?

    if [ "$status" -eq 0 ]; then
        echo "FAIL: $name — expected a nonzero exit, got 0 (output: $out)"
        FAIL=$((FAIL + 1))
        return
    fi
    if [[ "$out" != *"$expect"* ]]; then
        echo "FAIL: $name — diagnostic did not contain '$expect': $out"
        FAIL=$((FAIL + 1))
        return
    fi
    PASS=$((PASS + 1))
}

IMPORT='(import (scheme base) (srfi 241))'

# An ellipsis with no preceding sub-pattern.
check_expansion_error "misplaced-ellipsis" \
    "match: misplaced ellipsis" \
    "$IMPORT
(match (list 1) ((... ,x) 1))"

# Two ellipses at the same list level.
check_expansion_error "multiple-ellipses" \
    "match: multiple ellipses in one list" \
    "$IMPORT
(match (list 1 2) ((,x ... ,y ...) 1))"

# A named cata whose variable position holds a non-identifier.
check_expansion_error "invalid-cata-variable" \
    "match: invalid cata variable" \
    "$IMPORT
(match (list 1) ((,(f -> \"s\")) 1))"

# A cata whose variable list is improper.
check_expansion_error "invalid-cata-pattern" \
    "match: invalid cata pattern" \
    "$IMPORT
(match (list 1) ((,(x . y)) 1))"

# ,@ outside any list context in a match-body quasiquote template.
check_expansion_error "splicing-outside-list" \
    "match quasiquote: unquote-splicing outside list context" \
    "$IMPORT
(display (match (list 1) ((,x) \`,@x)))"

# An ellipsis iterating a subtemplate with nothing unquoted to iterate.
check_expansion_error "ellipsis-over-constant-template" \
    "match quasiquote: no unquoted expressions under ellipsis" \
    "$IMPORT
(display (match (list 1) ((,x) \`((a) ...))))"

echo ""
echo "SRFI 241 expansion errors: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
