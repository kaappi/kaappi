;;; R7RS Vector compliance tests
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "vectors")

;; --- vector literals ---
(test-group "vector literals"
  (test-equal "vector literal #(1 2 3)" #(1 2 3) #(1 2 3))
  (test-equal "empty vector literal" #() #())
  (test-equal "symbol vector literal" #(a b c) #(a b c)))

;; --- vector? predicate ---
(test-group "vector? predicate"
  (test-eqv "vector? on vector" #t (vector? #(1 2 3)))
  (test-eqv "vector? on list" #f (vector? '(1 2 3)))
  (test-eqv "vector? on number" #f (vector? 42)))

;; --- vector constructor ---
(test-group "vector constructor"
  (test-equal "vector with numbers" #(1 2 3) (vector 1 2 3))
  (test-equal "empty vector" #() (vector))
  (test-equal "vector with symbols" #(a b c) (vector 'a 'b 'c)))

;; --- make-vector ---
(test-group "make-vector"
  (test-equal "make-vector with fill" #(0 0 0) (make-vector 3 0))
  (test-equal "make-vector zero length" #() (make-vector 0)))

;; --- vector-length ---
(test-group "vector-length"
  (test-eqv "length of 3-element vector" 3 (vector-length #(1 2 3)))
  (test-eqv "length of empty vector" 0 (vector-length #())))

;; --- vector-ref ---
(test-group "vector-ref"
  (test-eqv "vector-ref index 0" 'a (vector-ref #(a b c) 0))
  (test-eqv "vector-ref index 1" 'b (vector-ref #(a b c) 1))
  (test-eqv "vector-ref index 2" 'c (vector-ref #(a b c) 2)))

;; --- vector-set! ---
(test-group "vector-set!"
  (test-equal "vector-set! middle element"
    #(1 99 3)
    (let ((v (vector 1 2 3)))
      (vector-set! v 1 99)
      v)))

;; --- vector->list ---
(test-group "vector->list"
  (test-equal "vector->list full" '(a b c) (vector->list #(a b c)))
  (test-equal "vector->list with start/end" '(b c) (vector->list #(a b c d e) 1 3)))

;; --- list->vector ---
(test-group "list->vector"
  (test-equal "list->vector" #(1 2 3) (list->vector '(1 2 3)))
  (test-equal "empty list->vector" #() (list->vector '())))

;; --- vector-fill! ---
(test-group "vector-fill!"
  (test-equal "vector-fill! all elements"
    #(7 7 7 7)
    (let ((v (make-vector 4 0)))
      (vector-fill! v 7)
      v)))

;; --- vector-copy ---
(test-group "vector-copy"
  (test-equal "vector-copy full" #(a b c d e) (vector-copy #(a b c d e)))
  (test-equal "vector-copy with start/end" #(b c) (vector-copy #(a b c d e) 1 3)))

;; --- vector-copy! ---
(test-group "vector-copy!"
  (test-equal "vector-copy! into middle"
    #(1 10 20 30 5)
    (let ((to (vector 1 2 3 4 5)))
      (vector-copy! to 1 #(10 20 30))
      to)))

;; --- vector-append ---
(test-group "vector-append"
  (test-equal "append two vectors" #(1 2 3 4) (vector-append #(1 2) #(3 4)))
  (test-equal "append three vectors" #(1 2 3) (vector-append #(1) #(2) #(3)))
  (test-equal "append no vectors" #() (vector-append)))

;; --- vector-map ---
(test-group "vector-map"
  (test-equal "vector-map square" #(1 4 9 16) (vector-map (lambda (x) (* x x)) #(1 2 3 4)))
  (test-equal "vector-map with two vectors" #(11 22 33) (vector-map + #(1 2 3) #(10 20 30))))

;; --- vector-for-each ---
(test-group "vector-for-each"
  (test-eqv "vector-for-each sum" 15
    (let ((sum 0))
      (vector-for-each (lambda (x) (set! sum (+ sum x))) #(1 2 3 4 5))
      sum)))

;; --- vector->string ---
(test-group "vector->string"
  (test-equal "vector->string" "hello" (vector->string #(#\h #\e #\l #\l #\o))))

;; --- equal? on vectors ---
(test-group "equal? on vectors"
  (test-eqv "equal vectors" #t (equal? #(1 2 3) #(1 2 3)))
  (test-eqv "unequal vectors" #f (equal? #(1 2 3) #(1 2 4)))
  (test-eqv "equal empty vectors" #t (equal? #() #())))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "vectors")
(if (> %test-fail-count 0) (exit 1))
