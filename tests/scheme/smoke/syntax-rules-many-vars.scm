;; Regression test for #279: syntax-rules with 17+ pattern variables
;; caused stack buffer overflow via @ptrCast mismatch (16 vs 64 elements).

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "syntax-rules-many-vars")

;; The template builds a LIST, not a sum. Addition is commutative, so a
;; permuted binding of the 17 variables would still total 153 and an
;; order-blind assertion would pass while claiming to check order.
(define-syntax many-vars
  (syntax-rules ()
    ((many-vars a b c d e f g h i j k l m n o p q)
     (list a b c d e f g h i j k l m n o p q))))

(test-equal "17 pattern variables expand in order"
            '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17)
            (many-vars 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17))

(let ((runner (test-runner-current)))
  (test-end "syntax-rules-many-vars")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
