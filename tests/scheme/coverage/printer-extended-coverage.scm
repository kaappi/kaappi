(import (scheme base) (scheme write) (scheme read) (scheme complex) (scheme inexact)
        (srfi 18))

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

(define (write-to-string obj)
  (let ((p (open-output-string)))
    (write obj p)
    (get-output-string p)))
(define (display-to-string obj)
  (let ((p (open-output-string)))
    (display obj p)
    (get-output-string p)))

;;; ---- Complex number printing ----
(check-true "write 1+2i" (string? (write-to-string 1+2i)))
(check-true "write 0+1i" (string? (write-to-string 0+1i)))
(check-true "write 3+0i" (string? (write-to-string (make-rectangular 3.0 0.0))))
(check-true "write 0-1i" (string? (write-to-string 0-1i)))
(check-true "write +inf+inf.0i" (string? (write-to-string (make-rectangular +inf.0 +inf.0))))
(check-true "write +nan.0i" (string? (write-to-string (make-rectangular 0.0 +nan.0))))

;;; ---- display complex ----
(check-true "display 1+2i" (string? (display-to-string 1+2i)))
(check-true "display 3-4i" (string? (display-to-string 3-4i)))

;;; ---- Symbol edge cases ----
(check "write regular symbol" (write-to-string 'hello) "hello")
(check "write + symbol" (write-to-string '+) "+")
(check "write ... symbol" (write-to-string '...) "...")

;;; ---- Rational printing ----
(check "write 1/3" (write-to-string 1/3) "1/3")
(check "write -2/5" (write-to-string -2/5) "-2/5")
(check "display 3/4" (display-to-string 3/4) "3/4")

;;; ---- Bignum printing ----
(check-true "write bignum" (> (string-length (write-to-string (expt 2 100))) 10))
(check-true "write neg bignum" (char=? #\- (string-ref (write-to-string (- (expt 2 100))) 0)))

;;; ---- Float edge cases ----
(check "write 0.0" (write-to-string 0.0) "0.0")
(check "write -0.0" (write-to-string -0.0) "-0.0")
(check-true "write very small" (string? (write-to-string 1e-300)))
(check-true "write very large" (string? (write-to-string 1e300)))

;;; ---- Char special names ----
(check "write #\\space" (write-to-string #\space) "#\\space")
(check "write #\\newline" (write-to-string #\newline) "#\\newline")
(check "write #\\tab" (write-to-string #\tab) "#\\tab")
(check "write #\\return" (write-to-string #\return) "#\\return")
(check "write #\\null" (write-to-string #\null) "#\\null")
(check "write #\\alarm" (write-to-string #\alarm) "#\\alarm")
(check "write #\\backspace" (write-to-string #\backspace) "#\\backspace")
(check "write #\\delete" (write-to-string #\delete) "#\\delete")
(check "write #\\escape" (write-to-string #\escape) "#\\escape")
(check "display #\\A" (display-to-string #\A) "A")
(check "display #\\space" (display-to-string #\space) " ")
(check "display #\\newline" (display-to-string #\newline) "\n")

;;; ---- String escapes ----
(check "write string \\n" (write-to-string "a\nb") "\"a\\nb\"")
(check "write string \\t" (write-to-string "a\tb") "\"a\\tb\"")
(check "write string \\\\" (write-to-string "a\\b") "\"a\\\\b\"")
(check "write string \\\"" (write-to-string "a\"b") "\"a\\\"b\"")
(check "write string \\r" (write-to-string "a\rb") "\"a\\rb\"")

;;; ---- Deeply nested structures ----
(check "write deep" (write-to-string '((((1 2) (3 4))))) "((((1 2) (3 4))))")
(check "write deep vectors" (write-to-string #(#(#(1)))) "#(#(#(1)))")

;;; ---- write-shared with shared vector ----
(let ((v (vector 1 2 3)))
  (let ((x (list v v)))
    (let ((p (open-output-string)))
      (write-shared x p)
      (let ((result (get-output-string p)))
        (check-true "write-shared shared vec" (string-contains result "#0"))))))

;;; ---- write-shared with self-referencing ----
(let ((x (list 1 2)))
  (set-cdr! (cdr x) x)
  (let ((p (open-output-string)))
    (write-shared x p)
    (check-true "write-shared circular" (string-contains (get-output-string p) "#"))))

;;; ---- Error object printing ----
(let ((e (guard (e (#t e)) (error "test msg" 'irritant1 'irritant2))))
  (check-true "write error obj" (string? (write-to-string e)))
  (check-true "display error obj" (string? (display-to-string e))))

;;; ---- Record printing ----
(define-record-type <point>
  (make-point x y)
  point?
  (x point-x)
  (y point-y))
(check-true "write record" (string? (write-to-string (make-point 10 20))))
(check-true "display record" (string? (display-to-string (make-point 10 20))))

;;; ---- Procedure printing ----
(check-true "write lambda" (string? (write-to-string (lambda () 42))))
(check-true "write car" (string? (write-to-string car)))
(check-true "display procedure" (string? (display-to-string cons)))

;;; ---- Port printing ----
(check-true "write port" (string? (write-to-string (current-input-port))))
(check-true "display port" (string? (display-to-string (current-output-port))))

;;; ---- Promise printing ----
(check-true "write promise" (string? (write-to-string (delay 42))))

;;; ---- SRFI-18 type printing ----
(check-true "write mutex" (string? (write-to-string (make-mutex 'test-mutex))))
(check-true "write condvar" (string? (write-to-string (make-condition-variable 'test-cv))))
(check-true "write thread" (string? (write-to-string (current-thread))))
(check-true "write time" (string? (write-to-string (current-time))))

;;; ---- Void printing ----
(check "display void" (display-to-string (if #f #f)) "")

;;; ---- Empty structures ----
(check "write empty list" (write-to-string '()) "()")
(check "write empty vector" (write-to-string #()) "#()")
(check "write empty bytevector" (write-to-string #u8()) "#u8()")
(check "write empty string" (write-to-string "") "\"\"")

;;; ---- Long list (tests buffer handling) ----
(let ((long-list (make-list 100 'x)))
  (check-true "write long list" (> (string-length (write-to-string long-list)) 100)))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Printer extended coverage tests failed" fail))
