;; Phase 1 basic test
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "basic")

;; Literals and arithmetic
(test-assert "literal 42" 42)
(test-eqv "addition" 3 (+ 1 2))
(test-eqv "subtraction" 7 (- 10 3))
(test-eqv "multiplication" 20 (* 4 5))

;; Conditionals
(test-eq "if true" 'yes (if #t 'yes 'no))
(test-eq "if false" 'no (if #f 'yes 'no))

;; Variadic arithmetic
(test-eqv "variadic +" 15 (+ 1 2 3 4 5))

;; Define and set!
(define x 42)
(test-eqv "define x" 42 x)
(set! x 99)
(test-eqv "set! x" 99 x)

;; Lambda
(define add1 (lambda (x) (+ x 1)))
(test-eqv "lambda add1" 11 (add1 10))
(test-eqv "anonymous lambda" 7 ((lambda (x y) (+ x y)) 3 4))

;; Begin
(test-eqv "begin" 3 (begin 1 2 3))

;; Quote
(test-equal "quote" '(a b c) (quote (a b c)))

;; Pairs
(test-equal "cons" '(1 . 2) (cons 1 2))
(test-eqv "car" 1 (car (cons 1 2)))
(test-eqv "cdr" 2 (cdr (cons 1 2)))

;; Type predicates
(test-eqv "null? empty" #t (null? '()))
(test-eqv "null? non-empty" #f (null? 42))
(test-eqv "pair? pair" #t (pair? (cons 1 2)))
(test-eqv "pair? non-pair" #f (pair? 42))

;; Nested arithmetic
(test-eqv "nested arithmetic" 12 (+ (* 2 3) (- 10 4)))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "basic")
(if (> %test-fail-count 0) (exit 1))
