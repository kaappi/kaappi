; call/cc capture benchmark.
;
; Stresses the capture path: at a built-up call-stack depth, perform many
; immediately-escaping call/cc captures. Each iteration captures and discards
; a continuation, exercising captureContinuation + allocContinuation.

; Build `depth` real (non-tail) frames so the register base is elevated, then
; run the capture loop at the bottom.
(define (at-depth depth thunk)
  (if (= depth 0)
      (thunk)
      (+ 0 (at-depth (- depth 1) thunk))))

; Tail loop: `iters` captures, each escaping immediately via (k 1).
(define (capture-loop iters)
  (let loop ((i iters) (acc 0))
    (if (= i 0)
        acc
        (loop (- i 1)
              (+ acc (call/cc (lambda (k) (k 1))))))))

(define ITERS 400000)
(define DEPTH 40)

(display (at-depth DEPTH (lambda () (capture-loop ITERS))))
(newline)
