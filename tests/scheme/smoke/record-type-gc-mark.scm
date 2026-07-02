;; Regression test for #708: RecordInstance.record_type not marked
;; in markObjectContents/referencesYoung during minor GC collections.
;;
;; If the record_type pointer isn't traced from the remembered set,
;; a minor collection can free a young RecordType while an old
;; RecordInstance still references it, causing use-after-free.

(import (scheme base) (scheme write))

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
      (make-vector 50 (list i i i))
      (loop (+ i 1)))))

(define (promote)
  (let loop ((i 0))
    (when (< i 20)
      (gc-pressure)
      (loop (+ i 1)))))

;; Test 1: record predicate survives GC (uses record_type pointer)
(define-record-type <point>
  (make-point x y)
  point?
  (x point-x)
  (y point-y))

(define p1 (make-point 10 20))
(promote)
(gc-pressure)
(check "predicate after promotion" (point? p1) #t)
(check "accessor-x after promotion" (point-x p1) 10)
(check "accessor-y after promotion" (point-y p1) 20)

;; Test 2: multiple record types — predicates must distinguish correctly
(define-record-type <color>
  (make-color r g b)
  color?
  (r color-r)
  (g color-g)
  (b color-b))

(define c1 (make-color 255 128 0))
(promote)
(gc-pressure)
(check "color predicate" (color? c1) #t)
(check "point not color" (color? p1) #f)
(check "color not point" (point? c1) #f)
(check "color-r" (color-r c1) 255)

;; Test 3: records with heap-allocated fields under GC pressure
(define p2 (make-point (make-string 100 #\x) (make-vector 50 'y)))
(promote)
(gc-pressure)
(check "heap-field predicate" (point? p2) #t)
(check "heap-field string" (string-length (point-x p2)) 100)
(check "heap-field vector" (vector-length (point-y p2)) 50)

;; Test 4: create instances in a loop with interleaved GC pressure
(define instances '())
(let loop ((i 0))
  (when (< i 50)
    (set! instances (cons (make-point i (* i 2)) instances))
    (gc-pressure)
    (loop (+ i 1))))
(promote)
(gc-pressure)
(check "all instances pass predicate"
  (let loop ((lst instances))
    (if (null? lst) #t
        (and (point? (car lst)) (loop (cdr lst)))))
  #t)
(check "first instance x" (point-x (car instances)) 49)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
