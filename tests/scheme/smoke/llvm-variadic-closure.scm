;; Regression test for #685: variadic (rest-arg) native closures must
;; not crash with arity mismatch when called with extra arguments.

(define (make-variadic)
  (lambda (a b . rest)
    (list a b rest)))

(define (caller)
  (let ((f (make-variadic)))
    (f 1 2 3 4 5)))

(define result (caller))
(unless (equal? result '(1 2 (3 4 5)))
  (display "FAIL: expected (1 2 (3 4 5)), got ")
  (display result)
  (newline)
  (exit 1))

;; Also test direct variadic call
(define variadic-add
  (lambda (a . rest)
    (apply + a rest)))

(unless (= (variadic-add 1 2 3 4) 10)
  (display "FAIL: variadic-add should return 10")
  (newline)
  (exit 1))

(display "PASS")
(newline)
