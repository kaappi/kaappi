(import (scheme base) (scheme write) (srfi 1))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define (check-true name val)
  (if val
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name) (newline))))

(define (check-false name val)
  (if (not val)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name) (newline))))

(check "fold" (fold + 0 '(1 2 3 4 5)) 15)
(check "filter even?" (filter even? '(1 2 3 4 5)) '(2 4))
(check "find even?" (find even? '(1 3 5 8 9)) 8)
(check-false "any even? none" (any even? '(1 3 5)))
(check "iota" (iota 5) '(0 1 2 3 4))
(check "take" (take '(a b c d) 2) '(a b))
(check "drop" (drop '(a b c d) 2) '(c d))
(check "lset-intersection" (lset-intersection eq? '(a b c d) '(b c e)) '(b c))
(check "lset-difference" (lset-difference eq? '(a b c d) '(b c e)) '(a d))
(check-true "lset= reorder" (lset= eq? '(a b c) '(c b a)))
(check-false "lset= different size" (lset= eq? '(a b) '(a b c)))
(check "lset-intersection 3 lists"
       (lset-intersection eq? '(a b c) '(b c d) '(c d e))
       '(c))
(check "lset-difference chained"
       (lset-difference eq? '(a b c d) '(b) '(d))
       '(a c))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 1 smoke tests failed" fail))
