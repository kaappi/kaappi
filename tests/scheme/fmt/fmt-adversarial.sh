#!/bin/bash
# `kaappi fmt` — adversarial comment placement and parser-depth robustness.
#
# `fmt`'s round-trip guard re-reads both texts with the real reader and compares
# datums, so it can never let the *program* change. Comments are not datums, so
# it is structurally blind to them: a comment that moves, is duplicated, or is
# dropped passes the guard unnoticed. Idempotence — `fmt(fmt(x)) == fmt(x)` —
# is the other property the guard cannot see. This suite is those two blind
# spots, driven by cases where the layout engine has a decision to make.
#
# Each case asserts three things at once: `fmt` accepts it, every comment
# marker (`C1`, `C2`, …) survives in the same order, and a second pass is a
# no-op. Cases are one line each; the corpus-wide properties live in fmt.sh,
# and exact input→output layout lives in src/tests_fmt.zig.
#
# The generator that found the failures below is `tools/fmt_fuzz.py` — it is
# deliberately *not* run here (it takes minutes; this file takes ~2 seconds).
# See kaappi#2141, kaappi#2142, kaappi#2143.

set -uo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
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

markers() { grep -o 'C[0-9][0-9]*' "$1" | tr '\n' ' '; }

# case <label> <source-with-\n-escapes>
#
# fmt accepts it, the comment markers survive in order, and a second pass
# changes nothing.
case_() {
    local label="$1" src="$2" status=0
    printf '%b' "$src" > "$TMP/a.scm"
    "$KAAPPI" fmt < "$TMP/a.scm" > "$TMP/b.scm" 2> "$TMP/err" || status=$?
    if [[ "$status" -ne 0 ]]; then
        fail "$label" "fmt exit $status: $(cat "$TMP/err")"
        return
    fi
    local want got
    want="$(markers "$TMP/a.scm")"
    got="$(markers "$TMP/b.scm")"
    if [[ "$want" != "$got" ]]; then
        fail "$label" "comments [$want] came out as [$got]"
        return
    fi
    status=0
    "$KAAPPI" fmt < "$TMP/b.scm" > "$TMP/c.scm" 2> "$TMP/err" || status=$?
    if [[ "$status" -ne 0 ]]; then
        fail "$label" "second pass exit $status: $(cat "$TMP/err")"
        return
    fi
    if ! cmp -s "$TMP/b.scm" "$TMP/c.scm"; then
        fail "$label" "not idempotent: [$(tr '\n' '~' < "$TMP/b.scm")] then [$(tr '\n' '~' < "$TMP/c.scm")]"
        return
    fi
    pass "$label"
}

# ── Comments where the layout engine must make a decision ───────────────────

case_ "comment between define and its name"          '(define ; C1\n  x 1)\n'
case_ "comment on its own line before the name"      '(define\n  ; C1\n  x 1)\n'
case_ "comment inside a let binding list"            '(let ((a 1) ; C1\n      (b 2)) ; C2\n  (+ a b))\n'
case_ "own-line comments inside a binding list"      '(let (; C1\n      (a 1)\n      ; C2\n      (b 2))\n  (+ a b))\n'
case_ "comment between last form and close paren"    '(begin\n  (a)\n  ; C1\n  )\n'
case_ "trailing comment before the close paren"      '(begin (a) ; C1\n)\n'
case_ "comment after a dotted pair's dot"            '(a . ; C1\n   b)\n'
case_ "comment before a dotted pair's dot"           '(a ; C1\n   . b)\n'
case_ "comment inside a quasiquote unquote"          '`(a ,(f ; C1\n       x) b)\n'
case_ "comment between unquote and its datum"        '`(a , ; C1\n  b)\n'
case_ "comment in a case clause datum list"          "(case x\n  ((1 2 ; C1\n    3) 'lo)\n  (else 'hi))\n"
case_ "comment before a #; datum comment"            '(list ; C1\n  #;(dead) alive)\n'
case_ "comment after a #; datum comment"             '(list #;(dead) ; C1\n  alive)\n'
case_ "comment between #; and its datum"             '(list #; ; C1\n  (dead) alive)\n'
case_ "nested block comments"                        '#| outer C1 #| inner C2 |# tail C3 |#\n(a)\n'
case_ "; inside a block comment is not a comment"    '#| C1 ; C2 still in the block |#\n(a)\n'
case_ "#| inside a line comment never opens"         '; C1 #| never opens\n(a)\n'
case_ "|# inside a line comment never closes"        '; C1 |# never closes\n(a)\n'
case_ "comment is the whole file"                    '; C1 only\n'
case_ "line comment with no trailing newline"        '(a)\n; C1 no newline'
case_ "block comment with no trailing newline"       '(a)\n#| C1 |#'
case_ "comment is the only child of a list"          '( ; C1\n)\n'
case_ "block comment is the only child of a list"    '(#| C1 |#)\n'
case_ "comment between operator and first argument"  '(f ; C1\n  a b)\n'
case_ "block comment riding the head line"           '(define #| C1 |# x 1)\n'
case_ "block comment between let and its bindings"   '(let #| C1 |# ((a 1)) a)\n'
case_ "two block comments on one line"               '(f a #| C1 |# #| C2 |# b)\n'
case_ "line comment after a block comment"           '(f a #| C1 |# ; C2\n  b)\n'
case_ "comment inside an empty vector"               '#( ; C1\n)\n'
case_ "comment between vector elements"              '#(1 ; C1\n  2 3)\n'
case_ "comment inside a bytevector"                  '#u8(1 ; C1\n    2)\n'
case_ "comment between quote and its datum"          "'; C1\nx\n"
case_ "blank line then a comment in a body"          '(define (f)\n  (a)\n\n  ; C1\n  (b))\n'
case_ "comment then a blank line in a body"          '(define (f)\n  (a)\n  ; C1\n\n  (b))\n'
case_ "comment trailing a top-level form"            '(a) ; C1\n(b)\n'
case_ "comment forces a form that would fit inline"  '(f a ; C1\n  b)\n'
case_ "line comment past 80 columns"                 '(f a) ; C1 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
case_ "comment in a deeply nested tail"              '(a (b (c (d ; C1\n  e))))\n'
case_ "comment after the last binding"               '(let ((a 1) ; C1\n      )\n  a)\n'
case_ "datum comment over a whole define"            '#;(define x 1)\n(define y 2)\n'
case_ "datum comment targeting a block comment"      '#; #| C1 |# (dead)\n(alive)\n'
case_ "nested datum comments"                        '(list #;#;(a) (b) c)\n'
case_ "comments between do's distinguished forms"    '(do ((i 0 (+ i 1))) ; C1\n    ((= i 3)) ; C2\n  (f i))\n'
case_ "comment first, operator after it"             '(; C1\n f a)\n'
case_ "comment inside syntax-rules literals"         '(syntax-rules (; C1\n               lit)\n  ((_ x) x))\n'
case_ "comment between cond clauses"                 '(cond ((a) 1)\n      ; C1\n      ((b) 2))\n'
case_ "comment at the end of a cond clause"          '(cond ((a) 1 ; C1\n       ))\n'
case_ "carriage return inside a block comment"       '#| C1\rC2 |#\n(a)\n'
case_ "comment containing a close paren"             '(f a ; C1 )\n  b)\n'
case_ "comment containing an open paren"             '(f a ; C1 (\n  b)\n'
case_ "comment containing a double quote"            '(f a ; C1 "\n  b)\n'
case_ "block comment containing a double quote"      '(f a #| C1 " |# b)\n'
case_ "a semicolon inside a string is not a comment" '(f "; C1 not a comment")\n'

