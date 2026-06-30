;; Regression test for #543: tail calls inside let/let* bodies must be
;; optimized in the LLVM native backend. Without the fix, this overflows
;; the native stack instead of looping in O(1) space.
;;
;; This test runs in the interpreter (which already handles TCO correctly),
;; verifying the semantics. The LLVM backend fix ensures --emit-llvm
;; generates a loop back-edge instead of a plain call.

(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define-syntax check
  (syntax-rules ()
    ((_ name expr)
     (begin
       (display name)
       (display ": ")
       (if expr
         (begin (set! pass (+ pass 1)) (display "ok"))
         (begin (set! fail (+ fail 1)) (display "FAIL")))
       (newline)))))

;; Self-tail-call inside let body
(define (sum-let n acc)
  (if (= n 0)
      acc
      (let ((m (- n 1)))
        (sum-let m (+ acc n)))))

(check "let-tail-call" (= (sum-let 100000 0) 5000050000))

;; Self-tail-call inside let* body
(define (sum-let* n acc)
  (if (= n 0)
      acc
      (let* ((m (- n 1))
             (new-acc (+ acc n)))
        (sum-let* m new-acc))))

(check "let*-tail-call" (= (sum-let* 100000 0) 5000050000))

(display pass) (display " pass, ") (display fail) (display " fail")
(newline)
(when (> fail 0) (exit 1))
