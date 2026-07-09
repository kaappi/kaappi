;; Regression test for #1155: make-thread and spawn must accept
;; native (built-in) procedures, not only closures.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (srfi 64))

(test-begin "srfi18-native-thunk")

;;; --- make-thread with native procedures ---

(test-equal "make-thread + list (zero-arg native)"
  '()
  (thread-join! (thread-start! (make-thread list))))

(test-equal "make-thread + values (zero-arg native)"
  #t
  (let ((t (make-thread values)))
    (thread? t)))

;;; --- make-thread still works with closures ---

(test-equal "make-thread + lambda"
  42
  (thread-join! (thread-start! (make-thread (lambda () 42)))))

;;; --- error on non-procedures ---

(test-assert "make-thread rejects non-procedure"
  (guard (e (#t #t))
    (make-thread 42)
    #f))

(let ((runner (test-runner-current)))
  (test-end "srfi18-native-thunk")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
