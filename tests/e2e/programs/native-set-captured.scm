; #1422 regression: a captured binding mutated AFTER the closure is created
; must be visible through the closure (by-location semantics), not snapshotted
; by value at closure-creation time.

; The inner lambda captures u; the sibling argument set!s u before the call.
(define (f0 u) ((lambda (a) (+ u a)) (let ((b 5)) (set! u 90) b)))
(display (f0 1)) (newline)              ; 95  (reads u=90 through the box, + 5)

; Retained-closure variant: set! the captured binding, then call the closure.
(define (make u)
  (let ((get (lambda () u)))
    (set! u 90)
    (get)))
(display (make 1)) (newline)            ; 90

; Double nesting: the box pointer threads through two closure layers.
(define (outer u)
  (lambda (v)
    (set! u (+ u v))
    (lambda () u)))
(define step (outer 1))
(define r1 (step 10))                    ; u := 11
(display (r1)) (display " ")             ; 11
(define r2 (step 100))                   ; u := 111 (same box)
(display (r2)) (newline)                 ; 111
