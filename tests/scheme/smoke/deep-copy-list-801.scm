;; Regression test for issue #801: gc_deep_copy deepCopyValue recursed on the
;; cdr spine, so deep-copying a flat list of ~15k+ elements across an SRFI-18
;; thread boundary overflowed the native stack and killed the whole process.
;; Deep copy runs at thread-start! (thunk closure upvalues) and at thread-join!
;; (result), so both directions are exercised. Without the fix this crashes
;; with a Bus error (non-zero exit); with it, both joins return 100000.
(import (scheme base) (scheme write) (srfi 18))

(define (make-long-list n)
  (let loop ((i 0) (acc '()))
    (if (= i n) acc (loop (+ i 1) (cons i acc)))))

;; Direction 1: closure upvalue deep-copied into the child at thread-start!.
(define t1
  (let ((lst (make-long-list 100000)))
    (make-thread (lambda () (length lst)))))
(define r1 (begin (thread-start! t1) (thread-join! t1)))

;; Direction 2: result deep-copied back to the parent at thread-join!.
(define t2 (make-thread (lambda () (make-long-list 100000))))
(define r2 (begin (thread-start! t2) (length (thread-join! t2))))

(if (and (= r1 100000) (= r2 100000))
    (begin (display "ok") (newline))
    (begin (display "FAIL: ") (display r1) (display " ") (display r2) (newline)
           (exit 1)))
