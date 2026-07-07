;; Regression test for #1191: deeply nested native re-entrancy must not
;; panic with "GC root stack overflow" — the root buffer grows on demand.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "gc-root-growth")

;; Re-entrant promise forcing raises a catchable error
(define selfp (delay (force selfp)))
(test-assert "re-entrant force is catchable"
  (guard (e (#t #t)) (force selfp) #f))

;; Deeply nested native higher-order calls no longer panic.
;; In Release the root buffer grows and the call succeeds; in Debug the
;; native re-entrancy cap (200) fires first with a catchable error.
;; Both outcomes are acceptable — the key property is no @panic.
(define (deep n)
  (if (= n 0) 1
      (car (map (lambda (x) (deep (- n 1))) '(1)))))

(test-assert "deep nested map does not panic"
  (guard (e (#t #t))
    (eqv? (deep 2000) 1)))

(let ((runner (test-runner-current)))
  (test-end "gc-root-growth")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
