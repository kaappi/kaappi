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

# ── Regression #1652: arguments past the 64th must not be dropped ────────────
# The CLI once collected script args into a fixed [64] buffer and silently
# discarded the rest, so a single fmt/--check invocation over a big file list
# (exactly how xargs drives the corpus below) never touched files 65+.

mkdir -p "$TMP/argcliff"
cliff_files=()
for i in $(seq 1 70); do
    printf '(define x %d)\n' "$i" > "$TMP/argcliff/f$i.scm"
    cliff_files+=("$TMP/argcliff/f$i.scm")
done
printf '(define    y   70)\n' > "$TMP/argcliff/f70.scm" # only unformatted file
status=0
"$KAAPPI" fmt --check "${cliff_files[@]}" > "$TMP/argcliff.out" 2>&1 || status=$?
if [[ "$status" -eq 1 ]] && grep -q "f70.scm" "$TMP/argcliff.out"; then
    pass "check: file #70 of 70 still checked (#1652)"
else
    fail "check: file #70 of 70 still checked (#1652)" "exit $status, output: $(cat "$TMP/argcliff.out")"
fi

# ── Line endings: LF, like `zig fmt` (kaappi#1897) ───────────────────────────
#
# Every fixture here is built with an explicit printf, never checked in: a
# committed CRLF file would be rewritten by git's own eol filters on a checkout
# with core.autocrlf=true — which is precisely the Windows configuration these
# cases exist to cover — and the test would then assert nothing. printf writes
# the bytes it is given on every platform, Git Bash included, and the fd is
# opened O_BINARY throughout (src/platform.zig), so no CRT translation touches
# it either.
#
# assert_bytes <label> <expected-file> <actual-file>: byte-exact comparison.
# `cmp`, not `$(cat …)`: command substitution would strip the trailing newline
# whose presence is half of what several of these check.
assert_bytes() {
    if cmp -s "$2" "$3"; then
        pass "$1"
    else
        fail "$1" "expected [$(od -c < "$2" | tr '\n' ' ')], got [$(od -c < "$3" | tr '\n' ' ')]"
    fi
}

# eol_case <label> <input-printf-format> <expected-printf-format>
eol_case() {
    local label="$1"
    printf "$2" > "$TMP/eol-in.scm"
    printf "$3" > "$TMP/eol-want.scm"
    "$KAAPPI" fmt "$TMP/eol-in.scm" > /dev/null 2>&1
    assert_bytes "eol: $label" "$TMP/eol-want.scm" "$TMP/eol-in.scm"
    # Whatever the policy produces must be a fixed point, or a formatted tree
    # goes dirty again on the next run.
    assert_exit "eol: $label (fixed point)" 0 "$KAAPPI" fmt --check "$TMP/eol-in.scm"
}

eol_case "CRLF throughout becomes LF" \
    '(define x 1)\r\n(define y 2)\r\n' '(define x 1)\n(define y 2)\n'
eol_case "lone CR becomes LF" \
    '(define x 1)\r(define y 2)\r' '(define x 1)\n(define y 2)\n'
eol_case "mixed endings all become LF" \
    '(a)\r\n(b)\n(c)\r' '(a)\n(b)\n(c)\n'
eol_case "CRLF file gains no second newline" \
    '(define x 1)\r\n(define y 2)' '(define x 1)\n(define y 2)\n'
eol_case "trailing CR of a line comment is dropped" \
    '(define x 1) ; note\r\n(define y 2)\r\n' '(define x 1) ; note\n(define y 2)\n'
eol_case "block comment interior normalises" \
    '#| a\r\nb |#\r\n(define x 1)\r\n' '#| a\nb |#\n(define x 1)\n'
eol_case "CRLF blank line stays one blank line" \
    '(a)\r\n\r\n(b)\r\n' '(a)\n\n(b)\n'

# A CR *inside a datum* is program data — changing it changes the program — so
# it survives under any policy. These files are already canonical: --check must
# say so, and fmt must not touch a byte.
eol_case "CR inside a string literal is untouched" \
    '(define s "a\rb")\n' '(define s "a\rb")\n'
eol_case "CR inside a raw string is untouched" \
    '(define s #"X"a\rb"X")\n' '(define s #"X"a\rb"X")\n'
eol_case "CR inside a piped symbol is untouched" \
    '(define |a\rb| 1)\n' '(define |a\rb| 1)\n'
eol_case "raw return character literal is untouched" \
    '(define c #\\\r)\n' '(define c #\\\r)\n'

# --check reports a CRLF file, because fmt would rewrite it. The two share one
# comparison in formatFile, so they cannot disagree — this pins the direction.
printf '(define x 1)\r\n' > "$TMP/eol-crlf.scm"
assert_exit "eol: --check flags a CRLF-only difference" 1 "$KAAPPI" fmt --check "$TMP/eol-crlf.scm"
before="$(od -c < "$TMP/eol-crlf.scm")"
"$KAAPPI" fmt --check "$TMP/eol-crlf.scm" > /dev/null 2>&1 || true
assert_eq "eol: --check leaves the CRLF file untouched" "$before" "$(od -c < "$TMP/eol-crlf.scm")"

# stdin takes the same policy. fd 0/1 are _setmode(O_BINARY) on Windows
# (src/platform.zig), so this is the same comparison there.
printf '(define x 1)\n' > "$TMP/eol-stdin-want.scm"
printf '(define x 1)\r\n' | "$KAAPPI" fmt > "$TMP/eol-stdin-got.scm" 2>/dev/null
assert_bytes "eol: stdin CRLF formats to LF" "$TMP/eol-stdin-want.scm" "$TMP/eol-stdin-got.scm"

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
