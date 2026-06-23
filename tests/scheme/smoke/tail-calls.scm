;; Phase 2: Proper tail calls
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "tail-calls")

;; Tail-recursive loop -- must not overflow
(define (loop n) (if (= n 0) 'done (loop (- n 1))))
(test-eq "tail-recursive loop" 'done (loop 1000000))

;; Tail-recursive factorial with accumulator
(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc))))
(test-eqv "factorial 10" 3628800 (fact 10 1))

;; Mutual tail recursion
(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))
(define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))
(test-eqv "mutual even? 10000" #t (my-even? 10000))
(test-eqv "mutual odd? 10001" #t (my-odd? 10001))

;; Non-tail recursion still works
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(test-eqv "fibonacci 10" 55 (fib 10))

;; Tail call in begin
(define (count n) (if (= n 0) 0 (begin (count (- n 1)))))
(test-eqv "tail call in begin" 0 (count 100000))

;; Nested calls with user-defined functions
(define (id x) x)
(test-eqv "nested id calls" 7 (+ (id 3) (id 4)))
(define (add a b) (+ a b))
(test-eqv "nested fib calls" 13 (add (fib 5) (fib 6)))

;; Regression: recursive sort with tail call to a closure.
;; Exercises JIT tail_call side-exit (insert-sorted is a closure,
;; not a native) and self-call sequences under JIT compilation.
(define (insert-sorted entry sorted)
  (if (null? sorted) (list entry)
      (if (>= (car entry) (car (car sorted)))
          (cons entry sorted)
          (cons (car sorted) (insert-sorted entry (cdr sorted))))))

(define (sort-desc entries)
  (if (null? entries) '()
      (insert-sorted (car entries) (sort-desc (cdr entries)))))

(define sort-data '((5 . "a") (3 . "b") (7 . "c") (1 . "d") (4 . "e")))

;; Run enough iterations to trigger JIT (threshold = 100 calls).
;; sort-desc makes 6 calls per iteration on a 5-element list.
(define (repeat-sort n)
  (if (= n 0) (sort-desc sort-data)
      (begin (sort-desc sort-data) (repeat-sort (- n 1)))))

(test-equal "JIT recursive tail call to closure"
  '((7 . "c") (5 . "a") (4 . "e") (3 . "b") (1 . "d"))
  (repeat-sort 25))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "tail-calls")
(if (> %test-fail-count 0) (exit 1))
