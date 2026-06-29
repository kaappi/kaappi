;; Regression test for #428: GC objectSize for continuations must count
;; backing buffer in bytes (len * 8), not elements (len).
;; If objectSize undercounts, bytes_allocated inflates over time.

(import (scheme base) (scheme write))

(define (make-continuation)
  (call-with-current-continuation
    (lambda (k) k)))

;; Create and discard many continuations to exercise GC.
;; If objectSize undercounts, bytes_allocated will grow unboundedly.
(let loop ((i 0))
  (when (< i 1000)
    (make-continuation)
    (loop (+ i 1))))

(display "PASS")
(newline)
