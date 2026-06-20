(import (scheme base) (scheme write) (scheme char) (scheme read))

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

;;; Helper: capture write output as string
(define (write-to-string obj)
  (let ((p (open-output-string)))
    (write obj p)
    (get-output-string p)))

(define (display-to-string obj)
  (let ((p (open-output-string)))
    (display obj p)
    (get-output-string p)))

;;; ---- Fixnum printing ----
(check "write 0" (write-to-string 0) "0")
(check "write 42" (write-to-string 42) "42")
(check "write -1" (write-to-string -1) "-1")
(check "write large" (write-to-string 123456789) "123456789")

;;; ---- Boolean printing ----
(check "write #t" (write-to-string #t) "#t")
(check "write #f" (write-to-string #f) "#f")

;;; ---- Character printing ----
(check "write char a" (write-to-string #\a) "#\\a")
(check "write char space" (write-to-string #\space) "#\\space")
(check "write char newline" (write-to-string #\newline) "#\\newline")
(check "write char tab" (write-to-string #\tab) "#\\tab")
(check "write char nul" (write-to-string #\null) "#\\null")
(check "write char alarm" (write-to-string #\alarm) "#\\alarm")
(check "write char backspace" (write-to-string #\backspace) "#\\backspace")
(check "write char delete" (write-to-string #\delete) "#\\delete")
(check "write char escape" (write-to-string #\escape) "#\\escape")
(check "write char return" (write-to-string #\return) "#\\return")
(check "display char a" (display-to-string #\a) "a")
(check "display char space" (display-to-string #\space) " ")

;;; ---- String printing ----
(check "write string" (write-to-string "hello") "\"hello\"")
(check "write empty string" (write-to-string "") "\"\"")
(check "write string with escape" (write-to-string "a\"b") "\"a\\\"b\"")
(check "write string with newline" (write-to-string "a\nb") "\"a\\nb\"")
(check "write string with tab" (write-to-string "a\tb") "\"a\\tb\"")
(check "write string with backslash" (write-to-string "a\\b") "\"a\\\\b\"")
(check "display string" (display-to-string "hello") "hello")
(check "display string with newline" (display-to-string "a\nb") "a\nb")

;;; ---- Symbol printing ----
(check "write symbol" (write-to-string 'hello) "hello")
(check "write symbol with special" (write-to-string '+) "+")

;;; ---- Pair/list printing ----
(check "write list" (write-to-string '(1 2 3)) "(1 2 3)")
(check "write dotted pair" (write-to-string '(1 . 2)) "(1 . 2)")
(check "write nested" (write-to-string '(1 (2 3) 4)) "(1 (2 3) 4)")
(check "write empty list" (write-to-string '()) "()")
(check "write improper list" (write-to-string '(1 2 . 3)) "(1 2 . 3)")
(check "write deeply nested" (write-to-string '((((1))))) "((((1))))")

;;; ---- Vector printing ----
(check "write vector" (write-to-string #(1 2 3)) "#(1 2 3)")
(check "write empty vector" (write-to-string #()) "#()")
(check "write nested vector" (write-to-string #(1 #(2 3) 4)) "#(1 #(2 3) 4)")

;;; ---- Bytevector printing ----
(check "write bytevector" (write-to-string #u8(1 2 3)) "#u8(1 2 3)")
(check "write empty bytevector" (write-to-string #u8()) "#u8()")

;;; ---- Float printing ----
(check "write 1.0" (write-to-string 1.0) "1.0")
(check "write -0.5" (write-to-string -0.5) "-0.5")
(check "write +inf" (write-to-string +inf.0) "+inf.0")
(check "write -inf" (write-to-string -inf.0) "-inf.0")
(check "write +nan" (write-to-string +nan.0) "+nan.0")

;;; ---- Void, eof ----
(check "display void" (display-to-string (if #f #f)) "")
(check "write eof" (write-to-string (eof-object)) "#<eof>")

;;; ---- Procedure printing ----
(check-true "write lambda" (string? (write-to-string (lambda (x) x))))
(check-true "write builtin" (string? (write-to-string car)))

;;; ---- Multiple values via write-shared ----
(let ((p (open-output-string)))
  (write-shared '(1 2 3) p)
  (check "write-shared simple" (get-output-string p) "(1 2 3)"))

;;; ---- Circular structure ----
(let ((x (list 1 2 3)))
  (set-cdr! (cddr x) x)
  (let ((p (open-output-string)))
    (write-shared x p)
    (let ((result (get-output-string p)))
      (check-true "write-shared circular has #" (string-contains result "#")))))

;;; ---- write-shared with shared substructure ----
(let ((sub (list 'a 'b)))
  (let ((x (list sub sub)))
    (let ((p (open-output-string)))
      (write-shared x p)
      (let ((result (get-output-string p)))
        (check-true "write-shared shared has #0" (string-contains result "#0"))))))

;;; ---- Display for different types ----
(check "display number" (display-to-string 42) "42")
(check "display symbol" (display-to-string 'hello) "hello")
(check "display list" (display-to-string '(1 2 3)) "(1 2 3)")
(check "display #t" (display-to-string #t) "#t")
(check "display #f" (display-to-string #f) "#f")
(check "display vector" (display-to-string #(1 2 3)) "#(1 2 3)")

;;; ---- Quasiquoted structures ----
(check "write quoted" (write-to-string '(quote x)) "(quote x)")

;;; ---- Complex numbers ----
(check-true "write complex" (string? (write-to-string (make-rectangular 1 2))))

;;; ---- Rational ----
(check "write 1/3" (write-to-string 1/3) "1/3")
(check "write -2/5" (write-to-string -2/5) "-2/5")
(check "write 3/1" (write-to-string 3/1) "3")

;;; ---- Bignum ----
(check-true "write bignum" (string? (write-to-string (* 999999999999999999 999999999999999999))))

;;; ---- Records ----
(define-record-type <point>
  (make-point x y)
  point?
  (x point-x)
  (y point-y))
(check-true "write record" (string? (write-to-string (make-point 1 2))))

;;; ---- Error objects ----
(check-true "write error object"
  (string? (write-to-string (guard (e (#t e)) (error "test" 1 2)))))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Printer coverage tests failed" fail))
