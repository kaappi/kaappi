;; Regression test for #51: quasiquote + unquote-splicing must process nested unquotes

(import (scheme base) (scheme write))

(define (test name expected actual)
  (if (equal? expected actual)
    (begin (display "PASS: ") (display name) (newline))
    (begin (display "FAIL: ") (display name)
           (display " expected=") (write expected)
           (display " actual=") (write actual) (newline))))

(define c 99)
(define d (list 7 8))

(test "nested unquote with splice"
  '(a (b 99) 7 8)
  `(a (b ,c) ,@d))

(test "deeply nested unquote with splice"
  '(x (y (z 99)) 7 8)
  `(x (y (z ,c)) ,@d))

(test "multiple nested unquotes with splice"
  '((1 99) (2 99) 7 8)
  `((1 ,c) (2 ,c) ,@d))

(test "no splice still works"
  '(a (b 99))
  `(a (b ,c)))

(test "splice only"
  '(7 8)
  `(,@d))
