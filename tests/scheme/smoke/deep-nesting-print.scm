;; Regression test for #49: markCyclesRec depth guard
;; Deep nesting should print without crashing (stack overflow).
;;
;; Deliberately import-free, and therefore one of the few files that signals
;; failure with a bare `(exit 1)` rather than the SRFI-64 epilogue every other
;; file in the corpus uses (kaappi#2116). This file is listed in
;; run-wasm-differential.sh's KNOWN_DIFFS against kaappi#2107 — on wasm32 the
;; 200000-deep car nest was expected to exhaust the shadow stack and abort the
;; module. The bare top-level `(display ...)`/`(write ...)` below is the
;; measurement, so it stays free of a SRFI-64 suite that would consume those
;; forms rather than let them run at top level.
;;
;; Separately, and NOT caused by that: its KNOWN_DIFFS entry is already
;; reported STALE at e62b90eb with this file unmodified — on the current
;; wasmtime it no longer diverges, so #2107 may not reproduce here any more.
;; That is a pre-existing observation about the entry, not about this file's
;; shape; the entry is left in place for whoever owns #2107 to judge.
;;
;; Until #2116 this file had no verdict at all: it printed its length and
;; exited 0 whatever that length was, so a printer that truncated or
;; depth-capped would still have read as a pass.

(define (nest n acc) (if (= n 0) acc (nest (- n 1) (list acc))))

;; 200k deep nesting — previously overflowed the native stack in markCyclesRec
;; and in GC's markValue. Both now use iterative cdr-spine traversal.
(define deep (nest 200000 '()))

(define port (open-output-string))
(write deep port)
(define actual (string-length (get-output-string port)))

;; 200000 "(" + "()" + 200000 ")". Asserted exactly, not merely reported: a
;; truncating printer also "does not crash".
(define expected (+ 200000 2 200000))

(display "PASS: deep nesting printed without crash, length=")
(display actual)
(newline)

(if (not (= actual expected))
    (begin
      (display "FAIL: expected length ")
      (display expected)
      (display ", got ")
      (display actual)
      (newline)
      (exit 1)))
