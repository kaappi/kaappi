;;; SRFI 70 (Numbers) conformance tests
;;; Run: zig-out/bin/kaappi --lib-path lib tests/scheme/srfi/srfi70.scm
;;;
;;; See lib/srfi/70.sld's header for the deliberately excluded "0/0 is a
;;; comparison error" clause; the final section here confirms R7RS's
;;; NaN-comparison semantics (which Kaappi already implements) are
;;; unaffected by importing (srfi 70).

(import (scheme base) (scheme process-context) (scheme inexact) (srfi 70) (srfi 64))

(test-begin "srfi-70")

;;; --- exact-floor / exact-ceiling / exact-truncate / exact-round ---

(test-equal "exact-floor of inexact" 1 (exact-floor 1.5))
(test-equal "exact-floor result is exact" #t (exact? (exact-floor 1.5)))
(test-equal "exact-ceiling of inexact" 2 (exact-ceiling 1.5))
(test-equal "exact-truncate of negative inexact" -1 (exact-truncate -1.5))
(test-equal "exact-round of inexact (round-half-to-even, low)" 2 (exact-round 2.5))
(test-equal "exact-round of inexact (round-half-to-even, high)" 4 (exact-round 3.5))
(test-equal "exact-floor of negative inexact" -2 (exact-floor -1.5))
(test-equal "exact-ceiling of negative inexact" -1 (exact-ceiling -1.5))
(test-equal "exact-floor of exact rational input" 3 (exact-floor 7/2))
(test-equal "exact-truncate of already-exact input" 4 (exact-truncate 4))

;;; --- quotient/remainder/modulo: existing integer behavior unchanged ---

(test-equal "quotient: plain integers" 3 (quotient 7 2))
(test-equal "modulo: plain integers, positive" 1 (modulo 13 4))
(test-equal "remainder: plain integers, negative dividend" -1 (remainder -13 4))
(test-equal "modulo: plain integers, negative dividend" 3 (modulo -13 4))
(test-equal "modulo: plain integers, negative divisor" -3 (modulo 13 -4))
(test-equal "remainder: plain integers, negative divisor" 1 (remainder 13 -4))

;;; --- quotient/remainder/modulo: already-working inexact-real case ---
;;; (Kaappi's native primitives already accept these; must keep working.)

(test-equal "quotient: inexact non-integer dividend" 3.0 (quotient 6.5 2))
(test-equal "modulo: inexact non-integer dividend" 0.5 (modulo 6.5 2))

;;; --- quotient/remainder/modulo: NEW exact-rational case ---
;;; Values below are SRFI 70's own worked examples.

(test-equal "quotient: exact rationals (spec example)" 3 (quotient 2/3 1/5))
(test-equal "modulo: exact rationals (spec example)" 1/15 (modulo 2/3 1/5))
(test-equal "remainder: exact rationals (same sign, equals modulo)" 1/15 (remainder 2/3 1/5))
(test-equal "quotient: negative exact-rational dividend" -3 (quotient -2/3 1/5))
(test-equal "remainder: negative exact-rational dividend" -1/15 (remainder -2/3 1/5))
(test-equal "modulo: negative exact-rational dividend" 2/15 (modulo -2/3 1/5))
(test-equal "quotient: integer dividend, rational divisor" 20 (quotient 4 1/5))
(test-equal "remainder: integer dividend, rational divisor" 0 (remainder 4 1/5))

;; Identity the spec derives from the definitions of quotient/remainder:
;; x1 = x2*quotient(x1,x2) + remainder(x1,x2), for exact arguments.
(test-equal "quotient/remainder identity holds for exact rationals"
  #t
  (= 2/3 (+ (* 1/5 (quotient 2/3 1/5)) (remainder 2/3 1/5))))

;;; --- gcd/lcm: existing integer behavior unchanged ---

(test-equal "gcd: plain integers (spec example)" 4 (gcd 32 -36))
(test-equal "lcm: plain integers (spec example)" 288 (lcm 32 -36))
(test-equal "gcd: no arguments" 0 (gcd))
(test-equal "lcm: no arguments" 1 (lcm))
(test-equal "gcd: one argument" 12 (gcd 12))
(test-equal "lcm: one argument" 12 (lcm 12))
(test-equal "gcd: three integer arguments" 6 (gcd 12 18 24))

;;; --- gcd/lcm: NEW exact-rational case ---
;;; Values below are SRFI 70's own worked examples.

(test-equal "gcd: exact rationals (spec example)" 1/12 (gcd 1/6 1/4))
(test-equal "lcm: exact rationals (spec example)" 1/2 (lcm 1/6 1/4))
(test-equal "gcd: exact rationals, second example" 1/12 (gcd 1/6 5/4))
(test-equal "lcm: exact rationals, second example" 5/2 (lcm 1/6 5/4))
(test-equal "gcd: negative exact-rational argument" 1/12 (gcd -1/6 1/4))
(test-equal "gcd: mixed integer and exact rational" 1/6 (gcd 4 1/6))

;;; --- expt: zero base with negative exponent ---

(test-equal "expt: normal positive exponent" 1024 (expt 2 10))
(test-equal "expt: normal negative exponent, nonzero base" 1/8 (expt 2 -3))
(test-equal "expt: zero base, positive exponent" 0 (expt 0 5))
(test-equal "expt: zero base, zero exponent" 1 (expt 0 0))
(test-equal "expt: exact zero base, negative integer exponent (spec fix)"
  +inf.0 (expt 0 -5))
(test-equal "expt: exact zero base, negative rational exponent"
  +inf.0 (expt 0 -1/2))
;; Inexact +/-0.0 already behave correctly (IEEE-signed) and must be left
;; alone by the shadowed expt.
(test-equal "expt: inexact negative-zero base keeps IEEE sign (odd power)"
  -inf.0 (expt -0.0 -5))
(test-equal "expt: inexact negative-zero base keeps IEEE sign (even power)"
  +inf.0 (expt -0.0 -4))
(test-equal "expt: inexact positive-zero base unaffected"
  +inf.0 (expt 0.0 -5))

;;; --- R7RS NaN-comparison semantics are unaffected by (srfi 70) ---
;;; SRFI 70's own rationale calls 0/0 (NaN) "an illegal argument to the
;;; comparison procedures `<', `<=', `>', and `>='"; R7RS later overrode
;;; that ("If any of the arguments are +nan.0, all the predicates return
;;; #f"), and lib/srfi/70.sld deliberately does not implement SRFI 70's
;;; clause -- it does not export or redefine =, <, <=, >, >= at all. These
;;; must return #f, not raise an error, even with (srfi 70) imported.

(test-equal "= with NaN returns #f, does not raise" #f (= +nan.0 +nan.0))
(test-equal "< with NaN returns #f, does not raise" #f (< +nan.0 1))
(test-equal "> with NaN returns #f, does not raise" #f (> +nan.0 1))
(test-equal "<= with NaN returns #f, does not raise" #f (<= +nan.0 1))
(test-equal ">= with NaN returns #f, does not raise" #f (>= +nan.0 1))

(let ((runner (test-runner-current)))
  (test-end "srfi-70")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
