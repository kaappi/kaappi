#!/bin/bash
# `kaappi ast` / `expand` / `ir` — pipeline-stage dumps (kaappi#1512).
#
# Covers the round-trip contract (feeding `expand` output back preserves
# behavior), the `ast` reader-view basics (quote desugaring, fold-case), the
# `ir` before/after-optimization difference `--no-opt` exposes, and the usage
# exit codes.

set -uo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# assert_roundtrip <label> <source> — running the program and running its full
# expansion must produce byte-identical stdout+stderr.
assert_roundtrip() {
    local label="$1" src="$2"
    printf '%s\n' "$src" > "$TMP/prog.scm"
    if ! "$KAAPPI" expand "$TMP/prog.scm" > "$TMP/prog.expanded.scm" 2> "$TMP/expand.err"; then
        fail "$label" "expand failed: $(cat "$TMP/expand.err")"
        return
    fi
    local a b
    a="$("$KAAPPI" "$TMP/prog.scm" 2>&1)"
    b="$("$KAAPPI" "$TMP/prog.expanded.scm" 2>&1)"
    if [[ "$a" == "$b" ]]; then
        pass "$label"
    else
        fail "$label" "round-trip diverged"$'\n'"  original: $a"$'\n'"  expanded: $b"
    fi
}

# assert_out <label> <cmd...> ::: <pattern> — stdout of the command matches.
assert_out() {
    local label="$1"; shift
    local pattern="$1"; shift
    local out
    out="$("$@" 2>&1)"
    if grep -qF "$pattern" <<< "$out"; then
        pass "$label"
    else
        fail "$label" "expected to find: $pattern"$'\n'"  got: $out"
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

# ── Round-trip: expand output preserves behavior ────────────────────────────

assert_roundtrip "roundtrip: swap! macro" '
(import (scheme base) (scheme write))
(define-syntax swap! (syntax-rules () ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(define x 1) (define y 2)
(swap! x y)
(display (list x y)) (newline)'

assert_roundtrip "roundtrip: recursive my-or in a body" '
(import (scheme base) (scheme write))
(define-syntax my-or (syntax-rules () ((_) #f) ((_ e) e) ((_ e1 e2 ...) (let ((t e1)) (if t t (my-or e2 ...))))))
(display (my-or #f #f 7)) (newline)'

assert_roundtrip "roundtrip: macro across cond/case/do/let-values" '
(import (scheme base) (scheme write))
(define-syntax inc (syntax-rules () ((_ x) (+ x 1))))
(define (classify n)
  (cond ((< n 0) (quote neg))
        (else (case (inc n) ((1 2 3) (quote small)) (else (quote big))))))
(do ((k 0 (inc k))) ((= k 2)) (display (classify k)) (newline))
(let-values (((q r) (floor/ 7 2))) (display (list q r)) (newline))'

assert_roundtrip "roundtrip: imported macro (receive from srfi 8)" '
(import (scheme base) (scheme write) (srfi 8))
(receive (q r) (floor/ 17 5) (display (list q r)) (newline))'

assert_roundtrip "roundtrip: quoted data untouched" '
(import (scheme base) (scheme write))
(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))
(display (quote (dbl 1 2))) (newline)
(display (dbl 4)) (newline)'

# kaappi#1894: expand expanded a let-syntax/letrec-syntax body with the OUTER
# binding of a shadowed keyword, then re-emitted the never-applied inner
# binding — so the dump printed 42 where the program yields 99. The body of a
# local-macro form is now left unexpanded (its local transformers are never
# built here), so re-reading re-establishes the inner binding and round-trips.
assert_roundtrip "roundtrip: let-syntax shadowing an outer keyword (#1894)" '
(import (scheme base) (scheme write))
(define-syntax c (syntax-rules () ((c) 42)))
(display (let-syntax ((c (syntax-rules () ((c) 99)))) (c))) (newline)'

assert_roundtrip "roundtrip: letrec-syntax shadowing an outer keyword (#1894)" '
(import (scheme base) (scheme write))
(define-syntax c (syntax-rules () ((c) 42)))
(display (letrec-syntax ((c (syntax-rules () ((c) 99)))) (c))) (newline)'

# kaappi#1894 second shape: a macro (here a SRFI 139 syntax parameter) expands
# into a let-syntax whose binder is hygiene-renamed while the body use keeps its
# original spelling — severing the link, so the re-read dump raised
# "abort used outside of a loop" instead of yielding 4. registerEnvForExpand now
# registers the macro-generated define-syntax, so the shared keyword stays bare
# through the later expansion.
assert_roundtrip "roundtrip: syntax-parameter through let-syntax (#1894)" '
(import (scheme base) (scheme write) (srfi 139))
(define-syntax-parameter abort
  (syntax-rules () ((_ . _) (syntax-error "abort used outside of a loop"))))
(define-syntax forever
  (syntax-rules ()
    ((forever body1 body2 ...)
     (call-with-current-continuation
      (lambda (escape)
        (syntax-parameterize
            ((abort (syntax-rules () ((abort v (... ...)) (escape v (... ...))))))
          (let loop () body1 body2 ... (loop))))))))
(display
  (let ((n 0))
    (forever (set! n (+ n 1)) (when (> n 3) (abort n))))) (newline)'

# ── ast: the reader view ────────────────────────────────────────────────────

printf "%s\n" "'(a b c)" > "$TMP/ast.scm"
assert_out "ast: quote desugars" "(quote (a b c))" "$KAAPPI" ast "$TMP/ast.scm"

printf '%s\n' '#!fold-case' '(HELLO World)' > "$TMP/fold.scm"
assert_out "ast: fold-case lowercases identifiers" "(hello world)" "$KAAPPI" ast "$TMP/fold.scm"

# ── ir: optimized vs --no-opt ───────────────────────────────────────────────

printf '%s\n' '(+ 1 2)' > "$TMP/fold-num.scm"
assert_out "ir: optimized folds (+ 1 2) to a constant" "(constant 3)" "$KAAPPI" ir "$TMP/fold-num.scm"
assert_out "ir: --no-opt keeps the call" "(global-ref +)" "$KAAPPI" ir "$TMP/fold-num.scm" --no-opt

printf '%s\n' '(define-syntax m (syntax-rules () ((_ x) x)))' '(m 5)' > "$TMP/mac.scm"
assert_out "ir: macro use lowers to passthrough" "(passthrough (m 5))" "$KAAPPI" ir "$TMP/mac.scm"

# ── Exit codes ───────────────────────────────────────────────────────────────

printf '%s\n' '(a b' > "$TMP/bad.scm"
assert_exit "ast: read error exits 1" 1 "$KAAPPI" ast "$TMP/bad.scm"
assert_exit "expand: read error exits 1" 1 "$KAAPPI" expand "$TMP/bad.scm"
assert_exit "ir: missing file argument is a usage error" 2 "$KAAPPI" ir

echo ""
echo "pipeline: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
