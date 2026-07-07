;; Regression test for #1191: deeply nested native re-entrancy must not
;; panic with "GC root stack overflow" — the root buffer grows on demand.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "gc-root-growth")

;; Re-entrant promise forcing raises a catchable error
(define selfp (delay (force selfp)))
(test-assert "re-entrant force is catchable"
  (guard (e (#t #t)) (force selfp) #f))

;; Deeply nested native higher-order calls succeed (root buffer grows)
(define (deep n)
  (if (= n 0) 1
      (car (map (lambda (x) (deep (- n 1))) '(1)))))

(test-equal "deep nested map 2000" 1 (deep 2000))

(let ((runner (test-runner-current)))
  (test-end "gc-root-growth")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
