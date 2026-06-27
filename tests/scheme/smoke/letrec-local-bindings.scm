;; Regression test for issue #70:
;; letrec/letrec* must give each activation fresh bindings (not shared globals).

(import (scheme base) (scheme write))

;; Per-activation state: two closures from the same letrec must be independent
(define (counter)
  (letrec ((n 0) (inc (lambda () (set! n (+ n 1)) n)))
    inc))
(define a (counter))
(define b (counter))
(unless (equal? (list (a) (a) (b)) '(1 2 1))
  (display "FAIL: per-activation state") (newline) (exit 1))

;; Reentrancy: recursive call must not clobber outer activation's bindings
(define (f depth)
  (letrec ((local depth)
           (recurse (lambda () (if (> depth 0) (f (- depth 1))) local)))
    (recurse)))
(unless (= (f 3) 3)
  (display "FAIL: reentrancy") (newline) (exit 1))

;; Mutual recursion still works
(unless (letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
                 (odd? (lambda (n) (if (= n 0) #f (even? (- n 1))))))
          (and (even? 10) (odd? 11)))
  (display "FAIL: mutual recursion") (newline) (exit 1))

;; letrec* sequential visibility
(unless (= (letrec* ((x 1) (y (+ x 1))) y) 2)
  (display "FAIL: letrec* sequential") (newline) (exit 1))

(display "OK")
(newline)
