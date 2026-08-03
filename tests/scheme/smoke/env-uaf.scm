;; Regression test for #867: GC frees (environment ...) map still referenced
;; by eval'd closures via Function.env — use-after-free.
;;
;; A closure produced by (eval expr (environment ...)) must keep the
;; environment's binding map alive even after the environment object
;; becomes otherwise unreachable.

(import (scheme base) (scheme eval) (scheme process-context) (srfi 64))

(test-begin "env-uaf")

(define f (eval '(let ((secret 42)) (lambda () secret))
                (environment '(scheme base))))

;; Environment object is now unreachable; churn to force collections
;; and reuse of the freed map memory.
(define junk
  (let churn ((n 200000) (acc '()))
    (if (= n 0) acc (churn (- n 1) (cons n acc)))))

(test-equal "closure from a collected (environment ...) still reads its binding"
            42 (f))

(let ((runner (test-runner-current)))
  (test-end "env-uaf")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
