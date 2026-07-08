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

;;; ---- string-contains ----
(check "string-contains found" (string-contains "hello world" "world") 6)
(check "string-contains start" (string-contains "hello world" "hello") 0)
(check-false "string-contains miss" (string-contains "hello" "xyz"))
(check "string-contains empty needle" (string-contains "hello" "") 0)
(check "string-contains single char" (string-contains "abcdef" "d") 3)

;;; ---- string-prefix? / string-suffix? ----
(check-true "string-prefix?" (string-prefix? "hel" "hello"))
(check-false "string-prefix? no" (string-prefix? "xyz" "hello"))
(check-true "string-prefix? empty" (string-prefix? "" "hello"))
(check-true "string-prefix? equal" (string-prefix? "hello" "hello"))
(check-false "string-prefix? longer" (string-prefix? "hello world" "hello"))

(check-true "string-suffix?" (string-suffix? "llo" "hello"))
(check-false "string-suffix? no" (string-suffix? "xyz" "hello"))
(check-true "string-suffix? empty" (string-suffix? "" "hello"))
(check-true "string-suffix? equal" (string-suffix? "hello" "hello"))

;;; ---- string-trim ----
(check "string-trim leading" (string-trim "  hello  ") "hello  ")
(check "string-trim no leading" (string-trim "hello  ") "hello  ")
(check "string-trim all spaces" (string-trim "     ") "")
(check "string-trim empty" (string-trim "") "")
(check "string-trim tabs" (string-trim "\t\thello") "hello")

(check "string-trim-right trailing" (string-trim-right "  hello  ") "  hello")
(check "string-trim-right no trailing" (string-trim-right "  hello") "  hello")
(check "string-trim-right all" (string-trim-right "     ") "")
(check "string-trim-right empty" (string-trim-right "") "")
(check "string-trim-right tabs" (string-trim-right "hello\t\t") "hello")

(check "string-trim-both" (string-trim-both "  hello  ") "hello")
(check "string-trim-both no ws" (string-trim-both "hello") "hello")
(check "string-trim-both all ws" (string-trim-both "    ") "")
(check "string-trim-both empty" (string-trim-both "") "")
(check "string-trim-both mixed ws" (string-trim-both "\t hello \t") "hello")

