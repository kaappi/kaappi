#!/bin/bash
# `kaappi fmt` — canonical, comment-preserving formatter (kaappi#1518).
#
# Golden CLI behaviour (write in place, --check exit codes, stdin), plus two
# tree-wide properties that are the issue's acceptance criteria:
#
#   * zero semantic drift — formatting every .scm/.sld under tests/scheme and
#     lib must never change the datums a reader sees (fmt's built-in round-trip
#     check reports any drift on stderr and refuses to write);
#   * idempotence — formatting an already-formatted tree is a no-op.
#
# Exact input→output layout cases live in the Zig unit tests (src/tests_fmt.zig);
# this suite exercises the CLI and the whole repo corpus.

set -uo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
# Resolve to an absolute path: the tree checks format files in a temp mirror,
# so a relative binary path would break once we reference it from elsewhere.
case "$KAAPPI" in
    /*) : ;;
    *) KAAPPI="$PWD/$KAAPPI" ;;
esac

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
    if [[ "$2" == "$3" ]]; then
        pass "$1"
    else
        fail "$1" "expected [$2], got [$3]"
    fi
}

# assert_exit <label> <expected> <cmd...>
assert_exit() {
    local label="$1" expected="$2"; shift 2
    local status=0
    "$@" > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        pass "$label"
    else
        fail "$label" "expected exit $expected, got $status"
    fi
}

# ── stdin formatting ─────────────────────────────────────────────────────────

got="$(printf '(list   1  2\t3)' | "$KAAPPI" fmt)"
assert_eq "stdin: collapses whitespace" "$(printf '(list 1 2 3)')" "$got"

# `'x` (the reader abbreviation) glues to its datum; a written-out `(quote x)`
# list stays a list — the formatter normalizes spacing, it does not rewrite one
# spelling into the other.
got="$(printf "'   x" | "$KAAPPI" fmt)"
assert_eq "stdin: quote abbreviation glues" "$(printf "'x")" "$got"
got="$(printf "( quote    x )" | "$KAAPPI" fmt)"
assert_eq "stdin: quote list keeps its spelling" "$(printf '(quote x)')" "$got"

# ── --check exit codes ───────────────────────────────────────────────────────

printf '(list 1 2 3)\n' > "$TMP/ok.scm"
assert_exit "check: formatted file exits 0" 0 "$KAAPPI" fmt --check "$TMP/ok.scm"

printf '(list   1 2 3)\n' > "$TMP/bad.scm"
assert_exit "check: unformatted file exits 1" 1 "$KAAPPI" fmt --check "$TMP/bad.scm"

# --check must never modify the file it inspects.
before="$(cat "$TMP/bad.scm")"
"$KAAPPI" fmt --check "$TMP/bad.scm" > /dev/null 2>&1 || true
assert_eq "check: leaves the file untouched" "$before" "$(cat "$TMP/bad.scm")"

# ── write in place, then idempotent ──────────────────────────────────────────

printf '(define    (f x)\n  (+ x    1))\n' > "$TMP/w.scm"
"$KAAPPI" fmt "$TMP/w.scm" > /dev/null 2>&1
assert_eq "write: reformats in place" "$(printf '(define (f x) (+ x 1))')" "$(cat "$TMP/w.scm")"
assert_exit "write: result is already formatted" 0 "$KAAPPI" fmt --check "$TMP/w.scm"

# ── Syntax errors are reported, not silently mangled ─────────────────────────

printf '(a b c\n' > "$TMP/unterminated.scm"
assert_exit "error: unterminated list exits 1" 1 "$KAAPPI" fmt --check "$TMP/unterminated.scm"

# ── Corpus: zero semantic drift + idempotence over the repo tree ─────────────

corpus_files() {
    find tests/scheme lib \( -name '*.scm' -o -name '*.sld' \) -type f | sort
}

count="$(corpus_files | wc -l | tr -d ' ')"
if [[ "$count" -eq 0 ]]; then
    fail "corpus: found files" "no .scm/.sld under tests/scheme or lib"
else
    # (1) Zero drift on the original tree. --check exits 1 when files are merely
    # unformatted; a genuine drift/parse failure instead prints to stderr, which
    # is what we assert is empty.
    corpus_files | xargs "$KAAPPI" fmt --check > /dev/null 2> "$TMP/drift.err" || true
    if [[ -s "$TMP/drift.err" ]]; then
        fail "corpus: zero semantic drift ($count files)" "fmt reported: $(cat "$TMP/drift.err")"
    else
        pass "corpus: zero semantic drift ($count files)"
    fi

    # (2) Idempotence: format a mirror of the tree, then re-check it. An
    # already-formatted tree must need no changes (exit 0) and still not drift.
    mkdir -p "$TMP/mirror"
    tar cf - $(corpus_files) | (cd "$TMP/mirror" && tar xf -)
    ( cd "$TMP/mirror" && corpus_files | xargs "$KAAPPI" fmt > /dev/null 2> "$TMP/fmt1.err" ) || true
    if [[ -s "$TMP/fmt1.err" ]]; then
        fail "corpus: idempotent ($count files)" "first pass reported: $(cat "$TMP/fmt1.err")"
    else
        recheck=0
        ( cd "$TMP/mirror" && corpus_files | xargs "$KAAPPI" fmt --check > "$TMP/recheck.out" 2>&1 ) || recheck=$?
        if [[ "$recheck" -eq 0 ]]; then
            pass "corpus: idempotent ($count files)"
        else
            fail "corpus: idempotent ($count files)" "re-check flagged: $(cat "$TMP/recheck.out")"
        fi
    fi
fi

echo ""
echo "fmt: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
