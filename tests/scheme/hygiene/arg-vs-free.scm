;; Regression test for #1288: use-site macro argument mis-resolved
;; to a captured def-site local of the same name.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "arg-vs-free")

;; Core bug: pattern variable substitution carries use-site `y` (100),
;; but the template free reference `y` must bind to the def-site `y` (7).
(test-equal "define-syntax: arg same name as captured local"
  107
  (let ((y 7))
    (define-syntax m (syntax-rules () ((_ x) (+ x y))))
    (let ((y 100))
      (m y))))

(test-equal "let-syntax: arg same name as captured local"
  107
  (let ((y 7))
    (let-syntax ((m (syntax-rules () ((_ x) (+ x y)))))
      (let ((y 100))
        (m y)))))

;; Multiple captured locals, one collides with the argument
(test-equal "two captured locals, arg collides with one"
  112
  (let ((a 5) (b 7))
    (define-syntax m (syntax-rules () ((_ x) (+ x a b))))
    (let ((b 100))
      (m b))))

;; Argument collides with captured local used in binding position
(test-equal "captured local in template let, arg collision"
  107
  (let ((x 7))
    (define-syntax m (syntax-rules () ((_ y) (let ((z y)) (+ z x)))))
    (let ((x 100))
      (m x))))

;; No collision (baseline — should already work)
(test-equal "no name collision"
  107
  (let ((y 7))
    (define-syntax m (syntax-rules () ((_ x) (+ x y))))
    (m 100)))

;; Argument is a complex expression, not a bare symbol
(test-equal "complex arg, no collision"
  110
  (let ((y 7))
    (define-syntax m (syntax-rules () ((_ x) (+ x y))))
    (let ((y 100))
      (m (+ y 3)))))

(let ((runner (test-runner-current)))
  (test-end "arg-vs-free")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