;;; ---- string-index ----
(check "string-index found" (string-index "hello" (lambda (c) (char=? c #\l))) 2)
(check-false "string-index miss" (string-index "hello" char-upper-case?))
(check "string-index first" (string-index "Hello" char-upper-case?) 0)

;;; ---- string-count ----
(check "string-count" (string-count "hello world" char-alphabetic?) 10)
(check "string-count none" (string-count "hello" char-numeric?) 0)
(check "string-count all" (string-count "hello" char-alphabetic?) 5)
(check "string-count empty" (string-count "" char-alphabetic?) 0)

;;; ---- string-split ----
(check "string-split comma" (string-split "a,b,c" ",") '("a" "b" "c"))
(check "string-split space" (string-split "hello world" " ") '("hello" "world"))
(check "string-split no match" (string-split "hello" ",") '("hello"))
(check "string-split empty" (string-split "" ",") '(""))
(check "string-split multi-char" (string-split "a::b::c" "::") '("a" "b" "c"))
(check "string-split leading" (string-split ",a,b" ",") '("" "a" "b"))
(check "string-split trailing" (string-split "a,b," ",") '("a" "b" ""))

;;; ---- string-join ----
(check "string-join" (string-join '("a" "b" "c") ", ") "a, b, c")
(check "string-join single" (string-join '("hello") " ") "hello")
(check "string-join empty list" (string-join '() " ") "")
(check "string-join empty sep" (string-join '("a" "b" "c") "") "abc")
(check "string-join no sep" (string-join '("a" "b" "c")) "a b c")

;;; ---- string-concatenate ----
(check "string-concatenate" (string-concatenate '("a" "b" "c")) "abc")
(check "string-concatenate empty" (string-concatenate '()) "")
(check "string-concatenate single" (string-concatenate '("hello")) "hello")

;;; ---- string-take / string-drop ----
(check "string-take" (string-take "hello world" 5) "hello")
(check "string-take 0" (string-take "hello" 0) "")
(check "string-take all" (string-take "hi" 2) "hi")
(check "string-drop" (string-drop "hello world" 6) "world")
(check "string-drop 0" (string-drop "hello" 0) "hello")
(check "string-drop all" (string-drop "hello" 5) "")

;;; ---- string-take-right / string-drop-right ----
(check "string-take-right" (string-take-right "hello world" 5) "world")
(check "string-take-right 0" (string-take-right "hello" 0) "")
(check "string-drop-right" (string-drop-right "hello world" 6) "hello")
(check "string-drop-right 0" (string-drop-right "hello" 0) "hello")

;;; ---- string-pad / string-pad-right ----
(check "string-pad" (string-pad "42" 5) "   42")
(check "string-pad char" (string-pad "42" 5 #\0) "00042")
(check "string-pad long" (string-pad "hello" 3) "llo")
(check "string-pad exact" (string-pad "hi" 2) "hi")
(check "string-pad-right" (string-pad-right "hi" 5) "hi   ")
(check "string-pad-right char" (string-pad-right "42" 5 #\.) "42...")
(check "string-pad-right long" (string-pad-right "hello" 3) "hel")

;;; ---- string-reverse ----
(check "string-reverse" (string-reverse "hello") "olleh")
(check "string-reverse empty" (string-reverse "") "")
(check "string-reverse 1" (string-reverse "x") "x")
(check "string-reverse palindrome" (string-reverse "abba") "abba")

;;; ---- string-filter / string-delete ----
(check "string-filter alpha" (string-filter char-alphabetic? "h3ll0 w0rld") "hllwrld")
(check "string-filter all" (string-filter char-alphabetic? "hello") "hello")
(check "string-filter none" (string-filter char-alphabetic? "123") "")
(check "string-filter empty" (string-filter char-alphabetic? "") "")
(check "string-delete numeric" (string-delete char-numeric? "h3ll0 w0rld") "hll wrld")
(check "string-delete all" (string-delete char-alphabetic? "abc") "")
(check "string-delete none" (string-delete char-numeric? "hello") "hello")

;;; ---- string-replace ----
(check "string-replace mid" (string-replace "hello world" "there" 5 10) "hellothered")
(check "string-replace begin" (string-replace "abcdef" "XY" 0 2) "XYcdef")
(check "string-replace end" (string-replace "abcdef" "XY" 4 6) "abcdXY")
(check "string-replace empty" (string-replace "abcdef" "" 2 4) "abef")
(check "string-replace insert" (string-replace "abcdef" "XY" 3 3) "abcXYdef")

;;; ---- string-titlecase ----
(check "string-titlecase" (string-titlecase "hello WORLD foo") "Hello World Foo")
(check "string-titlecase single" (string-titlecase "hello") "Hello")
(check "string-titlecase empty" (string-titlecase "") "")
(check "string-titlecase already" (string-titlecase "Hello") "Hello")

;;; ---- string-every / string-any ----
(check-true "string-every alpha" (string-every char-alphabetic? "hello"))
(check-false "string-every mixed" (string-every char-alphabetic? "hello1"))
(check-true "string-every empty" (string-every char-alphabetic? ""))
(check-true "string-any digit" (string-any char-numeric? "abc3def"))
(check-false "string-any miss" (string-any char-numeric? "abcdef"))
(check-false "string-any empty" (string-any char-numeric? ""))

;;; ---- string-tabulate ----
(check "string-tabulate" (string-tabulate (lambda (i) (integer->char (+ i 65))) 5) "ABCDE")
(check "string-tabulate 0" (string-tabulate values 0) "")
(check "string-tabulate 1" (string-tabulate (lambda (i) #\x) 1) "x")

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "String extension coverage tests failed" fail))
