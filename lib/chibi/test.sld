(define-library (chibi test)
  (import (scheme base) (scheme write) (scheme complex))
  (export test test-assert test-error test-values test-begin test-end)
  (begin

    (define pass-count 0)
    (define fail-count 0)
    (define total-pass 0)
    (define total-fail 0)
    (define current-section "")

    (define (test-begin name)
      (set! current-section name)
      (set! pass-count 0)
      (set! fail-count 0)
      (display "== ")
      (display name)
      (display " ==")
      (newline))

    (define (test-end . args)
      (set! total-pass (+ total-pass pass-count))
      (set! total-fail (+ total-fail fail-count))
      (display "  ")
      (display pass-count)
      (display " pass, ")
      (display fail-count)
      (display " fail")
      (newline))

    (define (test-pass)
      (set! pass-count (+ pass-count 1)))

    (define (test-fail expected actual)
      (set! fail-count (+ fail-count 1))
      (display "FAIL [")
      (display current-section)
      (display "]: expected ")
      (write expected)
      (display " got ")
      (write actual)
      (newline))

    ;; Inexact real results are compared with a small relative tolerance, the
    ;; way the real (chibi test) does: the R7RS suite hard-codes constants like
    ;; 3.14159265358979 that differ from a full-precision result only in the
    ;; last few digits. Exact values, and any non-real/complex values, use
    ;; equal?. NaN/inf match through the equal? fast path.
    (define (test-approx=? a b)
      (or (equal? a b)
          (and (real? a) (real? b)
               (let ((diff (abs (- a b))))
                 (<= diff (* 1e-6 (max 1.0 (abs a) (abs b))))))
          (and (complex? a) (complex? b)
               (not (real? a)) (not (real? b))
               (test-approx=? (real-part a) (real-part b))
               (test-approx=? (imag-part a) (imag-part b)))))

    (define (test-equal? expected actual)
      (cond
        ((and (number? expected) (number? actual)
              (inexact? expected) (inexact? actual))
         (test-approx=? expected actual))
        ((and (complex? expected) (complex? actual)
              (not (real? expected)) (not (real? actual)))
         (test-approx=? expected actual))
        (else (equal? expected actual))))

    (define-syntax test
      (syntax-rules ()
        ((test expected expr)
         (let ((res expr))
           (if (test-equal? expected res)
               (test-pass)
               (test-fail expected res))))
        ((test name expected expr)
         (test expected expr))))

    (define-syntax test-assert
      (syntax-rules ()
        ((test-assert expr)
         (test #t (if expr #t #f)))
        ((test-assert name expr)
         (test-assert expr))))

    (define-syntax test-error
      (syntax-rules ()
        ((test-error expr)
         (test #t (guard (e (#t #t)) expr #f)))
        ((test-error name expr)
         (test-error expr))))

    (define-syntax test-values
      (syntax-rules ()
        ((test-values expected expr)
         (test (call-with-values (lambda () expected) list)
               (call-with-values (lambda () expr) list)))))

    ))
