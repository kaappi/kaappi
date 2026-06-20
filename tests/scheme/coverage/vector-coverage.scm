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

;;; ---- Basic constructors ----
(check "vector" (vector 1 2 3) #(1 2 3))
(check "vector empty" (vector) #())
(check "make-vector" (make-vector 3 0) #(0 0 0))
(check "make-vector 1" (make-vector 1 'x) #(x))

;;; ---- Predicates ----
(check-true "vector?" (vector? #(1 2 3)))
(check-true "vector? empty" (vector? #()))
(check-false "vector? list" (vector? '(1 2 3)))
(check-false "vector? number" (vector? 42))
(check-true "vector-empty? empty" (vector-empty? #()))
(check-false "vector-empty? non" (vector-empty? #(1)))

;;; ---- Accessors ----
(check "vector-length" (vector-length #(a b c)) 3)
(check "vector-length empty" (vector-length #()) 0)
(check "vector-ref" (vector-ref #(a b c) 1) 'b)
(check "vector-ref 0" (vector-ref #(10 20 30) 0) 10)
(check "vector-ref last" (vector-ref #(10 20 30) 2) 30)

;;; ---- Mutation ----
(let ((v (vector 1 2 3)))
  (vector-set! v 1 99)
  (check "vector-set!" v #(1 99 3)))

(let ((v (vector 1 2 3 4 5)))
  (vector-fill! v 0)
  (check "vector-fill!" v #(0 0 0 0 0)))

(let ((v (vector 1 2 3 4 5)))
  (vector-fill! v 0 1 3)
  (check "vector-fill! range" v #(1 0 0 4 5)))

;;; ---- Conversion ----
(check "vector->list" (vector->list #(a b c)) '(a b c))
(check "vector->list empty" (vector->list #()) '())
(check "vector->list start" (vector->list #(a b c d e) 2) '(c d e))
(check "vector->list start end" (vector->list #(a b c d e) 1 3) '(b c))
(check "list->vector" (list->vector '(1 2 3)) #(1 2 3))
(check "list->vector empty" (list->vector '()) #())
(check "vector->string" (vector->string #(#\a #\b #\c)) "abc")
(check "vector->string range" (vector->string #(#\a #\b #\c #\d) 1 3) "bc")

;;; ---- Copy ----
(let ((v (vector 1 2 3 4 5)))
  (check "vector-copy" (vector-copy v) #(1 2 3 4 5))
  (check "vector-copy start" (vector-copy v 2) #(3 4 5))
  (check "vector-copy start end" (vector-copy v 1 4) #(2 3 4)))

(let ((dest (vector 0 0 0 0 0))
      (src  (vector 10 20 30)))
  (vector-copy! dest 1 src)
  (check "vector-copy!" dest #(0 10 20 30 0)))

(let ((dest (vector 0 0 0 0 0))
      (src  (vector 10 20 30 40 50)))
  (vector-copy! dest 0 src 2 4)
  (check "vector-copy! range" dest #(30 40 0 0 0)))

;;; ---- Append / concatenate ----
(check "vector-append" (vector-append #(1 2) #(3 4) #(5)) #(1 2 3 4 5))
(check "vector-append empty" (vector-append #() #(1 2)) #(1 2))
(check "vector-append all empty" (vector-append #() #()) #())
(check "vector-concatenate" (vector-concatenate (list #(1 2) #(3 4))) #(1 2 3 4))

;;; ---- Map / for-each ----
(check "vector-map" (vector-map + #(1 2 3) #(10 20 30)) #(11 22 33))
(check "vector-map single" (vector-map (lambda (x) (* x x)) #(1 2 3 4)) #(1 4 9 16))
(check "vector-map empty" (vector-map + #()) #())

(let ((result '()))
  (vector-for-each (lambda (x) (set! result (cons x result))) #(1 2 3))
  (check "vector-for-each" result '(3 2 1)))
(let ((result '()))
  (vector-for-each (lambda (a b) (set! result (cons (+ a b) result))) #(1 2 3) #(10 20 30))
  (check "vector-for-each 2-vec" result '(33 22 11)))

;;; ---- SRFI-133 extensions ----
(check "vector-count" (vector-count even? #(1 2 3 4 5 6)) 3)
(check "vector-count none" (vector-count even? #(1 3 5)) 0)
(check "vector-count empty" (vector-count even? #()) 0)

(check-true "vector-any even?" (vector-any even? #(1 3 4 5)))
(check-false "vector-any none" (vector-any even? #(1 3 5)))
(check-false "vector-any empty" (vector-any even? #()))

(check-true "vector-every even?" (vector-every even? #(2 4 6)))
(check-false "vector-every mixed" (vector-every even? #(2 3 4)))
(check-true "vector-every empty" (vector-every even? #()))

(check "vector-index" (vector-index even? #(1 3 4 5)) 2)
(check-false "vector-index miss" (vector-index even? #(1 3 5)))
(check "vector-index-right" (vector-index-right even? #(1 2 3 4 5)) 3)
(check-false "vector-index-right miss" (vector-index-right even? #(1 3 5)))

(check "vector-skip" (vector-skip odd? #(1 3 4 5)) 2)
(check "vector-skip-right" (vector-skip-right odd? #(1 2 3 4 5)) 3)

(let ((v (vector 1 2 3 4 5)))
  (vector-swap! v 0 4)
  (check "vector-swap!" v #(5 2 3 4 1)))

(let ((v (vector 1 2 3 4 5)))
  (vector-reverse! v)
  (check "vector-reverse!" v #(5 4 3 2 1)))

(let ((v (vector 1 2 3 4 5)))
  (vector-reverse! v 1 4)
  (check "vector-reverse! range" v #(1 4 3 2 5)))

(check "vector-reverse-copy" (vector-reverse-copy #(1 2 3 4 5)) #(5 4 3 2 1))
(check "vector-reverse-copy range" (vector-reverse-copy #(1 2 3 4 5) 1 4) #(4 3 2))

(check "vector-unfold" (vector-unfold (lambda (i) (+ i 1)) 5) #(1 2 3 4 5))
(check "vector-unfold empty" (vector-unfold values 0) #())

(check "vector-cumulate" (vector-cumulate + 0 #(1 2 3 4 5)) #(1 3 6 10 15))
(check "vector-cumulate empty" (vector-cumulate + 0 #()) #())

(let-values (((matching count) (vector-partition even? #(1 2 3 4 5 6))))
  (check "vector-partition count" count 3)
  (check "vector-partition first 3 even" (vector-ref matching 0) 2)
  (check "vector-partition second even" (vector-ref matching 1) 4)
  (check "vector-partition third even" (vector-ref matching 2) 6))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Vector coverage tests failed" fail))
