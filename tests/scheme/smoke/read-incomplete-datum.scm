;; Regression test: (read port) must signal an error satisfying read-error?
;; when end of file is encountered mid-datum (R7RS 6.13.2), instead of
;; returning the EOF object. EOF before any datum text still returns the
;; EOF object. Covers both string ports and file ports.
(import (scheme base) (scheme read) (scheme write) (scheme file)
        (scheme process-context) (srfi 64))

(define (read-raises-read-error? s)
  (guard (e (#t (read-error? e)))
    (read (open-input-string s))
    #f))

(test-begin "read-incomplete-datum")

;; EOF mid-datum: must raise a read error
(test-assert "unclosed list" (read-raises-read-error? "(unclosed"))
(test-assert "unclosed nested list" (read-raises-read-error? "(a (b c"))
(test-assert "unterminated string" (read-raises-read-error? "\"abc"))
(test-assert "unclosed vector" (read-raises-read-error? "#(1 2"))
(test-assert "unclosed bytevector" (read-raises-read-error? "#u8(1 2"))
(test-assert "lone quote" (read-raises-read-error? "'"))
(test-assert "unterminated block comment" (read-raises-read-error? "#| foo"))
(test-assert "incomplete datum comment" (read-raises-read-error? "#;(1"))

;; EOF before any datum begins: must return the EOF object
(test-assert "empty input"
  (eof-object? (read (open-input-string ""))))
(test-assert "whitespace only"
  (eof-object? (read (open-input-string "  \n\t "))))
(test-assert "line comment only"
  (eof-object? (read (open-input-string "; nothing"))))
(test-assert "block comment only"
  (eof-object? (read (open-input-string "#| done |#"))))
(test-assert "datum comment only"
  (eof-object? (read (open-input-string "#;(1 2)"))))

;; Complete datum still reads normally, then EOF
(test-equal "complete then eof" '(1 2)
  (let ((p (open-input-string " (1 2) ")))
    (let ((v (read p)))
      (and (eof-object? (read p)) v))))

;; File ports (fd path) follow the same rule
(define test-file "/tmp/kaappi-read-incomplete-test.scm")
(call-with-output-file test-file
  (lambda (p) (write-string "(unclosed" p)))
(test-assert "unclosed list from file port"
  (guard (e (#t (read-error? e)))
    (call-with-input-file test-file read)
    #f))
(call-with-output-file test-file
  (lambda (p) (write-string "   ; just a comment\n" p)))
(test-assert "whitespace-only file port"
  (eof-object? (call-with-input-file test-file read)))
(delete-file test-file)

(let ((runner (test-runner-current)))
  (test-end "read-incomplete-datum")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
