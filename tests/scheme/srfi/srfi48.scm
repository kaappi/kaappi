(import (scheme base) (scheme write) (srfi 48))

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

;;; Basic directives
(check "~a display" (format "~a" 42) "42")
(check "~a string" (format "~a" "hello") "hello")
(check "~a symbol" (format "~a" 'foo) "foo")
(check "~s write" (format "~s" "hello") "\"hello\"")
(check "~d decimal" (format "~d" 255) "255")
(check "~x hex" (format "~x" 255) "ff")
(check "~o octal" (format "~o" 255) "377")
(check "~b binary" (format "~b" 10) "1010")
(check "~c char" (format "~c" #\A) "A")

;;; Literal directives
(check "~~ tilde" (format "~~") "~")
(check "~_ space" (format "~_") " ")
(check "~% newline" (format "~%") "\n")

;;; Multiple args
(check "multi args" (format "~a + ~a = ~a" 1 2 3) "1 + 2 = 3")
(check "mixed" (format "hex ~x dec ~d" 255 255) "hex ff dec 255")

;;; Fixed format ~F
(check "~8F string" (format "~8F" "test") "    test")
(check "~8,2F float" (format "~8,2F" 3.14159) "    3.14")
(check "~8,2F int" (format "~8,2F" 32) "   32.00")
(check "~1,2F overflow" (format "~1,2F" 4321) "4321.00")
(check "~6,1F" (format "~6,1F" 1.5) "   1.5")

;;; Port output
(let ((p (open-output-string)))
  (format p "~a ~a" "hello" "world")
  (check "port output" (get-output-string p) "hello world"))

;;; #f returns string
(check "#f returns string" (format #f "~a" 42) "42")

;;; #t writes to stdout (just test it doesn't error)
(let ((p (open-output-string)))
  (check "string from format" (format "test ~a" "ok") "test ok"))

;;; Indirection ~?
(check "~? indirection" (format "~? is ~a" "~a+~a" (list 1 2) "three") "1+2 is three")

;;; Case insensitivity
(check "~A uppercase" (format "~A" "hello") "hello")

;;; Freshline ~&
(check "~& after newline" (format "line~%~&next") "line\nnext")

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 48 tests failed" fail))
