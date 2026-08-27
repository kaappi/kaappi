;; GC generational minor mark (#1961): a minor collection marks only the
;; young generation plus the remembered set of old objects that point into
;; it. End-to-end guards for the three loads that makes load-bearing —
;; guardian registration (an old guardian holding a young entry), the
;; running main fiber's parameter overrides, and a large old heap left
;; intact while young garbage churns. The deterministic pins live in
;; src/tests_gc_tracing.zig and src/tests_scheduler.zig.
(import (scheme base) (scheme write) (kaappi fibers) (srfi 254))

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

;; Allocation churn: enough transient pairs to drive several collections
;; (the initial threshold is 8192 objects), promoting whatever survives.
(define (churn n)
  (let loop ((i 0))
    (when (< i n) (cons i i) (loop (+ i 1)))))

;; 1. An old guardian registering a young object (#1961 Gap 1): the
;; registration barrier puts the guardian in the remembered set, so the
;; minor mark still probes the entry, resurrects the dead object, and keeps
;; it alive until retrieval — with its contents intact.
(define g (make-guardian))
(churn 30000) ; promote the guardian before registering anything
(let ((obj (vector 'a 'b 'c)))
  (g obj)
  (set! obj #f)) ; the guardian's weak entry is now the only reference
(churn 30000) ; minors while an old guardian holds a young entry
(let ((got (g)))
  (check "guardian entry resurrected intact across minors"
    (and (vector? got) (vector-ref got 1))
    'b))
(check "guardian queue drained" (g) #f)

;; 2. The running main fiber's parameter overrides (#1961 Gap 3): with a
;; scheduler present, parameterize stores into the (by now promoted) main
;; fiber's override map — reachable in a minor collection only through the
;; fiber's explicit mutable-state marking and the store's write barrier.
(define p (make-parameter 1))
(churn 30000) ; promote the main fiber
(parameterize ((p (vector 42)))
  (churn 30000) ; minors while the override holds a young vector
  (check "parameterized value survives minor collections"
    (vector-ref (p) 0)
    42))
(check "parameter restored after dynamic extent" (p) 1)

;; 3. A large old heap stays intact while young garbage churns around it.
(define old-data
  (let loop ((i 0) (acc '()))
    (if (= i 50000) acc (loop (+ i 1) (cons i acc)))))
(churn 60000)
(check "old heap length intact" (length old-data) 50000)
(check "old heap contents intact" (car old-data) 49999)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "gc-generational-minor-1961 tests failed" fail))
