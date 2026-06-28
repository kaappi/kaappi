;; Regression test for #220: accessor/mutator functions not unrooted
;; from extra_roots after compilation in define-record-type.
;;
;; Creates multiple record types and exercises their accessors and
;; mutators under GC pressure to verify no root leak.

(import (scheme base)
        (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ")
        (display name)
        (display " got=")
        (write got)
        (display " expected=")
        (write expected)
        (newline))))

(define (gc-pressure)
  (let loop ((i 0))
    (when (< i 500)
      (make-vector 50 i)
      (loop (+ i 1)))))

(define-record-type <point>
  (make-point x y)
  point?
  (x point-x set-point-x!)
  (y point-y set-point-y!))

(define-record-type <rect>
  (make-rect left top right bottom)
  rect?
  (left rect-left)
  (top rect-top)
  (right rect-right)
  (bottom rect-bottom))

;; Exercise accessors
(let ((p (make-point 10 20)))
  (gc-pressure)
  (check "point-x" (point-x p) 10)
  (check "point-y" (point-y p) 20))

;; Exercise mutators
(let ((p (make-point 1 2)))
  (set-point-x! p 100)
  (gc-pressure)
  (set-point-y! p 200)
  (gc-pressure)
  (check "mutated-x" (point-x p) 100)
  (check "mutated-y" (point-y p) 200))

;; Exercise multiple record types
(let ((r (make-rect 0 0 640 480)))
  (gc-pressure)
  (check "rect-left" (rect-left r) 0)
  (check "rect-right" (rect-right r) 640)
  (check "rect-bottom" (rect-bottom r) 480))

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
