;; A let-syntax macro bound under the name `quote` (R7RS lets a binding
;; shadow any keyword) whose template mutates an enclosing local, driven
;; through a re-entrant continuation (#1168's shape).
;;
;; The set! pre-scan cannot see this target early: the binding's name
;; derails a naive walk (kaappi#1802's let-syntax scan handles the spec
;; positions individually for exactly that reason), and at pre-scan time
;; the macro isn't registered yet, so the use site can't be expanded
;; either. Termination therefore depends on the late path: Part B
;; (scanSetTargets at real expansion) discovering the target and the
;; box_local transition boxing the already-bound local after the fact.
;; If that late-boxing self-heal ever regresses, this test hangs rather
;; than terminating at 3.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "quote-shadow-boxing")

(test-equal "quote-named macro's set! target is boxed late"
  3
  (let ((n 0) (k* #f))
    (let-syntax ((quote (syntax-rules () ((_) (set! n (+ n 1))))))
      (call/cc (lambda (k) (set! k* k)))
      (quote)
      (if (< n 3) (k* #f))
      n)))

;; Same shape but the shadowing macro also fires in result position, and
;; the template target is a literal global — exercises the spec-position
;; walk (the binding pair must not be misread as a quote form).
(test-equal "quote-named macro rebinding a global"
  3
  (let-syntax ((quote (syntax-rules () ((_) (set! + -)))))
    (define (f) (+ 5 2))
    (quote)
    (f)))

(let ((runner (test-runner-current)))
  (test-end "quote-shadow-boxing")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
