;; SRFI-156 (Syntactic combiners for binary predicates) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi156.scm

(import (scheme base) (scheme process-context) (srfi 156) (srfi 64))

(test-begin "srfi-156")

;;; --- basic infix ---
(test-assert "is: basic infix, true" (is 3 < 5))
(test-assert "is: basic infix, false" (not (is 5 < 3)))
(test-assert "isnt: negates" (isnt 5 < 3))
(test-assert "isnt: negates false to true is false" (not (isnt 3 < 5)))

;;; --- unary (two-argument) form ---
(test-assert "is: unary predicate application" (is 4 even?))
(test-assert "isnt: unary predicate negation" (isnt 4 odd?))

;;; --- underscore placeholder: builds a lambda ---
(test-assert "is: single placeholder" ((is _ < 5) 3))
(test-assert "is: placeholder on the left" ((is 5 < _) 10))
(test-assert "is: two placeholders" ((is _ < _) 3 5))
(test-assert "is: single placeholder, unary predicate" ((is _ even?) 4))
(test-assert "isnt: placeholder negation" ((isnt _ even?) 3))

;;; --- chained comparisons: conjunction, each middle term evaluated once ---
(test-assert "is: chain, all true" (is 1 < 2 <= 2 < 3))
(test-assert "is: chain, one comparison false" (not (is 1 < 2 <= 2 < 1)))

;; Regression: each middle argument must be evaluated exactly once even
;; though it participates in two comparisons.
(let ((calls 0))
  (define (mid) (set! calls (+ calls 1)) 5)
  (is 1 < (mid) < 10)
  (test-equal "is: chain evaluates each middle term once" 1 calls))

(let ((runner (test-runner-current)))
  (test-end "srfi-156")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
