;; Regression test for #1271: define-syntax must capture let/lambda
;; bindings from its definition scope (same as let-syntax).
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "define-syntax-capture")

;; --- let binding ---
(test-equal "let binding captured by define-syntax"
  7
  (let ((y 7))
    (define-syntax gety (syntax-rules () ((_) y)))
    (gety)))

;; --- let* binding ---
(test-equal "let* binding captured by define-syntax"
  7
  (let* ((y 7))
    (define-syntax gety (syntax-rules () ((_) y)))
    (gety)))

;; --- lambda parameter ---
(test-equal "lambda parameter captured by define-syntax"
  7
  ((lambda (y)
     (define-syntax gety (syntax-rules () ((_) y)))
     (gety)) 7))

;; --- let + intervening define before define-syntax ---
(test-equal "let binding with intervening define"
  7
  (let ((y 7))
    (define z 1)
    (define-syntax gety (syntax-rules () ((_) y)))
    (gety)))

;; --- Multiple captured locals ---
(test-equal "multiple let bindings captured"
  15
  (let ((a 5) (b 10))
    (define-syntax sum-ab (syntax-rules () ((_) (+ a b))))
    (sum-ab)))

;; --- Nested let scopes ---
(test-equal "inner let binding shadows outer in define-syntax"
  20
  (let ((x 10))
    (let ((x 20))
      (define-syntax getx (syntax-rules () ((_) x)))
      (getx))))

;; --- let-syntax parity: both should behave the same ---
(test-equal "let-syntax captures let binding (baseline)"
  7
  (let ((y 7))
    (let-syntax ((gety (syntax-rules () ((_) y))))
      (gety))))

;; --- Global reference still works ---
(define g 99)
(test-equal "global reference in define-syntax template"
  99
  (let ((y 7))
    (define-syntax getg (syntax-rules () ((_) g)))
    (getg)))

;; --- Internal define in procedure body still works ---
(test-equal "internal define captured by body define-syntax"
  7
  (let ()
    (define y 7)
    (define-syntax gety (syntax-rules () ((_) y)))
    (gety)))

(let ((runner (test-runner-current)))
  (test-end "define-syntax-capture")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
