; Takeuchi function — three-way recursion exercised natively (direct calls +
; inlined arithmetic). Serves as the #1492 -O2 micro-benchmark parity case:
; the native binary is built at -O2 and its output must match the interpreter.
(define (tak x y z)
  (if (not (< y x))
      z
      (tak (tak (- x 1) y z)
           (tak (- y 1) z x)
           (tak (- z 1) x y))))
(display (tak 18 12 6))
(newline)
