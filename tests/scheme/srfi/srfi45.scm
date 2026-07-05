;; SRFI-45 (primitives for lazy evaluation) conformance tests — Phase 3c
;; The library currently exports only the R7RS names; lazy and eager are
;; missing (#1207). Iterative-forcing behavior itself is covered in depth
;; by tests/scheme/audit/primitives_lazy-audit.scm.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi45.scm

(import (scheme base) (srfi 45) (chibi test))

(test-begin "srfi-45")

;;; --- the R7RS-name surface works ---
(test 3 (force (delay (+ 1 2))))
(test #t (promise? (delay 1)))
(test #t (promise? (make-promise 1)))
(test 42 (force (delay-force (delay 42))))

;; memoization
(let ()
  (define count 0)
  (define p (delay (begin (set! count (+ count 1)) count)))
  (test 1 (force p))
  (test 1 (force p)))

;; bounded-space iterative forcing through delay-force chains
(letrec ((chain (lambda (n)
                  (if (= n 0) (delay 'done) (delay-force (chain (- n 1)))))))
  (test 'done (force (chain 10000))))

;;; --- SRFI-45's own names ---
;; "lazy: Takes an expression of type (Promise a) and returns a promise";
;; "eager: ... (eager expression) is equivalent to (let ((value expression))
;;  (delay value))"
;; FAIL: #1207 (lazy and eager are not exported from (srfi 45))
;; (test 1 (force (lazy (delay 1))))
;; FAIL: #1207 (lazy and eager are not exported from (srfi 45))
;; (test 2 (force (eager 2)))
;; FAIL: #1207 (lazy and eager are not exported from (srfi 45))
;; (test #t (promise? (eager 5)))

(test-end "srfi-45")
