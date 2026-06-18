; Phase 2: Proper tail calls

; Tail-recursive loop — must not overflow
(define (loop n) (if (= n 0) 'done (loop (- n 1))))
(loop 1000000)

; Tail-recursive factorial with accumulator
(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc))))
(fact 10 1)

; Mutual tail recursion
(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))
(define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))
(my-even? 10000)
(my-odd? 10001)

; Non-tail recursion still works
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(fib 10)

; Tail call in begin
(define (count n) (if (= n 0) 0 (begin (count (- n 1)))))
(count 100000)

; Nested calls with user-defined functions
(define (id x) x)
(+ (id 3) (id 4))
(define (add a b) (+ a b))
(add (fib 5) (fib 6))
