;; Regression test for #419: string->number with #e prefix must return #f
;; for +inf.0, -inf.0, +nan.0, -nan.0 (no exact representation exists).

(import (scheme base) (scheme write))

(define (test name expr expected)
  (unless (equal? expr expected)
    (display "FAIL: ")
    (display name)
    (display " => ")
    (write expr)
    (display " expected ")
    (write expected)
    (newline)
    (error "test failed" name)))

(test "#e+inf.0" (string->number "#e+inf.0") #f)
(test "#e-inf.0" (string->number "#e-inf.0") #f)
(test "#e+nan.0" (string->number "#e+nan.0") #f)
(test "#e-nan.0" (string->number "#e-nan.0") #f)

;; #i prefix should still work
(test "#i+inf.0" (infinite? (string->number "#i+inf.0")) #t)
(test "#i-inf.0" (infinite? (string->number "#i-inf.0")) #t)
(test "#i+nan.0" (nan? (string->number "#i+nan.0")) #t)

;; No prefix should still work
(test "+inf.0" (infinite? (string->number "+inf.0")) #t)
(test "-inf.0" (infinite? (string->number "-inf.0")) #t)
(test "+nan.0" (nan? (string->number "+nan.0")) #t)
(test "-nan.0" (nan? (string->number "-nan.0")) #t)

(display "PASS")
(newline)
