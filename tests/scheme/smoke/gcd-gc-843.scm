;; Regression test for #843: GC use-after-free in gcd and rational-reduction
;; Euclid loops. Consecutive Fibonacci numbers are coprime and maximize
;; Euclid iterations, exposing unrooted intermediates.

(define (fib-pair n)
  (let loop ((i 1) (a 1) (b 1))
    (if (= i n) (cons a b) (loop (+ i 1) b (+ a b)))))

(define x (car (fib-pair 300)))
(define y (cdr (fib-pair 300)))

;; gcd(F300, F301) must always be 1
(let loop ((i 0) (ok #t))
  (if (< i 50)
      (let ((g (gcd x y)))
        (loop (+ i 1) (and ok (= g 1))))
      (begin (display ok) (newline))))

;; Rational reduction: F300/F301 is already in lowest terms
(let loop ((i 0) (ok #t))
  (if (< i 50)
      (let ((r (/ x y)))
        (loop (+ i 1) (and ok (= (numerator r) x) (= (denominator r) y))))
      (begin (display ok) (newline))))

;; lcm with bignums
(let ((l (lcm x y)))
  (display (= l (* x y)))
  (newline))
