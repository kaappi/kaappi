;; Multi-shot re-entry within a single program (global mutable counter so
;; set! persists across continuation invocations). Should count up to 5.
(import (scheme base) (scheme process-context) (srfi 64))

(define k #f)
(define n 0)
(define (go)
  (call/cc (lambda (c) (set! k c)))
  (set! n (+ n 1))
  (if (< n 5) (k #f))
  n)

;; Run before test-begin because go mutates globals via continuations
(define go-result (go))

(define %test-fail-count 0)
(test-begin "callcc-multishot")

(test-eqv "multi-shot counts to 5" 5 go-result)

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "callcc-multishot")
(if (> %test-fail-count 0) (exit 1))
