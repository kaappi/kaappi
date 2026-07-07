;; Regression test for #1153: mutex-lock!/mutex-unlock! with timeout
;; on locked mutex / unsignaled condvar must return #f, not steal the lock.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18))
(import (srfi 64))

(test-begin "mutex-timeout")

;; mutex-lock! with timeout on an already-locked mutex returns #f
(let ((m (make-mutex)))
  (mutex-lock! m)
  (test-equal "mutex-lock! timeout on locked mutex" #f (mutex-lock! m 0.05)))

;; mutex-lock! with zero relative timeout on locked mutex returns #f
(let ((m (make-mutex)))
  (mutex-lock! m)
  (test-equal "mutex-lock! zero timeout on locked mutex" #f (mutex-lock! m 0)))

;; mutex-unlock! with condvar and timeout returns #f when not signaled
(let ((m (make-mutex)) (cv (make-condition-variable)))
  (mutex-lock! m)
  (test-equal "condvar timeout unsignaled" #f (mutex-unlock! m cv 0.01)))

;; normal mutex-lock!/unlock! still works (no regression)
(let ((m (make-mutex)))
  (test-equal "lock succeeds" #t (mutex-lock! m))
  (test-equal "unlock succeeds" #t (mutex-unlock! m)))

;; lock after unlock works
(let ((m (make-mutex)))
  (mutex-lock! m)
  (mutex-unlock! m)
  (test-equal "re-lock after unlock" #t (mutex-lock! m)))

;; stale deadline: a timed-out wait must not poison later untimed waits
(let ((m (make-mutex)))
  (mutex-lock! m)
  (mutex-lock! m 0.01)                    ; times out, was leaving stale deadline_ns
  (mutex-unlock! m)
  (test-equal "untimed lock after timed timeout" #t (mutex-lock! m)))

(let ((runner (test-runner-current)))
  (test-end "mutex-timeout")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
