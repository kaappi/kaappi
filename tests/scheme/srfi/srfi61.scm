;; SRFI-61 (a more general cond clause) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi61.scm

(import (scheme base) (srfi 61) (chibi test))

(test-begin "srfi-61")

;; importing (srfi 61) must not break ordinary cond
(test 'a (cond (#t 'a) (else 'b)))
(test 'b (cond (#f 'a) (else 'b)))
(test 2 (cond ((assv 1 '((1 . 2))) => cdr) (else 'no)))

;; test-only clause returns the test value
(test 42 (cond (42)))

;;; --- the SRFI-61 (generator guard => receiver) clause ---

;; multi-value generator, guard succeeds
(test 3 (cond ((values 1 2) (lambda (a b) #t) => (lambda (a b) (+ a b)))
              (else 'no)))

;; multi-value generator, guard fails — falls through to else
(test 'skipped (cond ((values 1 2) (lambda (a b) #f) => (lambda (a b) 'used))
                     (else 'skipped)))

;; single-value generator with guard
(test 10 (cond (5 positive? => (lambda (x) (* x 2)))
               (else 'no)))

;; single-value guard fails, falls to next clause
(test 'neg (cond (-1 positive? => (lambda (x) (* x 2)))
                 (else 'neg)))

;; SRFI-61 clause mixed with standard clauses
(test 'second (cond (#f 'first)
                    (42 number? => (lambda (x) 'second))
                    (else 'third)))

;; guard fails, next SRFI-61 clause matches
(test 'b (cond ((values 1) (lambda (x) (> x 5)) => (lambda (x) 'a))
               ((values 2) (lambda (x) (< x 5)) => (lambda (x) 'b))
               (else 'c)))

(test-end "srfi-61")
