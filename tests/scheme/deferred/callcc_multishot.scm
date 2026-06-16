; Multi-shot re-entry within a single program (global mutable counter so
; set! persists across continuation invocations). Should count up to 5.
(define k #f)
(define n 0)
(define (go)
  (call/cc (lambda (c) (set! k c)))
  (set! n (+ n 1))
  (if (< n 5) (k #f))
  n)
(display (go))   ; expect 5
(newline)
