;; Regression test for #442:
;; (zero? #t) and (zero? #f) must raise type errors, not fold to #f.

(import (scheme base) (scheme write))

;; zero? on #t should be a type error
(define caught-1 #f)
(guard (exn (#t (set! caught-1 #t)))
  (zero? #t))
(if caught-1
    (display "PASS: (zero? #t) raises type error")
    (display "FAIL: (zero? #t) did not raise error"))
(newline)

;; zero? on #f should be a type error
(define caught-2 #f)
(guard (exn (#t (set! caught-2 #t)))
  (zero? #f))
(if caught-2
    (display "PASS: (zero? #f) raises type error")
    (display "FAIL: (zero? #f) did not raise error"))
(newline)

;; zero? on a string should be a type error
(define caught-3 #f)
(guard (exn (#t (set! caught-3 #t)))
  (zero? "hello"))
(if caught-3
    (display "PASS: (zero? \"hello\") raises type error")
    (display "FAIL: (zero? \"hello\") did not raise error"))
(newline)

;; zero? on 0 should return #t (sanity check)
(if (zero? 0)
    (display "PASS: (zero? 0) is #t")
    (display "FAIL: (zero? 0) should be #t"))
(newline)

;; zero? on 1 should return #f (sanity check)
(if (not (zero? 1))
    (display "PASS: (zero? 1) is #f")
    (display "FAIL: (zero? 1) should be #f"))
(newline)
