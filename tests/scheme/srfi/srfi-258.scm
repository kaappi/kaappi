;; SRFI 258 — Uninterned Symbols conformance test.
;;
;; An uninterned symbol is a symbol not `eqv?` to any other symbol, even one
;; with the same name. The three procedures are string->uninterned-symbol,
;; symbol-interned?, and generate-uninterned-symbol. Deterministic GC-sweep and
;; cross-thread deep-copy coverage lives in src/tests_srfi258.zig.

(import (scheme base) (scheme write) (scheme read)
        (scheme process-context) (srfi 64) (srfi 258))

(test-begin "srfi-258")

;;; --- string->uninterned-symbol --------------------------------------------

(define a (string->uninterned-symbol "x"))
(define b (string->uninterned-symbol "x"))

(test-assert "result is a symbol" (symbol? a))
(test-assert "result is uninterned" (not (symbol-interned? a)))
(test-equal "name round-trips through symbol->string" "x" (symbol->string a))

;; Two uninterned symbols with the same name are distinct under every
;; equivalence — Kaappi compares symbols by identity, not name.
(test-assert "two same-name uninterned are not eqv?" (not (eqv? a b)))
(test-assert "two same-name uninterned are not eq?" (not (eq? a b)))
(test-assert "two same-name uninterned are not equal?" (not (equal? a b)))

;; An uninterned symbol is never the like-named interned symbol.
(test-assert "uninterned is not eqv? to interned of same name" (not (eqv? a 'x)))
(test-assert "uninterned is not eq? to interned of same name" (not (eq? a 'x)))

;; But it is of course eqv? to itself, and usable as an identity key.
(test-assert "an uninterned symbol is eqv? to itself" (eqv? a a))
(test-equal "usable as an assq identity key"
  'found (cond ((assq a (list (cons a 'found) (cons b 'other))) => cdr) (else 'missing)))

;; Wrong argument types are rejected.
(test-error "string->uninterned-symbol on a non-string errors"
  (string->uninterned-symbol 'not-a-string))

;;; --- symbol-interned? -----------------------------------------------------

(test-assert "an ordinary symbol is interned" (symbol-interned? 'ordinary))
(test-assert "a read symbol is interned" (symbol-interned? (string->symbol "y")))
(test-assert "uninterned symbol is not interned" (not (symbol-interned? a)))
(test-error "symbol-interned? on a non-symbol errors" (symbol-interned? 42))

;;; --- generate-uninterned-symbol -------------------------------------------

(test-assert "generated symbol is uninterned"
  (not (symbol-interned? (generate-uninterned-symbol))))

(let ((g1 (generate-uninterned-symbol))
      (g2 (generate-uninterned-symbol)))
  (test-assert "two generated symbols are distinct" (not (eqv? g1 g2))))

;; Optional prefix: a string is used verbatim, a symbol contributes its name.
(test-assert "string prefix is prepended"
  (let ((n (symbol->string (generate-uninterned-symbol "pre-"))))
    (and (>= (string-length n) 4) (string=? (substring n 0 4) "pre-"))))
(test-assert "symbol prefix contributes its name"
  (let ((n (symbol->string (generate-uninterned-symbol 'tag))))
    (and (>= (string-length n) 3) (string=? (substring n 0 3) "tag"))))
(test-error "non-string, non-symbol prefix errors"
  (generate-uninterned-symbol 42))
(test-error "more than one argument errors"
  (generate-uninterned-symbol "a" "b"))

;;; --- external representation: read must reject it --------------------------

;; SRFI 258 deliberately breaks R7RS 6.5 write/read invariance: an uninterned
;; symbol has no external representation that reads back, so `read` must signal
;; an error when it meets the form `write` produces.
(test-error "read rejects the written form of an uninterned symbol"
  (read (open-input-string
         (let ((out (open-output-string)))
           (write a out)
           (get-output-string out)))))

;; display, being lossy, still shows the bare name.
(test-equal "display shows the bare name"
  "x" (let ((out (open-output-string))) (display a out) (get-output-string out)))

(let ((runner (test-runner-current)))
  (test-end "srfi-258")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
