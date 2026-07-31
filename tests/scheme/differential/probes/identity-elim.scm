;; Probe: identity elimination (ir.eliminateIdentity).
;;
;; `(+ x 0)` -> x, `(* x 1)` -> x, `(* x 0)` -> 0.  In Scheme these are NOT
;; unconditional identities:
;;   (* 1.5 0)  is 0 or 0.0, not 1.5, and R7RS §6.2.3 lets an implementation
;;              choose — but it must choose the SAME thing in both tiers;
;;   (+ 1.5 0)  must stay inexact;
;;   (* +nan.0 0), (* +inf.0 0) are not 0.
;; The implementation guards on both operands being exact integers.  These
;; forms probe the guard from both sides.

;; --- the identities that do hold (exact integers) ------------------------
(display (+ 7 0)) (newline)
(display (+ 0 7)) (newline)
(display (* 7 1)) (newline)
(display (* 1 7)) (newline)
(display (* 7 0)) (newline)
(display (* 0 7)) (newline)
(display (- 7 0)) (newline)

;; --- exactness must be preserved ----------------------------------------
(display (exact? (+ 7 0))) (newline)
(display (exact? (* 7 1))) (newline)
(display (exact? (* 7 0))) (newline)

;; --- inexact operands: the identity must NOT be applied blindly ---------
(display (+ 1.5 0)) (newline)
(display (exact? (+ 1.5 0))) (newline)
(display (* 1.5 1)) (newline)
(display (exact? (* 1.5 1))) (newline)
(display (* 1.5 0)) (newline)
(display (exact? (* 1.5 0))) (newline)
(display (* 0 1.5)) (newline)

;; --- infinities and NaN: (* x 0) is not 0 for these ---------------------
(display (* +inf.0 0)) (newline)
(display (* -inf.0 0)) (newline)
(display (* +nan.0 0)) (newline)
(display (+ +inf.0 0)) (newline)

;; --- bignum operands ------------------------------------------------------
(display (+ 1267650600228229401496703205376 0)) (newline)
(display (* 1267650600228229401496703205376 1)) (newline)
(display (* 1267650600228229401496703205376 0)) (newline)

;; --- rationals and complex ------------------------------------------------
(display (+ 1/3 0)) (newline)
(display (* 1/3 1)) (newline)
(display (* 1/3 0)) (newline)

;; --- `+` and `*` shadowed: the rewrite MUST NOT fire ---------------------
(define (+ a b) 'user-plus)
(define (* a b) 'user-times)
(display (+ 7 0)) (newline)
(display (* 7 1)) (newline)
(display (* 7 0)) (newline)
