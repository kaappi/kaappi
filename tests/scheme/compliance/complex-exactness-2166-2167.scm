;; #2166 / #2167: exactness of complex numbers.
;;
;; #2167: R7RS 6.1 requires (eqv? a b) => #f when one number is exact and the
;; other inexact. Every eqv?-semantics comparator (eqv?, equal?, memv, assv,
;; compiled case, SRFI-69 eqv-keyed tables) compared the two f64 components
;; bitwise and ignored the exact_real/exact_imag flags, so an exact complex
;; and its inexact twin were interchangeable everywhere except `=` — which is
;; the one place they SHOULD be equal. Fixed by one shared types.complexEqv.
;;
;; #2166 (interim slice): negating an exact complex must stay exact
;; (R7RS 6.2 — kaappi advertises exact-closed and exact-complex). Unary (- z)
;; and (- 0 z) are rounding-free, so they now preserve the exactness flags,
;; normalizing an exact zero component to +0.0 (the exact tower has no -0).
;; The rest of complex arithmetic still collapses to inexact — that is the
;; representation problem #2166 tracks, and these tests deliberately pin only
;; the rounding-free subset.

(import (scheme base) (scheme complex) (scheme process-context) (srfi 64) (srfi 69))

(test-begin "complex-exactness-2166-2167")

(define z (make-rectangular 3/2 1))

;; --- #2166: negation preserves exactness ------------------------------------

(test-assert "make-rectangular of exact args is exact" (exact? z))
(test-assert "(- z) stays exact" (exact? (- z)))
;; real-part of a non-integral exact component is still inexact (#2166), so
;; pin the components through eqv? against a constructed value instead.
(test-assert "(- z) equals constructed exact negation"
  (eqv? (- z) (make-rectangular -3/2 -1)))
(test-equal "(- z) imag component negated" -1 (imag-part (- z)))
(test-assert "(- 0 z) stays exact" (exact? (- 0 z)))
(test-assert "(- 0 z) equals (- z)" (eqv? (- 0 z) (- z)))
(test-assert "(- 0.0 z) is inexact (inexact minuend)" (inexact? (- 0.0 z)))
(test-assert "inexact complex negation stays inexact"
  (inexact? (- (make-rectangular 1.5 1.0))))
(test-assert "mixed flags preserved componentwise"
  (eqv? (- (make-rectangular 3/2 1.0)) (make-rectangular -3/2 -1.0)))
(test-assert "exact zero component normalizes to +0.0"
  (eqv? (- (make-rectangular 0 1)) (make-rectangular 0 -1)))
(test-assert "negation of exact-zero-real complex stays exact"
  (exact? (- (make-rectangular 0 1))))
(test-assert "double negation round-trips under eqv?" (eqv? (- (- z)) z))

;; --- #2167: eqv? family discriminates exactness ------------------------------

(define ex (make-rectangular -3/2 -1))

(test-eqv "eqv? exact vs inexact complex" #f (eqv? ex -1.5-1.0i))
(test-eqv "eqv? inexact vs exact complex (flipped)" #f (eqv? -1.5-1.0i ex))
(test-eqv "equal? exact vs inexact complex" #f (equal? ex -1.5-1.0i))
(test-eqv "= still numerically equal" #t (= ex -1.5-1.0i))
(test-eqv "eqv? exact vs inexact via make-rectangular" #f
  (eqv? (make-rectangular 3/2 1) (make-rectangular 1.5 1)))
(test-eqv "eqv? mixed-component vs all-inexact" #f
  (eqv? (make-rectangular 3/2 1.0) 1.5+1.0i))
(test-eqv "eqv? same exact complex" #t (eqv? z (make-rectangular 3/2 1)))
(test-eqv "eqv? same inexact complex" #t (eqv? 1.5+1.0i 1.5+1.0i))
(test-eqv "signed zero still discriminated" #f (eqv? 0.0+1i -0.0+1i))
(test-eqv "NaN components still eqv?" #t (eqv? +nan.0+1i +nan.0+1i))
(test-eqv "memv misses across exactness" #f (memv ex (list -1.5-1.0i)))
(test-eqv "assv misses across exactness" #f (assv ex (list (cons -1.5-1.0i 'x))))
(test-equal "memv still finds same-exactness complex" (list ex)
  (memv (make-rectangular -3/2 -1) (list ex)))
(test-eq "case falls to else across exactness" 'else-branch
  (case ex ((-1.5-1.0i) 'inexact-branch) (else 'else-branch)))
(test-eq "case matches exact negation result against exact datum" 'hit
  (case (- z) ((-3/2-1i) 'hit) (else 'miss)))
(test-eq "eqv-keyed hash table misses across exactness" 'miss
  (let ((t (make-hash-table eqv?)))
    (hash-table-set! t -1.5-1.0i 'inexact-key)
    (hash-table-ref/default t ex 'miss)))
(test-eq "eqv-keyed hash table still hits same exactness" 'exact-key
  (let ((t (make-hash-table eqv?)))
    (hash-table-set! t (make-rectangular -3/2 -1) 'exact-key)
    (hash-table-ref/default t ex 'miss)))

;; Non-complex eqv? exactness discrimination was already correct — pin it so
;; a shared-helper refactor cannot regress it.
(test-eqv "eqv? fixnum vs flonum" #f (eqv? 1 1.0))
(test-eqv "eqv? rational vs flonum" #f (eqv? 1/2 0.5))

(let ((runner (test-runner-current)))
  (test-end "complex-exactness-2166-2167")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
