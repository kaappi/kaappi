(import (scheme base) (scheme write) (scheme read) (scheme file) (scheme char))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; ---- String ports ----
(let ((p (open-input-string "hello world")))
  (check-true "input-port? string port" (input-port? p))
  (check-false "output-port? string port" (output-port? p))
  (check-true "textual-port?" (textual-port? p))
  (check "read-char" (read-char p) #\h)
  (check "read-char 2" (read-char p) #\e)
  (check "peek-char" (peek-char p) #\l)
  (check "peek-char again" (peek-char p) #\l)
  (check "read-char after peek" (read-char p) #\l))

(let ((p (open-input-string "")))
  (check-true "eof on empty" (eof-object? (read-char p))))

(let ((p (open-input-string "42")))
  (check "read datum" (read p) 42))

(let ((p (open-input-string "(+ 1 2)")))
  (check "read list" (read p) '(+ 1 2)))

(let ((p (open-input-string "hello world")))
  (check "read-line" (read-line p) "hello world"))

(let ((p (open-input-string "line1\nline2\nline3")))
  (check "read-line 1" (read-line p) "line1")
  (check "read-line 2" (read-line p) "line2")
  (check "read-line 3" (read-line p) "line3")
  (check-true "read-line eof" (eof-object? (read-line p))))

(let ((p (open-output-string)))
  (check-true "output-port?" (output-port? p))
  (check-false "input-port?" (input-port? p))
  (write-char #\H p)
  (write-char #\i p)
  (check "get-output-string" (get-output-string p) "Hi"))

(let ((p (open-output-string)))
  (display "hello" p)
  (display " " p)
  (display "world" p)
  (check "display to string port" (get-output-string p) "hello world"))

(let ((p (open-output-string)))
  (write 42 p)
  (check "write to string port" (get-output-string p) "42"))

(let ((p (open-output-string)))
  (write-string "abc" p)
  (check "write-string" (get-output-string p) "abc"))

(let ((p (open-output-string)))
  (newline p)
  (check "newline" (get-output-string p) "\n"))

;;; ---- read-string ----
(let ((p (open-input-string "hello world")))
  (check "read-string" (read-string 5 p) "hello"))

(let ((p (open-input-string "hi")))
  (check "read-string short" (read-string 10 p) "hi"))

(let ((p (open-input-string "")))
  (check-true "read-string empty" (eof-object? (read-string 5 p))))

;;; ---- Port predicates ----
(check-true "port? input" (port? (current-input-port)))
(check-true "port? output" (port? (current-output-port)))
(check-true "port? error" (port? (current-error-port)))
(check-false "port? number" (port? 42))
(check-false "port? string" (port? "hello"))

(check-true "input-port? current" (input-port? (current-input-port)))
(check-true "output-port? current" (output-port? (current-output-port)))
(check-true "output-port? error" (output-port? (current-error-port)))

(check-true "input-port-open? string" (input-port-open? (open-input-string "x")))
(check-true "output-port-open? string" (output-port-open? (open-output-string)))

;;; ---- Close port ----
(let ((p (open-input-string "hello")))
  (check-true "port open before close" (input-port-open? p))
  (close-port p)
  (check-false "port closed after close" (input-port-open? p)))

(let ((p (open-output-string)))
  (check-true "output open before close" (output-port-open? p))
  (close-port p)
  (check-false "output closed after close" (output-port-open? p)))

;;; ---- EOF object ----
(check-true "eof-object?" (eof-object? (eof-object)))
(check-false "eof-object? number" (eof-object? 42))
(check-false "eof-object? #f" (eof-object? #f))

;;; ---- File I/O ----
(define test-file "/tmp/kaappi-io-coverage-test.txt")

;; Write and read back
(let ((p (open-output-file test-file)))
  (display "line1\n" p)
  (display "line2\n" p)
  (display "line3\n" p)
  (close-port p))

(check-true "file-exists?" (file-exists? test-file))

(let ((p (open-input-file test-file)))
  (check-true "open-input-file returns input port" (input-port? p))
  (check "read-line from file" (read-line p) "line1")
  (check "read-line from file 2" (read-line p) "line2")
  (check "read-line from file 3" (read-line p) "line3")
  (close-port p))

;; Read datum from file
(let ((p (open-output-file test-file)))
  (display "(hello 42 #t)\n" p)
  (close-port p))

(let ((p (open-input-file test-file)))
  (check "read from file" (read p) '(hello 42 #t))
  (close-port p))

;; Write chars and read back
(let ((p (open-output-file test-file)))
  (write-char #\A p)
  (write-char #\B p)
  (write-char #\C p)
  (close-port p))

(let ((p (open-input-file test-file)))
  (check "read-char A" (read-char p) #\A)
  (check "read-char B" (read-char p) #\B)
  (check "read-char C" (read-char p) #\C)
  (check-true "read-char eof" (eof-object? (read-char p)))
  (close-port p))

;; Cleanup
(delete-file test-file)
(check-false "file deleted" (file-exists? test-file))

;;; ---- read from custom port ----
(let ((p (open-input-string "(+ 1 2)")))
  (check "read from input-string" (read p) '(+ 1 2)))

;;; ---- write to string port ----
(let ((p (open-output-string)))
  (display "hello" p)
  (check "display to port" (get-output-string p) "hello"))

;;; ---- Bytevector ports ----
(let ((bv (string->utf8 "hello")))
  (let ((p (open-input-bytevector bv)))
    (check-true "binary-port?" (binary-port? p))
    (check "read-u8" (read-u8 p) 104)
    (check "read-u8 2" (read-u8 p) 101)
    (check "peek-u8" (peek-u8 p) 108)
    (check "peek-u8 again" (peek-u8 p) 108)
    (check "read-u8 after peek" (read-u8 p) 108)))

(let ((p (open-output-bytevector)))
  (write-u8 65 p)
  (write-u8 66 p)
  (write-u8 67 p)
  (check "get-output-bytevector" (get-output-bytevector p) #u8(65 66 67)))

;;; ---- read-bytevector ----
(let ((p (open-input-bytevector #u8(1 2 3 4 5))))
  (check "read-bytevector" (read-bytevector 3 p) #u8(1 2 3))
  (check "read-bytevector rest" (read-bytevector 10 p) #u8(4 5)))

;;; ---- write-bytevector ----
(let ((p (open-output-bytevector)))
  (write-bytevector #u8(10 20 30) p)
  (check "write-bytevector" (get-output-bytevector p) #u8(10 20 30)))

;;; ---- char-ready? / u8-ready? ----
(let ((p (open-input-string "x")))
  (check-true "char-ready?" (char-ready? p)))
(let ((p (open-input-bytevector #u8(1))))
  (check-true "u8-ready?" (u8-ready? p)))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "IO coverage tests failed" fail))
