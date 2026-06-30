;; Regression test for string->number R7RS radix and exactness prefixes
;; Issue #369
(import (scheme base) (scheme write))

(define failures 0)
(define (test name expected actual)
  (if (equal? expected actual)
      #t
      (begin (set! failures (+ failures 1))
             (display "FAIL: ") (display name)
             (display " expected ") (display expected)
             (display " got ") (display actual) (newline))))

;; Radix prefixes
(test "#xff" 255 (string->number "#xff"))
(test "#b1010" 10 (string->number "#b1010"))
(test "#o17" 15 (string->number "#o17"))
(test "#d42" 42 (string->number "#d42"))
(test "#XFF" 255 (string->number "#XFF"))
(test "#xeff" 3839 (string->number "#xeff"))

;; Exactness prefixes
(test "#i42" 42.0 (string->number "#i42"))
(test "#e1.5 rational" #t (rational? (string->number "#e1.5")))
(test "#e1.5" 3/2 (string->number "#e1.5"))
(test "#e2.0" 2 (string->number "#e2.0"))

;; Both in either order
(test "#e#xff" 255 (string->number "#e#xff"))
(test "#i#b1010" 10.0 (string->number "#i#b1010"))
(test "#b#i1010" 10.0 (string->number "#b#i1010"))

;; Prefix overrides parameter
(test "#x10 base 10" 16 (string->number "#x10" 10))

;; Rational with non-decimal radix
(test "a/b base 16" 10/11 (string->number "a/b" 16))

;; Regression for #604: #e with large floats must not abort
(test "#e1e20" 100000000000000000000 (string->number "#e1e20"))
(test "#e9.5e18" 9500000000000000000 (string->number "#e9.5e18"))
(test "#e1e19" 10000000000000000000 (string->number "#e1e19"))
(test "#e1e20 = exact" #t (= (string->number "#e1e20") (exact 1e20)))

;; Existing functionality preserved
(test "42" 42 (string->number "42"))
(test "3.14" 3.14 (string->number "3.14"))
(test "ff base 16" 255 (string->number "ff" 16))
(test "+inf.0" +inf.0 (string->number "+inf.0"))
(test "#b (empty)" #f (string->number "#b"))
(test "#z42 (invalid)" #f (string->number "#z42"))

(if (= failures 0)
    (display "all passed")
    (begin (display failures) (display " failures")))
(newline)
