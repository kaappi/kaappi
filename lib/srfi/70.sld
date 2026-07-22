;;; SRFI 70 — Numbers
;;;
;;; SRFI 70 folds together a cluster of interrelated R5RS numeric-tower
;;; clarifications and extensions: IEEE-754 infinities (+inf.0/-inf.0,
;;; already native to Kaappi), an exactness-contagion cleanup (also already
;;; native), extending `quotient`/`remainder`/`modulo`/`gcd`/`lcm` beyond
;;; plain integers, `expt` returning +inf.0 for a zero base raised to a
;;; negative power, and four new `exact-<foo>` convenience procedures.
;;; R7RS-small later absorbed nearly all of this (infinities, exactness
;;; rules, and more), so the numeric surface this library actually needs to
;;; add or change on top of Kaappi's existing (scheme base)/(scheme inexact)
;;; is small. See below for exactly what is, and is not, implemented.
;;;
;;; EXCLUDED CLAUSE: 0/0 as a comparison error
;;; ---------------------------------------------------------------------
;;; SRFI 70 treats the indeterminate value 0/0 (what IEEE-754 calls NaN) as
;;; a numerical error-object and explicitly forbids passing it to `<`,
;;; `<=`, `>`, or `>=`. Its own rationale:
;;;
;;;   "While finding +inf.0 and -inf.0 to be very useful in computation, I
;;;   cannot say the same for 0/0. ... Tolerating one error is useful;
;;;   tolerating more than one error in a computation masks programming
;;;   errors."
;;;
;;;   "Because it has no sensible place in the total-order of real numbers,
;;;   0/0 is not a real number. Thus it is an illegal argument to the
;;;   comparison procedures `<', `<=', `>', and `>='."
;;;
;;; R7RS-small explicitly overrode this stance. Its description of `=`,
;;; `<`, `>`, `<=`, `>=` says plainly: "If any of the arguments are
;;; +nan.0, all the predicates return #f" — no error. Its numeric tower
;;; section is equally explicit: "A NaN always compares false to any
;;; number, including a NaN." Kaappi already implements R7RS's rule
;;; throughout its arithmetic ((= +nan.0 +nan.0) => #f, (< +nan.0 1) => #f,
;;; etc.), and this port deliberately does NOT implement SRFI 70's
;;; incompatible clause: it leaves `=`, `<`, `<=`, `>`, `>=` completely
;;; untouched, and does not export or redefine any of them. Importing
;;; (srfi 70) changes nothing about NaN comparisons.
;;;
;;; WHAT THIS PORT IMPLEMENTS
;;; ---------------------------------------------------------------------
;;; - exact-floor, exact-ceiling, exact-truncate, exact-round: new
;;;   convenience procedures, exactly `(inexact->exact (floor x))` etc. per
;;;   SRFI 70's own reference implementation. Not previously present in
;;;   Kaappi under any name.
;;;
;;; - quotient, remainder, modulo: SRFI 70 extends these from "integers,
;;;   exact or inexact" to "exact rationals and inexact reals" (its
;;;   rationale section "Integer versus Exact"). Kaappi's native
;;;   primitives already accept inexact non-integer reals directly, e.g.
;;;   (quotient 6.5 2) => 3.0 — the one real gap is Kaappi's exact
;;;   non-integer rational type (what its own type-error messages call
;;;   "#<rational>", e.g. 2/3), which the native primitives reject
;;;   outright. This library's shadowed versions detect that one case (an
;;;   exact, rational, non-integer operand) and fall back to the general
;;;   definitions from SRFI 70's own reference implementation
;;;   (`(truncate (/ x1 x2))` for quotient, etc.); every other input,
;;;   including the already-working inexact case, delegates straight to
;;;   Kaappi's native primitive, unchanged.
;;;
;;; - gcd, lcm: SRFI 70 changes their domain to exact rationals — a
;;;   narrower extension than quotient/remainder/modulo's (it does NOT
;;;   cover inexact non-integers). Extended via the reference
;;;   implementation's numerator/denominator decomposition
;;;   (gcd(x/y, w/z) = gcd(x,w)/lcm(y,z), and symmetrically for lcm) when
;;;   at least one argument is an exact non-integer rational; otherwise
;;;   delegates straight to the native primitive, preserving its exact
;;;   current behavior for plain integers (including the 0- and
;;;   1-argument identity cases) and for anything already outside both
;;;   the native and the SRFI 70 domain, like inexact non-integers.
;;;
;;; - expt: SRFI 70 defines 0 raised to a negative power as +inf.0
;;;   (division by zero returns an infinity rather than erroring — its
;;;   central rationale for the whole SRFI). Kaappi's native `expt`
;;;   already gets this right whenever the base is inexact zero, signed
;;;   correctly per IEEE 754 ((expt -0.0 -5) => -inf.0, (expt 0.0 -5) =>
;;;   +inf.0), and whenever the exponent is a non-integer ((expt 0 -1/2)
;;;   => +inf.0 already); the one gap is an EXACT zero base with a
;;;   negative exponent, e.g. (expt 0 -5), which raises a
;;;   division-by-zero error instead. This library's shadowed `expt`
;;;   intercepts only that exact case (exact zero base, any negative real
;;;   exponent) and returns +inf.0; every other combination — including
;;;   inexact +/-0.0, which must keep its existing sign-aware IEEE
;;;   behavior untouched — delegates straight to the native primitive.
;;;
;;; Everything else SRFI 70 specifies (infinities, exactness rules, sqrt,
;;; rationalize, finite?/infinite?, complex-number procedures,
;;; number->string/string->number, ...) already matches in Kaappi's
;;; (scheme base)/(scheme inexact) with no changes needed, so this library
;;; does not re-export or shadow any of it — import (scheme base) /
;;; (scheme inexact) directly for those, alongside this library, as the
;;; test file does.

(define-library (srfi 70)
  (export exact-floor exact-ceiling exact-truncate exact-round
          quotient remainder modulo
          gcd lcm
          expt)
  (import (except (scheme base) quotient remainder modulo gcd lcm expt)
          (rename (only (scheme base) quotient remainder modulo gcd lcm expt)
                  (quotient %quotient)
                  (remainder %remainder)
                  (modulo %modulo)
                  (gcd %gcd)
                  (lcm %lcm)
                  (expt %expt)))
  (begin

    ;; --- new convenience procedures ----------------------------------

    (define (exact-floor x) (inexact->exact (floor x)))
    (define (exact-ceiling x) (inexact->exact (ceiling x)))
    (define (exact-truncate x) (inexact->exact (truncate x)))
    (define (exact-round x) (inexact->exact (round x)))

    ;; --- quotient / remainder / modulo over exact rationals ----------

    ;; #t for exactly the type Kaappi's native quotient/remainder/modulo/
    ;; gcd/lcm reject: an exact rational that is not an integer (2/3, 1/5,
    ;; ...). Plain integers (exact or inexact) and inexact non-integers
    ;; (6.5) already work natively and must not be rerouted.
    (define (%exact-ratio? x)
      (and (exact? x) (rational? x) (not (integer? x))))

    (define (%needs-general-division? x1 x2)
      (or (%exact-ratio? x1) (%exact-ratio? x2)))

    (define (quotient x1 x2)
      (if (%needs-general-division? x1 x2)
          (truncate (/ x1 x2))
          (%quotient x1 x2)))

    (define (remainder x1 x2)
      (if (%needs-general-division? x1 x2)
          (- x1 (* x2 (quotient x1 x2)))
          (%remainder x1 x2)))

    (define (modulo x1 x2)
      (if (%needs-general-division? x1 x2)
          (- x1 (* x2 (floor (/ x1 x2))))
          (%modulo x1 x2)))

    ;; --- gcd / lcm over exact rationals -------------------------------

    (define (%any-exact-ratio? args)
      (cond ((null? args) #f)
            ((%exact-ratio? (car args)) #t)
            (else (%any-exact-ratio? (cdr args)))))

    (define (gcd . args)
      (if (%any-exact-ratio? args)
          (/ (apply %gcd (map numerator args))
             (apply %lcm (map denominator args)))
          (apply %gcd args)))

    (define (lcm . args)
      (if (%any-exact-ratio? args)
          (/ (apply %lcm (map numerator args))
             (apply %gcd (map denominator args)))
          (apply %lcm args)))

    ;; --- expt: 0 raised to a negative power ---------------------------

    (define (expt z1 z2)
      (if (and (exact? z1) (zero? z1) (real? z2) (negative? z2))
          +inf.0
          (%expt z1 z2)))))
