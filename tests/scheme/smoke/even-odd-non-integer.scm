;; Regression test for #441:
;; even? and odd? must reject non-integer flonums.

(import (scheme base) (scheme write))

;; Non-integer flonum should error
(define caught-1 #f)
(guard (exn (#t (set! caught-1 #t)))
  (odd? 2.5))
(if caught-1
    (display "PASS: (odd? 2.5) raises error")
    (display "FAIL: (odd? 2.5) did not raise error"))
(newline)

(define caught-2 #f)
(guard (exn (#t (set! caught-2 #t)))
  (even? 2.5))
(if caught-2
    (display "PASS: (even? 2.5) raises error")
    (display "FAIL: (even? 2.5) did not raise error"))
(newline)

;; Infinity should error
(define caught-3 #f)
(guard (exn (#t (set! caught-3 #t)))
  (odd? +inf.0))
(if caught-3
    (display "PASS: (odd? +inf.0) raises error")
    (display "FAIL: (odd? +inf.0) did not raise error"))
(newline)

;; NaN should error
(define caught-4 #f)
(guard (exn (#t (set! caught-4 #t)))
  (even? +nan.0))
(if caught-4
    (display "PASS: (even? +nan.0) raises error")
    (display "FAIL: (even? +nan.0) did not raise error"))
(newline)

;; Integer-valued flonums should work
(if (even? 4.0)
    (display "PASS: (even? 4.0) is #t")
    (display "FAIL: (even? 4.0) should be #t"))
(newline)

(if (odd? 3.0)
    (display "PASS: (odd? 3.0) is #t")
    (display "FAIL: (odd? 3.0) should be #t"))
(newline)
