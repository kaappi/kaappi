;; Regression test for #600: constant folding must not fold redefined primitives
;; Uses manual pass/fail since SRFI-64 depends on standard + which we redefine.
(import (scheme base) (scheme write) (scheme process-context))

(define failures 0)
(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (begin (set! failures (+ failures 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write actual) (newline))))

;; Save originals before redefining
(define orig+ +)
(define orig- -)

;; Top-level redefine + to -
(define + -)
(check "redefined + folds as -" -1 (+ 3 4))

;; Restore and redefine *
(define + orig+)
(define * orig-)
(check "redefined * folds as -" -1 (* 3 4))
(define * (lambda (a b) (orig+ a b)))

;; Redefine = to >
(define = >)
(check "redefined = folds as >" #f (= 1 2))
(define = equal?)

;; Redefine not
(define not (lambda (x) 'shadowed))
(check "redefined not" 'shadowed (not #f))

;; simplifyBooleans: (if (not X) A B) must not rewrite when not is redefined
(define not (lambda (x) x))
(check "redefined not in if" 'then (if (not #t) 'then 'else))

;; Redefine zero?
(define zero? (lambda (x) 'custom))
(check "redefined zero?" 'custom (zero? 0))

(if (= failures 0)
    (display "all passed")
    (begin (display failures) (display " failures")))
(newline)
(if (> failures 0) (exit 1))
