(import (scheme base) (scheme write) (srfi 133))

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

;; Test 1: vector-map — mapping proc allocates heap objects
(let ((v (make-vector 200 0)))
  (do ((i 0 (+ i 1))) ((= i 200)) (vector-set! v i i))
  (let ((out (vector-map
              (lambda (x)
                (make-list 5 x))
              v)))
    (check "vector-map length" (vector-length out) 200)
    (check "vector-map first" (vector-ref out 0) '(0 0 0 0 0))
    (check "vector-map last" (vector-ref out 199) '(199 199 199 199 199))
    (check "vector-map mid" (car (vector-ref out 100)) 100)))

;; Test 2: vector-map with string allocation
(let* ((v (vector 1 2 3 4 5))
       (out (vector-map
             (lambda (x)
               (make-string (* x 10) #\a))
             v)))
  (check "vector-map string lengths"
         (vector->list (vector-map string-length out))
         '(10 20 30 40 50)))

;; Test 3: vector-cumulate — accumulator is a heap value
(let* ((v (vector 1 2 3 4 5))
       (out (vector-cumulate
             (lambda (acc x) (cons x acc))
             '()
             v)))
  (check "vector-cumulate last" (vector-ref out 4) '(5 4 3 2 1))
  (check "vector-cumulate first" (vector-ref out 0) '(1)))

;; Test 4: vector-unfold — results and seeds are heap values
(let ((out (vector-unfold
            (lambda (i seed)
              (values (cons i seed) (+ seed 1)))
            5
            100)))
  (check "vector-unfold length" (vector-length out) 5)
  (check "vector-unfold first" (vector-ref out 0) '(0 . 100))
  (check "vector-unfold last" (vector-ref out 4) '(4 . 104)))

;; Test 5: vector-unfold-right
(let ((out (vector-unfold-right
            (lambda (i seed)
              (values (list i seed) (* seed 2)))
            4
            1)))
  (check "vector-unfold-right length" (vector-length out) 4)
  (check "vector-unfold-right elem 0" (vector-ref out 0) '(0 8))
  (check "vector-unfold-right elem 3" (vector-ref out 3) '(3 1)))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "vector-map GC tests failed" fail))
