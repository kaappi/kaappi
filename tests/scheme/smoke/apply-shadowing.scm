;; Regression test for #444:
;; apply tail-call optimization must respect local variable shadowing.

;; When 'apply' is shadowed by a local binding, calls to that binding
;; should treat it as a regular function call, not as the built-in apply.

(import (scheme base) (scheme write))

(define (test-apply-shadowed)
  (let ((apply +))
    (apply 1 2)))

(let ((result (test-apply-shadowed)))
  (if (= result 3)
      (display "PASS: shadowed apply uses local binding")
      (begin
        (display "FAIL: expected 3, got ")
        (display result)))
  (newline))

;; Non-tail position should also work
(define (test-apply-shadowed-non-tail)
  (let ((apply +))
    (let ((r (apply 10 20)))
      r)))

(let ((result (test-apply-shadowed-non-tail)))
  (if (= result 30)
      (display "PASS: shadowed apply in non-tail position")
      (begin
        (display "FAIL: expected 30, got ")
        (display result)))
  (newline))

;; Unshadowed apply should still work normally
(define (test-normal-apply)
  (apply + '(1 2 3)))

(let ((result (test-normal-apply)))
  (if (= result 6)
      (display "PASS: unshadowed apply works normally")
      (begin
        (display "FAIL: expected 6, got ")
        (display result)))
  (newline))
