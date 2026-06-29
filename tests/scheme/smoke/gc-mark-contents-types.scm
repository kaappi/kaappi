;; Regression test for #407: markObjectContents missing types.
;; Exercises old-gen objects of various types (promise, parameter,
;; error-object, continuation, rational) referencing young-gen values
;; under GC pressure that triggers minor collections.

(import (scheme base)
        (scheme write)
        (scheme lazy)
        (scheme case-lambda))

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

;; Promote objects to old generation
(define (promote)
  (let loop ((i 0))
    (when (< i 20)
      (gc-pressure)
      (loop (+ i 1)))))

;; Test 1: Promise with young-gen result after promotion
(define p (delay (make-string 50 #\x)))
(promote)
(gc-pressure)
(check "promise-force" (string-length (force p)) 50)
(gc-pressure)
(check "promise-reforce" (string-length (force p)) 50)

;; Test 2: Parameter with mutated value
(define param (make-parameter '()))
(promote)
(param (list 'a 'b 'c))
(gc-pressure)
(check "parameter-value" (param) '(a b c))
(gc-pressure)
(check "parameter-value-2" (param) '(a b c))

;; Test 3: Parameter with converter
(define param2 (make-parameter 0 (lambda (x) (+ x 1))))
(promote)
(check "parameter-converter" (param2) 1)
(gc-pressure)
(check "parameter-converter-stable" (param2) 1)

;; Test 4: Error object survives GC
(define saved-err #f)
(guard (e (#t (set! saved-err e)))
  (error "test error" (make-string 30 #\z)))
(promote)
(gc-pressure)
(check "error-message" (error-object-message saved-err) "test error")
(check "error-irritants"
       (string-length (car (error-object-irritants saved-err)))
       30)

;; Test 5: Continuation with captured state
(define k #f)
(define cont-result
  (call-with-current-continuation
    (lambda (c)
      (set! k c)
      'first)))
(promote)
(gc-pressure)
(check "continuation-result" cont-result 'first)

;; Test 6: Rationals (numerator/denominator are heap bignums for large values)
(define r (/ 1 3))
(promote)
(gc-pressure)
(check "rational-value" (* r 3) 1)
(check "rational-exact" (exact? r) #t)

;; Test 7: Multiple values (values object survives GC)
(define mv-result #f)
(call-with-values
  (lambda () (values (make-string 20 #\a) (make-string 20 #\b)))
  (lambda (a b)
    (set! mv-result (list a b))))
(promote)
(gc-pressure)
(check "multiple-values-a" (string-length (car mv-result)) 20)
(check "multiple-values-b" (string-length (cadr mv-result)) 20)

;; Test 8: Record instance
(define-record-type <point>
  (make-point x y)
  point?
  (x point-x)
  (y point-y))

(define pt (make-point (make-string 10 #\x) (make-string 10 #\y)))
(promote)
(gc-pressure)
(check "record-x" (string-length (point-x pt)) 10)
(check "record-y" (string-length (point-y pt)) 10)

;; Test 9: Hash table
(import (srfi 69))
(define ht (make-hash-table))
(hash-table-set! ht 'key (make-string 25 #\h))
(promote)
(gc-pressure)
(check "hash-table-value" (string-length (hash-table-ref ht 'key)) 25)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
