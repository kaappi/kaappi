;;; SRFI 144 — Flonums
(define-library (srfi 144)
  (import (scheme base) (scheme inexact))
  (export fl+ fl- fl* fl/ fl= fl< fl> fl<= fl>=
          flzero? flpositive? flnegative? flodd? fleven?
          flinteger? flfinite? flinfinite? flnan?
          flabs flfloor flceiling fltruncate flround
          flmin flmax
          flsqrt flexp fllog flsin flcos fltan
          flasin flacos flatan
          flexpt
          fl->exact exact->fl
          flonum? fixnum->flonum
          fl-e fl-pi fl-1/pi fl-2/pi
          fl-greatest fl-least fl-epsilon
          fl-integer-exponent-zero fl-integer-exponent-nan)
  (begin

    ;; Constants
    (define fl-e 2.718281828459045)
    (define fl-pi 3.141592653589793)
    (define fl-1/pi 0.3183098861837907)
    (define fl-2/pi 0.6366197723675814)
    (define fl-greatest 1.7976931348623157e308)
    (define fl-least 5e-324)
    (define fl-epsilon 2.220446049250313e-16)
    (define fl-integer-exponent-zero 0)
    (define fl-integer-exponent-nan 0)

    ;; Predicates
    (define (flonum? x) (and (number? x) (inexact? x)))
    (define (flzero? x) (= x 0.0))
    (define (flpositive? x) (> x 0.0))
    (define (flnegative? x) (< x 0.0))
    (define (flinteger? x) (= x (floor x)))
    (define (flodd? x) (and (flinteger? x) (odd? (exact x))))
    (define (fleven? x) (and (flinteger? x) (even? (exact x))))
    (define (flfinite? x) (finite? x))
    (define (flinfinite? x) (infinite? x))
    (define (flnan? x) (nan? x))

    ;; Arithmetic
    (define (fl+ . args) (apply + args))
    (define (fl- x . args) (apply - x args))
    (define (fl* . args) (apply * args))
    (define (fl/ x . args) (apply / x args))

    ;; Comparison
    (define (fl= . args) (apply = args))
    (define (fl< . args) (apply < args))
    (define (fl> . args) (apply > args))
    (define (fl<= . args) (apply <= args))
    (define (fl>= . args) (apply >= args))

    ;; Rounding
    (define flabs abs)
    (define flfloor floor)
    (define flceiling ceiling)
    (define fltruncate truncate)
    (define flround round)

    ;; Min/max
    (define (flmin . args)
      (if (null? args)
          +inf.0
          (let loop ((best (car args)) (rest (cdr args)))
            (if (null? rest)
                best
                (loop (if (< (car rest) best) (car rest) best) (cdr rest))))))
    (define (flmax . args)
      (if (null? args)
          -inf.0
          (let loop ((best (car args)) (rest (cdr args)))
            (if (null? rest)
                best
                (loop (if (> (car rest) best) (car rest) best) (cdr rest))))))

    ;; Math
    (define flsqrt sqrt)
    (define flexp exp)
    (define (fllog x . args)
      (if (pair? args) (/ (log x) (log (car args))) (log x)))
    (define flsin sin)
    (define flcos cos)
    (define fltan tan)
    (define flasin asin)
    (define flacos acos)
    (define (flatan y . args)
      (if (pair? args) (atan y (car args)) (atan y)))
    (define flexpt expt)

    ;; Conversion
    (define fl->exact exact)
    (define exact->fl inexact)
    (define fixnum->flonum inexact)))
