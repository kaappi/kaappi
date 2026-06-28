(define (test-cc)
  (call-with-current-continuation
    (lambda (k) (k 42))))
(display (test-cc))
(newline)
