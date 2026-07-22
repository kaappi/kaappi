;; SRFI-247 (Syntactic Monads) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi247.scm
;;
;; Every expected value below is the SRFI's own worked example output,
;; not just an internally-consistent check.

(import (scheme base) (scheme process-context) (srfi 247) (srfi 64))

(test-begin "srfi-247")

(define-syntactic-monad $ a b)

;;; --- 1. lambda ---
(test-equal "$ lambda: threads state variables ahead of the given formals"
  '(1 2 3)
  (($ lambda (c) (list a b c)) 1 2 3))

;; the spec's own shadowing rule: a local formal with the same name as a
;; state variable shadows it rather than producing a duplicate parameter
;; -- "a" drops out of the threaded prefix, leaving just (b . (a)), so
;; the first argument becomes b and the second becomes the local a
(test-equal "$ lambda: a local formal shadows a same-named state variable"
  '(2 1 9)
  (($ lambda (a) (list a b 9)) 1 2))

;;; --- 2. define ---
($ define (f c d) (list a b c d))
(test-equal "$ define: equivalent to (define name ($ lambda ...))" '(1 2 3 4) (f 1 2 3 4))

;;; --- 3. case-lambda ---
(test-equal "$ case-lambda: threads state variables into every clause"
  '(1 2)
  (($ case-lambda (() (list a b))) 1 2))
(test-equal "$ case-lambda: dispatches on arity like ordinary case-lambda"
  '(1 2 9)
  (($ case-lambda (() (list a b)) ((x) (list a b x))) 1 2 9))

;;; --- 4. let*-values ---
;; the spec's own example
(test-equal "$ let*-values: spec's own worked example"
  '(1 5)
  ($ let*-values (((c) (values 1 2 3)) (() (values a (+ b c)))) (list a b)))

;;; --- 5. procedure call, with optional per-state-variable bindings ---
(test-equal "$ call: an explicit binding overrides a state variable for this call"
  '(1 2 4)
  (let ((a 1)) ($ list ((b 2)) 4)))
(test-equal "$ call: shorthand with no bindings and no extra arguments"
  '(1 6)
  (let ((a 1) (b 6)) ($ list)))
(test-equal "$ call: an unbound state variable falls back to its lexical value"
  '(1 6 9)
  (let ((a 1) (b 6)) ($ list () 9)))

;;; --- 6. let loop ---
;; the spec's own worked example
(test-equal "$ let loop: spec's own worked example"
  '(2 8 10)
  (let ((a 1))
    ($ let loop ((c 3) (b 2))
      (if (= a 2) (list a b c) (loop 2 (+ b 6) (+ c 7))))))

;; a state variable never mentioned in the loop's own clauses still
;; becomes one of the expanded loop procedure's own parameters, so
;; recursive calls must still pass it explicitly (same as the spec's own
;; example, which passes all three of a/b/c on every recursive call)
(define-syntactic-monad $1 v)
(test-equal "$ let loop: a state variable absent from the loop's clauses stays fixed"
  '(1 0)
  (let ((v 1))
    ($1 let loop ((n 3))
      (if (= n 0) (list v n) (loop v (- n 1))))))

(let ((runner (test-runner-current)))
  (test-end "srfi-247")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
