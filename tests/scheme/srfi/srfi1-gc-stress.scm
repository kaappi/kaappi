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

;; filter-map: allocating callback (cons creates heap pressure) — regression #1027
(let ((result (filter-map (lambda (x) (cons x x))
                          (list-tabulate 500 values))))
  (check "filter-map length" (length result) 500)
  (check "filter-map first" (car result) '(0 . 0))
  (check "filter-map last" (list-ref result 499) '(499 . 499)))

;; append-map: allocating callback — regression #1027
(let ((result (append-map (lambda (x) (list (cons x x)))
                          (list-tabulate 500 values))))
  (check "append-map length" (length result) 500)
  (check "append-map first" (car result) '(0 . 0))
  (check "append-map last" (list-ref result 499) '(499 . 499)))

;; unfold with allocating callbacks — regression #1027
(let ((result (unfold (lambda (i) (= i 500))
                      (lambda (i) (cons i (* i i)))
                      (lambda (i) (+ i 1))
                      0)))
  (check "unfold-alloc length" (length result) 500)
  (check "unfold-alloc first" (car result) '(0 . 0))
  (check "unfold-alloc last" (list-ref result 499) '(499 . 249001)))

;; list-tabulate with an allocating callback — regression #2160
;;
;; The sibling #1027 missed. Every element is a fresh list reachable from
;; nothing but the primitive's own ArrayList, which the collector cannot see,
;; so the next callback's allocation frees it. Unlike the three above, this
;; one is visible on a *default* build as well, which is why it is the one
;; case here sized past the 8192-object GC threshold rather than to the 200-500
;; the rest of this file uses: at 2000 three-pair elements a plain build
;; returns (1 1 1)-shaped garbage for element 0.
;; Compared as booleans, not values: a lost element comes back spliced into
;; the recycled tail, so printing the "got" side of element 0 dumps hundreds
;; of pairs into the log.
(let ((result (list-tabulate 2000 (lambda (i) (list i i i)))))
  (check "list-tabulate-alloc first" (equal? (car result) '(0 0 0)) #t)
  (check "list-tabulate-alloc middle" (equal? (list-ref result 1000) '(1000 1000 1000)) #t)
  (check "list-tabulate-alloc last" (equal? (list-ref result 1999) '(1999 1999 1999)) #t))

;; The control: an immediate needs no rooting, so this half was always
;; correct. If it ever fails, list-tabulate itself is broken, not its buffer.
(let ((result (list-tabulate 500 values)))
  (check "list-tabulate-immediate first" (car result) 0)
  (check "list-tabulate-immediate last" (list-ref result 499) 499))

;; zip and alist-copy — regression #2160
;;
;; Neither takes a callback, so #1027 never looked at them, but both allocate
;; their elements directly and park them in the same unrooted buffer: zip's
;; rows and alist-copy's copied entries. Both abort at three elements under
;; -Dgc-stress=true.
(let ((result (zip (list-tabulate 200 values) (list-tabulate 200 values))))
  (check "zip first row" (car result) '(0 0))
  (check "zip last row" (list-ref result 199) '(199 199)))

(let* ((original (map (lambda (i) (cons i i)) (list-tabulate 200 values)))
       (result (alist-copy original)))
  (check "alist-copy first entry" (car result) '(0 . 0))
  (check "alist-copy last entry" (list-ref result 199) '(199 . 199))
  (check "alist-copy is a copy, not the original spine"
    (eq? (car result) (car original)) #f))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI-1 GC stress tests failed" fail))
