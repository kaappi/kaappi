;; Probe: boolean simplification (ir.simplifyBooleans).
;;
;; The pass rewrites `(if (not X) A B)` into `(if X B A)`.  Two things can go
;; wrong and only show up against `--no-ir-opt`:
;;   1. the arms get swapped the wrong way round;
;;   2. `X` is evaluated a different number of times, or its side effects
;;      move relative to the surrounding forms.
;; The one-armed case `(if (not X) A)` is the sharp edge: rewriting it needs
;; an alternate synthesised out of nothing.

(define seen '())
(define (note! tag v) (set! seen (cons tag seen)) v)

;; --- plain arm swap ------------------------------------------------------
(if (not #f) (begin (display "nf-then") (newline)) (begin (display "nf-else") (newline)))
(if (not #t) (begin (display "nt-then") (newline)) (begin (display "nt-else") (newline)))
(if (not (= 1 2)) (begin (display "ne-then") (newline)) (begin (display "ne-else") (newline)))
(if (not (= 1 1)) (begin (display "eq-then") (newline)) (begin (display "eq-else") (newline)))

;; --- one-armed `if` under `not`: the alternate has to be synthesised -----
(if (not #f) (begin (display "onearm-ran") (newline)))
(if (not #t) (begin (display "ONEARM-WRONG") (newline)))
(display (if (not #t) 'yes)) (newline)
(write (if (not #t) 'yes)) (newline)

;; --- double negation -----------------------------------------------------
(if (not (not #t)) (begin (display "dn-then") (newline)) (begin (display "dn-else") (newline)))
(if (not (not (not #t))) (begin (display "tn-then") (newline)) (begin (display "tn-else") (newline)))

;; --- the test's side effect must fire exactly once, in place ------------
(if (not (note! 'a #f)) (begin (display "side-then") (newline)) (begin (display "side-else") (newline)))
(if (not (note! 'b #t)) (begin (display "side2-then") (newline)) (begin (display "side2-else") (newline)))
(display (reverse seen)) (newline)

;; --- `not` shadowed by a user binding: the rewrite MUST NOT fire ---------
;; ir.isRedefined("not") is the guard.  If it misses, the arms swap against
;; a `not` that no longer means negation.
(define (not x) 'always-truthy)
(if (not #f) (begin (display "shadowed-then") (newline)) (begin (display "shadowed-else") (newline)))
(if (not #t) (begin (display "shadowed2-then") (newline)) (begin (display "shadowed2-else") (newline)))
