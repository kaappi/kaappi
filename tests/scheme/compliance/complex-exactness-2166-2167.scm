;; #2166 / #2167: exactness of complex numbers.
;;
;; #2167: R7RS 6.1 requires (eqv? a b) => #f when one number is exact and the
;; other inexact. Every eqv?-semantics comparator (eqv?, equal?, memv, assv,
;; compiled case, SRFI-69 eqv-keyed tables) compared the two f64 components
;; bitwise and ignored the exact_real/exact_imag flags, so an exact complex
;; and its inexact twin were interchangeable everywhere except `=` — which is
;; the one place they SHOULD be equal. Fixed by one shared types.complexEqv,
;; which compares components with numeric eqv? under the #2166 representation.
;;
;; #2166: complex components are stored as Values (fixnum/bignum/rational/
;; flonum) instead of f64+exactness-flags, so exact complexes are computed,
;; stored, printed, and read back digit-exactly. A stored complex is never
;; mixed-exactness: if either component is inexact both are (R7RS 6.2.2's
;; inexactness rule), and a zero imaginary part demotes to the real
;; component. These tests pin the full behavior, including the exact
;; arithmetic the interim slice deliberately left inexact.

(import (scheme base) (scheme complex) (scheme write) (scheme process-context) (srfi 64) (srfi 69))

(define (write-to-string v)
  (let ((port (open-output-string)))
    (write v port)
    (get-output-string port)))

(test-begin "complex-exactness-2166-2167")

(define z (make-rectangular 3/2 1))

;; --- #2166: negation preserves exactness ------------------------------------

