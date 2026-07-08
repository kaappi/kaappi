;; SRFI-232 (flexible curried procedures) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi232.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 232))

(test-begin "srfi-232")

;;; --- one-argument-at-a-time application ---
(define-curried (inc x) (+ x 1))
(test-equal "unary define-curried" 6 (inc 5))

(define-curried (add2 a b) (+ a b))
(test-equal "2-arg one-at-a-time" 3 ((add2 1) 2))

(define-curried (mul3 a b c) (* a b c))
(test-equal "3-arg one-at-a-time" 24 (((mul3 2) 3) 4))

(define-curried (cat4 a b c d) (list a b c d))
(test-equal "4-arg one-at-a-time" '(1 2 3 4) ((((cat4 1) 2) 3) 4))

;; partial applications are reusable closures
(define add10 (add2 10))
(test-equal "reusable partial 1" 11 (add10 1))
(test-equal "reusable partial 2" 30 (add10 20))

;; each partial application captures independently
(define t2 (mul3 2))
(define t3 (mul3 3))
(test-equal "independent capture 1" 24 ((t2 3) 4))
(test-equal "independent capture 2" 36 ((t3 3) 4))

;;; --- grouped application (#1238) ---
(test-equal "2-arg grouped" 3 (add2 1 2))
(test-equal "3-arg grouped" 24 (mul3 2 3 4))
(test-equal "3-arg partial+grouped" 24 ((mul3 2 3) 4))
(test-equal "4-arg grouped" '(1 2 3 4) (cat4 1 2 3 4))
(test-equal "4-arg 2+2" '(1 2 3 4) ((cat4 1 2) 3 4))
(test-equal "4-arg 1+2+1" '(1 2 3 4) (((cat4 1) 2 3) 4))
(test-equal "4-arg 3+1" '(1 2 3 4) ((cat4 1 2 3) 4))

;;; --- curried lambda form (#1238: was not exported) ---
(test-equal "curried form grouped" 7 ((curried (a b) (+ a b)) 3 4))
(test-equal "curried form one-at-a-time" 7 (((curried (a b) (+ a b)) 3) 4))

;;; --- zero-arg returns self (#1238) ---
(define f-self (curried (a b c) (+ a b c)))
(test-assert "zero-arg returns self" (eq? f-self (f-self)))

;;; --- nullary formals (#1238: was syntax error) ---
(define-curried (thunk) 'ok)
(test-equal "nullary define-curried" 'ok thunk)
(test-equal "nullary curried" 'ok (curried () 'ok))
(test-equal "nullary chains to curried" 3
  ((curried () (curried (x y) (+ x y))) 1 2))
(test-equal "nullary chain one-at-a-time" 3
  (((curried () (curried (x y) (+ x y))) 1) 2))

;;; --- >4 args (#1238: was syntax error) ---
(define-curried (five a b c d e) (list a b c d e))
(test-equal "5-arg grouped" '(1 2 3 4 5) (five 1 2 3 4 5))
(test-equal "5-arg one-at-a-time" '(1 2 3 4 5) (((((five 1) 2) 3) 4) 5))
(test-equal "5-arg 2+3" '(1 2 3 4 5) ((five 1 2) 3 4 5))

;;; --- variadic (dotted) formals ---
(test-equal "variadic grouped" '(3 (3 4))
  ((curried (a b . rest) (list (+ a b) rest)) 1 2 3 4))
(test-equal "variadic partial" '(3 (3 4))
  (((curried (a b . rest) (list (+ a b) rest)) 1) 2 3 4))
(test-equal "variadic no rest args" '(3 ())
  ((curried (a b . rest) (list (+ a b) rest)) 1 2))

;;; --- surplus forwarding ---
(test-equal "surplus forwarding grouped" 20
  ((curried (x y) (curried (z) (* z (+ x y)))) 2 3 4))
(test-equal "surplus forwarding partial" 20
  (((curried (x y) (curried (z) (* z (+ x y)))) 2) 3 4))

;;; --- deep nullary nesting (zero-arg is identity) ---
(test-equal "deep nullary" 4
  (((((((((curried (a b c) 4)))))))) 1 2 3))

;;; --- multiple body expressions ---
(define-curried (multi a b)
  (define x (+ a b))
  (* x 2))
(test-equal "multiple body" 10 (multi 2 3))
(test-equal "multiple body partial" 10 ((multi 2) 3))

;;; --- single-identifier formals (plain lambda) ---
(test-equal "single-id formals" '(1 2 3)
  ((curried args args) 1 2 3))

(let ((runner (test-runner-current)))
  (test-end "srfi-232")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
