; Nested continuation capture — inner continuation escapes while captured
; inside an outer call/cc. Previously failed with NotAProcedure because the
; call/cc proc frame was restored with dst=0 instead of the call/cc result
; register; fixed by threading the result register through callHandler.

; Inner escapes, no surrounding arithmetic
(display (call/cc (lambda (o) (call/cc (lambda (i) (i 5))))))     ; 5
(newline)

; Inner escapes, surrounding arithmetic in the outer extent
(display (call/cc (lambda (o) (+ 1 (call/cc (lambda (i) (i 5))))))) ; 6
(newline)

; Inner captured via let binding (non-tail), then escapes
(display
 (call/cc (lambda (o)
   (let ((x (call/cc (lambda (i) (i 5))))) (+ 1 x)))))            ; 6
(newline)

; Outer continuation escaped from within the inner extent
(display (call/cc (lambda (o) (+ 1 (call/cc (lambda (i) (o 7))))))) ; 7
(newline)

; Triple nesting, innermost escapes through two outer frames
(display
 (call/cc (lambda (a)
   (+ 1 (call/cc (lambda (b)
     (+ 10 (call/cc (lambda (c) (c 100))))))))))                  ; 111
(newline)

; Mixed call/cc and call/ec nesting
(display (call/ec (lambda (o) (+ 1 (call/cc (lambda (i) (i 5))))))) ; 6
(newline)
(display (call/cc (lambda (o) (+ 1 (call/ec (lambda (i) (i 5))))))) ; 6
(newline)

; dynamic-wind after-thunk still runs when an inner nested escape unwinds
(define lg '())
(define (note x) (set! lg (cons x lg)))
(call/cc (lambda (o)
  (+ 1 (call/cc (lambda (i)
    (dynamic-wind
      (lambda () (note 'before))
      (lambda () (i 9))
      (lambda () (note 'after))))))))
(display (reverse lg))                                            ; (before after)
(newline)
