(import (scheme base) (scheme write) (scheme char) (srfi 13))

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

;;; string-take / string-drop
(check "string-take" (string-take "hello world" 5) "hello")
(check "string-take 0" (string-take "hello" 0) "")
(check "string-take all" (string-take "hi" 2) "hi")
(check "string-drop" (string-drop "hello world" 6) "world")
(check "string-drop 0" (string-drop "hello" 0) "hello")

;;; string-take-right / string-drop-right
(check "string-take-right" (string-take-right "hello world" 5) "world")
(check "string-take-right 0" (string-take-right "hello" 0) "")
(check "string-drop-right" (string-drop-right "hello world" 6) "hello")
(check "string-drop-right 0" (string-drop-right "hello" 0) "hello")

;;; string-pad / string-pad-right
(check "string-pad" (string-pad "42" 5) "   42")
(check "string-pad char" (string-pad "42" 5 #\0) "00042")
(check "string-pad long" (string-pad "hello" 3) "llo")
(check "string-pad exact" (string-pad "hi" 2) "hi")
(check "string-pad-right" (string-pad-right "hi" 5) "hi   ")
(check "string-pad-right char" (string-pad-right "42" 5 #\.) "42...")
(check "string-pad-right long" (string-pad-right "hello" 3) "hel")

;;; string-reverse
(check "string-reverse" (string-reverse "hello") "olleh")
(check "string-reverse empty" (string-reverse "") "")
(check "string-reverse 1" (string-reverse "x") "x")

;;; string-filter / string-delete
(check "string-filter" (string-filter char-alphabetic? "h3ll0 w0rld") "hllwrld")
(check "string-filter all" (string-filter char-alphabetic? "hello") "hello")
(check "string-filter none" (string-filter char-alphabetic? "123") "")
(check "string-delete" (string-delete char-numeric? "h3ll0 w0rld") "hll wrld")
(check "string-delete all" (string-delete char-alphabetic? "abc") "")

;;; string-replace
(check "string-replace" (string-replace "hello world" "there" 5 10) "hellothered")
(check "string-replace begin" (string-replace "abcdef" "XY" 0 2) "XYcdef")
(check "string-replace end" (string-replace "abcdef" "XY" 4 6) "abcdXY")

;;; string-titlecase
(check "string-titlecase" (string-titlecase "hello WORLD foo") "Hello World Foo")
(check "string-titlecase single" (string-titlecase "hello") "Hello")
(check "string-titlecase empty" (string-titlecase "") "")

;;; string-every / string-any
(check-true "string-every alpha" (string-every char-alphabetic? "hello"))
(check-false "string-every mixed" (string-every char-alphabetic? "hello1"))
(check-true "string-every empty" (string-every char-alphabetic? ""))
(check-true "string-any digit" (string-any char-numeric? "abc3def"))
(check-false "string-any miss" (string-any char-numeric? "abcdef"))

;;; string-tabulate
(check "string-tabulate" (string-tabulate (lambda (i) (integer->char (+ i 65))) 5) "ABCDE")
(check "string-tabulate 0" (string-tabulate values 0) "")

;;; Re-exported standard ops
(check "string-contains" (string-contains "hello world" "world") 6)
(check-false "string-contains miss" (string-contains "hello" "xyz"))
(check-true "string-prefix?" (string-prefix? "hel" "hello"))
(check-false "string-prefix? no" (string-prefix? "xyz" "hello"))
(check-true "string-suffix?" (string-suffix? "llo" "hello"))
(check "string-trim" (string-trim "  hello  ") "hello  ")
(check "string-trim-right" (string-trim-right "  hello  ") "  hello")
(check "string-trim-both" (string-trim-both "  hello  ") "hello")
(check "string-index" (string-index "hello" char-upper-case?) #f)
(check "string-count" (string-count "hello world" char-alphabetic?) 10)
(check "string-split" (string-split "a,b,c" ",") '("a" "b" "c"))
(check "string-join" (string-join '("a" "b" "c") ", ") "a, b, c")
(check "string-concatenate" (string-concatenate '("a" "b" "c")) "abc")

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 13 extended tests failed" fail))
