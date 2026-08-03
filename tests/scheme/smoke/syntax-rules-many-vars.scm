;; Regression test for #279: syntax-rules with 17+ pattern variables
;; caused stack buffer overflow via @ptrCast mismatch (16 vs 64 elements).

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "syntax-rules-many-vars")

(define-syntax many-vars
  (syntax-rules ()
    ((many-vars a b c d e f g h i j k l m n o p q)
     (+ a b c d e f g h i j k l m n o p q))))

(test-equal "17 pattern variables expand in order"
            153
            (many-vars 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17))

(let ((runner (test-runner-current)))
  (test-end "syntax-rules-many-vars")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
