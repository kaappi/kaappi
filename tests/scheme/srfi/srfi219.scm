;; SRFI-219 (define higher-order lambda) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi219.scm

(import (scheme base) (srfi 219) (chibi test))

(test-begin "srfi-219")

;;; --- plain define still works alongside the import ---
(define forty-two 42)
(test 42 forty-two)
(define (plain x) (* x 2))
(test 10 (plain 5))
(define (var-args . xs) xs)
(test '(1 2) (var-args 1 2))

;;; --- one level of currying ---
(define ((adder n) m) (+ n m))
(test 7 ((adder 3) 4))
(define add5 (adder 5))
(test 15 (add5 10))

;;; --- two levels ---
(define (((compose3 f) g) x) (f (g x)))
(test 9 (((compose3 (lambda (n) (* n n))) (lambda (n) (+ n 1))) 2))

;;; --- rest arguments at each level ---
(define ((cat . xs) . ys) (append xs ys))
(test '(1 2 3) ((cat 1 2) 3))

;;; --- multi-expression bodies ---
(define ((counter start) step)
  (define next (+ start step))
  next)
(test 12 ((counter 10) 2))

;;; --- curried define inside let/begin bodies ---
(define let-result (let () (define ((f a) b) (+ a b)) ((f 1) 2)))
(test 3 let-result)
(define begin-result (begin (define ((g a) b) (* a b)) ((g 4) 5)))
(test 20 begin-result)

(test-end "srfi-219")
