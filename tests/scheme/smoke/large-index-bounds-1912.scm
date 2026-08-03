;;; Large-index bounds checking, and the cross-tier probe for kaappi#1912.
;;;
;;; Natively this is an ordinary regression test: an index far beyond any
;;; vector's length must raise, whether or not its low 32 bits happen to be in
;;; range.
;;;
;;; On wasm32 it is the probe for kaappi#1912. Index arguments are @intCast to
;;; usize INSIDE the bounds comparison, and usize is u32 there, so 2^32+1 wraps
;;; to 1 before the check, passes it, and aliases element 1 — a silent wrong
;;; read, and for vector-set! a silent wrong WRITE to a valid-but-unintended
;;; element. Measured (wasmtime 46.0.0, v0.22.1):
;;;
;;;     (vector-ref v 4294967297)   native: raised   wasm32: 11
;;;     (vector-set! v 4294967297 99) then (vector-ref v 1)
;;;                                 native: 11       wasm32: 99
;;;
;;; The 2^32+9 line is the discriminating control that makes this attributable
;;; to low-32-bit truncation rather than to a missing bounds check: its low 32
;;; bits are 9, which still exceeds the length 4, so it raises on BOTH tiers.
;;;
;;; run-wasm-differential.sh lists this file in KNOWN_DIFFS against #1912, so
;;; the divergence does not fail the run while the bug is open — and its STALE
;;; check reports the entry once the tiers agree again, which is the signal to
;;; delete both the entry and this note.
;;;
;;; Deliberately import-free so it runs on every tier — which is why this is
;;; the one file in the corpus that signals failure with a bare `(exit 1)`
;;; rather than the SRFI-64 epilogue every other file uses (kaappi#2116).
;;; `(import (srfi 64))` would make the WASM leg fail at library load
;;; (kaappi#2108, no .sld on WASM), and run-wasm-differential.sh classifies
;;; that as LIBDIFF — which would silently retire this file's KNOWN_DIFFS
;;; entry as stale and stop it tracking #1912 at all. The printed lines are
;;; unchanged and remain the cross-tier comparison channel; the exit status is
;;; the native verdict layered on top.

(define v (vector 10 11 12 13))

(define (try thunk) (guard (e (#t 'raised)) (thunk)))

;; 2^32+1 — low 32 bits are 1, which IS in range for a 4-element vector.
(define ref-big (try (lambda () (vector-ref v 4294967297))))
(display (list 'ref-2^32+1 ref-big))
(newline)

;; Control: 2^32+9 — low 32 bits are 9, still out of range. Raises everywhere.
(define ref-ctl (try (lambda () (vector-ref v 4294967305))))
(display (list 'ref-2^32+9 ref-ctl))
(newline)

;; The write side, which is the more serious half: element 1 must be untouched.
(define set-big (try (lambda () (vector-set! v 4294967297 99))))
(define elt1 (vector-ref v 1))
(display (list 'set-2^32+1 set-big 'elt1 elt1))
(newline)

;; Native verdict. On wasm32 these fail while #1912 is open, and the harness
;; suppresses that via KNOWN_DIFFS rather than this file pretending to pass.
(define failures 0)
(define (check ok name)
  (if (not ok)
      (begin
        (set! failures (+ failures 1))
        (display "FAIL: ")
        (display name)
        (newline))))

(check (eq? ref-big 'raised) "(vector-ref v 2^32+1) must raise")
(check (eq? ref-ctl 'raised) "(vector-ref v 2^32+9) must raise")
(check (eq? set-big 'raised) "(vector-set! v 2^32+1 99) must raise")
(check (= elt1 11) "element 1 must be untouched by the rejected set!")

(if (> failures 0) (exit 1))
