;; Regression test: a template-introduced binding whose name collides
;; with a builtin procedure must shadow the builtin inside the template.
;; renameForHygiene kept references to procedure-valued globals
;; unrenamed, so the binding occurrence was renamed but the body
;; references still resolved to the builtin. This broke the SRFI-19
;; test harness, whose check macro binds (exp expected): every
;; comparison used #<builtin exp> instead of the expected value,
;; reporting 99 bogus failures.

(define fails 0)
(define (check name expected actual)
  (if (equal? expected actual)
      (begin (display "  PASS  ") (display name) (newline))
      (begin (set! fails (+ fails 1))
             (display "  FAIL  ") (display name)
             (display " expected=") (write expected)
             (display " got=") (write actual) (newline))))

;; 1. Template let binding named after a builtin procedure
(define-syntax capture-exp
  (syntax-rules ()
    ((_ v) (let ((exp v)) exp))))
(check "template let binding shadows builtin exp" 42 (capture-exp 42))

;; 2. The SRFI-19 harness shape: two bindings, one collides with exp
(define-syntax check-eq
  (syntax-rules ()
    ((_ a b)
     (let ((result a) (exp b))
       (equal? result exp)))))
(check "srfi-19 harness shape compares values" #t (check-eq 7 7))
(check "srfi-19 harness shape detects mismatch" #f (check-eq 7 8))

;; 3. A template reference without a template binding still reaches
;;    the builtin
(define-syntax call-exp
  (syntax-rules ()
    ((_ v) (exp v))))
(check "template reference still reaches builtin exp" 1 (exact (round (call-exp 0))))

;; 4. Same collision with a different builtin (list)
(define-syntax capture-list
  (syntax-rules ()
    ((_ v) (let ((list v)) list))))
(check "template binding shadows builtin list" 5 (capture-list 5))

(when (> fails 0) (exit 1))
