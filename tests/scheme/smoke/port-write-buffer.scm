;; KEP-0001 Phase 3 (#1441): file ports buffer output until
;; flush-output-port, close-port, or a read on the same port. Checks the
;; user-visible buffering contract end to end: bytes must NOT be on disk
;; before the first flush, and MUST be after flush/close.
(import (scheme base) (scheme write) (scheme file) (srfi 170))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

(define test-file "/tmp/kaappi-port-write-buffer-test.txt")
(when (file-exists? test-file) (delete-file test-file))

(define (size-of path)
  (file-info:size (file-info path #t)))

(define out (open-output-file test-file))
(write-string "hello" out)
(check "writes buffer until flushed" (size-of test-file) 0)

(flush-output-port out)
(check "flush-output-port drains the buffer" (size-of test-file) 5)

(write-string " world" out)
(close-port out)
(check "close-port flushes the remainder" (size-of test-file) 11)

(define in (open-input-file test-file))
(check "round trip" (read-line in) "hello world")
(close-port in)
(delete-file test-file)

;; String ports and the default (stdout) port accept flush as a no-op.
(define sp (open-output-string))
(write-string "ab" sp)
(flush-output-port sp)
(check "string port flush is harmless" (get-output-string sp) "ab")
(flush-output-port)

(display "port-write-buffer: ")
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (exit 1))
