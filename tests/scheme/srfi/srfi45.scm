;; SRFI-45 (primitives for lazy evaluation) conformance tests — Phase 3c
;; The library currently exports only the R7RS names; lazy and eager are
;; missing (#1207). Iterative-forcing behavior itself is covered in depth
;; by tests/scheme/audit/primitives_lazy-audit.scm.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi45.scm

(import (scheme base) (srfi 45) (scheme process-context) (srfi 64))

(test-begin "srfi-45")

;;; --- the R7RS-name surface works ---
(test-equal 3 (force (delay (+ 1 2))))
(test-equal #t (promise? (delay 1)))
(test-equal #t (promise? (make-promise 1)))
(test-equal 42 (force (delay-force (delay 42))))

;; memoization
(let ()
  (define count 0)
  (define p (delay (begin (set! count (+ count 1)) count)))
  (test-equal 1 (force p))
  (test-equal 1 (force p)))

;; bounded-space iterative forcing through delay-force chains
(letrec ((chain (lambda (n)
                  (if (= n 0) (delay 'done) (delay-force (chain (- n 1)))))))
  (test-equal 'done (force (chain 10000))))

;;; --- SRFI-45's own names ---
;; "lazy: Takes an expression of type (Promise a) and returns a promise";
;; "eager: ... (eager expression) is equivalent to (let ((value expression))
;;  (delay value))"
(test-equal 1 (force (lazy (delay 1))))
(test-equal 2 (force (eager 2)))
(test-equal #t (promise? (eager 5)))

(let ((runner (test-runner-current)))
  (test-end "srfi-45")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
