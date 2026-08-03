;;; Cross-tier canary for the printer's car-recursion depth (audit v2, Phase 4D).
;;;
;;; `printer.zig` bounds its car-recursion at MAX_PRINT_DEPTH = 1024 and walks
;;; the cdr spine iteratively, so a deep proper list costs no stack while a
;;; deep CAR nest costs one frame per level. That bound is only safe if the
;;; target's stack can hold 1024 such frames.
;;;
;;; On wasm32 it cannot: `write` of an 848-deep car nest exhausts the shadow
;;; stack and aborts the module with an out-of-bounds memory access, before the
;;; 1024 guard can fire and with no Kaappi diagnostic (kaappi#2107 — the guard
;;; is calibrated to the 64 MB stack build.zig gives every NATIVE executable;
;;; wasm_exe is the one with no stack_size set). Its sibling
;;; deep-nesting-print.scm nests 200000 deep and so aborts there outright; it
;;; is listed in run-wasm-differential.sh's KNOWN_DIFFS until #2107 is fixed.
;;;
;;; This file is the positive control that stays green on BOTH tiers, so the
;;; differential keeps watching the margin instead of only the known failure.
;;; Depth 500 is deliberate: comfortably under the measured 847 cliff (a ~40%
;;; margin, so it cannot flake on a runtime whose frame layout differs
;;; slightly), and comfortably under MAX_PRINT_DEPTH, so it exercises real
;;; recursion rather than the truncation path. A change that materially grows
;;; the per-frame cost, shrinks the WASM stack, or raises MAX_PRINT_DEPTH shows
;;; up here as a tier divergence rather than silently eating the headroom.
;;;
;;; Deliberately import-free so it costs nothing on the other tiers — which is
;;; also why it signals failure with a bare `(exit 1)` rather than the SRFI-64
;;; epilogue every other file in the corpus uses (kaappi#2116).
;;; `(import (srfi 64))` would make the WASM leg fail at library load
;;; (kaappi#2108, no .sld on WASM), and run-wasm-differential.sh classifies
;;; that as LIBDIFF — which would stop this file being the cross-tier control
;;; it exists to be. The printed PASS/FAIL lines are the cross-tier comparison
;;; channel and are unchanged; the exit status is the verdict layered on top.
;;; Until #2116 it had no verdict at all: both checks below printed `FAIL:`
;;; and exited 0, which neither runner reads as a failure.

(define failures 0)

(define (nest n acc) (if (= n 0) acc (nest (- n 1) (list acc))))

(define depth 500)

;; Depth 500 renders as 500 open parens + "()" + 500 close parens.
(define expected (+ 500 2 500))

(define port (open-output-string))
(write (nest depth '()) port)
(define actual (string-length (get-output-string port)))

(if (= actual expected)
    (begin (display "PASS: car-nested write at depth 500, length=")
           (display actual)
           (newline))
    (begin (set! failures (+ failures 1))
           (display "FAIL: car-nested write at depth 500 — expected length ")
           (display expected)
           (display ", got ")
           (display actual)
           (newline)))

;; The cdr spine is walked iteratively, so this is 400x more pairs at O(1)
;; stack. It is the control that keeps the assertion above attributable to
;; recursion DEPTH rather than to structure size.
(define (mk n acc) (if (= n 0) acc (mk (- n 1) (cons 1 acc))))
(define flat-port (open-output-string))
(write (mk 200000 '()) flat-port)
(if (= (string-length (get-output-string flat-port)) 400001)
    (begin (display "PASS: cdr-nested write of 200000 pairs") (newline))
    (begin (set! failures (+ failures 1))
           (display "FAIL: cdr-nested write of 200000 pairs") (newline)))

(if (> failures 0) (exit 1))
