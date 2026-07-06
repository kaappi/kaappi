;; Regression test for #1156: GC crash on stale VM registers after
;; thread start/join cycles under gc-stress.

(import (scheme base) (scheme write) (srfi 18) (srfi 64))

(test-begin "thread-frame-gc-1156")

;; Basic start/join cycle
(let ((t (make-thread (lambda () 'done))))
  (thread-start! t)
  (test-equal 'done (thread-join! t)))

;; Timeout join then successful join (the pattern from the crash)
(let ((t (make-thread (lambda () (thread-sleep! 0.3) 'slow))))
  (thread-start! t)
  (test-equal 'timeout (thread-join! t 0.01 'timeout))
  (test-equal 'slow (thread-join! t)))

;; Multiple cycles to increase allocation pressure
(let loop ((i 0))
  (when (< i 5)
    (let ((t (make-thread (lambda () (+ i 1)))))
      (thread-start! t)
      (test-equal (+ i 1) (thread-join! t)))
    (loop (+ i 1))))

(let ((runner (test-runner-current)))
  (test-end "thread-frame-gc-1156")
  (when (> (test-runner-fail-count runner) 0)
    (exit 1)))
