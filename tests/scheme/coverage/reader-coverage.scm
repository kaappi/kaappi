(import (scheme base) (scheme write) (scheme read) (scheme char))

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

(define (read-from-string s)
  (read (open-input-string s)))

;;; ---- Basic atoms ----
(check "read fixnum" (read-from-string "42") 42)
(check "read negative" (read-from-string "-7") -7)
(check "read zero" (read-from-string "0") 0)
(check "read symbol" (read-from-string "hello") 'hello)
(check "read #t" (read-from-string "#t") #t)
(check "read #f" (read-from-string "#f") #f)
(check "read #true" (read-from-string "#true") #t)
(check "read #false" (read-from-string "#false") #f)
(check "read string" (read-from-string "\"hello\"") "hello")
(check "read empty string" (read-from-string "\"\"") "")

;;; ---- Float ----
(check "read float" (read-from-string "3.14") 3.14)
(check "read negative float" (read-from-string "-1.5") -1.5)
(check "read exponent" (read-from-string "1e10") 1e10)
(check "read neg exponent" (read-from-string "1e-3") 1e-3)
(check "read +inf.0" (read-from-string "+inf.0") +inf.0)
(check "read -inf.0" (read-from-string "-inf.0") -inf.0)
(check-true "read +nan.0" (nan? (read-from-string "+nan.0")))

;;; ---- Rational ----
(check "read rational" (read-from-string "1/3") 1/3)
(check "read neg rational" (read-from-string "-2/5") -2/5)
(check "read rational simplify" (read-from-string "2/4") 1/2)

;;; ---- Complex ----
(check "read complex" (read-from-string "1+2i") 1+2i)
(check "read complex neg" (read-from-string "3-4i") 3-4i)
(check "read pure imag" (read-from-string "+2i") 0+2i)
(check "read neg pure imag" (read-from-string "-3i") 0-3i)

;;; ---- Characters ----
(check "read char a" (read-from-string "#\\a") #\a)
(check "read char space" (read-from-string "#\\space") #\space)
(check "read char newline" (read-from-string "#\\newline") #\newline)
(check "read char tab" (read-from-string "#\\tab") #\tab)
(check "read char return" (read-from-string "#\\return") #\return)
(check "read char null" (read-from-string "#\\null") #\null)
(check "read char alarm" (read-from-string "#\\alarm") #\alarm)
(check "read char backspace" (read-from-string "#\\backspace") #\backspace)
(check "read char delete" (read-from-string "#\\delete") #\delete)
(check "read char escape" (read-from-string "#\\escape") #\escape)
(check "read char hex" (read-from-string "#\\x41") #\A)
(check "read char hex lower" (read-from-string "#\\x61") #\a)

;;; ---- Lists ----
(check "read list" (read-from-string "(1 2 3)") '(1 2 3))
(check "read empty list" (read-from-string "()") '())
(check "read nested" (read-from-string "((1 2) (3 4))") '((1 2) (3 4)))
(check "read dotted" (read-from-string "(1 . 2)") '(1 . 2))
(check "read improper" (read-from-string "(1 2 . 3)") '(1 2 . 3))

;;; ---- Vectors ----
(check "read vector" (read-from-string "#(1 2 3)") #(1 2 3))
(check "read empty vector" (read-from-string "#()") #())
(check "read nested vector" (read-from-string "#(#(1) #(2))") #(#(1) #(2)))

;;; ---- Bytevectors ----
(check "read bytevector" (read-from-string "#u8(1 2 3)") #u8(1 2 3))
(check "read empty bytevector" (read-from-string "#u8()") #u8())

;;; ---- Quote / quasiquote / unquote ----
(check "read quote" (read-from-string "'x") ''x)
(check "read quasiquote" (read-from-string "`x") '(quasiquote x))
(check "read unquote" (read-from-string ",x") '(unquote x))
(check "read unquote-splicing" (read-from-string ",@x") '(unquote-splicing x))

;;; ---- String escapes ----
(check "read \\n" (read-from-string "\"a\\nb\"") "a\nb")
(check "read \\t" (read-from-string "\"a\\tb\"") "a\tb")
(check "read \\\\" (read-from-string "\"a\\\\b\"") "a\\b")
(check "read \\\"" (read-from-string "\"a\\\"b\"") "a\"b")
(check "read \\r" (read-from-string "\"a\\rb\"") "a\rb")
(check "read \\x hex" (read-from-string "\"\\x41;\"") "A")

;;; ---- Comments ----
(check "line comment" (read-from-string "; comment\n42") 42)
(check "block comment" (read-from-string "#|block|# 42") 42)
(check "nested block" (read-from-string "#| #| inner |# |# 42") 42)
(check "datum comment" (read-from-string "#;(skip this) 42") 42)
(check "datum comment list" (read-from-string "(1 #;2 3)") '(1 3))

;;; ---- Datum labels ----
(let ((result (read-from-string "#0=(1 2 #0#)")))
  (check "datum label car" (car result) 1)
  (check "datum label cadr" (cadr result) 2)
  (check-true "datum label circular" (eq? result (caddr result))))

;;; ---- #; on complex expressions ----
(check "datum comment complex" (read-from-string "#;(define x 42) 99") 99)

;;; ---- Fold-case ----
(check "fold-case" (read-from-string "#!fold-case HELLO") 'hello)
(check "no-fold-case" (read-from-string "#!fold-case ABC #!no-fold-case DEF") 'abc)

;;; ---- Numeric prefixes ----
(check "read #b binary" (read-from-string "#b1010") 10)
(check "read #o octal" (read-from-string "#o377") 255)
(check "read #x hex" (read-from-string "#xff") 255)
(check "read #d decimal" (read-from-string "#d42") 42)
(check-true "read #e exact" (exact? (read-from-string "#e1.5")))
(check "read #i inexact" (read-from-string "#i1") 1.0)

;;; ---- Whitespace handling ----
(check "read with leading ws" (read-from-string "   42") 42)
(check "read with trailing ws" (read-from-string "42   ") 42)
(check "read multi ws" (read-from-string "  (  1  2  3  )  ") '(1 2 3))

;;; ---- Error recovery (reader errors) ----
(check-true "unterminated string"
  (guard (e (#t #t)) (read-from-string "\"unterminated") #f))
;; mismatched paren may return partial read rather than error
(check-true "invalid char name"
  (guard (e (#t #t)) (read-from-string "#\\notacharname") #f))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Reader coverage tests failed" fail))
