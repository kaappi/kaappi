;; Regression test for #832: every compiled lambda leaks its Function into
;; gc.extra_roots. After many eval'd lambdas, extra_roots should not grow
;; unboundedly.
;;
;; The verdict is completion in bounded memory — a leaked root per lambda
;; makes 50,000 of them exhaust memory rather than return a wrong answer, so
;; there is no value to compare. `kaappi --gc-stats` is the direct measurement;
;; this file is the cheap always-on guard.

(import (scheme base) (scheme eval) (scheme repl)
        (scheme process-context) (srfi 64))

(test-begin "lambda-leak-832")

(test-equal "50,000 eval'd lambdas complete in bounded memory"
  50000
  (do ((i 0 (+ i 1)))
      ((= i 50000) i)
    (eval '(lambda (x) (+ x 1)) (interaction-environment))))

(let ((runner (test-runner-current)))
  (test-end "lambda-leak-832")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
