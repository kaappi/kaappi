;; Regression test for #845: guard re-raises unmatched conditions with
;; raise instead of raise-continuable

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "guard-continuable-845")

;; Non-continuable raise through non-matching guard should work
(test-equal "raise through a non-matching guard reaches the outer guard"
  'caught
  (guard (outer-c (#t 'caught))
    (guard (c (#f #f))
      (raise 'boom))))

;; raise-continuable through non-matching guard should not crash: the
;; handler's return value must come back as the value of raise-continuable.
(test-equal "raise-continuable through a non-matching guard stays continuable"
  100
  (with-exception-handler
    (lambda (e) 100)
    (lambda ()
      (guard (c (#f #f))
        (raise-continuable 'x)))))

(let ((runner (test-runner-current)))
  (test-end "guard-continuable-845")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
