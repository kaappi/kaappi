(import (scheme base) (scheme write) (scheme process-context) (srfi 170))

;; Windows reports no block geometry (documented degradation) — skip there.
(cond-expand
  (windows (display "skipped on windows\n") (exit 0))
  (else #f))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define test-file "/tmp/kaappi-blocks-test.txt")

;; Write enough data to occupy multiple disk blocks
(call-with-output-file test-file
  (lambda (p) (write-string (make-string 100000 #\a) p)))

(define fi (file-info test-file))

(check "file-info:size" (file-info:size fi) 100000)

;; blocks should be a positive integer for a 100KB file
(check "file-info:blocks is number" (number? (file-info:blocks fi)) #t)
(check "file-info:blocks > 0" (> (file-info:blocks fi) 0) #t)

;; An empty file should have 0 blocks (or very few)
(define empty-file "/tmp/kaappi-blocks-empty.txt")
(call-with-output-file empty-file (lambda (p) (values)))
(define fi2 (file-info empty-file))
(check "empty file blocks >= 0" (>= (file-info:blocks fi2) 0) #t)

;; Clean up
(delete-file test-file)
(delete-file empty-file)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "file-info:blocks tests failed" fail))
