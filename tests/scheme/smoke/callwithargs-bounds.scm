;; Regression tests for callWithArgs bounds checking
;; Issue #366: register bounds check used args.len instead of locals_count
;; Issue #367: @intCast to u8 panics when args.len > 255

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "callwithargs-bounds")

;; Test 1: call-with-values with many values (>255) should not panic. Either
;; outcome is a pass — a clean raise or a successful call — because what #367
;; did was abort the process, which neither branch below can reach.
(test-assert ">255 values do not panic the VM"
             (guard (e (#t 'raised))
               (call-with-values
                 (lambda () (apply values (make-list 300 #t)))
                 (lambda args (length args)))))

;; Test 2: A closure with many locals called via apply should work
(define (many-locals x)
  (let* ((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7) (h 8)
         (i 9) (j 10) (k 11) (l 12) (m 13) (n 14) (o 15) (p 16))
    (+ x a b c d e f g h i j k l m n o p)))

(test-equal "many-locals via apply" 136 (apply many-locals '(0)))

;; Test 3: map with a closure that has many locals
(define (transform val)
  (let* ((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7) (h 8))
    (+ val a b c d e f g h)))

(test-equal "map with many-locals closure" '(36 46 56) (map transform '(0 10 20)))

(let ((runner (test-runner-current)))
  (test-end "callwithargs-bounds")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
