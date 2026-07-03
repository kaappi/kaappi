;; Regression test for #827: LLVM native backend eval fallback inside
;; let/lambda bodies must not lose the lexical environment.
;;
;; These tests run through the interpreter (which handles scoping
;; correctly), verifying the semantics that the native backend must
;; reproduce.  The LLVM backend fix ensures that when a let or lambda
;; body contains forms needing eval fallback (cond, do, letrec, etc.),
;; the entire enclosing form is evaluated by the interpreter instead of
;; splitting the lexical scope across the native/interpreted boundary.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "llvm-let-scope-827")

;; Repro 1: cond inside a let body — the cond must see let-bound x.
(test-equal "cond inside let"
  5
  (let ((x 5)) (cond ((> x 1) x) (else 0))))

;; Repro 2: lambda capturing a let local — the lambda must close over y.
(test-equal "lambda capturing let local"
  10
  ((let ((y 10)) (lambda () y))))

;; Repro 3: parameter must not clobber a same-named global.
(define x 100)
(define (f x) (cond ((> x 0) x) (else 0)))
(test-equal "function returns param, not global" 5 (f 5))
(test-equal "global x unchanged after call" 100 x)

;; Additional edge cases:

;; let* with cond referencing earlier binding
(test-equal "let* cond references earlier binding"
  11
  (let* ((a 10) (b (+ a 1)))
    (cond ((> b 5) b) (else 0))))

;; Nested let with cond in inner body
(test-equal "nested let with cond"
  6
  (let ((x 5))
    (let ((y (+ x 1)))
      (cond ((> y 3) y) (else 0)))))

;; do inside a let body
(test-equal "do inside let"
  55
  (let ((n 10))
    (do ((i 0 (+ i 1))
         (sum 0 (+ sum i)))
        ((= i n) (+ sum n)))))

;; letrec inside a let body
(test-equal "letrec inside let"
  #t
  (let ((x 5))
    (letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
             (odd?  (lambda (n) (if (= n 0) #f (even? (- n 1))))))
      (odd? x))))

;; case inside a lambda body
(define (classify n)
  (case n
    ((1 2 3) 'small)
    ((4 5 6) 'medium)
    (else 'large)))
(test-equal "case inside define" 'medium (classify 5))
(test-equal "case inside define (else)" 'large (classify 99))

;; lambda with let local in a let* binding init
(test-equal "lambda capturing let* local in init"
  10
  (let* ((y 10)
         (f (lambda () y)))
    (f)))

(let ((runner (test-runner-current)))
  (test-end "llvm-let-scope-827")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
