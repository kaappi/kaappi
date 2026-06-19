;; Tests for foundational SRFIs with assertion-based checks.
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

(define (check-true name val)
  (if val
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name) (newline))))

;; SRFI-8: receive
(import (srfi 8))
(check "srfi-8 receive" (receive (a b c) (values 1 2 3) (+ a b c)) 6)

;; SRFI-2: and-let*
(import (srfi 2))
(check "srfi-2 and-let* truthy" (and-let* ((x 10) (y (* x 2))) (+ x y)) 30)
(check "srfi-2 and-let* false" (and-let* ((x #f)) x) #f)

;; SRFI-11: let-values (re-export of R7RS built-in)
(import (srfi 11))
(check "srfi-11 let-values" (let-values (((a b) (values 1 2))) (+ a b)) 3)

;; SRFI-16: case-lambda
(import (srfi 16))
(define f
  (case-lambda
    ((x) x)
    ((x y) (+ x y))))
(check "srfi-16 case-lambda arities" (list (f 5) (f 3 4)) '(5 7))

;; SRFI-28: format
(import (srfi 28))
(check "srfi-28 format ~a"
       (format "Hello ~a, you are ~a!" "world" 42)
       "Hello world, you are 42!")
(check "srfi-28 format ~s"
       (format "~s is ~a" "test" "good")
       "\"test\" is good")

;; SRFI-31: rec
(import (srfi 31))
(check "srfi-31 rec factorial"
       ((rec (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) 5)
       120)

;; SRFI-34: exception handling
(import (srfi 34))
(check "srfi-34 guard catches raise"
       (guard (exn (#t "caught")) (raise "oops"))
       "caught")

;; SRFI-111: boxes
(import (srfi 111))
(check "srfi-111 box/unbox/set-box!"
       (let ((b (box 42)))
         (let ((before (unbox b)))
           (set-box! b 99)
           (list before (unbox b))))
       '(42 99))

;; SRFI-145: assume
(import (srfi 145))
(define _assume-ok (assume #t "should pass"))
(check-true "srfi-145 assume reached" #t)

;; SRFI-222: compound objects
(import (srfi 222))
(check "srfi-222 compound basics"
       (let ((c (make-compound 'a 'b 'c)))
         (list (compound? c) (compound-length c) (compound-ref c 1)))
       '(#t 3 b))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Foundation SRFI tests failed" fail))
