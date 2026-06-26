(import (scheme base) (scheme write) (srfi 1))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; Build large argument lists for stress testing.
;; With a low gc-threshold these force GC mid-construction.

;; circular-list: build a 200-element circular list and verify wrapping
(let ((cl (apply circular-list (list-tabulate 200 values))))
  (check "circular-list wraps"
    (list-ref cl 200)   ; element 200 == element 0
    0)
  (check "circular-list wraps+1"
    (list-ref cl 201)
    1)
  (check "circular-list last before wrap"
    (list-ref cl 199)
    199))

;; append-reverse: reverse a 500-element list onto a tail
(let ((result (append-reverse (list-tabulate 500 values) '(done))))
  (check "append-reverse length" (length result) 501)
  (check "append-reverse first" (car result) 499)
  (check "append-reverse last" (list-ref result 500) 'done))

;; lset-adjoin: adjoin 200 elements into a base set
(let ((base (list 0 1 2))
      (elts (list-tabulate 200 values)))
  (let ((result (apply lset-adjoin = base elts)))
    (check "lset-adjoin covers all"
      (length result) 200)))

;; lset-union: union of several 100-element lists with overlaps
(let ((a (list-tabulate 100 values))
      (b (list-tabulate 100 (lambda (i) (+ i 50))))
      (c (list-tabulate 100 (lambda (i) (+ i 100)))))
  (let ((result (lset-union = a b c)))
    (check "lset-union no duplicates"
      (length result) 200)))

;; lset-xor: symmetric difference of two 100-element lists
(let ((a (list-tabulate 100 values))
      (b (list-tabulate 100 (lambda (i) (+ i 50)))))
  (let ((result (lset-xor = a b)))
    ;; a has 0..99, b has 50..149
    ;; xor = {0..49} union {100..149} = 100 elements
    (check "lset-xor size" (length result) 100)))

;; concatenate: flatten 50 ten-element sublists
(let ((sublists (list-tabulate 50 (lambda (i)
                  (list-tabulate 10 (lambda (j) (+ (* i 10) j)))))))
  (let ((result (concatenate sublists)))
    (check "concatenate length" (length result) 500)
    (check "concatenate first" (car result) 0)
    (check "concatenate last" (list-ref result 499) 499)))

;; cons*: build a long dotted spine
(let ((result (apply cons* (list-tabulate 300 values))))
  (check "cons* first" (car result) 0)
  (check "cons* second" (cadr result) 1)
  (check "cons* tail" (list-ref result 298) 298))

;; unfold: generate a 500-element list
(let ((result (unfold (lambda (i) (= i 500))
                      values
                      (lambda (i) (+ i 1))
                      0)))
  (check "unfold length" (length result) 500)
  (check "unfold first" (car result) 0)
  (check "unfold last" (list-ref result 499) 499))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI-1 GC stress tests failed" fail))
