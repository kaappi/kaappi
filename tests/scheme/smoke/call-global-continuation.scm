;; Regression test for #449: ContinuationInvoked not handled in
;; call_global fast path. Continuations invoked inside native
;; higher-order functions (for-each, map) called via call_global
;; should work correctly.

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

;; Test 1: continuation invoked through for-each (call_global)
(define k1 #f)
(define result1
  (+ 100
     (call-with-current-continuation
       (lambda (cont)
         (set! k1 cont)
         0))))

(check "initial" result1 100)

(define (invoke-through-for-each)
  (for-each (lambda (x) (when (= x 2) (k1 42))) (list 1 2 3))
  (display "should not reach here"))

(invoke-through-for-each)
(check "for-each-continuation" result1 142)

;; Test 2: continuation invoked through map (call_global)
(define k2 #f)
(define result2
  (+ 200
     (call-with-current-continuation
       (lambda (cont)
         (set! k2 cont)
         0))))

(check "map-initial" result2 200)

(define (invoke-through-map)
  (map (lambda (x) (when (= x 3) (k2 50))) (list 1 2 3))
  (display "should not reach here"))

(invoke-through-map)
(check "map-continuation" result2 250)

;; Test 3: continuation with dynamic-wind through call_global
(define wind-log '())
(define k3 #f)

(define result3
  (call-with-current-continuation
    (lambda (c)
      (dynamic-wind
        (lambda () (set! wind-log (cons 'in wind-log)))
        (lambda ()
          (for-each
            (lambda (x)
              (when (= x 1) (set! k3 c))
              (when (= x 2) (c 'done)))
            (list 1 2 3)))
        (lambda () (set! wind-log (cons 'out wind-log)))))))

(check "dynamic-wind-result" result3 'done)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
