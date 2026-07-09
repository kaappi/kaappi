;; SRFI-197 (pipeline operators) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi197.scm

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 197))

(test-begin "srfi-197")

;;; --- chain with _ placeholder ---
(test-equal "chain _ last arg" -9 (chain 10 (- 1 _)))
(test-equal "chain _ first arg" 9 (chain 10 (- _ 1)))
(test-equal "chain _ builds list" '(a x) (chain 'x (list 'a _)))
(test-equal "chain _ first in list" '(x a) (chain 'x (list _ 'a)))
(test-equal "chain multiple _" 0 (chain 5 (- _ _)))
(test-equal "chain _ in operator position" 3 (chain + (_ 1 2)))

;;; --- chain multi-step ---
(test-equal "chain two steps" 9 (chain 1 (+ _ 2) (* _ 3)))
(test-equal "chain subtraction" 4 (chain 16 (- _ 12)))
(test-equal "chain list step" '(1 2) (chain 1 (list _ 2)))

;;; --- chain: no _ means pipeline value is ignored (SRFI-197 spec) ---
(test-equal "chain no _ ignores pipeline" 3 (chain 99 (+ 1 2)))

;;; --- chain base case ---
(test-equal "chain identity" 5 (chain 5))

;;; --- chain-and ---
(test-equal "chain-and basic" 3 (chain-and 1 (+ _ 2)))
(test-equal "chain-and short-circuit" #f (chain-and #f (+ _ 2)))
(define (to-false x) #f)
(define (boom x) (error "must not run"))
(test-equal "chain-and multi-step" #f
  (chain-and 1 (+ _ 1) (to-false _) (boom _)))
(test-equal "chain-and immediate false" #f
  (chain-and 1 (to-false _) (boom _)))

;;; --- chain-when: guard is an expression, not a procedure call ---
(test-equal "chain-when guard true" 15
  (chain-when 10 (#t (+ _ 5))))
(test-equal "chain-when guard false" 10
  (chain-when 10 (#f (+ _ 5))))
(test-equal "chain-when expression guard"
  '("positive" "odd")
  (let ((n 3))
    (chain-when '()
      ((odd? n) (cons "odd" _))
      ((even? n) (cons "even" _))
      ((positive? n) (cons "positive" _)))))
(test-equal "chain-when false guard in middle"
  '("positive" "even")
  (let ((n 4))
    (chain-when '()
      ((odd? n) (cons "odd" _))
      ((even? n) (cons "even" _))
      ((positive? n) (cons "positive" _)))))

;;; --- chain-lambda ---
(test-equal "chain-lambda basic" 9
  ((chain-lambda (+ _ 2) (* _ 3)) 1))
(test-equal "chain-lambda placeholder" -9
  ((chain-lambda (- 1 _)) 10))

;;; --- nest ---
(test-equal "nest basic" '(a (b (c)))
  (nest (list 'a _) (list 'b _) (list 'c)))
(test-equal "nest two levels" '(1 (2 3))
  (nest (list 1 _) (list 2 3)))
(test-equal "nest identity" 42 (nest 42))

;;; --- nest-reverse ---
(test-equal "nest-reverse basic" '(a (b (c)))
  (nest-reverse (list 'c) (list 'b _) (list 'a _)))
(test-equal "nest-reverse two levels" '(1 (2 3))
  (nest-reverse (list 2 3) (list 1 _)))
(test-equal "nest-reverse identity" 42 (nest-reverse 42))

;;; --- nest and nest-reverse equivalence ---
(test-equal "nest = nest-reverse (reversed)"
  '(a (b c))
  (nest-reverse 'c (list 'b _) (list 'a _)))

(let ((runner (test-runner-current)))
  (test-end "srfi-197")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
