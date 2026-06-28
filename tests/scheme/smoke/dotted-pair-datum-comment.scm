(import (scheme base) (scheme write))

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

;; Dotted pair with datum comment after the cdr value.
;; The reader must root the cdr value before processing the datum comment,
;; which can trigger GC.

;; Allocate to create GC pressure
(let loop ((i 0))
  (when (< i 2000)
    (make-list 10 i)
    (loop (+ i 1))))

(check "dotted pair with datum comment"
  '(a . b #; discarded)
  '(a . b))

(check "dotted pair with complex datum comment"
  '(x . y #; (a long list that allocates))
  '(x . y))

(check "dotted pair with nested datum comments"
  '(1 . 2 #; #; nested also-nested)
  '(1 . 2))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "dotted-pair datum comment tests failed" fail))
