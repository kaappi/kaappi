;; Regression test for #2035: the VM register file used to stop growing at
;; 4096 of its documented 65536 — a tail-position call replaced the frame in
;; place without re-ensuring room for the callee's locals, so 819 nested
;; dynamic-wind extents (or a pure-Scheme stand-in of the same shape)
;; aborted an ordinary program with a catchable KP9001 "internal error".
;; The file now grows to the cap (deep nesting returns normally); past it the
;; failure is the same uncatchable KP3008 as every other VM stack, and that
;; reporting half lives in tests/scheme/errors/error-format.sh.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "register-growth-2035")

;; Deep dynamic-wind nesting: each level consumes registers for the
;; dynamic-wind lambda, the before-thunk and the thunk frames, so this is
;; the shape that used to die at the 4096 cliff (depth 819). 10000 is
;; comfortably past the old cliff and still well inside the cap.
(test-equal "deep dynamic-wind nesting returns"
            'bottom
            (letrec ((nd (lambda (n) (if (= n 0) 'bottom
                                         (dynamic-wind (lambda () 1)
                                                       (lambda () (nd (- n 1)))
                                                       (lambda () 2))))))
              (nd 10000)))

;; Re-entrant promise forcing: the R7RS 4.2.5 *terminating* form re-enters
;; force on the same promise and must return — with the register file
;; growing, the recursion no longer dies early at a fixed cliff. The
;; unbounded `(delay (force p))` form is genuinely runaway recursion and is
;; reported as an uncatchable KP3008 stack overflow; that half lives in
;; tests/scheme/errors/error-format.sh.
(define selfp
  (let ((count 0))
    (delay (begin (set! count (+ count 1))
                  (if (> count 100) count (force selfp))))))
(test-assert "terminating re-entrant force returns"
  (eqv? 101 (force selfp)))

(let ((runner (test-runner-current)))
  (test-end "register-growth-2035")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
