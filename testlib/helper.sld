(define-library (testlib helper)
  (export double triple)
  (begin
    (define (double x) (* x 2))
    (define (triple x) (* x 3))))
