;; Regression test for #843: GC use-after-free in gcd and rational-reduction
;; Euclid loops. Consecutive Fibonacci numbers are coprime and maximize
;; Euclid iterations, exposing unrooted intermediates.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "gcd-gc-843")

(define (fib-pair n)
  (let loop ((i 1) (a 1) (b 1))
    (if (= i n) (cons a b) (loop (+ i 1) b (+ a b)))))

(define x (car (fib-pair 300)))
(define y (cdr (fib-pair 300)))

;; gcd(F300, F301) must always be 1
(test-assert "50 consecutive (gcd F300 F301) all give 1"
  (let loop ((i 0) (ok #t))
    (if (< i 50)
        (loop (+ i 1) (and ok (= (gcd x y) 1)))
        ok)))

;; Rational reduction: F300/F301 is already in lowest terms
(test-assert "50 consecutive (/ F300 F301) stay in lowest terms"
  (let loop ((i 0) (ok #t))
    (if (< i 50)
        (let ((r (/ x y)))
          (loop (+ i 1) (and ok (= (numerator r) x) (= (denominator r) y))))
        ok)))

;; lcm with bignums
(test-assert "(lcm F300 F301) = F300 * F301" (= (lcm x y) (* x y)))

(let ((runner (test-runner-current)))
  (test-end "gcd-gc-843")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
