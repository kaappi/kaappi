(import (scheme base) (scheme write) (srfi 196))

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

;; Constructors
(let ((r (numeric-range 0 5)))
  (check-true "range?" (range? r))
  (check "length" (range-length r) 5)
  (check "ref 0" (range-ref r 0) 0)
  (check "ref 4" (range-ref r 4) 4)
  (check "first" (range-first r) 0)
  (check "last" (range-last r) 4))

(let ((r (numeric-range 1 10 2)))
  (check "step length" (range-length r) 5)
  (check "step ref" (range-ref r 2) 5))

(let ((r (iota-range 5)))
  (check "iota" (range->list r) '(0 1 2 3 4)))

(let ((r (iota-range 4 10 3)))
  (check "iota start step" (range->list r) '(10 13 16 19)))

(let ((r (vector-range (vector 'a 'b 'c))))
  (check "vector-range" (range->list r) '(a b c)))

(let ((r (string-range "hello")))
  (check "string-range len" (range-length r) 5)
  (check "string-range ref" (range-ref r 1) #\e))

;; range constructor
(let ((r (range 3 (lambda (i) (* i i)))))
  (check "range" (range->list r) '(0 1 4)))

;; Predicates
(check-true "range=?" (range=? = (numeric-range 0 3) (iota-range 3)))
(check-false "range=? diff" (range=? = (numeric-range 0 3) (numeric-range 1 4)))

;; Slicing
(let ((r (numeric-range 0 10)))
  (check "take" (range->list (range-take r 3)) '(0 1 2))
  (check "drop" (range->list (range-drop r 7)) '(7 8 9))
  (check "take-right" (range->list (range-take-right r 3)) '(7 8 9))
  (check "drop-right" (range->list (range-drop-right r 7)) '(0 1 2))
  (check "subrange" (range->list (subrange r 2 5)) '(2 3 4)))

;; Split
(let ((r (numeric-range 0 5)))
  (let-values (((a b) (range-split-at r 3)))
    (check "split-at left" (range->list a) '(0 1 2))
    (check "split-at right" (range->list b) '(3 4))))

;; Segment
(let ((segs (range-segment (numeric-range 0 7) 3)))
  (check "segment count" (length segs) 3)
  (check "segment 0" (range->list (car segs)) '(0 1 2))
  (check "segment 2" (range->list (caddr segs)) '(6)))

;; Append
(let ((r (range-append (numeric-range 0 3) (numeric-range 10 13))))
  (check "append" (range->list r) '(0 1 2 10 11 12)))

;; Reverse
(check "reverse" (range->list (range-reverse (numeric-range 0 4))) '(3 2 1 0))

;; Count, any, every
(let ((r (numeric-range 0 10)))
  (check "count" (range-count even? r) 5)
  (check-true "any" (range-any (lambda (x) (> x 8)) r))
  (check-false "every" (range-every even? r))
  (check-true "every pos" (range-every (lambda (x) (>= x 0)) r)))

;; Map
(check "map" (range->list (range-map (lambda (x) (* x 2)) (numeric-range 0 4))) '(0 2 4 6))
(check "map->list" (range-map->list (lambda (x) (* x x)) (numeric-range 0 4)) '(0 1 4 9))
(check "map->vector" (range-map->vector (lambda (x) (+ x 1)) (numeric-range 0 3)) #(1 2 3))

;; Filter
(check "filter->list" (range-filter->list even? (numeric-range 0 6)) '(0 2 4))
(check "remove->list" (range-remove->list even? (numeric-range 0 6)) '(1 3 5))
(check "filter" (range->list (range-filter even? (numeric-range 0 6))) '(0 2 4))

;; Fold
(check "fold" (range-fold + 0 (numeric-range 1 6)) 15)
(check "fold-right" (range-fold-right cons '() (numeric-range 0 4)) '(0 1 2 3))

;; Search
(check "index" (range-index even? (numeric-range 1 10)) 1)
(check "index-right" (range-index-right even? (numeric-range 0 5)) 4)
(check-false "index miss" (range-index (lambda (x) (> x 100)) (numeric-range 0 5)))

;; Take/drop while
(check "take-while" (range->list (range-take-while (lambda (x) (< x 3)) (numeric-range 0 6)))
       '(0 1 2))
(check "drop-while" (range->list (range-drop-while (lambda (x) (< x 3)) (numeric-range 0 6)))
       '(3 4 5))

;; Conversion
(check "->list" (range->list (numeric-range 0 4)) '(0 1 2 3))
(check "->vector" (range->vector (numeric-range 0 3)) #(0 1 2))
(check "->string" (range->string (string-range "hello")) "hello")

;; Generator
(let ((g (range->generator (numeric-range 0 3))))
  (check "gen 0" (g) 0)
  (check "gen 1" (g) 1)
  (check "gen 2" (g) 2)
  (check-true "gen eof" (eof-object? (g))))

;; For-each
(let ((sum 0))
  (range-for-each (lambda (x) (set! sum (+ sum x))) (numeric-range 1 6))
  (check "for-each" sum 15))

;; Multi-range
(check "map 2 ranges"
  (range-map->list + (numeric-range 0 3) (numeric-range 10 13))
  '(10 12 14))
(check "fold 2 ranges"
  (range-fold (lambda (a b acc) (+ acc (* a b))) 0
              (numeric-range 1 4) (numeric-range 1 4))
  14)

;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 196 tests failed" fail))
