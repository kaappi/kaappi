;; Regression tests for memv/assv with heap-allocated numeric types
;; Issue #274

(import (scheme base) (scheme write))

;; memv with bignums
(let ((big (expt 2 100)))
  (display (pair? (memv big (list 1 big 3)))))  ; #t
(newline)

;; memv with rationals
(display (pair? (memv 1/3 (list 1/2 1/3 1/4))))  ; #t
(newline)

;; memv with complex
(display (pair? (memv 1+2i (list 3+4i 1+2i 0+0i)))) ; #t
(newline)

;; memv negative case
(display (memv 1+2i (list 3+4i 5+6i)))  ; #f
(newline)

;; assv with bignums
(let ((big (expt 2 100)))
  (display (pair? (assv big (list (list big 'found))))))  ; #t
(newline)

;; assv with rationals
(display (pair? (assv 1/3 (list (list 1/2 'a) (list 1/3 'b))))) ; #t
(newline)

;; assv with complex
(display (pair? (assv 1+2i (list (list 3+4i 'a) (list 1+2i 'b))))) ; #t
(newline)

;; assv negative case
(display (assv 7/9 (list (list 1/2 'a) (list 3/4 'b)))) ; #f
(newline)

;; memv fixnum-bignum cross-comparison
(display (pair? (memv 0 (list (expt 2 100) 0 1)))) ; #t (fixnum 0)
(newline)

(display "all passed")
(newline)
