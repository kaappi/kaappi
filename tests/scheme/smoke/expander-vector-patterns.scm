;; Regression test for #680: vector patterns and templates in syntax-rules

;; Vector pattern matching
(define-syntax my-vec
  (syntax-rules ()
    ((_ #(a b c)) (list a b c))))
(let ((result (my-vec #(1 2 3))))
  (unless (equal? result '(1 2 3))
    (display "FAIL: vector pattern") (newline) (exit 1)))

;; Vector template
(define-syntax list-to-vec
  (syntax-rules ()
    ((_ a b c) #(a b c))))
(let ((result (list-to-vec 10 20 30)))
  (unless (equal? result #(10 20 30))
    (display "FAIL: vector template") (newline) (exit 1)))

(display "PASS")
(newline)
