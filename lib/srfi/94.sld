;;; SRFI 94 — Type-Restricted Numerical Functions
;;;
;;; Adds real-only and integer-only variants of R5RS numeric procedures so
;;; that a type violation is caught at the point of the call that would
;;; otherwise produce a value outside the intended number system, rather
;;; than letting an unintended infinity, NaN, complex, or rational result
;;; propagate silently. Per the spec's own rationale: "By the present SRFI
;;; making `real-sqrt' and `real-ln' of negative numbers an error, compilers
;;; can deduce that the expressions calculating the inputs ... must return
;;; non-negative reals."
;;;
;;; This library provides the spec's 14 real-only procedures (real-exp,
;;; real-ln, real-log, real-sin, real-cos, real-tan, real-asin, real-acos,
;;; real-atan, real-sqrt, real-expt, quo, rem, mod), its 3 integer-only
;;; procedures (integer-sqrt, integer-expt, integer-log), and the `ln'
;;; synonym for `log' that the spec explicitly calls out as not itself
;;; type-restricted ("Although not a type-restricted function, `ln' is
;;; added as a synonym for `log' because `log' is not used consistently to
;;; denote the natural logarithm.").
;;;
;;; The spec's "Specification" section also describes tightened, but
;;; *same-named*, replacements for seven R5RS procedures: abs, the
;;; two-argument atan, make-rectangular, make-polar, quotient, remainder,
;;; and modulo. This library deliberately does not re-export any of those
;;; seven names, for reasons verified directly against Kaappi's engine:
;;;
;;;   - abs, atan (2-arg), make-rectangular, and make-polar already signal
;;;     a type error on non-real input in Kaappi's (scheme base) -- e.g.
;;;     (abs 3+4i), (atan 1 2+3i), (make-rectangular 1 2+3i), and
;;;     (make-polar 1 2+3i) all raise a type error already -- so
;;;     re-exporting wrappers for them here would add nothing.
;;;   - quotient, remainder, and modulo are the one place where Kaappi's
;;;     (scheme base) is *more* permissive than this SRFI wants: R7RS lets
;;;     them accept inexact integers (e.g. (quotient 5. 2) => 2.), whereas
;;;     SRFI 94 requires exact integers and mandates an error otherwise.
;;;     Shipping stricter same-named versions here would create an
;;;     R7RS-ambiguous binding in any program that imports both
;;;     (scheme base) and (srfi 94) -- the common case, including this
;;;     library's own test file -- since R7RS says it is an error to
;;;     import two different bindings for one identifier. Kaappi's library
;;;     system does not currently detect that particular ambiguity (it
;;;     silently lets the later import win rather than signaling an
;;;     error), but this library does not rely on that non-standard,
;;;     undiagnosed shadowing behavior. A program that wants the stricter
;;;     exact-integer-only behavior under the standard names can shadow it
;;;     explicitly, e.g. `(import (except (scheme base) quotient remainder
;;;     modulo) (srfi 94))` plus local definitions built from this
;;;     library's other procedures.
;;;
;;; Separately, while implementing and testing this library against
;;; Kaappi's engine we found that `expt' does not handle negative reals as
;;; completely as `sqrt' does: (sqrt -8) correctly returns a complex result
;;; (+2.828...i), but (expt -8 1/3) returns +nan.0 instead of the
;;; mathematically correct complex value (1+1.732...i per the general
;;; z1^z2 = e^(z2 * ln z1) definition that R7RS's own `expt' spec uses, and
;;; that Kaappi's `expt' already implements for genuinely complex
;;; arguments -- it just doesn't reach that code path when both arguments
;;; are real). `real-expt' below never exercises this path: it signals its
;;; own error for a negative base with a non-integer exponent *before*
;;; calling `expt' at all, exactly per this SRFI's reference
;;; implementation, so the gap does not affect this library's correctness.
;;; It is still a real gap in `expt' itself; see the accompanying report
;;; for a full repro (also: (expt -8 1/3) and (expt -8.0 0.5) both give
;;; +nan.0, while (expt -8.0 -2), an integer exponent, correctly gives
;;; 0.015625 -- so the bug is specifically the negative-base
;;; non-integer-exponent combination, not general negative-base handling).
(define-library (srfi 94)
  (import (scheme base) (scheme inexact) (scheme case-lambda))
  (export real-exp real-ln real-log real-sin real-cos real-tan
          real-asin real-acos real-atan real-sqrt real-expt
          integer-sqrt integer-expt integer-log
          quo rem mod ln)
  (begin

    (define (%real-error name . irritants)
      (apply error (string-append name ": argument(s) must be real") irritants))

    (define (real-exp x) (if (real? x) (exp x) (%real-error "real-exp" x)))
    (define (real-sin x) (if (real? x) (sin x) (%real-error "real-sin" x)))
    (define (real-cos x) (if (real? x) (cos x) (%real-error "real-cos" x)))
    (define (real-tan x) (if (real? x) (tan x) (%real-error "real-tan" x)))

    ;; must-be-real+: non-negative real required.
    (define (real-ln x)
      (if (and (real? x) (>= x 0))
          (log x)
          (error "real-ln: argument must be a non-negative real number" x)))

    (define (real-sqrt x)
      (if (and (real? x) (>= x 0))
          (sqrt x)
          (error "real-sqrt: argument must be a non-negative real number" x)))

    ;; must-be-real-1+1: real in [-1, 1] required.
    (define (real-asin x)
      (if (and (real? x) (<= -1 x 1))
          (asin x)
          (error "real-asin: argument must be a real number in [-1, 1]" x)))

    (define (real-acos x)
      (if (and (real? x) (<= -1 x 1))
          (acos x)
          (error "real-acos: argument must be a real number in [-1, 1]" x)))

    ;; Single- or two-argument, matching the reference implementation's
    ;; (lambda (y . x) ...): the two-argument form is the type-restricted
    ;; replacement for R5RS's two-argument atan.
    (define real-atan
      (case-lambda
        ((y) (if (real? y) (atan y) (%real-error "real-atan" y)))
        ((y x) (if (and (real? y) (real? x))
                   (atan y x)
                   (%real-error "real-atan" y x)))))

    ;; real-log y x = log base y of x = (/ (ln x) (ln y)). Note the
    ;; argument order: y (first) is the base, x (second) is the value --
    ;; this is the OPPOSITE order from Kaappi's native two-argument `log',
    ;; which takes (log value base). We compute directly from `log' calls
    ;; rather than delegating to two-argument `log' itself, to avoid
    ;; silently swapping base and value.
    (define (real-log y x)
      (if (and (real? y) (> y 0) (real? x) (> x 0))
          (/ (log x) (log y))
          (error "real-log: arguments must be positive real numbers" y x)))

    ;; real-expt: mirrors the spec's reference implementation guard,
    ;; `(or (not (negative? x1)) (integer? x2))`, which is exactly the
    ;; condition under which x1^x2 is guaranteed real. This also sidesteps
    ;; the `expt' gap documented above, since we never call `expt' with a
    ;; negative base and a non-integer exponent.
    ;;
    ;; One extra check beyond the reference: (expt 0.0 <negative>) returns
    ;; +inf.0 in Kaappi rather than signaling an error, but the spec's text
    ;; explicitly requires an error for 0.0 raised to a negative power
    ;; ("(real-expt 0.0 x2) ... signals an error otherwise"), so that case
    ;; is checked explicitly. (Exact 0 to a negative exact power already
    ;; signals "division by zero" natively and needs no extra check.)
    (define (real-expt x1 x2)
      (cond
        ((not (and (real? x1) (real? x2)))
         (error "real-expt: arguments must be real numbers" x1 x2))
        ((and (inexact? x1) (= x1 0) (negative? x2))
         (error "real-expt: 0.0 raised to a negative power is undefined" x1 x2))
        ((or (not (negative? x1)) (integer? x2))
         (expt x1 x2))
        (else
         (error "real-expt: result would not be a real number" x1 x2))))

    ;; integer-sqrt: built on the R7RS-mandated `exact-integer-sqrt', which
    ;; already computes exactly what the spec's hand-rolled isqrt algorithm
    ;; computes (the largest integer whose square is <= n) plus a
    ;; remainder we don't need.
    (define (integer-sqrt n)
      (if (and (exact-integer? n) (>= n 0))
          (call-with-values (lambda () (exact-integer-sqrt n))
            (lambda (root rem) root))
          (error "integer-sqrt: argument must be a non-negative exact integer" n)))

    ;; integer-expt: mirrors the spec's reference guard exactly -- both
    ;; arguments exact integers, and not (|n1| > 1 and n2 negative), which
    ;; is precisely when n1^n2 is guaranteed to be an exact integer.
    ;; (integer-expt 0 <negative>) falls through to `expt', which already
    ;; signals "division by zero" natively in Kaappi.
    (define (integer-expt n1 n2)
      (if (and (exact-integer? n1) (exact-integer? n2)
               (not (and (not (<= -1 n1 1)) (negative? n2))))
          (expt n1 n2)
          (error "integer-expt: arguments must be exact integers whose power is itself an exact integer" n1 n2)))

    ;; integer-log k1 k2: largest exact integer n such that k1^n <= k2.
    ;; The spec's prose says "positive exact integer" for both k1 and k2,
    ;; but its own reference implementation additionally requires k1 > 1
    ;; (via `(eigt? base 1)`, i.e. base > 1) since log base 1 is undefined
    ;; (1^n = 1 for every n). We follow the reference's stricter, correct
    ;; guard rather than the looser prose.
    (define (integer-log k1 k2)
      (if (and (exact-integer? k1) (> k1 1)
               (exact-integer? k2) (> k2 0))
          (let loop ((n 0) (p 1))
            (if (> (* p k1) k2) n (loop (+ n 1) (* p k1))))
          (error "integer-log: k1 must be an exact integer > 1 and k2 an exact integer > 0" k1 k2)))

    ;; quo/rem/mod: the real-number (Common Lisp truncate/floor-based)
    ;; division trio, ported verbatim from the spec's reference
    ;; implementation formulas. Only the "must be real" restriction is
    ;; checked explicitly -- like the reference, we let a zero divisor
    ;; propagate through `/' exactly as `/' itself already handles it
    ;; (the spec states "x2 should be non-zero" as a caller obligation,
    ;; not as an additional error condition to check, unlike the stronger
    ;; "an error is signaled" wording used for quotient/remainder/modulo).
    (define (quo x1 x2)
      (if (and (real? x1) (real? x2))
          (truncate (/ x1 x2))
          (%real-error "quo" x1 x2)))

    (define (rem x1 x2)
      (if (and (real? x1) (real? x2))
          (- x1 (* x2 (quo x1 x2)))
          (%real-error "rem" x1 x2)))

    (define (mod x1 x2)
      (if (and (real? x1) (real? x2))
          (- x1 (* x2 (floor (/ x1 x2))))
          (%real-error "mod" x1 x2)))

    ;; Not type-restricted -- a plain synonym, per the spec text.
    (define ln log)))
