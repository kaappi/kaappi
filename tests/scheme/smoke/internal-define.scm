;; Regression test for #591: internal define must support recursion (R7RS 5.3.2)
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "internal-define")

;; Self-recursive internal define
(test-equal "self-recursive factorial"
  120
  (let ()
    (define (f n) (if (= n 0) 1 (* n (f (- n 1)))))
    (f 5)))

;; Mutual recursion via internal defines
(test-equal "mutually recursive even?/odd?"
  #t
  (let ()
    (define (even? n) (if (= n 0) #t (odd? (- n 1))))
    (define (odd? n) (if (= n 0) #f (even? (- n 1))))
    (even? 10)))

(test-equal "mutually recursive odd? result"
  #t
  (let ()
    (define (even? n) (if (= n 0) #t (odd? (- n 1))))
    (define (odd? n) (if (= n 0) #f (even? (- n 1))))
    (odd? 7)))

;; Forward reference (foo calls bar, defined after foo)
(test-equal "forward reference between internal defines"
  45
  (let ((x 5))
    (define foo (lambda (y) (bar x y)))
    (define bar (lambda (a b) (+ (* a b) a)))
    (foo (+ x 3))))

;; Non-recursive internal defines still work
(test-equal "non-recursive sequential defines"
  43
  (let ()
    (define x 42)
    (define y (+ x 1))
    y))

;; Internal define in function body (not just let body)
(test-equal "internal define in function body"
  120
  (begin
    (define (test-fn)
      (define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))
      (fact 5))
    (test-fn)))

;; Mixed defines and body expressions
(test-equal "defines followed by body expression"
  30
  (let ()
    (define a 10)
    (define (double x) (* x 2))
    (+ a (double a))))

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "internal-define")
(if (> %test-fail-count 0) (exit 1))
