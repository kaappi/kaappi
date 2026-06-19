(import (scheme base) (scheme write) (srfi 133))

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

;;; vector-empty?
(check-true "empty?" (vector-empty? (vector)))
(check-false "empty? non" (vector-empty? (vector 1)))

;;; vector-count
(check "count even" (vector-count even? (vector 1 2 3 4 5)) 2)
(check "count none" (vector-count (lambda (x) (> x 10)) (vector 1 2 3)) 0)
(check "count all" (vector-count positive? (vector 1 2 3)) 3)

;;; vector-any / vector-every
(check-true "any even" (vector-any even? (vector 1 3 4 5)))
(check-false "any miss" (vector-any even? (vector 1 3 5)))
(check-true "every pos" (vector-every positive? (vector 1 2 3)))
(check-false "every fail" (vector-every even? (vector 2 3 4)))

;;; vector-index / vector-index-right
(check "index" (vector-index even? (vector 1 3 4 5)) 2)
(check-false "index miss" (vector-index even? (vector 1 3 5)))
(check "index-right" (vector-index-right even? (vector 2 3 4)) 2)

;;; vector-skip / vector-skip-right
(check "skip" (vector-skip even? (vector 2 4 5 6)) 2)
(check-false "skip all match" (vector-skip even? (vector 2 4 6)))
(check "skip-right" (vector-skip-right even? (vector 1 2 3)) 2)

;;; vector-swap!
(let ((v (vector 1 2 3)))
  (vector-swap! v 0 2)
  (check "swap" v (vector 3 2 1)))

;;; vector-reverse!
(let ((v (vector 1 2 3 4 5)))
  (vector-reverse! v)
  (check "reverse!" v (vector 5 4 3 2 1)))

(let ((v (vector 1 2 3 4 5)))
  (vector-reverse! v 1 4)
  (check "reverse! range" v (vector 1 4 3 2 5)))

;;; vector-reverse-copy
(check "reverse-copy" (vector-reverse-copy (vector 1 2 3)) (vector 3 2 1))
(check "reverse-copy range" (vector-reverse-copy (vector 1 2 3 4 5) 1 4) (vector 4 3 2))

;;; vector-unfold
(check "unfold" (vector-unfold (lambda (i) (values (* i i))) 5) (vector 0 1 4 9 16))
(check "unfold seed" (vector-unfold (lambda (i seed) (values seed (* seed 2))) 4 1)
       (vector 1 2 4 8))

;;; vector-concatenate
(check "concatenate" (vector-concatenate (list (vector 1 2) (vector 3 4) (vector 5)))
       (vector 1 2 3 4 5))
(check "concatenate empty" (vector-concatenate '()) (vector))

;;; vector-cumulate
(check "cumulate" (vector-cumulate + 0 (vector 1 2 3 4 5)) (vector 1 3 6 10 15))
(check "cumulate *" (vector-cumulate * 1 (vector 1 2 3 4)) (vector 1 2 6 24))

;;; vector-partition
(let-values (((yes count) (vector-partition even? (vector 1 2 3 4 5))))
  (check "partition count" count 2)
  (check "partition vec" (vector-length yes) 2))

;;; Standard ops (re-exported)
(check "vector" (vector 1 2 3) #(1 2 3))
(check "make-vector" (make-vector 3 0) #(0 0 0))
(check-true "vector?" (vector? (vector)))
(check "vector-length" (vector-length (vector 1 2 3)) 3)
(check "vector-ref" (vector-ref (vector 10 20 30) 1) 20)
(check "vector->list" (vector->list (vector 1 2 3)) '(1 2 3))
(check "list->vector" (list->vector '(1 2 3)) #(1 2 3))
(check "vector-copy" (vector-copy (vector 1 2 3)) #(1 2 3))
(check "vector-append" (vector-append (vector 1 2) (vector 3 4)) #(1 2 3 4))

;;; vector-for-each / vector-map
(let ((sum 0))
  (vector-for-each (lambda (x) (set! sum (+ sum x))) (vector 1 2 3))
  (check "for-each sum" sum 6))
(check "map" (vector-map (lambda (x) (* x 2)) (vector 1 2 3)) #(2 4 6))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 133 extended tests failed" fail))
