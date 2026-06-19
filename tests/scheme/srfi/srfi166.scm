(import (scheme base) (scheme write) (srfi 166))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; show with #f returns string
(check "show #f" (show #f "hello") "hello")
(check "show num" (show #f 42) "42")
(check "show multi" (show #f "a" "b" "c") "abc")

;; displayed / written
(check "displayed" (show #f (displayed "hello")) "hello")
(check "written" (show #f (written "hello")) "\"hello\"")
(check "written sym" (show #f (written 'foo)) "foo")

;; each
(check "each" (show #f (each "hello" " " "world")) "hello world")
(check "each-in-list" (show #f (each-in-list '("a" "b" "c"))) "abc")

;; nl, fl, nothing
(check "nl" (show #f "a" nl "b") "a\nb")
(check "nothing" (show #f "a" nothing "b") "ab")

;; joined
(check "joined" (show #f (joined displayed '(1 2 3) ", ")) "1, 2, 3")
(check "joined empty" (show #f (joined displayed '() ", ")) "")
(check "joined/prefix" (show #f (joined/prefix displayed '(1 2 3) "> ")) "> 1> 2> 3")
(check "joined/suffix" (show #f (joined/suffix displayed '(1 2) "; ")) "1; 2; ")

;; padded
(check "padded" (show #f (padded 10 "hello")) "     hello")
(check "padded/right" (show #f (padded/right 10 "hello")) "hello     ")
(check "padded/both" (show #f (padded/both 10 "hi")) "    hi    ")
(check "padded short" (show #f (padded 3 "hello")) "hello")

;; trimmed
(check "trimmed/right" (show #f (trimmed/right 3 "hello")) "hel")
(check "trimmed" (show #f (trimmed 3 "hello")) "llo")
(check "trimmed short" (show #f (trimmed/right 10 "hi")) "hi")

;; fitted
(check "fitted" (show #f (fitted 5 "hi")) "   hi")
(check "fitted long" (show #f (fitted 3 "hello")) "llo")

;; numeric
(check "numeric" (show #f (numeric 42)) "42")
(check "numeric hex" (show #f (numeric 255 16)) "ff")
(check "numeric prec" (show #f (numeric 3.14159 10 2)) "3.14")

;; numeric/si
(check "numeric/si" (show #f (numeric/si 1500)) "1.5k")
(check "numeric/si M" (show #f (numeric/si 2500000)) "2.5M")

;; space-to
(check "space-to" (show #f "ab" (space-to 5) "x") "ab   x")

;; tab-to
(check "tab-to" (show #f "ab" (tab-to 8) "x") "ab      x")

;; with pad-char
(check "with pad-char" (show #f (with (list (list pad-char #\.)) (padded 10 "hi"))) "........hi")

;; call-with-output
(check "call-with-output"
  (show #f (call-with-output "hello" (lambda (s) (string-append "[" s "]"))))
  "[hello]")

;; escaped
(check "escaped" (show #f (escaped "he\"llo")) "\"he\\\"llo\"")

;; show to #t (stdout) — just verify no error
(show #t "")

;; joined/range
(check "joined/range" (show #f (joined/range displayed 0 5 ",")) "0,1,2,3,4")

;; joined/last
(check "joined/last"
  (show #f (joined/last displayed (lambda (x) (each "and " (displayed x))) '(1 2 3) ", "))
  "1, 2, and 3")

;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 166 tests failed" fail))
