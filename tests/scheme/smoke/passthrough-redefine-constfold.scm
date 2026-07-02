;; Regression test for #698: constant folding in compiler_passthrough
;; must respect redefined primitives.

(define (+ a b) (list 'custom a b))

(define-syntax my-add
  (syntax-rules ()
    ((_ x y) (+ x y))))

(define result (my-add 1 2))
(unless (equal? result '(custom 1 2))
  (display "FAIL: expected (custom 1 2), got ")
  (display result)
  (newline)
  (exit 1))

(display "PASS")
(newline)
