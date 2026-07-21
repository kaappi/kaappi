;;; SRFI 253 test suite — Data (Type-)Checking
;;; Adapted from the reference test.scm by Artyom Bologov (MIT license).

(import (scheme base)
        (scheme case-lambda)
        (srfi 253)
        (srfi 64))

(test-begin "srfi-253")

;; ---- check-arg ----

(test-begin "check-arg")

(define-syntax check-arg-true
  (syntax-rules ()
    ((_ pred val)
     (begin
       (check-arg pred val)
       #t))))

;; Sanity checks
(test-assert (check-arg-true exact-integer? 3))
(test-assert (check-arg-true integer? 3))
(test-assert (check-arg-true boolean? #f))
(test-assert (check-arg-true char? #\d))
(test-assert (check-arg-true complex? 3+2i))
(test-assert (check-arg-true inexact? 3.8))
(test-assert (check-arg-true real? 3))
(test-assert (check-arg-true real? 3/2))
(test-assert (check-arg-true real? 3.8))
(test-assert (check-arg-true list? '()))
(test-assert (check-arg-true list? '(1 2 3)))
(test-assert (check-arg-true null? '()))
(test-assert (check-arg-true number? 3))
(test-assert (check-arg-true number? 3+2i))
(test-assert (check-arg-true number? 3.8))
(test-assert (check-arg-true pair? '(1 2 3)))
(test-assert (check-arg-true input-port? (current-input-port)))
(test-assert (check-arg-true output-port? (current-output-port)))
(test-assert (check-arg-true procedure? procedure?))
(test-assert (check-arg-true rational? 3))
(test-assert (check-arg-true rational? 3/2))
(test-assert (check-arg-true string? ""))
(test-assert (check-arg-true string? "hello"))
(test-assert (check-arg-true symbol? 'hello))
(test-assert (check-arg-true vector? #(1 2 3)))

;; Predicate checks
(test-assert (check-arg-true (lambda (x) (positive? (string-length x)))
                             "hello"))
(test-assert (check-arg-true positive? 9))
(test-assert (check-arg-true string-length "hello")) ;; If it works it works.
(test-assert (check-arg-true (lambda (x)
                               (and (integer? x) (positive? x)))
                             8))
(test-assert (check-arg-true ((lambda (x y)
                                (lambda (a) (and (x a) (y a))))
                              integer? positive?)
                             8))

;; Erroring checks
(test-error (check-arg string? 3))
(test-error (check-arg real? 3+2i))
(test-error (check-arg symbol? "hello"))
(test-error (check-arg procedure? 3))
(test-error (check-arg (lambda (a) (> a 3)) 0))

;; Syntax checks
(test-assert (begin (check-arg integer? 3 'testing-caller-arg) #t))

(test-end "check-arg")


;; ---- values-checked ----

(test-begin "values-checked")

(test-equal 3 (values-checked (integer?) 3))
(test-equal 3 (values-checked ((lambda (x) (= 3 x))) 3))
(test-approximate 3.0 (values-checked (real?) 3.0) 0.00001)
(test-equal 3 (values-checked (real?) 3))
(test-assert (values-checked (integer? string?) 3 "hello"))
(test-approximate 3.0 (values-checked (inexact?) 3.0) 0.00001)
(test-error (values-checked (integer?) "hello"))
(test-error (values-checked (integer? string?) 3 3))

(test-end "values-checked")


;; ---- check-case ----

(test-begin "check-case")

(test-assert (check-case "hello" (string? #t)))
(test-assert (check-case 3 (integer? #t) (string? #f)))
(test-assert (check-case 3.7 (inexact? #t)))
(test-assert (check-case (current-output-port) (output-port? #t)))
(test-assert (check-case #(1 2 3) (vector? #t)))
(test-assert (check-case 3 (string? #f) (else #t)))
(test-error (check-case 3 (string? #t)))

(test-end "check-case")


;; ---- lambda-checked ----

(test-begin "lambda-checked")

(test-assert (lambda-checked () #t))
(test-assert (lambda-checked args #t))
(test-assert (lambda-checked (a) #t))
(test-assert (lambda-checked (a b) #t))
(test-assert (lambda-checked ((a integer?)) #t))
(test-assert (lambda-checked (a (b integer?)) #t))
(test-assert (lambda-checked ((a string?) (b integer?)) #t))
(test-assert ((lambda-checked () #t)))
(test-assert ((lambda-checked args #t) 1 2 3))
(test-assert ((lambda-checked (a) #t) 3))
(test-assert ((lambda-checked (a) #t) "hello"))
(test-assert ((lambda-checked ((a integer?)) #t) 3))
(test-assert ((lambda-checked (a (b integer?)) #t) 3 3))
(test-assert ((lambda-checked (a (b integer?)) #t) "hello" 3))
(test-error ((lambda-checked ((a integer?)) #t) "hello"))
(test-error ((lambda-checked (a (b integer?)) #t) "hello" "hi"))

;; Return value checks
(test-assert ((lambda-checked ((b integer?)) => (integer?) 2) 1))
(test-error ((lambda-checked ((b integer?)) => (integer?) #t) 1))

(test-end "lambda-checked")


;; ---- case-lambda-checked ----

(test-begin "case-lambda-checked")

(test-assert (case-lambda-checked
              (() #t)))
(test-assert (case-lambda-checked
              (args #t)))
(test-assert (case-lambda-checked
              ((a) #t)))
(test-assert (case-lambda-checked
              (() #t) ((a) #t)))
(test-assert (case-lambda-checked
              (() #t) ((a) #t) (args #t)))
(test-assert (case-lambda-checked
              (((a integer?)) #t)))
(test-assert (case-lambda-checked
              (((a integer?) b) #t)))
(test-assert (case-lambda-checked
              ((a (b integer?)) #t)))
(test-assert (case-lambda-checked
              (() #t)
              (((a integer?)) #t)
              ((a (b string?)) #t)
              (args #t)))

(define checked-case-lambda
  (case-lambda-checked
   (() #t)
   (((a integer?)) #t)
   ((a (b string?)) #t)
   (((a string?) b . rest) #t)))
(test-assert (checked-case-lambda))
(test-assert (checked-case-lambda 3))
(test-error (checked-case-lambda "hello"))
(test-assert (checked-case-lambda 3 "hello"))
(test-assert (checked-case-lambda "hi" "hello"))
(test-error (checked-case-lambda 3 3 3))

;; Return value checks
(define good-return-checked-case-lambda
  (case-lambda-checked
   (() => (integer?) 1)
   (((a integer?)) => (integer?) 1)
   (args => (integer?) 1)))
(test-assert (good-return-checked-case-lambda 1))
(test-assert (good-return-checked-case-lambda))
(test-assert (good-return-checked-case-lambda 1 2 3))

(define bad-return-checked-case-lambda
  (case-lambda-checked
   (() => (integer?) #t)
   (((a integer?)) => (integer?) #t)
   (args => (integer?) #t)))
(test-error (bad-return-checked-case-lambda 1))
(test-error (bad-return-checked-case-lambda))
(test-error (bad-return-checked-case-lambda 1 2 3))

(test-end "case-lambda-checked")


;; ---- define-checked ----

(test-begin "define-checked")

(define-checked (c) #t)
(test-assert (c))
(define-checked (c (a integer?)) #t)
(test-assert (c 3))
(test-error (c "hello"))
(define-checked (c b) #t)
(test-assert (c "anything"))
(test-error (c 1 2 3))
(define-checked (c (b string?)) #t)
(test-assert (c "hello"))
(test-error (c 3))
(define-checked c string? "hello")
(test-assert c)
(set! c "whatever")
(test-assert c)

(test-end "define-checked")


;; ---- define-record-type-checked ----

(test-begin "define-record-type-checked")

(define-record-type-checked <test>
  (make-test a b)
  test?
  (a integer? test-a)
  (b string? test-b test-b-set!))
(test-assert (make-test 1 "hello"))
(test-error (make-test 1))
(test-error (make-test 1 2))
(test-error (make-test 1.2 "hello"))

(define test-test (make-test 1 "hello"))
(test-assert (begin
               (test-b-set! test-test "foo")
               #t))
(test-error (test-b-set! test-test 1))

(test-end "define-record-type-checked")


;; ---- summary ----

(let ((runner (test-runner-current)))
  (test-end "srfi-253")
  (when (> (test-runner-fail-count runner) 0)
    (exit 1)))
