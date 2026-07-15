; Build-once cache for quoted heap constants (#1495).
;
; A quoted pair/vector literal has no immediate representation, so the native
; backend serializes it to a (quote …) form. Before #1495 that form was rebuilt
; by kaappi_eval on every evaluation, so a literal read twice was never eq? to
; itself — a divergence from the interpreter, which compiles a quote to a single
; constant-pool entry and returns the SAME object each time. The cache restores
; per-call-site sharing: build once, memoize, return the cached object.
(import (scheme base) (scheme write))

; Same literal, same call site, two evaluations: eq? in the interpreter, and now
; eq? natively too. This printed #f before the cache (a fresh rebuild each call).
(define (lst) '(1 2 3))
(display (eq? (lst) (lst)))
(newline)

; eqv? on the same literal follows eq? for heap objects (identity) — also #t.
(display (eqv? (lst) (lst)))
(newline)

; Quoted vector literals share the same path.
(define (vec) '#(4 5 6))
(display (eq? (vec) (vec)))
(newline)

; Two textually distinct occurrences are independent constants — distinct cache
; slots, so NOT eq?, matching the interpreter's separate constant-pool entries.
(display (eq? '(7 8) '(7 8)))
(newline)

; Build-once under load: every iteration of a hot self-tail loop sees the SAME
; object. A per-iteration rebuild would make some (eq? (lst) (lst)) return #f and
; flip the accumulator, so a #t here means the fast path stayed cached.
(define (hot n acc)
  (if (= n 0)
      acc
      (hot (- n 1) (and acc (eq? (lst) (lst))))))
(display (hot 10000 #t))
(newline)

; The cached value is structurally correct, not merely stable.
(display (lst))
(newline)
