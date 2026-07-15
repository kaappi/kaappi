; Compile-once eval-fallback cache (#1494).
;
; make-adder compiles natively, but its body is a *variadic* inner lambda that
; no native-closure tier accepts, so it goes through the eval fallback
; (emitLambdaViaEval). Before #1494 that lambda was re-parsed and re-compiled on
; every call to make-adder; now it is compiled once per call site and cached.
; Driving it from a hot self-tail loop must stay identical to the interpreter.
(define (make-adder base)
  (lambda (a . rest) (+ base a)))

(define (sum-run n acc)
  (if (= n 0)
      acc
      ; Create the adder and apply it immediately so the captured base is the
      ; current n (avoids the orthogonal by-value/by-global capture question).
      (sum-run (- n 1) (+ acc ((make-adder n) 1)))))

(display (sum-run 1000 0))
(newline)
