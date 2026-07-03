;; Regression test for #799: (read) on a string port must consume a
;; pending peek_byte instead of returning EOF.

(import (scheme base) (scheme read) (scheme write) (scheme process-context) (srfi 64))

(test-begin "read-string-port-peek-799")

;; Case 1: read-line pushes back a byte after consuming \r
(let ((p (open-input-string "a\rb")))
  (test-equal "read-line consumes up to CR" "a" (read-line p))
  (test-equal "read sees pushed-back byte after read-line" 'b (read p)))

;; Case 2: peek-u8 sets peek_byte, then read must see it
(let ((p (open-input-string "5")))
  (test-equal "peek-u8 returns byte" 53 (peek-u8 p))
  (test-equal "read sees datum after peek-u8" 5 (read p)))

;; Case 3: peek-char then read on a single-char string
(let ((p (open-input-string "x")))
  (peek-char p)
  (test-equal "read sees datum after peek-char" 'x (read p)))

(let ((runner (test-runner-current)))
  (test-end "read-string-port-peek-799")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
