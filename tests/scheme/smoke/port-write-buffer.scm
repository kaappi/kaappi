;; KEP-0001 Phase 3 (#1441): file ports buffer output until
;; flush-output-port, close-port, or a read on the same port. Checks the
;; user-visible buffering contract end to end: bytes must NOT be on disk
;; before the first flush, and MUST be after flush/close.
(import (scheme base) (scheme write) (scheme file) (scheme process-context)
        (srfi 64) (srfi 170))

(test-begin "port-write-buffer")

(define test-file "/tmp/kaappi-port-write-buffer-test.txt")
(when (file-exists? test-file) (delete-file test-file))

(define (size-of path)
  (file-info:size (file-info path #t)))

(define out (open-output-file test-file))
(write-string "hello" out)
(test-equal "writes buffer until flushed" 0 (size-of test-file))

(flush-output-port out)
(test-equal "flush-output-port drains the buffer" 5 (size-of test-file))

(write-string " world" out)
(close-port out)
(test-equal "close-port flushes the remainder" 11 (size-of test-file))

(define in (open-input-file test-file))
(test-equal "round trip" "hello world" (read-line in))
(close-port in)
(delete-file test-file)

;; String ports and the default (stdout) port accept flush as a no-op.
(define sp (open-output-string))
(write-string "ab" sp)
(flush-output-port sp)
(test-equal "string port flush is harmless" "ab" (get-output-string sp))
(flush-output-port)
(test-assert "default-port flush returns" #t)

(let ((runner (test-runner-current)))
  (test-end "port-write-buffer")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
