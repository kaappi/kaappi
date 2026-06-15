;; let-values tests
(display (let-values (((a b) (values 1 2)))
  (+ a b)))
(newline)

(display (let*-values (((a b) (values 1 2))
                       ((c) (values (+ a b))))
  c))
(newline)
