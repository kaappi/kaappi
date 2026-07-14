; Assignment conversion / boxing of captured+mutated variables (#1497).
; Each shape below compiles natively (the captured, mutated binding becomes a
; heap box) and must match the interpreter's by-location closure semantics.

; --- Counter via let: captured+mutated let-local ---
(define (make-counter)
  (let ((n 0))
    (lambda () (set! n (+ n 1)) n)))
(define c (make-counter))
(display (c)) (display (c)) (display (c)) (newline)   ; 123

; --- Accumulator: captured+mutated parameter ---
(define (make-acc n)
  (lambda (amt) (set! n (+ n amt)) n))
(define a (make-acc 100))
(display (a 10)) (display " ") (display (a 10)) (display " ") (display (a 5)) (newline)  ; 110 120 125

; --- Two closures share one binding; a mutation through one is seen by both ---
(define (make-pair)
  (let ((n 0))
    (cons (lambda () (set! n (+ n 1)) n)
          (lambda () n))))              ; reader captures the same box
(define p (make-pair))
(display ((car p))) (display " ")       ; 1
(display ((car p))) (display " ")       ; 2
(display ((cdr p))) (newline)           ; 2  (reader sees the shared mutation)

; --- Write-only closure + reader over the same binding ---
(define (make-cell init)
  (cons (lambda (v) (set! init v))      ; writer never reads init
        (lambda () init)))
(define b (make-cell 7))
(display ((cdr b))) (display " ")       ; 7
((car b) 42)
(display ((cdr b))) (newline)           ; 42
