;; Regression test for #1314: yield raises inside with-exception-handler after spawn
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "yield-exception-handler")

;; yield should be a no-op after all fibers complete
(fiber-join (spawn (lambda () 42)))

(test-equal "yield in with-exception-handler after spawn"
  'ok
  (with-exception-handler
    (lambda (e) 'fail)
    (lambda () (yield) 'ok)))

(test-equal "yield in guard after spawn"
  'ok
  (guard (e (#t 'fail))
    (yield) 'ok))

;; yield with no scheduler is still a no-op
(test-equal "yield without scheduler"
  'done
  (with-exception-handler
    (lambda (e) 'fail)
    (lambda () (yield) 'done)))

(let ((runner (test-runner-current)))
  (test-end "yield-exception-handler")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
