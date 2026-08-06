;; Regression test for #1191: deeply nested native re-entrancy must not
;; panic with "GC root stack overflow" — the root buffer grows on demand.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "gc-root-growth")

;; Re-entrant promise forcing: the R7RS 4.2.5 *terminating* form re-enters
;; force on the same promise and must return (the register file grows rather
;; than dying at a fixed cliff — #2035). The unbounded `(delay (force p))`
;; form is runaway recursion and correctly dies as an uncatchable KP3008
;; stack overflow; that half lives in tests/scheme/errors/error-format.sh.
(define selfp
  (let ((count 0))
    (delay (begin (set! count (+ count 1))
                  (if (> count 100) count (force selfp))))))
(test-assert "terminating re-entrant force returns"
  (eqv? 101 (force selfp)))

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
