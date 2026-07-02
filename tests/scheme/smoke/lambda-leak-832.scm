;; Regression test for #832: every compiled lambda leaks its Function into
;; gc.extra_roots. After many eval'd lambdas, extra_roots should not grow
;; unboundedly. We test by running --gc-stats and checking that the process
;; completes in bounded memory (no OOM).
(do ((i 0 (+ i 1)))
    ((= i 50000))
  (eval '(lambda (x) (+ x 1)) (interaction-environment)))
(display "ok")
(newline)
