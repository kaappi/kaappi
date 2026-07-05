;; SRFI-6 (basic string ports) conformance tests — audit Phase 3a
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi6.scm

(import (scheme base) (scheme read) (scheme write) (srfi 6) (chibi test))

(test-begin "srfi-6")

;;; --- open-input-string ---
(define ip (open-input-string "(a b) 42 \"str\" #\\x"))
(test '(a b) (read ip))
(test 42 (read ip))
(test "str" (read ip))
(test #\x (read ip))
(test #t (eof-object? (read ip)))
(test #t (eof-object? (read ip)))          ; stays at EOF

;; char-level reads
(define ip2 (open-input-string "xy"))
(test #\x (peek-char ip2))
(test #\x (read-char ip2))
(test #\y (read-char ip2))
(test #t (eof-object? (read-char ip2)))

;; empty source
(test #t (eof-object? (read (open-input-string ""))))

;;; --- open-output-string / get-output-string ---
(define op (open-output-string))
(test "" (get-output-string op))
(write 'hello op)
(display " " op)
(write "wo" op)
(test "hello \"wo\"" (get-output-string op))

;; the port keeps accumulating after get-output-string
(display "+" op)
(test "hello \"wo\"+" (get-output-string op))

;; each get-output-string result is independent of later writes
(define op2 (open-output-string))
(display "ab" op2)
(define snap (get-output-string op2))
(display "cd" op2)
(test "ab" snap)
(test "abcd" (get-output-string op2))

;; SRFI-6 example shape: reverse a datum through string ports
(define (rev-datum s)
  (let ((in (open-input-string s))
        (out (open-output-string)))
    (write (reverse (read in)) out)
    (get-output-string out)))
(test "(c b a)" (rev-datum "(a b c)"))

(test-end "srfi-6")