# ── Blank-line grouping around head-line comments (kaappi#2142) ──────────────
#
# These three are the discriminating controls for #2142: same blank, same
# comment, only the position differs — and all three are stable. The unstable
# one is disabled below.

case_ "blank before the first argument, no comment"  '(f\n\n   a b)\n'
case_ "blank one item after a head-line comment"     '(f #|c|# a\n\n   b)\n'
case_ "blank after a head-line line comment"         '(f ; c\n\n   a b)\n'
case_ "blank before a define body, not its name"     '(define #|c|# x\n\n  1)\n'

# FAIL: #2142 (hasBodyBlank indexes children; the printer counts non-comments,
# so a head-line-riding block comment shifts them out of step — pass 1 drops
# the blank it forced a break for, pass 2 then collapses the form inline)
# case_ "blank before an arg displaced by a comment"   '(f #|c|#\n\n   a b)\n'
# case_ "blank before a name displaced by a comment"   '(define #|c|#\n\n  x 1)\n'

# ── Lexeme boundaries the reader and fmt must agree on (kaappi#2143) ─────────
#
# Enabled: the space-separated spellings, which are the discriminating controls.

case_ "block comment after an identifier, spaced"    '(a b #|c|# d)\n'
case_ "datum comment after an identifier, spaced"    '(list a #;(b) c)\n'
case_ "vector after an identifier, spaced"           '(a b #(1) d)\n'

# FAIL: #2143 (fmt.Lexer.scanAtom runs to the next delimiter; Reader.readSymbol
# stops at the first non-subsequent, so a glued `#`-led lexeme splits
# differently — `kaappi ast` reads all three of these without complaint)
# case_ "block comment glued to an identifier"         '(a b#|c|# d)\n'
# case_ "datum comment glued to an identifier"         '(list a#;(b) c)\n'
# case_ "vector glued to an identifier"                '(a b#(1) d)\n'

# ── Parser depth: a deep input is rejected, never fatal (kaappi#2141) ────────

# repeat <byte> <count> — a portable "print this byte N times" with no seq,
# no python and no shell loop.
repeat() { head -c "$2" /dev/zero | tr '\0' "$1"; }

# assert_clean_reject <label> <path>
#   The input is deeper than any reader accepts (`kaappi` itself answers
#   `read error[KP1009]: nesting too deep` at 1025), so `fmt` must decline it —
#   but with an exit code, not a signal. Anything >= 128 is a crash.
assert_clean_reject() {
    local label="$1" path="$2" status=0
    "$KAAPPI" fmt < "$path" > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq 1 ]]; then
        pass "$label"
    elif [[ "$status" -ge 128 ]]; then
        fail "$label" "died on a signal (exit $status), not a clean rejection"
    else
        fail "$label" "expected exit 1, got $status"
    fi
}

{ repeat '(' 300000; repeat ')' 300000; echo; } > "$TMP/deep-list.scm"
assert_clean_reject "depth: 300000 nested lists rejected cleanly" "$TMP/deep-list.scm"

# FAIL: #2141 (max_nesting is checked in parseList only; parsePrefixTarget
# recurses unguarded, so a long prefix chain overflows the native stack —
# ~158000 on an 8 MB stack, and every prefix kind reaches it)
# { repeat "'" 300000; echo x; } > "$TMP/deep-quote.scm"
# assert_clean_reject "depth: 300000 quote prefixes rejected cleanly" "$TMP/deep-quote.scm"

echo ""
echo "fmt-adversarial: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
