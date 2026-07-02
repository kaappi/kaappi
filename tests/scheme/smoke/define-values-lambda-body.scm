;; Regression test for #687: define-values with 2+ names inside a lambda
;; body must not corrupt registers.

;; Two names inside lambda body — the primary failure case
(define (f)
  (define-values (p q) (values 100 200))
  (+ p q))
(unless (= (f) 300)
  (display "FAIL: (f) should be 300, got ")
  (display (f))
  (newline)
  (exit 1))

;; Three names
(define (g)
  (define-values (a b c) (values 1 2 3))
  (list a b c))
(unless (equal? (g) '(1 2 3))
  (display "FAIL: (g) should be (1 2 3), got ")
  (display (g))
  (newline)
  (exit 1))

;; Single name (should still work, was not broken)
(define (h)
  (define-values (x) (values 42))
  x)
(unless (= (h) 42)
  (display "FAIL: (h) should be 42, got ")
  (display (h))
  (newline)
  (exit 1))

;; Top-level define-values (was not broken, sanity check)
(define-values (a b) (values 10 20))
(unless (= (+ a b) 30)
  (display "FAIL: top-level define-values")
  (newline)
  (exit 1))

;; define-values inside let body (was not broken, sanity check)
(let ()
  (define-values (x y) (values 5 6))
  (unless (= (+ x y) 11)
    (display "FAIL: let body define-values")
    (newline)
    (exit 1)))

(display "PASS")
(newline)
