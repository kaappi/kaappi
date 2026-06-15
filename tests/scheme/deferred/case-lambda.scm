;; case-lambda tests
(define f
  (case-lambda
    (() 0)
    ((x) x)
    ((x y) (+ x y))))

(display (f))
(newline)
(display (f 42))
(newline)
(display (f 3 4))
(newline)
