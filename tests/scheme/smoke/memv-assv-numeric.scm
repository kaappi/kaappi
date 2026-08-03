;; Regression tests for memv/assv with heap-allocated numeric types
;; Issue #274

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "memv-assv-numeric")

;; memv with bignums
(let ((big (expt 2 100)))
  (test-assert "memv finds a bignum" (pair? (memv big (list 1 big 3)))))

;; memv with rationals
(test-assert "memv finds a rational" (pair? (memv 1/3 (list 1/2 1/3 1/4))))

;; memv with complex
(test-assert "memv finds a complex" (pair? (memv 1+2i (list 3+4i 1+2i 0+0i))))

;; memv negative case
(test-equal "memv reports a missing complex as #f"
            #f (memv 1+2i (list 3+4i 5+6i)))

;; assv with bignums
(let ((big (expt 2 100)))
  (test-assert "assv finds a bignum key"
               (pair? (assv big (list (list big 'found))))))

;; assv with rationals
(test-assert "assv finds a rational key"
             (pair? (assv 1/3 (list (list 1/2 'a) (list 1/3 'b)))))

;; assv with complex
(test-assert "assv finds a complex key"
             (pair? (assv 1+2i (list (list 3+4i 'a) (list 1+2i 'b)))))

;; assv negative case
(test-equal "assv reports a missing rational key as #f"
            #f (assv 7/9 (list (list 1/2 'a) (list 3/4 'b))))

;; memv fixnum-bignum cross-comparison
(test-assert "memv matches the fixnum 0 past a bignum"
             (pair? (memv 0 (list (expt 2 100) 0 1))))

(let ((runner (test-runner-current)))
  (test-end "memv-assv-numeric")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
