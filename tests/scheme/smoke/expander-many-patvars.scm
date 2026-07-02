;; Regression test for #683: syntax-rules with >16 pattern variables
;; per ellipsis sub-pattern must work.

;; 17 pattern variables — previously failed with InvalidSyntax
(define-syntax many-vars
  (syntax-rules ()
    ((_ (a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16) ...)
     (quote ((a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16) ...)))))

(let ((result (many-vars (0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16))))
  (if (equal? result '((0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)))
    (display "PASS")
    (begin
      (display "FAIL: got ")
      (display result)
      (newline)
      (exit 1))))
(newline)
