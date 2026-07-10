;; SRFI-61 (a more general cond clause) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi61.scm

(import (scheme base) (srfi 61) (scheme process-context) (srfi 64))

(test-begin "srfi-61")

;; importing (srfi 61) must not break ordinary cond
(test-equal 'a (cond (#t 'a) (else 'b)))
(test-equal 'b (cond (#f 'a) (else 'b)))
(test-equal 2 (cond ((assv 1 '((1 . 2))) => cdr) (else 'no)))

;; test-only clause returns the test value
(test-equal 42 (cond (42)))

;;; --- the SRFI-61 (generator guard => receiver) clause ---

;; multi-value generator, guard succeeds
(test-equal 3 (cond ((values 1 2) (lambda (a b) #t) => (lambda (a b) (+ a b)))
                    (else 'no)))

;; multi-value generator, guard fails — falls through to else
(test-equal 'skipped (cond ((values 1 2) (lambda (a b) #f) => (lambda (a b) 'used))
                           (else 'skipped)))

;; single-value generator with guard
(test-equal 10 (cond (5 positive? => (lambda (x) (* x 2)))
                     (else 'no)))

;; single-value guard fails, falls to next clause
(test-equal 'neg (cond (-1 positive? => (lambda (x) (* x 2)))
                       (else 'neg)))

;; SRFI-61 clause mixed with standard clauses
(test-equal 'second (cond (#f 'first)
                          (42 number? => (lambda (x) 'second))
                          (else 'third)))

;; guard fails, next SRFI-61 clause matches
(test-equal 'b (cond ((values 1) (lambda (x) (> x 5)) => (lambda (x) 'a))
                     ((values 2) (lambda (x) (< x 5)) => (lambda (x) 'b))
                     (else 'c)))

(let ((runner (test-runner-current)))
  (test-end "srfi-61")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
