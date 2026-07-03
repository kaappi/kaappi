;; Regression tests for case-lambda and case fixes:
;; #854: case rejects empty datum list (() body)
;; #836: case-lambda desugaring captured user variables named n or args
;;
;; Checks are manual (not SRFI-64) and every risky expression runs inside
;; guard: an uncaught top-level error does not fail the process exit code,
;; so each check must reach (exit 1) itself for run-all.sh to see a failure.

(import (scheme base) (scheme write) (scheme process-context))

(define (check name expected thunk)
  (let ((actual (guard (e (#t (display "FAIL ")
                              (display name)
                              (display ": raised an error")
                              (newline)
                              (exit 1)))
                  (thunk))))
    (if (equal? actual expected)
        (begin (display "ok ") (display name) (newline))
        (begin (display "FAIL ") (display name)
               (display ": expected ") (write expected)
               (display ", got ") (write actual) (newline)
               (exit 1)))))

;; #854: empty datum list in case
(check "case with empty datum list" 'one
  (lambda () (case 1 (() 'never) ((1) 'one) (else 'other))))

;; #836: case-lambda clause body referencing outer variable named n
(define n 42)
(define f (case-lambda ((x) (+ x n))))
(check "case-lambda body sees outer n" 43
  (lambda () (f 1)))

;; #836: case-lambda clause body referencing outer variable named args
(define args 100)
(define g (case-lambda ((x) (+ x args))))
(check "case-lambda body sees outer args" 101
  (lambda () (g 1)))

;; #836: rest-arg clause goes through the same desugaring
(define h (case-lambda ((x . rest) (+ x n args))))
(check "case-lambda rest clause sees outer n and args" 143
  (lambda () (h 1 2 3)))
