;; SRFI-254 — Ephemerons and Guardians conformance test.
;;
;; API behaviour plus end-to-end weak-reference semantics. A single `churn!`
;; allocates a little over the default GC threshold (8192 objects) to force a
;; couple of collections, which is enough to break every unreachable-key
;; ephemeron and resurrect every unreachable guarded object at once. It is kept
;; to one modest loop so the Debug build (which traces every allocation) stays
;; well under the per-file timeout. Deterministic GC break/resurrection is also
;; covered in src/tests_srfi254.zig.

(import (scheme base) (scheme write) (srfi 254))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define (check-true name val)
  (if val
      (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

(define (check-false name val)
  (if (not val)
      (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;; Allocate ~20000 short-lived pairs — comfortably past the 8192-object GC
;; threshold, so at least two collections run.
(define (churn!)
  (do ((i 0 (+ i 1))) ((= i 10000)) (list i i)))

;; --- Pure API (no collection needed) ---------------------------------------

(define e (make-ephemeron 'k 'v))
(check-true "ephemeron?" (ephemeron? e))
(check-false "not-ephemeron symbol" (ephemeron? 'x))
(check-false "fresh not broken" (ephemeron-broken? e))
(check "ephemeron-key" (ephemeron-key e) 'k)
(check "ephemeron-value" (ephemeron-value e) 'v)
(check "ephemeron-ref hit" (ephemeron-ref e 'k) 'v)
(check "ephemeron-ref miss default" (ephemeron-ref e 'nope 'd) 'd)
(check-false "ephemeron-ref miss no default" (ephemeron-ref e 'nope))

(define g (make-guardian))
(check-true "guardian?" (guardian? g))
(check-true "guardian is a procedure" (procedure? g))
(check-false "guardian not transport" (transport-cell-guardian? g))
(check-false "empty guardian yields #f" (g))

(define tg (make-transport-cell-guardian))
(check-true "transport-cell-guardian?" (transport-cell-guardian? tg))
(check-false "transport guardian not object guardian" (guardian? tg))
(define c (tg 'tk 'tv))
(check-true "transport-cell?" (transport-cell? c))
(check "transport-cell-key" (transport-cell-key c) 'tk)
(check "transport-cell-value" (transport-cell-value c) 'tv)
(check-false "transport-cell not broken" (transport-cell-broken? c))

(define o (list 1 2 3))
(define h0 (current-hash o))
(check-true "current-hash is an integer" (integer? h0))
(check-true "current-hash non-negative" (>= h0 0))
(check-true "current-hash stable for eq? object" (= h0 (current-hash o)))

;; --- Register everything that a collection must resolve ---------------------

(define live-key (list 'live))
(define e-live (make-ephemeron live-key 'kept))      ; key stays reachable
(define e-dead (make-ephemeron (list 'dead) 'gone))  ; key only via ephemeron
(define e-cycle                                      ; value references key
  (let ((k (list 'cyclic))) (make-ephemeron k (list k))))
(g (list 'finalize-me))                              ; unreachable → resurrected
(define keep (list 'keep))
(g keep)                                             ; reachable → not resurrected
(define g2 (make-guardian))
(g2 (list 'obj) 'representative)                     ; (obj rep) form

;; --- One collection cycle resolves all of the above ------------------------

(churn!)

;; Ephemerons
(check-false "live-key not broken" (ephemeron-broken? e-live))
(check "live-key value kept" (ephemeron-ref e-live live-key) 'kept)
(check-true "dead-key ephemeron breaks" (ephemeron-broken? e-dead))
(check-false "broken key is #f" (ephemeron-key e-dead))
(check-true "value->key ephemeron breaks (weak-pair failure case)"
            (ephemeron-broken? e-cycle))

;; Guardians
(let ((got (g)))
  (check-true "guardian resurrects unreachable object"
              (and (pair? got) (eq? (car got) 'finalize-me))))
(check-false "reachable object not resurrected" (g))
(check "guardian returns representative" (g2) 'representative)

;; Transport cells never move on this collector.
(check-false "transport guardian yields nothing" (tg))
(check-false "transport cell still not broken" (transport-cell-broken? c))

;; current-hash is stable across the collection.
(check-true "current-hash survives collection" (= h0 (current-hash o)))

;; reference-barrier returns (unspecified) without error.
(reference-barrier o)
(check-true "reference-barrier returns" #t)

(display pass) (display " passed, ") (display fail) (display " failed") (newline)
(if (> fail 0) (error "SRFI 254 tests failed" fail))
