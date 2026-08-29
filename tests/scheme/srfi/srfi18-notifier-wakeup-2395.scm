;; Regression test for kaappi#2395: thread-join! and the cross-thread
;; mutex/condvar waits are woken by reactor notifier rings (a child's exit
;; rings every live reactor; unlock/signal ring the object's registered
;; waiters) instead of re-checking shared state on a 1 ms poll.
;;
;; The scenarios here are the ones only real OS-thread timing exercises:
;;
;;  * A LOST exit ring makes a timed join sit out its whole timeout — so a
;;    generous timeout with a "returned the value, well before the deadline"
;;    assertion is the detector. The bound is deliberately loose (20 s vs a
;;    0.2 s child) so a loaded CI runner can't flake it, while a genuine
;;    regression (value replaced by the timeout marker at t=30 s) still
;;    fails decisively.
;;
;;  * The deadlock verdict must survive the rework: a wait that parks
;;    unbounded because another OS thread might help must re-evaluate when
;;    that thread exits (its exit ring is the only wake in this scenario)
;;    and turn into the mutex-lock! deadlock error rather than hanging.
;;    Before kaappi#2395 the 1 ms poll reached the same verdict; losing the
;;    exit ring turns this into a permanent hang, which the runner's
;;    per-file timeout converts into a failure.
;;
;; Cross-thread mutex handoff and condvar signal/broadcast latency (child
;; side) are already pinned by srfi18-cross-thread-wait.scm, and terminate
;; interrupting parked native waits by srfi18-terminate-native-wait-1982.scm
;; — both now ride the same notifier machinery.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "srfi18-notifier-wakeup-2395")

(define (elapsed-since t0)
  (- (time->seconds (current-time)) (time->seconds t0)))

;; ---- a timed join wakes on the child's exit ring, not the deadline ----
(let ((t (make-thread (lambda () (thread-sleep! 0.2) 'finished))))
  (thread-start! t)
  (let* ((t0 (current-time))
         (r (thread-join! t 30 'hit-the-timeout))
         (dt (elapsed-since t0)))
    (test-equal "timed join returns the value, not the timeout marker" 'finished r)
    (test-assert "timed join returned well before its 30s deadline" (< dt 20))
    (test-assert "timed join genuinely waited for the child" (>= dt 0.15))))

;; ---- the deadlock verdict re-fires when the last other thread exits ----
;; Main holds the mutex and then waits on it untimed; only the (unrelated)
;; child's existence makes a cross-thread resolution look possible, so main
;; parks instead of erroring. The child's exit ring must wake main into
;; re-running the verdict — now provably a self-deadlock — and raising.
(define self-m (make-mutex 'self-m))
(mutex-lock! self-m)
(let ((bystander (make-thread (lambda () (thread-sleep! 0.3) 'bystander-done))))
  (thread-start! bystander)
  (let* ((t0 (current-time))
         (outcome (guard (e ((abandoned-mutex-exception? e) 'abandoned)
                            ((join-timeout-exception? e) 'timeout)
                            (#t 'deadlock))
                    (mutex-lock! self-m)
                    'locked-own-mutex))
         (dt (elapsed-since t0)))
    (test-equal "untimed self-lock raises the deadlock error once no thread can help"
      'deadlock outcome)
    (test-assert "the verdict waited for the bystander thread's exit" (>= dt 0.25))
    (test-assert "the verdict arrived promptly after the exit ring, not at a poll or hang" (< dt 20)))
  (test-equal "the bystander thread still joins normally" 'bystander-done
    (thread-join! bystander)))
(mutex-unlock! self-m)

;; ---- exit-ring churn: rapid start/join cycles stay balanced ----
;; Every thread exit rings every live reactor and every join releases the
;; handle's published notifier reference; twenty quick cycles would surface
;; a refcount imbalance (use-after-free or leak-driven slowdown) while
;; staying fast enough for the suite.
(test-equal "twenty rapid start/join cycles complete"
  190
  (let loop ((i 0) (acc 0))
    (if (= i 20)
        acc
        (let ((t (make-thread (lambda () i))))
          (thread-start! t)
          (loop (+ i 1) (+ acc (thread-join! t)))))))

(let ((runner (test-runner-current)))
  (test-end "srfi18-notifier-wakeup-2395")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
