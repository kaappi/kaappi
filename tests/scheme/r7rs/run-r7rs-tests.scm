; R7RS Test Suite Runner for Kaappi
; Wraps the chibi r7rs-tests.scm with our test framework

(import (scheme base) (scheme char) (scheme lazy)
        (scheme inexact) (scheme complex) (scheme time)
        (scheme file) (scheme read) (scheme write)
        (scheme eval) (scheme process-context) (scheme case-lambda))

; Test framework (replaces (chibi test))
(define test-pass-count 0)
(define test-fail-count 0)
(define test-total-pass 0)
(define test-total-fail 0)
(define test-section "")

(define (test-begin name)
  (set! test-section name)
  (set! test-pass-count 0)
  (set! test-fail-count 0)
  (display "== ")
  (display name)
  (display " ==")
  (newline))

(define (test-end . args)
  (set! test-total-pass (+ test-total-pass test-pass-count))
  (set! test-total-fail (+ test-total-fail test-fail-count))
  (display "  ")
  (display test-pass-count)
  (display " pass, ")
  (display test-fail-count)
  (display " fail")
  (newline))

(define-syntax test
  (syntax-rules ()
    ((test expected expr)
     (let ((exp expected) (act expr))
       (if (equal? exp act)
           (set! test-pass-count (+ test-pass-count 1))
           (begin
             (set! test-fail-count (+ test-fail-count 1))
             (display "FAIL [")
             (display test-section)
             (display "]: expected ")
             (write exp)
             (display " got ")
             (write act)
             (newline)))))
    ((test name expected expr)
     (test expected expr))))

(define-syntax test-assert
  (syntax-rules ()
    ((test-assert expr)
     (if expr
         (set! test-pass-count (+ test-pass-count 1))
         (begin
           (set! test-fail-count (+ test-fail-count 1))
           (display "FAIL [")
           (display test-section)
           (display "]: assertion failed")
           (newline))))
    ((test-assert name expr)
     (test-assert expr))))

(define-syntax test-error
  (syntax-rules ()
    ((test-error expr)
     (guard (e (#t (set! test-pass-count (+ test-pass-count 1))))
       expr
       (set! test-fail-count (+ test-fail-count 1))
       (display "FAIL [")
       (display test-section)
       (display "]: expected error")
       (newline)))))

(define-syntax test-values
  (syntax-rules ()
    ((test-values expected expr)
     (test expected (call-with-values (lambda () expr) list)))))

; Also need (scheme r5rs) compatibility
; These are R5RS names for procedures that exist under different names in R7RS
(define exact->inexact inexact)
(define inexact->exact exact)

; Load the actual test suite
; We include it inline since our include mechanism works in library context
