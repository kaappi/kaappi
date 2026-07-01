;; Regression test for #646: referencesYoung .fiber case omits
;; handler_stack, wind_stack, param_overrides, and frame.native.
;;
;; Exercises fibers with closures and allocation across yield to stress
;; the GC remembered-set pruning path.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers))

(define pass 0)
(define fail 0)

(define (check name expected actual)
  (display name)
  (display ": ")
  (if (equal? expected actual)
    (begin (set! pass (+ pass 1)) (display "ok"))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL - expected ")
      (write expected)
      (display " got ")
      (write actual)))
  (newline))

;; Test 1: Fiber closures survive GC across multiple yields
;; The closure captures a freshly-allocated list, yields, allocates more,
;; then yields again. If the remembered set incorrectly prunes the fiber,
;; the captured list may be collected.
(let ((f (spawn (lambda ()
                  (let ((data (list 1 2 3 4 5)))
                    (yield)
                    (let ((more (list 6 7 8 9 10)))
                      (yield)
                      (append data more)))))))
  (check "closure data survives yield+GC"
         '(1 2 3 4 5 6 7 8 9 10)
         (fiber-join f)))

;; Test 2: Multiple fibers with captured closures and allocation pressure
(let ((ch (make-channel)))
  (let ((f1 (spawn (lambda ()
                     (let ((v (make-vector 100 0)))
                       (yield)
                       (vector-set! v 0 42)
                       (channel-send ch (vector-ref v 0))))))
        (f2 (spawn (lambda ()
                     (let ((s (make-string 50 #\x)))
                       (yield)
                       (channel-send ch (string-length s)))))))
    (let ((r1 (channel-receive ch))
          (r2 (channel-receive ch)))
      (fiber-join f1)
      (fiber-join f2)
      (check "fiber vector survives GC" 42 r1)
      (check "fiber string survives GC" 50 r2))))

;; Test 3: Deeply nested closures in fiber survive remembered-set pruning
(let ((f (spawn (lambda ()
                  (let* ((a (list 'a))
                         (b (cons 'b a))
                         (c (cons 'c b)))
                    (yield)
                    (let* ((d (cons 'd c))
                           (e (cons 'e d)))
                      (yield)
                      e))))))
  (check "nested cons chain survives yield+GC"
         '(e d c b a)
         (fiber-join f)))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
