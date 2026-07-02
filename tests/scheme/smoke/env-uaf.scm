;; Regression test for #867: GC frees (environment ...) map still referenced
;; by eval'd closures via Function.env — use-after-free.
;;
;; A closure produced by (eval expr (environment ...)) must keep the
;; environment's binding map alive even after the environment object
;; becomes otherwise unreachable.

(define f (eval '(begin (define secret 42) (lambda () secret))
                (environment '(scheme base))))

;; Environment object is now unreachable; churn to force collections
;; and reuse of the freed map memory.
(define junk
  (let churn ((n 200000) (acc '()))
    (if (= n 0) acc (churn (- n 1) (cons n acc)))))

(display (= (f) 42))
(newline)
