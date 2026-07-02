;; Regression test for #681: macro hygiene for template-introduced bindings
;; named after built-in procedures (list, map, cons, etc.)

(define-syntax capture-test
  (syntax-rules ()
    ((_ expr)
     (let ((list (lambda (x y) (cons 'captured (cons x (cons y '()))))))
       expr))))

;; The user's (list 1 2) should call the global list, not the macro's binding
(let ((result (capture-test (list 1 2))))
  (if (equal? result '(1 2))
    (display "PASS")
    (begin
      (display "FAIL: expected (1 2), got ")
      (display result)
      (exit 1))))
(newline)
