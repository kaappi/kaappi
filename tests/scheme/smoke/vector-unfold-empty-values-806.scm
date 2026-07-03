;; Regression test for #806: vector-unfold / vector-unfold-right must not
;; abort when the step procedure returns (values) (zero values).
(import (scheme base) (scheme write) (srfi 133))

(define (test name thunk)
  (let ((result (guard (exn (#t 'caught))
                  (thunk))))
    (if (eq? result 'caught)
        (begin (display "PASS: ") (display name) (newline))
        (begin (display "FAIL: ") (display name)
               (display " — expected error but got: ") (display result)
               (newline)))))

(test "vector-unfold with (values)"
  (lambda () (vector-unfold (lambda (i) (values)) 1)))

(test "vector-unfold-right with (values)"
  (lambda () (vector-unfold-right (lambda (i) (values)) 3)))
