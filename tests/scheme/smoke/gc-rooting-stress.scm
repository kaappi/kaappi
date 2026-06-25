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

;; Stress-test append with many lists to force GC during pair allocation
(check "append large"
  (length (append (make-list 500 'a) (make-list 500 'b) (make-list 500 'c)))
  1500)

(check "append correctness"
  (append '(1 2 3) '(4 5 6) '(7 8 9))
  '(1 2 3 4 5 6 7 8 9))

(check "append empty"
  (append '() '(1 2) '())
  '(1 2))

;; Stress-test list construction (makeList) with many elements
(check "make-list large"
  (length (make-list 2000 #t))
  2000)

;; Stress-test string-split with many parts
(let ((big-str (let loop ((n 500) (acc "x"))
                 (if (= n 0) acc
                     (loop (- n 1) (string-append acc ",x"))))))
  (check "string-split many parts"
    (length (string-split big-str ","))
    501))

(check "string-split basic"
  (string-split "a::b::c" "::")
  '("a" "b" "c"))

(check "string-split empty delim"
  (string-split "abc" "")
  '("a" "b" "c"))

(check "string-split no match"
  (string-split "hello" ",")
  '("hello"))

;; Stress-test interleaved allocations
(let ((result '()))
  (let loop ((i 0))
    (when (< i 100)
      (set! result (append result (list (make-string 50 #\x))))
      (loop (+ i 1))))
  (check "interleaved append+string alloc" (length result) 100))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "GC rooting stress tests failed" fail))
