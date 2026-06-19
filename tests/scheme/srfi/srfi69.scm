(import (scheme base) (scheme write) (srfi 69))

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

(define ht (make-hash-table))
(hash-table-set! ht 'name "kaappi")
(hash-table-set! ht 'version 1)

(check "hash-table-ref name" (hash-table-ref ht 'name) "kaappi")
(check "hash-table-size" (hash-table-size ht) 2)
(check-true "hash-table-exists? name" (hash-table-exists? ht 'name))
(check-false "hash-table-exists? missing" (hash-table-exists? ht 'missing))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 69 smoke tests failed" fail))
