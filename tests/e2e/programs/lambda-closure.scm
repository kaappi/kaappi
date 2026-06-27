(define make-adder (lambda (n) (lambda (x) (+ n x))))
(define add-10 (make-adder 10))
(display (add-10 5))
(newline)
