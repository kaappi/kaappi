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

;;; ---- write-string with start/end ----
(let ((p (open-output-string)))
  (write-string "hello world" p 2 7)
  (check "write-string range" (get-output-string p) "llo w"))

(let ((p (open-output-string)))
  (write-string "abcdef" p 0 3)
  (check "write-string from start" (get-output-string p) "abc"))

;;; ---- read-string ----
(let ((p (open-input-string "hello world")))
  (check "read-string 5" (read-string 5 p) "hello")
  (check "read-string rest" (read-string 100 p) " world"))

;;; ---- call-with-port ----
(check "call-with-port input" (call-with-port (open-input-string "42") read) 42)

(let ((result (call-with-port (open-output-string)
                (lambda (p) (display "hi" p) (get-output-string p)))))
  (check "call-with-port output" result "hi"))

;;; ---- with-input-from-file / with-output-to-file ----
(define test-file "/tmp/kaappi-io-ext-test.txt")

(with-output-to-file test-file (lambda () (display "hello from file")))
(check "with-output-to-file" (with-input-from-file test-file read-line) "hello from file")

;;; ---- call-with-input-file / call-with-output-file ----
(define test-file2 "/tmp/kaappi-io-ext-test2.txt")
(call-with-output-file test-file2 (lambda (p) (display "abc" p)))
(check "call-with-output-file"
  (call-with-input-file test-file2 (lambda (p) (read-line p)))
  "abc")

;;; ---- read-line with \r\n ----
(let ((p (open-input-string "line1\r\nline2\r\n")))
  (check "read-line crlf 1" (read-line p) "line1")
  (check "read-line crlf 2" (read-line p) "line2"))

;;; ---- read multiple datums ----
(let ((p (open-input-string "1 2 3")))
  (check "read multi 1" (read p) 1)
  (check "read multi 2" (read p) 2)
  (check "read multi 3" (read p) 3)
  (check-true "read multi eof" (eof-object? (read p))))

;;; ---- read various datum types ----
(let ((p (open-input-string "#t #f '() #\\a \"hello\" #(1 2) #u8(3 4)")))
  (check "read #t" (read p) #t)
  (check "read #f" (read p) #f)
  (check "read quote nil" (read p) ''())
  (check "read char" (read p) #\a)
  (check "read string" (read p) "hello")
  (check "read vector" (read p) #(1 2))
  (check "read bytevector" (read p) #u8(3 4)))

;;; ---- flush-output-port ----
(flush-output-port (current-output-port))
(check-true "flush-output-port" #t)

;;; ---- Binary I/O extended ----
(let ((p (open-output-bytevector)))
  (write-bytevector #u8(1 2 3 4 5) p 1 4)
  (check "write-bytevector range" (get-output-bytevector p) #u8(2 3 4)))

(let ((p (open-input-bytevector #u8(10 20 30 40 50))))
  (check "read-bytevector 3" (read-bytevector 3 p) #u8(10 20 30))
  (check "read-bytevector rest" (read-bytevector 10 p) #u8(40 50))
  (check-true "read-bytevector eof" (eof-object? (read-bytevector 1 p))))

;;; ---- write various types to output port ----
(let ((p (open-output-string)))
  (write '(1 "hello" #t #\a) p)
  (check "write complex datum" (get-output-string p) "(1 \"hello\" #t #\\a)"))

;;; ---- display various types ----
(let ((p (open-output-string)))
  (display '(1 "hello" #t #\a) p)
  (check "display complex datum" (get-output-string p) "(1 hello #t a)"))

;;; ---- newline to port ----
(let ((p (open-output-string)))
  (newline p)
  (check "newline to port" (get-output-string p) "\n"))

;;; ---- Multiple writes to same port ----
(let ((p (open-output-string)))
  (display "a" p)
  (display "b" p)
  (display "c" p)
  (check "multiple writes" (get-output-string p) "abc"))

;;; ---- close then check ----
(let ((p (open-input-string "x")))
  (close-input-port p)
  (check-false "closed input" (input-port-open? p)))

(let ((p (open-output-string)))
  (close-output-port p)
  (check-false "closed output" (output-port-open? p)))

;;; Cleanup
(delete-file test-file)
(delete-file test-file2)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "IO extended coverage tests failed" fail))
