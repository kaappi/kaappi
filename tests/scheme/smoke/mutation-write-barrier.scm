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

(define (gc-pressure)
  (let loop ((i 0))
    (when (< i 3000)
      (make-list 10 i)
      (loop (+ i 1)))))

;; --- vector-set! ---

(define v (vector 0 0 0))
(gc-pressure)
(vector-set! v 1 (string-copy "vec-val"))
(gc-pressure)
(check "vector-set! survives GC" (vector-ref v 1) "vec-val")

;; --- vector-fill! ---

(define v2 (make-vector 5 #f))
(gc-pressure)
(vector-fill! v2 (list 'x 'y))
(gc-pressure)
(check "vector-fill! survives GC" (vector-ref v2 0) '(x y))
(check "vector-fill! all slots" (vector-ref v2 4) '(x y))

;; --- vector-copy! ---

(define src (vector (string-copy "a") (string-copy "b") (string-copy "c")))
(define dst (make-vector 3 #f))
(gc-pressure)
(vector-copy! dst 0 src)
(gc-pressure)
(check "vector-copy! survives GC (0)" (vector-ref dst 0) "a")
(check "vector-copy! survives GC (1)" (vector-ref dst 1) "b")
(check "vector-copy! survives GC (2)" (vector-ref dst 2) "c")

;; --- hash-table-set! ---

(define ht (make-hash-table))
(gc-pressure)
(hash-table-set! ht 'key1 (string-copy "ht-val"))
(gc-pressure)
(check "hash-table-set! value survives GC"
  (hash-table-ref ht 'key1) "ht-val")

(hash-table-set! ht (string-copy "str-key") 42)
(gc-pressure)
(check "hash-table-set! string key survives GC"
  (hash-table-ref ht "str-key") 42)

;; --- hash-table-update!/default ---

(define ht2 (make-hash-table))
(gc-pressure)
(hash-table-update!/default ht2 'counter (lambda (x) (+ x 1)) 0)
(gc-pressure)
(check "hash-table-update!/default survives GC"
  (hash-table-ref ht2 'counter) 1)

;; --- list-set! ---

(define ls (list 'a 'b 'c))
(gc-pressure)
(list-set! ls 1 (string-copy "list-val"))
(gc-pressure)
(check "list-set! survives GC" (list-ref ls 1) "list-val")

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "mutation write barrier tests failed" fail))
