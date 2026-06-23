(define-library (srfi 78)
  (import (scheme base) (scheme write))
  (export check check-report check-reset!
          check-passed? check-failed?)
  (begin

    (define %pass 0)
    (define %fail 0)

    (define (check-reset!)
      (set! %pass 0)
      (set! %fail 0))

    (define (check-passed?) %pass)
    (define (check-failed?) %fail)

    (define-syntax check
      (syntax-rules (=>)
        ((_ expr => expected)
         (check-proc 'expr (lambda () expr) expected))
        ((_ expr (=> equal) expected)
         (check-proc-equal 'expr (lambda () expr) expected equal))))

    (define (check-proc name thunk expected)
      (let ((actual (thunk)))
        (if (equal? actual expected)
            (begin
              (set! %pass (+ %pass 1))
              (display "(") (display %pass) (display ") ")
              (write name) (display " => ")
              (write actual) (display " ; correct")
              (newline))
            (begin
              (set! %fail (+ %fail 1))
              (display "(") (display (+ %pass %fail)) (display ") ")
              (write name) (display " => ")
              (write actual) (display " ; *** WRONG ***")
              (display " expected: ") (write expected)
              (newline)))))

    (define (check-proc-equal name thunk expected equal)
      (let ((actual (thunk)))
        (if (equal actual expected)
            (begin
              (set! %pass (+ %pass 1))
              (display "(") (display %pass) (display ") ")
              (write name) (display " => ")
              (write actual) (display " ; correct")
              (newline))
            (begin
              (set! %fail (+ %fail 1))
              (display "(") (display (+ %pass %fail)) (display ") ")
              (write name) (display " => ")
              (write actual) (display " ; *** WRONG ***")
              (display " expected: ") (write expected)
              (newline)))))

    (define (check-report)
      (newline)
      (display "Checks: ")
      (display (+ %pass %fail))
      (display " total, ")
      (display %pass) (display " passed, ")
      (display %fail) (display " failed.")
      (newline)
      (when (> %fail 0) (exit 1)))))
