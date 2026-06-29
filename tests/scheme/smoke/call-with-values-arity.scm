;; Regression test for call-with-values ArityMismatch in multi-value branch
;; Issue #268

(import (scheme base) (scheme write))

;; Multi-value arity mismatch should raise an error, not a type error
(display
  (guard (exn (#t 'error-caught))
    (call-with-values (lambda () (values 1 2 3)) (lambda (x) x))))
(newline)
;; Expected: error-caught

;; Normal multi-value case still works
(display
  (call-with-values (lambda () (values 1 2 3)) (lambda (a b c) (+ a b c))))
(newline)
;; Expected: 6

;; Single-value case still works
(display
  (call-with-values (lambda () 42) (lambda (x) (* x 2))))
(newline)
;; Expected: 84

(display "all passed")
(newline)
