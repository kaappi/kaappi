(test-begin "6.12 Environments and evaluation")

;; (test 21 (eval '(* 7 3) (scheme-report-environment 5)))

(test 20
    (let ((f (eval '(lambda (f x) (f x x)) (null-environment 5))))
      (f + 10)))

(test 1024 (eval '(expt 2 10) (environment '(scheme base))))
;; (sin 0) may return exact number
(test 0.0 (inexact (eval '(sin 0) (environment '(scheme inexact)))))
;; ditto
(test 1024.0 (eval '(+ (expt 2 10) (inexact (sin 0)))
                   (environment '(scheme base) '(scheme inexact))))

(test-end)

(test-begin "6.13 Input and output")

(test #t (port? (current-input-port)))
(test #t (input-port? (current-input-port)))
(test #t (output-port? (current-output-port)))
(test #t (output-port? (current-error-port)))
(test #t (input-port? (open-input-string "abc")))
(test #t (output-port? (open-output-string)))

(test #t (textual-port? (open-input-string "abc")))
(test #t (textual-port? (open-output-string)))
(test #t (binary-port? (open-input-bytevector #u8(0 1 2))))
(test #t (binary-port? (open-output-bytevector)))

(test #t (input-port-open? (open-input-string "abc")))
(test #t (output-port-open? (open-output-string)))

(test #f
    (let ((in (open-input-string "abc")))
      (close-input-port in)
      (input-port-open? in)))

(test #f
    (let ((out (open-output-string)))
      (close-output-port out)
      (output-port-open? out)))

(test #f
    (let ((out (open-output-string)))
      (close-port out)
      (output-port-open? out)))

(test 'error
    (let ((in (open-input-string "abc")))
      (close-input-port in)
      (guard (exn (else 'error)) (read-char in))))

(test 'error
    (let ((out (open-output-string)))
      (close-output-port out)
      (guard (exn (else 'error)) (write-char #\c out))))

(test #t (eof-object? (eof-object)))
(test #t (eof-object? (read (open-input-string ""))))
(test #t (char-ready? (open-input-string "42")))
(test 42 (read (open-input-string " 42 ")))

(test #t (eof-object? (read-char (open-input-string ""))))
(test #\a (read-char (open-input-string "abc")))

(test #t (eof-object? (read-line (open-input-string ""))))
(test "abc" (read-line (open-input-string "abc")))
(test "abc" (read-line (open-input-string "abc\ndef\n")))

(test #t (eof-object? (read-string 3 (open-input-string ""))))
(test "abc" (read-string 3 (open-input-string "abcd")))
(test "abc" (read-string 3 (open-input-string "abc\ndef\n")))

(let ((in (open-input-string (string #\x10F700 #\x10F701 #\x10F702))))
  (let* ((c0 (peek-char in))
         (c1 (read-char in))
         (c2 (read-char in))
         (c3 (read-char in)))
    (test #\x10F700 c0)
    (test #\x10F700 c1)
    (test #\x10F701 c2)
    (test #\x10F702 c3)))

(test (string #\x10F700)
    (let ((out (open-output-string)))
      (write-char #\x10F700 out)
      (get-output-string out)))

(test "abc"
    (let ((out (open-output-string)))
      (write 'abc out)
      (get-output-string out)))

(test "abc def"
    (let ((out (open-output-string)))
      (display "abc def" out)
      (get-output-string out)))

(test "abc"
    (let ((out (open-output-string)))
      (display #\a out)
      (display "b" out)
      (display #\c out)
      (get-output-string out)))

(test #t
      (let* ((out (open-output-string))
             (r (begin (newline out) (get-output-string out))))
        (or (equal? r "\n") (equal? r "\r\n"))))

(test "abc def"
    (let ((out (open-output-string)))
      (write-string "abc def" out)
      (get-output-string out)))

(test "def"
    (let ((out (open-output-string)))
      (write-string "abc def" out 4)
      (get-output-string out)))

(test "c d"
    (let ((out (open-output-string)))
      (write-string "abc def" out 2 5)
      (get-output-string out)))

(test ""
  (let ((out (open-output-string)))
    (flush-output-port out)
    (get-output-string out)))

(test #t (eof-object? (read-u8 (open-input-bytevector #u8()))))
(test 1 (read-u8 (open-input-bytevector #u8(1 2 3))))

(test #t (eof-object? (read-bytevector 3 (open-input-bytevector #u8()))))
(test #t (u8-ready? (open-input-bytevector #u8(1))))
(test #u8(1) (read-bytevector 3 (open-input-bytevector #u8(1))))
(test #u8(1 2) (read-bytevector 3 (open-input-bytevector #u8(1 2))))
(test #u8(1 2 3) (read-bytevector 3 (open-input-bytevector #u8(1 2 3))))
(test #u8(1 2 3) (read-bytevector 3 (open-input-bytevector #u8(1 2 3 4))))

(test #t
    (let ((bv (bytevector 1 2 3 4 5)))
      (eof-object? (read-bytevector! bv (open-input-bytevector #u8())))))

(test #u8(6 7 8 9 10)
  (let ((bv (bytevector 1 2 3 4 5)))
    (read-bytevector! bv (open-input-bytevector #u8(6 7 8 9 10)) 0 5)
    bv))

(test #u8(6 7 8 4 5)
  (let ((bv (bytevector 1 2 3 4 5)))
    (read-bytevector! bv (open-input-bytevector #u8(6 7 8 9 10)) 0 3)
    bv))

(test #u8(1 2 3 6 5)
  (let ((bv (bytevector 1 2 3 4 5)))
    (read-bytevector! bv (open-input-bytevector #u8(6 7 8 9 10)) 3 4)
    bv))

(test #u8(1 2 3)
  (let ((out (open-output-bytevector)))
    (write-u8 1 out)
    (write-u8 2 out)
    (write-u8 3 out)
    (get-output-bytevector out)))

(test #u8(1 2 3 4 5)
  (let ((out (open-output-bytevector)))
    (write-bytevector #u8(1 2 3 4 5) out)
    (get-output-bytevector out)))

(test #u8(3 4 5)
  (let ((out (open-output-bytevector)))
    (write-bytevector #u8(1 2 3 4 5) out 2)
    (get-output-bytevector out)))

(test #u8(3 4)
  (let ((out (open-output-bytevector)))
    (write-bytevector #u8(1 2 3 4 5) out 2 4)
    (get-output-bytevector out)))

(test #u8()
  (let ((out (open-output-bytevector)))
    (flush-output-port out)
    (get-output-bytevector out)))

(test #t
    (and (member
          (let ((out (open-output-string))
                (x (list 1)))
            (set-cdr! x x)
            (write x out)
            (get-output-string out))
          ;; labels not guaranteed to be 0 indexed, spacing may differ
          '("#0=(1 . #0#)" "#1=(1 . #1#)"))
         #t))

(test "((1 2 3) (1 2 3))"
    (let ((out (open-output-string))
          (x (list 1 2 3)))
      (write (list x x) out)
      (get-output-string out)))

(test "((1 2 3) (1 2 3))"
    (let ((out (open-output-string))
          (x (list 1 2 3)))
      (write-simple (list x x) out)
      (get-output-string out)))

(test #t
    (and (member (let ((out (open-output-string))
                       (x (list 1 2 3)))
                   (write-shared (list x x) out)
                   (get-output-string out))
                 '("(#0=(1 2 3) #0#)" "(#1=(1 2 3) #1#)"))
         #t))

(test-begin "Read syntax")

;; check reading boolean followed by eof
(test #t (read (open-input-string "#t")))
(test #t (read (open-input-string "#true")))
(test #f (read (open-input-string "#f")))
(test #f (read (open-input-string "#false")))
(define (read2 port)
  (let* ((o1 (read port)) (o2 (read port)))
    (cons o1 o2)))
;; check reading boolean followed by delimiter
(test '(#t . (5)) (read2 (open-input-string "#t(5)")))
(test '(#t . 6) (read2 (open-input-string "#true 6 ")))
(test '(#f . 7) (read2 (open-input-string "#f 7")))
(test '(#f . "8") (read2 (open-input-string "#false\"8\"")))

(test '() (read (open-input-string "()")))
(test '(1 2) (read (open-input-string "(1 2)")))
(test '(1 . 2) (read (open-input-string "(1 . 2)")))
(test '(1 2) (read (open-input-string "(1 . (2))")))
(test '(1 2 3 4 5) (read (open-input-string "(1 . (2 3 4 . (5)))")))
(test '1 (cadr (read (open-input-string "#0=(1 . #0#)"))))
(test '(1 2 3) (cadr (read (open-input-string "(#0=(1 2 3) #0#)"))))

(test '(quote (1 2)) (read (open-input-string "'(1 2)")))
(test '(quote (1 (unquote 2))) (read (open-input-string "'(1 ,2)")))
(test '(quote (1 (unquote-splicing 2))) (read (open-input-string "'(1 ,@2)")))
(test '(quasiquote (1 (unquote 2))) (read (open-input-string "`(1 ,2)")))

(test #() (read (open-input-string "#()")))
(test #(a b) (read (open-input-string "#(a b)")))

(test #u8() (read (open-input-string "#u8()")))
(test #u8(0 1) (read (open-input-string "#u8(0 1)")))

(test 'abc (read (open-input-string "abc")))
(test 'abc (read (open-input-string "abc def")))
(test 'ABC (read (open-input-string "ABC")))
(test 'Hello (read (open-input-string "|H\\x65;llo|")))

(test 'abc (read (open-input-string "#!fold-case ABC")))
(test 'ABC (read (open-input-string "#!fold-case #!no-fold-case ABC")))

(test 'def (read (open-input-string "#; abc def")))
(test 'def (read (open-input-string "; abc \ndef")))
(test 'def (read (open-input-string "#| abc |# def")))
(test 'ghi (read (open-input-string "#| abc #| def |# |# ghi")))
(test 'ghi (read (open-input-string "#; ; abc\n def ghi")))
(test '(abs -16) (read (open-input-string "(#;sqrt abs -16)")))
(test '(a d) (read (open-input-string "(a #; #;b c d)")))
(test '(a e) (read (open-input-string "(a #;(b #;c d) e)")))
(test '(a . c) (read (open-input-string "(a . #;b c)")))
(test '(a . b) (read (open-input-string "(a . b #;c)")))

(define (test-read-error str)
  (test-assert str
      (guard (exn (else #t))
        (read (open-input-string str))
        #f)))

(test-read-error "(#;a . b)")
(test-read-error "(a . #;b)")
(test-read-error "(a #;. b)")
(test-read-error "(#;x #;y . z)")
(test-read-error "(#; #;x #;y . z)")
(test-read-error "(#; #;x . z)")

(test #\a (read (open-input-string "#\\a")))
(test #\space (read (open-input-string "#\\space")))
(test 0 (char->integer (read (open-input-string "#\\null"))))
(test 7 (char->integer (read (open-input-string "#\\alarm"))))
(test 8 (char->integer (read (open-input-string "#\\backspace"))))
(test 9 (char->integer (read (open-input-string "#\\tab"))))
(test 10 (char->integer (read (open-input-string "#\\newline"))))
(test 13 (char->integer (read (open-input-string "#\\return"))))
(test #x7F (char->integer (read (open-input-string "#\\delete"))))
(test #x1B (char->integer (read (open-input-string "#\\escape"))))
(test #x03BB (char->integer (read (open-input-string "#\\λ"))))
(test #x03BB (char->integer (read (open-input-string "#\\x03BB"))))

(test "abc" (read (open-input-string "\"abc\"")))
(test "abc" (read (open-input-string "\"abc\" \"def\"")))
(test "ABC" (read (open-input-string "\"ABC\"")))
(test "Hello" (read (open-input-string "\"H\\x65;llo\"")))
(test 7 (char->integer (string-ref (read (open-input-string "\"\\a\"")) 0)))
(test 8 (char->integer (string-ref (read (open-input-string "\"\\b\"")) 0)))
(test 9 (char->integer (string-ref (read (open-input-string "\"\\t\"")) 0)))
(test 10 (char->integer (string-ref (read (open-input-string "\"\\n\"")) 0)))
(test 13 (char->integer (string-ref (read (open-input-string "\"\\r\"")) 0)))
(test #x22 (char->integer (string-ref (read (open-input-string "\"\\\"\"")) 0)))
(test #x7C (char->integer (string-ref (read (open-input-string "\"\\|\"")) 0)))
(test "line 1\nline 2\n" (read (open-input-string "\"line 1\nline 2\n\"")))
(test "line 1continued\n" (read (open-input-string "\"line 1\\\ncontinued\n\"")))
(test "line 1continued\n" (read (open-input-string "\"line 1\\ \ncontinued\n\"")))
(test "line 1continued\n" (read (open-input-string "\"line 1\\\n continued\n\"")))
(test "line 1continued\n" (read (open-input-string "\"line 1\\ \t \n \t continued\n\"")))
(test "line 1\n\nline 3\n" (read (open-input-string "\"line 1\\ \t \n \t \n\nline 3\n\"")))
(test #x03BB (char->integer (string-ref (read (open-input-string "\"\\x03BB;\"")) 0)))

(define-syntax test-write-syntax
  (syntax-rules ()
    ((test-write-syntax expect-str obj-expr)
     (let ((out (open-output-string)))
       (write obj-expr out)
       (test expect-str (get-output-string out))))))

(test-write-syntax "|.|" '|.|)
(test-write-syntax "|a b|" '|a b|)
(test-write-syntax "|,a|" '|,a|)
(test-write-syntax "|\"|" '|\"|)
(test-write-syntax "|\\||" '|\||)
(test-write-syntax "||" '||)
(test-write-syntax "|\\\\123|" '|\\123|)
(test-write-syntax "a" '|a|)
;; (test-write-syntax "a.b" '|a.b|)
(test-write-syntax "|2|" '|2|)
(test-write-syntax "|+3|" '|+3|)
(test-write-syntax "|-.4|" '|-.4|)
(test-write-syntax "|+i|" '|+i|)
(test-write-syntax "|-i|" '|-i|)
(test-write-syntax "|+inf.0|" '|+inf.0|)
(test-write-syntax "|-inf.0|" '|-inf.0|)
(test-write-syntax "|+nan.0|" '|+nan.0|)
(test-write-syntax "|+NaN.0|" '|+NaN.0|)
(test-write-syntax "|+NaN.0abc|" '|+NaN.0abc|)

(test-end)

(test-begin "Numeric syntax")

;; Numeric syntax adapted from Peter Bex's tests.
;;
;; These are updated to R7RS, using string ports instead of
;; string->number, and "error" tests removed because implementations
;; are free to provide their own numeric extensions.  Currently all
;; tests are run by default - need to cond-expand and test for
;; infinities and -0.0.

(define-syntax test-numeric-syntax
  (syntax-rules ()
    ((test-numeric-syntax str expect strs ...)
     (let* ((z (read (open-input-string str)))
            (out (open-output-string))
            (z-str (begin (write z out) (get-output-string out))))
       (test expect (values z))
       (test #t (and (member z-str '(str strs ...)) #t))))))

;; Each test is of the form:
;;
;;   (test-numeric-syntax input-str expected-value expected-write-values ...)
;;
;; where the input should be eqv? to the expected-value, and the
;; written output the same as any of the expected-write-values.  The
;; form
;;
;;   (test-numeric-syntax input-str expected-value)
;;
;; is a shorthand for
;;
;;   (test-numeric-syntax input-str expected-value (input-str))

;; Simple
(test-numeric-syntax "1" 1)
(test-numeric-syntax "+1" 1 "1")
(test-numeric-syntax "-1" -1)
(test-numeric-syntax "#i1" 1.0 "1.0" "1.")
(test-numeric-syntax "#I1" 1.0 "1.0" "1.")
(test-numeric-syntax "#i-1" -1.0 "-1.0" "-1.")
;; Decimal
(test-numeric-syntax "1.0" 1.0 "1.0" "1.")
(test-numeric-syntax "1." 1.0 "1.0" "1.")
(test-numeric-syntax ".1" 0.1 "0.1" "100.0e-3")
(test-numeric-syntax "-.1" -0.1 "-0.1" "-100.0e-3")
;; Some Schemes don't allow negative zero. This is okay with the standard
(test-numeric-syntax "-.0" -0.0 "-0." "-0.0" "0.0" "0." ".0")
(test-numeric-syntax "-0." -0.0 "-.0" "-0.0" "0.0" "0." ".0")
(test-numeric-syntax "#i1.0" 1.0 "1.0" "1.")
(test-numeric-syntax "#e1.0" 1 "1")
(test-numeric-syntax "#e-.0" 0 "0")
(test-numeric-syntax "#e-0." 0 "0")
;; Decimal notation with suffix
(test-numeric-syntax "1e2" 100.0 "100.0" "100.")
(test-numeric-syntax "1E2" 100.0 "100.0" "100.")
(test-numeric-syntax "1s2" 100.0 "100.0" "100.")
(test-numeric-syntax "1S2" 100.0 "100.0" "100.")
(test-numeric-syntax "1f2" 100.0 "100.0" "100.")
(test-numeric-syntax "1F2" 100.0 "100.0" "100.")
(test-numeric-syntax "1d2" 100.0 "100.0" "100.")
(test-numeric-syntax "1D2" 100.0 "100.0" "100.")
(test-numeric-syntax "1l2" 100.0 "100.0" "100.")
(test-numeric-syntax "1L2" 100.0 "100.0" "100.")
;; NaN, Inf
(test-numeric-syntax "+nan.0" +nan.0 "+nan.0" "+NaN.0")
(test-numeric-syntax "+NAN.0" +nan.0 "+nan.0" "+NaN.0")
(test-numeric-syntax "+inf.0" +inf.0 "+inf.0" "+Inf.0")
(test-numeric-syntax "+InF.0" +inf.0 "+inf.0" "+Inf.0")
(test-numeric-syntax "-inf.0" -inf.0 "-inf.0" "-Inf.0")
(test-numeric-syntax "-iNF.0" -inf.0 "-inf.0" "-Inf.0")
(test-numeric-syntax "#i+nan.0" +nan.0 "+nan.0" "+NaN.0")
(test-numeric-syntax "#i+inf.0" +inf.0 "+inf.0" "+Inf.0")
(test-numeric-syntax "#i-inf.0" -inf.0 "-inf.0" "-Inf.0")
;; Exact ratios
(test-numeric-syntax "1/2" (/ 1 2))
(test-numeric-syntax "#e1/2" (/ 1 2) "1/2")
(test-numeric-syntax "10/2" 5 "5")
(test-numeric-syntax "-1/2" (- (/ 1 2)))
(test-numeric-syntax "0/10" 0 "0")
(test-numeric-syntax "#e0/10" 0 "0")
(test-numeric-syntax "#i3/2" (/ 3.0 2.0) "1.5")
;; Exact complex
(test-numeric-syntax "1+2i" (make-rectangular 1 2))
(test-numeric-syntax "1+2I" (make-rectangular 1 2) "1+2i")
(test-numeric-syntax "1-2i" (make-rectangular 1 -2))
(test-numeric-syntax "-1+2i" (make-rectangular -1 2))
(test-numeric-syntax "-1-2i" (make-rectangular -1 -2))
(test-numeric-syntax "+i" (make-rectangular 0 1) "+i" "+1i" "0+i" "0+1i")
(test-numeric-syntax "0+i" (make-rectangular 0 1) "+i" "+1i" "0+i" "0+1i")
(test-numeric-syntax "0+1i" (make-rectangular 0 1) "+i" "+1i" "0+i" "0+1i")
(test-numeric-syntax "-i" (make-rectangular 0 -1) "-i" "-1i" "0-i" "0-1i")
(test-numeric-syntax "0-i" (make-rectangular 0 -1) "-i" "-1i" "0-i" "0-1i")
(test-numeric-syntax "0-1i" (make-rectangular 0 -1) "-i" "-1i" "0-i" "0-1i")
(test-numeric-syntax "+2i" (make-rectangular 0 2) "2i" "+2i" "0+2i")
(test-numeric-syntax "-2i" (make-rectangular 0 -2) "-2i" "0-2i")
;; Decimal-notation complex numbers (rectangular notation)
(test-numeric-syntax "1.0+2i" (make-rectangular 1.0 2) "1.0+2.0i" "1.0+2i" "1.+2i" "1.+2.i")
(test-numeric-syntax "1+2.0i" (make-rectangular 1 2.0) "1.0+2.0i" "1+2.0i" "1.+2.i" "1+2.i")
(test-numeric-syntax "1e2+1.0i" (make-rectangular 100.0 1.0) "100.0+1.0i" "100.+1.i")
(test-numeric-syntax "1s2+1.0i" (make-rectangular 100.0 1.0) "100.0+1.0i" "100.+1.i")
(test-numeric-syntax "1.0+1e2i" (make-rectangular 1.0 100.0) "1.0+100.0i" "1.+100.i")
(test-numeric-syntax "1.0+1s2i" (make-rectangular 1.0 100.0) "1.0+100.0i" "1.+100.i")
;; Fractional complex numbers (rectangular notation)
(test-numeric-syntax "1/2+3/4i" (make-rectangular (/ 1 2) (/ 3 4)))
;; Mixed fractional/decimal notation complex numbers (rectangular notation)
(test-numeric-syntax "0.5+3/4i" (make-rectangular 0.5 (/ 3 4))
  "0.5+0.75i" ".5+.75i" "0.5+3/4i" ".5+3/4i" "500.0e-3+750.0e-3i")
;; Complex NaN, Inf (rectangular notation)
;;(test-numeric-syntax "+nan.0+nan.0i" (make-rectangular the-nan the-nan) "+NaN.0+NaN.0i") 
(test-numeric-syntax "+inf.0+inf.0i" (make-rectangular +inf.0 +inf.0) "+Inf.0+Inf.0i")
(test-numeric-syntax "-inf.0+inf.0i" (make-rectangular -inf.0 +inf.0) "-Inf.0+Inf.0i")
(test-numeric-syntax "-inf.0-inf.0i" (make-rectangular -inf.0 -inf.0) "-Inf.0-Inf.0i")
(test-numeric-syntax "+inf.0-inf.0i" (make-rectangular +inf.0 -inf.0) "+Inf.0-Inf.0i")
;; Complex numbers (polar notation)
;; Need to account for imprecision in write output.
;;(test-numeric-syntax "1@2" -0.416146836547142+0.909297426825682i "-0.416146836547142+0.909297426825682i")
;; Base prefixes
(test-numeric-syntax "#x11" 17 "17")
(test-numeric-syntax "#X11" 17 "17")
(test-numeric-syntax "#d11" 11 "11")
(test-numeric-syntax "#D11" 11 "11")
(test-numeric-syntax "#o11" 9 "9")
(test-numeric-syntax "#O11" 9 "9")
(test-numeric-syntax "#b11" 3 "3")
(test-numeric-syntax "#B11" 3 "3")
(test-numeric-syntax "#o7" 7 "7")
(test-numeric-syntax "#xa" 10 "10")
(test-numeric-syntax "#xA" 10 "10")
(test-numeric-syntax "#xf" 15 "15")
(test-numeric-syntax "#x-10" -16 "-16")
(test-numeric-syntax "#d-10" -10 "-10")
(test-numeric-syntax "#o-10" -8 "-8")
(test-numeric-syntax "#b-10" -2 "-2")
;; Combination of prefixes
(test-numeric-syntax "#e#x10" 16 "16")
(test-numeric-syntax "#i#x10" 16.0 "16.0" "16.")
(test-numeric-syntax "#x#i10" 16.0 "16.0" "16.")
(test-numeric-syntax "#i#x1/10" 0.0625 "0.0625")
(test-numeric-syntax "#x#i1/10" 0.0625 "0.0625")
;; (Attempted) decimal notation with base prefixes
(test-numeric-syntax "#d1." 1.0 "1.0" "1.")
(test-numeric-syntax "#d.1" 0.1 "0.1" ".1" "100.0e-3")
(test-numeric-syntax "#x1e2" 482 "482")
(test-numeric-syntax "#d1e2" 100.0 "100.0" "100.")
;; Fractions with prefixes
(test-numeric-syntax "#x10/2" 8 "8")
(test-numeric-syntax "#x11/2" (/ 17 2) "17/2")
(test-numeric-syntax "#d11/2" (/ 11 2) "11/2")
(test-numeric-syntax "#o11/2" (/ 9 2) "9/2")
(test-numeric-syntax "#b11/10" (/ 3 2) "3/2")
;; Complex numbers with prefixes
;;(test-numeric-syntax "#x10+11i" (make-rectangular 16 17) "16+17i")
(test-numeric-syntax "#d1.0+1.0i" (make-rectangular 1.0 1.0) "1.0+1.0i" "1.+1.i")
(test-numeric-syntax "#d10+11i" (make-rectangular 10 11) "10+11i")
;;(test-numeric-syntax "#o10+11i" (make-rectangular 8 9) "8+9i")
;;(test-numeric-syntax "#b10+11i" (make-rectangular 2 3) "2+3i")
;;(test-numeric-syntax "#e1.0+1.0i" (make-rectangular 1 1) "1+1i" "1+i")
;;(test-numeric-syntax "#i1.0+1.0i" (make-rectangular 1.0 1.0) "1.0+1.0i" "1.+1.i")

(define-syntax test-precision
  (syntax-rules ()
    ((test-round-trip str alt ...)
     (let* ((n (string->number str))
            (str2 (number->string n))
            (accepted (list str alt ...))
            (ls (member str2 accepted)))
       (test-assert (string-append "(member? " str2 " "
                                   (let ((out (open-output-string)))
                                     (write accepted out)
                                     (get-output-string out))
                                   ")")
         (pair? ls))
       (when (pair? ls)
         (test-assert (string-append "(eqv?: " str " " str2 ")")
           (eqv? n (string->number (car ls)))))))))

(test-precision "-1.7976931348623157e+308" "-inf.0")
(test-precision "4.940656458412465e-324" "4.94065645841247e-324" "5.0e-324" "0.0")
(test-precision "9.881312916824931e-324" "9.88131291682493e-324" "1.0e-323" "0.0")
(test-precision "1.48219693752374e-323" "1.5e-323" "0.0")
(test-precision "1.976262583364986e-323" "1.97626258336499e-323" "2.0e-323" "0.0")
(test-precision "2.470328229206233e-323" "2.47032822920623e-323" "2.5e-323" "0.0")
(test-precision "2.420921664622108e-322" "2.42092166462211e-322" "2.4e-322" "0.0")
(test-precision "2.420921664622108e-320" "2.42092166462211e-320" "2.421e-320" "0.0")
(test-precision "1.4489974452386991" "1.4489975")
(test-precision "0.14285714285714282" "0.14285714285714288" "0.14285715")
(test-precision "1.7976931348623157e+308" "+inf.0")

(test-end)

(test-end)

(test-begin "6.14 System interface")

;; 6.14 System interface

;; (test "/usr/local/bin:/usr/bin:/bin" (get-environment-variable "PATH"))

(test #t (string? (get-environment-variable "PATH")))

;; (test '(("USER" . "root") ("HOME" . "/")) (get-environment-variables))

(let ((env (get-environment-variables)))
  (define (env-pair? x)
    (and (pair? x) (string? (car x)) (string? (cdr x))))
  (define (all? pred ls)
    (or (null? ls) (and (pred (car ls)) (all? pred (cdr ls)))))
  (test #t (list? env))
  (test #t (all? env-pair? env)))

(test #t (list? (command-line)))

(test #t (real? (current-second)))
(test #t (inexact? (current-second)))
(test #t (exact? (current-jiffy)))
(test #t (exact? (jiffies-per-second)))

(test #t (list? (features)))
(test #t (and (memq 'r7rs (features)) #t))

(test #t (file-exists? "."))
(test #f (file-exists? " no such file "))

(test #t (file-error?
          (guard (exn (else exn))
            (delete-file " no such file "))))

(test-end)
