(define-library (chibi test)
  (import (scheme base) (scheme write))
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

    (define-syntax test
      (syntax-rules ()
        ((test expected expr)
         (let ((res expr))
           (if (equal? res expected)
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
