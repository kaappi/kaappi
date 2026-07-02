;; Regression test for #684: LLVM backend must respect parameter shadowing
;; in call position.

;; A global function 'f' that the LLVM backend will try to call directly
(define (f x)
  (if (< x 1) 99 (f (- x 1))))

;; 'apply-twice' takes a parameter named 'f' that shadows the global 'f'
(define (apply-twice f x)
  (f (f x)))

;; Should call the lambda, not the global f
(define result (apply-twice (lambda (y) (+ y 1)) 5))
(unless (= result 7)
  (display "FAIL: expected 7, got ")
  (display result)
  (newline)
  (exit 1))

;; Another case: higher-order with shadowed name
(define (add a b) (+ a b))
(define (apply-op add x y)
  (add x y))
(define result2 (apply-op * 3 4))
(unless (= result2 12)
  (display "FAIL: expected 12, got ")
  (display result2)
  (newline)
  (exit 1))

(display "PASS")
(newline)
