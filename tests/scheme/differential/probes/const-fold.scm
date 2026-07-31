;; Probe: IR constant folding (ir.foldConstants).
;;
;; Every form is at TOP-LEVEL EXPRESSION position, which is the only position
;; the five IR optimisation passes reach — a `define`/`lambda` body lowers to
;; an opaque `passthrough` node and is never visited.  Under the default
;; pipeline these calls collapse to `(constant ...)`; under `--no-ir-opt` they
;; stay live calls dispatched by the VM.  Both tiers must print the same bytes.
;;
;; Verify a probe is actually non-vacuous with:
;;   diff <(kaappi ir F) <(kaappi ir --no-opt F)

;; --- unary and binary folds over fixnums --------------------------------
(display (+ 1 2)) (newline)
(display (- 10 4)) (newline)
(display (* 6 7)) (newline)
(display (- 5)) (newline)

;; --- comparison folds ----------------------------------------------------
(display (< 1 2)) (newline)
(display (> 1 2)) (newline)
(display (= 3 3)) (newline)
(display (<= 3 3)) (newline)
(display (>= 2 3)) (newline)

;; --- boolean / predicate folds ------------------------------------------
(display (not #f)) (newline)
(display (not #t)) (newline)
(display (zero? 0)) (newline)
(display (even? 4)) (newline)
(display (odd? 4)) (newline)

;; --- fixnum boundary: a fold must promote to bignum exactly as the VM does
;; 2^47-1 is the top of the fixnum range (types.zig tagged representation).
(display (+ 140737488355327 1)) (newline)
(display (- 0 140737488355328)) (newline)
(display (* 4611686018427387904 4)) (newline)
(display (expt 2 100)) (newline)

;; --- exactness must survive the fold ------------------------------------
(display (exact? (* 6 7))) (newline)
(display (/ 1 3)) (newline)
(display (exact? (/ 1 3))) (newline)
(display (+ 1 2.0)) (newline)
(display (exact? (+ 1 2.0))) (newline)

;; --- error ORDER relative to the folds above.  If the optimiser evaluated a
;; foldable form at compile time and the VM evaluates it at run time, the error
;; moves relative to the surrounding `display`s — a stdout diff, not just a
;; stderr one.  That is the point of putting it last.
;;
;; The raising form here is deliberately NOT `(/ 1 0)`: a division-by-zero (or
;; any other error located only by `Function.source_line`) also trips the
;; separate cold-vs-warm cache divergence that
;; probes/cache-error-location.scm exists to pin down.  Keeping the two apart
;; means this file stays green and keeps checking the folds.
(display "before-error") (newline)
(display (vector-ref (vector 1 2) 9)) (newline)
(display "after-error") (newline)
