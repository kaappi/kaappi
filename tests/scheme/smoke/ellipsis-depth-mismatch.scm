;; Regression test for #682: ellipsis depth mismatch should be detected
;; Valid: same-depth pattern variables under single ellipsis
(define-syntax ok-depth
  (syntax-rules ()
    ((_ (a ...) (b ...))
     (list (list a b) ...))))
(let ((result (ok-depth (1 2) (10 20))))
  (if (equal? result '((1 10) (2 20)))
    (display "PASS")
    (begin (display "FAIL: got ") (display result) (exit 1))))
(newline)
