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

;; Record mutation must preserve young-gen values when the record is old-gen.
;; Without the write barrier in %record-set!, minor GC can collect the new value.

(define-record-type <point>
  (make-point x y)
  point?
  (x point-x set-point-x!)
  (y point-y set-point-y!))

;; Create a record and force it into old generation via GC pressure
(define p (make-point 1 2))

;; Allocate enough to trigger several GC cycles, promoting p to old gen
(let loop ((i 0))
  (when (< i 3000)
    (make-list 10 i)
    (loop (+ i 1))))

;; Now mutate the old-gen record with a new young-gen value (a freshly allocated string)
(set-point-x! p (string-copy "new-value"))

;; More allocation to trigger minor GC
(let loop ((i 0))
  (when (< i 3000)
    (make-list 10 i)
    (loop (+ i 1))))

;; The string must survive — the write barrier should have protected it
(check "record mutation survives GC"
  (point-x p)
  "new-value")

;; Test mutating multiple fields
(set-point-y! p (list 'a 'b 'c))

(let loop ((i 0))
  (when (< i 3000)
    (make-list 10 i)
    (loop (+ i 1))))

(check "record second field survives GC"
  (point-y p)
  '(a b c))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "record-set GC tests failed" fail))
