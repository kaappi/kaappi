;; SRFI-254 — Ephemerons and Guardians conformance test.
;;
;; API behaviour plus end-to-end weak-reference semantics: collections are
;; forced by allocating enough garbage to cross the GC threshold many times.

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

;; Allocate a lot of short-lived garbage to force many collections.
(define (churn!)
  (do ((i 0 (+ i 1))) ((= i 200000)) (list i i)))

;; --- Ephemerons ------------------------------------------------------------

(define e (make-ephemeron 'k 'v))
(check-true "ephemeron?" (ephemeron? e))
(check-false "not-ephemeron symbol" (ephemeron? 'x))
(check-false "fresh not broken" (ephemeron-broken? e))
(check "ephemeron-key" (ephemeron-key e) 'k)
(check "ephemeron-value" (ephemeron-value e) 'v)
(check "ephemeron-ref hit" (ephemeron-ref e 'k) 'v)
(check "ephemeron-ref miss default" (ephemeron-ref e 'nope 'd) 'd)
(check-false "ephemeron-ref miss no default" (ephemeron-ref e 'nope))

;; A live key keeps the ephemeron intact across collections.
(define live-key (list 'live))
(define e-live (make-ephemeron live-key 'kept))
(churn!)
(check-false "live-key not broken" (ephemeron-broken? e-live))
(check "live-key value kept" (ephemeron-ref e-live live-key) 'kept)

;; A key reachable only through the ephemeron is reclaimed → broken.
(define e-dead (make-ephemeron (list 'dead) 'gone))
(churn!)
(check-true "dead-key ephemeron breaks" (ephemeron-broken? e-dead))
(check-false "broken key is #f" (ephemeron-key e-dead))

;; The value referencing the key still breaks (the weak-pair failure case).
(define e-cycle
  (let ((k (list 'cyclic)))
    (make-ephemeron k (list k))))  ; value references key
(churn!)
(check-true "value->key ephemeron breaks" (ephemeron-broken? e-cycle))

;; --- Guardians -------------------------------------------------------------

(define g (make-guardian))
(check-true "guardian?" (guardian? g))
(check-true "guardian is a procedure" (procedure? g))
(check-false "guardian not transport" (transport-cell-guardian? g))
(check-false "empty guardian yields #f" (g))

;; Register an object reachable only through the guardian; after collection it
;; is resurrected and handed back.
(g (list 'finalize-me))
(churn!)
(let ((got (g)))
  (check-true "guardian resurrects unreachable object" (pair? got))
  (check "resurrected contents" (car got) 'finalize-me))
(check-false "guardian empty again" (g))

;; A still-reachable registered object is NOT resurrected.
(define keep (list 'keep))
(g keep)
(churn!)
(check-false "reachable object not resurrected" (g))

;; The two-argument (obj rep) form returns the representative.
(define g2 (make-guardian))
(g2 (list 'obj) 'representative)
(churn!)
(check "guardian returns representative" (g2) 'representative)

;; --- Transport cell guardians ----------------------------------------------

(define tg (make-transport-cell-guardian))
(check-true "transport-cell-guardian?" (transport-cell-guardian? tg))
(check-false "transport guardian not object guardian" (guardian? tg))
(define c (tg 'tk 'tv))
(check-true "transport-cell?" (transport-cell? c))
(check "transport-cell-key" (transport-cell-key c) 'tk)
(check "transport-cell-value" (transport-cell-value c) 'tv)
(check-false "transport-cell not broken" (transport-cell-broken? c))
;; Keys never move on this collector, so nothing is ever transported.
(churn!)
(check-false "transport guardian yields nothing" (tg))
(check-false "transport cell still not broken" (transport-cell-broken? c))

;; --- current-hash ----------------------------------------------------------

(define o (list 1 2 3))
(check-true "current-hash is an integer" (integer? (current-hash o)))
(check-true "current-hash non-negative" (>= (current-hash o) 0))
(check-true "current-hash stable for eq? object" (= (current-hash o) (current-hash o)))
(check-true "current-hash survives collection"
            (let ((h (current-hash o))) (churn!) (= h (current-hash o))))

;; --- reference-barrier -----------------------------------------------------

(reference-barrier o)
(check-true "reference-barrier returns" #t)

(display pass) (display " passed, ") (display fail) (display " failed") (newline)
(if (> fail 0) (error "SRFI 254 tests failed" fail))
