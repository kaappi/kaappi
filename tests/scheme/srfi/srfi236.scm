;; SRFI-236 (Evaluating expressions in an unspecified order) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi236.scm

(import (scheme base) (scheme process-context) (srfi 236) (srfi 64))

(test-begin "srfi-236")

;;; --- zero expressions: legal, unlike begin ---
(call-with-values (lambda () (independently)) (lambda vals (test-equal "independently: zero expressions returns zero values" '() vals)))

;;; --- side effects all happen, regardless of order ---
(let ((p (cons 0 0)))
  (independently (set-car! p 1) (set-cdr! p 2))
  (test-equal "independently: both side effects occur" '(1 . 2) p))

(let ((log '()))
  (independently
    (set! log (cons 'a log))
    (set! log (cons 'b log))
    (set! log (cons 'c log)))
  (test-equal "independently: all three side effects occur (order unspecified)" 3 (length log))
  (test-assert "independently: side effect a occurred" (memq 'a log))
  (test-assert "independently: side effect b occurred" (memq 'b log))
  (test-assert "independently: side effect c occurred" (memq 'c log)))

;;; --- the spec's own example ---
(define (set-car+cdr! p x y)
  (independently
    (set-car! p x)
    (set-cdr! p y)))
(let ((p (cons #f #f)))
  (set-car+cdr! p 'x 'y)
  (test-equal "independently: spec's set-car+cdr! example" '(x . y) p))

(let ((runner (test-runner-current)))
  (test-end "srfi-236")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
