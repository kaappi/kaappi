;; Regression test for #206: fiber scheduler slot exhaustion.
;; Spawns 100 fibers over the program's lifetime, more than the fiber
;; table's original fixed 64-slot cap (since removed — KEP-0001 Phase 2,
;; kaappi/kaappi#1440 — but slot reuse remains worth testing so completed
;; fibers don't grow the table unboundedly).

(import (scheme base)
        (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ")
        (display name)
        (display " got=")
        (write got)
        (display " expected=")
        (write expected)
        (newline))))

;; Spawn 100 fibers sequentially, each completing before the next.
;; Exercises slot reclamation (addFiber reuses a completed/errored slot
;; before growing the table).
(define results '())
(let loop ((i 0))
  (when (< i 100)
    (let ((f (spawn (lambda () (* i 2)))))
      (set! results (cons (fiber-join f) results)))
    (loop (+ i 1))))

(check "fiber-count" (length results) 100)
(check "first-result" (car results) 198)
(check "last-result" (list-ref results 99) 0)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
