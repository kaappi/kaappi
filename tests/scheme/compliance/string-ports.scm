;;; String port compliance tests (R7RS 6.13)
(import (scheme base) (scheme read) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "string-ports")

;; --- open-input-string / read-char ---
(test-group "read-char from string port"
  (test-eqv "read-char first"
    #\h
    (let ((p (open-input-string "hello")))
      (read-char p)))
  (test-eqv "read-char sequential"
    #\l
    (let ((p (open-input-string "hello")))
      (read-char p)  ; h
      (read-char p)  ; e
      (read-char p))))

;; --- open-output-string / get-output-string ---
(test-group "output string port"
  (test-equal "write-char and write-string"
    "Hello"
    (let ((p (open-output-string)))
      (write-char #\H p)
      (write-string "ello" p)
      (get-output-string p))))

;; --- read-line ---
(test-group "read-line from string port"
  (test-equal "read-line first line"
    "line1"
    (let ((p (open-input-string "line1\nline2\n")))
      (read-line p)))
  (test-equal "read-line second line"
    "line2"
    (let ((p (open-input-string "line1\nline2\n")))
      (read-line p)
      (read-line p))))

;; --- read ---
(test-group "read from string port"
  (test-equal "read s-expression"
    '(+ 1 2)
    (let ((p (open-input-string "(+ 1 2)")))
      (read p))))

;; --- peek-char ---
(test-group "peek-char from string port"
  (test-eqv "peek-char does not consume"
    #\a
    (let ((p (open-input-string "ab")))
      (peek-char p)
      (read-char p)))
  (test-eqv "read-char after peek-char"
    #\b
    (let ((p (open-input-string "ab")))
      (peek-char p)
      (read-char p)
      (read-char p))))

;; --- read-string ---
(test-group "read-string"
  (test-equal "read-string partial"
    "hello"
    (let ((p (open-input-string "hello world")))
      (read-string 5 p))))

;; --- eof on empty string port ---
(test-group "eof on empty string port"
  (test-assert "eof-object? on empty port"
    (let ((p (open-input-string "")))
      (eof-object? (read-char p)))))

;; --- flush-output-port ---
(test-group "flush-output-port"
  (test-assert "flush-output-port completes"
    (begin (flush-output-port) #t)))

;; --- port predicates ---
(test-group "port predicates on string ports"
  (test-assert "port? on input string port"
    (port? (open-input-string "test")))
  (test-assert "input-port? on input string port"
    (input-port? (open-input-string "test")))
  (test-assert "output-port? on output string port"
    (output-port? (open-output-string))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "string-ports")
(if (> %test-fail-count 0) (exit 1))
