;; Regression tests for constant folding with shadowed operators (issue #5)
;; tryConstantFold must not fold when the operator is locally rebound.
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "constant-fold-shadowing")

;; let-shadowed arithmetic
(test-eqv "let-shadowed +"
  2 (let ((+ (lambda (a b) (* a b)))) (+ 1 2)))

(test-eqv "let-shadowed -"
  10 (let ((- (lambda (a b) (+ a b)))) (- 3 7)))

(test-eqv "let-shadowed *"
  5 (let ((* (lambda (a b) (+ a b)))) (* 2 3)))

;; let-shadowed comparisons
(test-eq "let-shadowed <"
  'shadowed (let ((< (lambda (a b) 'shadowed))) (< 3 4)))

(test-eq "let-shadowed >"
  'shadowed (let ((> (lambda (a b) 'shadowed))) (> 4 3)))

(test-eq "let-shadowed <="
  'shadowed (let ((<= (lambda (a b) 'shadowed))) (<= 3 3)))

(test-eq "let-shadowed >="
  'shadowed (let ((>= (lambda (a b) 'shadowed))) (>= 3 3)))

(test-eq "let-shadowed ="
  'shadowed (let ((= (lambda (a b) 'shadowed))) (= 1 1)))

;; let-shadowed predicates
(test-eq "let-shadowed not"
  'mynot (let ((not (lambda (x) 'mynot))) (not #t)))

(test-eq "let-shadowed zero?"
  'custom (let ((zero? (lambda (x) 'custom))) (zero? 0)))

;; upvalue shadowing
(define (make-adder)
  (let ((+ (lambda (a b) (* a b))))
    (lambda () (+ 1 2))))
(test-eqv "upvalue-shadowed +" 2 ((make-adder)))

;; nested let shadowing
(test-eqv "nested let-shadowed +"
  0 (let ((+ (lambda (a b) 0))) (let ((x (+ 3 4))) x)))

;; lambda parameter shadowing
(test-eqv "lambda param-shadowed +"
  6 ((lambda (+) (+ 2 3)) (lambda (a b) (* a b))))

;; unshadowed still folds correctly
(test-eqv "unshadowed + still folds" 3 (+ 1 2))
(test-eqv "unshadowed * still folds" 6 (* 2 3))
(test-assert "unshadowed < still folds" (< 1 2))
(test-eq "unshadowed not still folds" #f (not #t))
(test-assert "unshadowed zero? still folds" (zero? 0))

(let ((result (+ %test-fail-count 0)))
  (test-end "constant-fold-shadowing")
  (if (> result 0) (exit 1)))