(test-assert "make-rectangular of exact args is exact" (exact? z))
(test-assert "(- z) stays exact" (exact? (- z)))
;; Pin the components through eqv? against a constructed value; the
;; real-part exactness is pinned directly further down (kaappi#2166).
(test-assert "(- z) equals constructed exact negation"
  (eqv? (- z) (make-rectangular -3/2 -1)))
(test-equal "(- z) imag component negated" -1 (imag-part (- z)))
(test-assert "(- 0 z) stays exact" (exact? (- 0 z)))
(test-assert "(- 0 z) equals (- z)" (eqv? (- 0 z) (- z)))
(test-assert "(- 0.0 z) is inexact (inexact minuend)" (inexact? (- 0.0 z)))
(test-assert "inexact complex negation stays inexact"
  (inexact? (- (make-rectangular 1.5 1.0))))
(test-assert "make-rectangular with an inexact part is all-inexact; negation matches"
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
(test-eqv "eqv? make-rectangular with an inexact part is all-inexact" #t
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



;; --- #2166 (full): exact complex arithmetic over the exact tower -----------

(test-assert "(+ z z) is exact" (exact? (+ z z)))
(test-assert "(+ z z) has the exact value" (eqv? (+ z z) (make-rectangular 3 2)))
(test-assert "(* z z) is exact" (exact? (* z z)))
(test-assert "(* z z) has the exact value" (eqv? (* z z) (make-rectangular 5/4 3)))
(test-equal "(- z z) demotes to exact 0" 0 (- z z))
(test-equal "(- z z) is exact" #t (exact? (- z z)))
(test-assert "(/ z) is exact" (exact? (/ z)))
(test-assert "(/ z) has the exact value" (eqv? (/ z) (make-rectangular 6/13 -4/13)))
(test-assert "(+ z) is exact (identity)" (exact? (+ z)))
(test-assert "mixed-inexact operand makes the result inexact"
  (inexact? (+ z 1.0)))
(test-assert "mixed result equals its inexact twin" (eqv? (+ z 1.0) 2.5+1.0i))
(test-assert "inexact operand result has both components inexact"
  (and (inexact? (real-part (+ z 1.0))) (inexact? (imag-part (+ z 1.0)))))
(test-assert "(* 1+2i 3-4i) exact" (eqv? (* 1+2i 3-4i) 11+2i))
(test-assert "(* z 0) is exact 0" (eqv? (* z 0) 0))
(test-assert "(/ z 2) is exact" (eqv? (/ z 2) (make-rectangular 3/4 1/2)))
(test-equal "division by exact complex zero raises" 'raised
  (guard (e (#t 'raised)) (/ 1+2i 0+0i)))
(test-equal "division by exact zero raises" 'raised
  (guard (e (#t 'raised)) (/ 1+2i 0)))
(test-assert "expt with exact integer exponent stays exact"
  (eqv? (expt 1+2i 3) -11-2i))
(test-assert "expt with negative integer exponent stays exact"
  (eqv? (expt 3/2+1i -2) (make-rectangular 20/169 -48/169)))
(test-assert "expt exact zero exponent is 1" (eqv? (expt 1+2i 0) 1))
(test-assert "negation exact round-trip" (eqv? (- (- z)) z))
(test-assert "magnitude stays inexact (out of scope)" (inexact? (magnitude z)))
(test-assert "sqrt of exact complex stays inexact (out of scope)" (inexact? (sqrt -4)))

;; --- #2166 (full): make-rectangular never rounds ---------------------------

(test-equal "2^53+1 survives make-rectangular" "9007199254740993+1i"
  (write-to-string (make-rectangular 9007199254740993 1)))
(test-assert "(expt 10 25) real-part round-trips"
  (= (real-part (make-rectangular (expt 10 25) 1)) (expt 10 25)))
(test-assert "(expt 10 400) is exact, not an exact infinity"
  (exact? (make-rectangular (expt 10 400) 1)))
(test-assert "(expt 10 400) is finite"
  (finite? (make-rectangular (expt 10 400) 1)))
(test-equal "make-rectangular 3/2 0 demotes to exact rational" 3/2
  (make-rectangular 3/2 0))
(test-equal "make-rectangular 3/2 0.0 demotes to inexact" 1.5
  (make-rectangular 3/2 0.0))
(test-assert "make-rectangular 3/2 0.0 result is inexact"
  (inexact? (make-rectangular 3/2 0.0)))
(test-equal "make-rectangular 1 0.0 demotes to inexact 1.0" 1.0
  (make-rectangular 1 0.0))
(test-assert "make-rectangular 1.5 0.0 is real" (real? (make-rectangular 1.5 0.0)))

;; --- #2166 (full): write and real-part agree -------------------------------

(define w2166 (make-rectangular 3/2 1))
(test-equal "write prints the exact rational" "3/2+1i" (write-to-string w2166))
(test-equal "real-part returns the exact rational" 3/2 (real-part w2166))
(test-assert "real-part of exact component is exact" (exact? (real-part w2166)))
(test-equal "imag-part returns the exact integer" 1 (imag-part w2166))
(test-equal "write of 1/3 component is honest" "1/3+1i" (write-to-string (make-rectangular 1/3 1)))
(test-equal "real-part of 1/3 is exact" 1/3 (real-part (make-rectangular 1/3 1)))
(test-equal "large exact real prints digit-exactly"
  "10000000000000000000000000+1i" (write-to-string (make-rectangular (expt 10 25) 1)))
(test-equal "unit imaginary spells +i" "+i" (write-to-string (make-rectangular 0 1)))
(test-equal "1+1i spells 1+1i" "1+1i" (write-to-string (make-rectangular 1 1)))
(test-equal "exact rational imag spells +3/4i" "+3/4i" (write-to-string (make-rectangular 0 3/4)))
(test-equal "negative imag keeps sign" "3/2-1i" (write-to-string (make-rectangular 3/2 -1)))
(test-equal "inexact complex prints flonums" "1.5+1.0i" (write-to-string (make-rectangular 1.5 1.0)))

;; --- #2166 (full): the reader is digit-exact and normalizes ----------------

(test-assert "reading 2^53+1+1i is exact" (exact? (read (open-input-string "9007199254740993+1i"))))
(test-assert "reading 2^53+1+1i equals construction"
  (eqv? (read (open-input-string "9007199254740993+1i")) (make-rectangular 9007199254740993 1)))
(test-assert "reading a huge bignum rational complex is exact"
  (eqv? (read (open-input-string "10000000000000000000000001/3+2i"))
        (make-rectangular (/ (+ (expt 10 25) 1) 3) 2)))
(test-assert "a literal with one inexact part is whole-inexact"
  (inexact? (read (open-input-string "1/2+1.0i"))))
(test-assert "1/2+1.0i and 0.5+1.0i read eqv?"
  (eqv? (read (open-input-string "1/2+1.0i")) (read (open-input-string "0.5+1.0i"))))
(test-equal "1/2+1.0i normalizes on write" "0.5+1.0i"
  (write-to-string (read (open-input-string "1/2+1.0i"))))
(test-assert "string->number is digit-exact for complex"
  (eqv? (string->number "9007199254740993+1i") (make-rectangular 9007199254740993 1)))
(test-assert "string->number 1/2+1.0i is whole-inexact"
  (inexact? (string->number "1/2+1.0i")))
(test-assert "#e prefix makes a complex exactly digit-exact"
  (eqv? (read (open-input-string "#e1.5+2.0i")) (make-rectangular 3/2 2)))
(test-assert "#i prefix makes a complex inexact"
  (eqv? (read (open-input-string "#i3/2+1i")) 1.5+1.0i))
(test-assert "read/string->number agree on radix complex"
  (eqv? (read (open-input-string "#x1/2+3i")) (string->number "#x1/2+3i")))

;; --- #2166 (full): eqv? and = on component values --------------------------

(test-eqv "eqv? exact complex with itself" #t (eqv? z (make-rectangular 3/2 1)))
(test-eqv "eqv? exact vs inexact twin" #f (eqv? z 1.5+1.0i))
(test-eqv "= ignores exactness on complex" #t (= z 1.5+1.0i))
(test-eqv "= compares exact components digit-exactly" #t
  (= (make-rectangular (expt 10 25) 1) (make-rectangular (expt 10 25) 1)))
(test-eqv "= distinguishes 2^53+1 from 2^53+2" #f
  (= (make-rectangular 9007199254740993 1) (make-rectangular 9007199254740995 1)))
(test-eqv "eqv? exact complex vs itself via write/read round-trip" #t
  (eqv? (read (open-input-string (write-to-string z))) z))
(test-eqv "zero? on a complex" #f (zero? 1+2i))
(test-eqv "zero? on demoted complex zero" #t (zero? (- z z)))
(test-assert "finite?/infinite?/nan? use components" (and (finite? z) (infinite? +inf.0+1i) (nan? +nan.0+1i)))


;; --- #2166: radix-prefixed exact complexes (reader use-after-free guard) ---
;; tryComplexTail parses the imaginary part before the real part is built;
;; with an unrooted heap imag that is a use-after-free under gc-stress
;; (review). These read digit-exactly and must not abort.

(test-assert "radix complex with bignum-rational real and imag reads exactly"
  (eqv? (read (open-input-string "#x1/2+3/4i"))
        (make-rectangular 1/2 3/4)))
(test-assert "radix complex with a huge hex imag reads exactly"
  (eqv? (read (open-input-string "#x800000000000+99999999999999999999i"))
        (make-rectangular 140737488355328 725355491768777504823705)))
(test-assert "radix complex with bignum real and rational imag reads exactly"
  (eqv? (read (open-input-string "#x20000000000001+3/4i"))
        (make-rectangular 9007199254740993 3/4)))

;; --- #2166: eqv?-keyed tables hash Value components by value ---------------

(test-eq "eqv-keyed hash table hits a re-constructed bignum complex" 'hit
  (let ((t (make-hash-table eqv?)))
    (hash-table-set! t (make-rectangular 9007199254740993 1) 'hit)
    (hash-table-ref/default t (make-rectangular 9007199254740993 1) 'miss)))
(test-eq "eqv-keyed hash table hits a re-constructed rational complex" 'hit
  (let ((t (make-hash-table eqv?)))
    (hash-table-set! t (make-rectangular (/ (expt 10 25) 3) 2) 'hit)
    (hash-table-ref/default t (make-rectangular (/ (expt 10 25) 3) 2) 'miss)))
(test-eq "eqv-keyed hash table misses across exactness still" 'miss
  (let ((t (make-hash-table eqv?)))
    (hash-table-set! t (make-rectangular 9007199254740993 1) 'hit)
    (hash-table-ref/default t 9007199254740993.0+1.0i 'miss)))

(let ((runner (test-runner-current)))
  (test-end "complex-exactness-2166-2167")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
