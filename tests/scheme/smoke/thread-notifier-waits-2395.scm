;; Regression tests for #2395 (KEP-0002 unresolved question 3): the SRFI-18
;; waits that can only be resolved by another OS thread now park on the
;; reactor and are woken by a ThreadNotifier ring, instead of polling their
;; own state at 1 ms.
;;
;; Every case below is a cross-thread hand-off with a generous timeout: if a
;; wake is ever lost, the wait runs out its whole timeout and the test fails
;; with the timeout value rather than hanging the suite.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (kaappi fibers) (srfi 64))

(test-begin "thread-notifier-waits-2395")

(define (elapsed thunk)
  (let* ((t0 (time->seconds (current-time)))
         (r (thunk)))
    (cons r (- (time->seconds (current-time)) t0))))

;; 1. thread-join! with a timeout wakes on the child's exit, not on the
;;    timeout. The 5 s timeout is 50x the child's runtime: a lost wake would
;;    return 'timed-out.
(let* ((t (thread-start! (make-thread (lambda () (thread-sleep! 0.1) 'done))))
       (r (elapsed (lambda () (thread-join! t 5 'timed-out)))))
  (test-equal "timed thread-join! returns the child's result" 'done (car r))
  (test-assert "timed thread-join! returns when the child exits, not at its deadline"
               (< (cdr r) 4)))

;; 2. A timed thread-join! no longer freezes this thread's own fibers: a
;;    sibling fiber must get dispatched while the join is parked. Before
;;    #2395 the join was a bare nanosleep loop and `ran` stayed #f.
(let ((ran #f))
  (let ((t (thread-start! (make-thread (lambda () (thread-sleep! 0.2) 'done)))))
    (spawn (lambda () (set! ran #t)))
    (test-equal "join still returns the result" 'done (thread-join! t 5 'timed-out))
    (test-assert "a sibling fiber runs while a timed thread-join! is parked" ran)))

;; 3. thread-join! on a handle that has not been started yet is resolved by a
;;    fiber on this same thread calling thread-start! -- only reachable now
;;    that the wait drives the scheduler instead of sleeping through it.
(let ((t (make-thread (lambda () 'started-late))))
  (spawn (lambda () (thread-start! t)))
  (test-equal "join of an unstarted handle waits for a sibling fiber to start it"
              'started-late (thread-join! t 5 'timed-out)))

;; 4. A never-started handle nobody starts still times out.
(let ((t (make-thread (lambda () 42))))
  (test-equal "unstarted handle nobody starts still times out"
              'timed-out (thread-join! t 0.05 'timed-out)))

;; 5. Cross-thread mutex hand-off: the child blocks in mutex-lock! on a mutex
;;    this thread holds, and the unlock is what must wake it.
(define m (make-mutex))
(let ()
  (mutex-lock! m)
  (let ((t (thread-start! (make-thread (lambda () (mutex-lock! m) (mutex-unlock! m) 'locked)))))
    (thread-sleep! 0.1)
    (mutex-unlock! m)
    (test-equal "child acquires the mutex once this thread unlocks it"
                'locked (thread-join! t 5 'timed-out))))

;; 6. Cross-thread condition variable: the child waits on cv, and
;;    condition-variable-signal! from here is what must wake it.
(define m2 (make-mutex))
(define cv (make-condition-variable))
(let ((t (thread-start! (make-thread (lambda ()
                                       (mutex-lock! m2)
                                       (if (mutex-unlock! m2 cv 5) 'signaled 'cv-timed-out))))))
  (thread-sleep! 0.2)
  (mutex-lock! m2)
  (condition-variable-signal! cv)
  (mutex-unlock! m2)
  (test-equal "child wakes from the condition variable when signaled"
              'signaled (thread-join! t 5 'timed-out)))

;; 7. thread-terminate! reaches a child parked in a long thread-sleep!. The
;;    sleep is 30 s; the terminate ring is the only thing that can end it in
;;    time (before #2395 it was the sleep's own 1 ms poll cap).
(let ((t (thread-start! (make-thread (lambda () (thread-sleep! 30) 'slept)))))
  (thread-sleep! 0.1)
  (thread-terminate! t)
  (let ((r (elapsed (lambda ()
                      (guard (e ((terminated-thread-exception? e) 'terminated))
                        (thread-join! t))))))
    (test-equal "terminate ends a long sleep" 'terminated (car r))
    (test-assert "terminated child is joined promptly" (< (cdr r) 10))))

;; 8. A "never" deadline is a real reactor park, not an error. SRFI-18 reads
;;    +inf.0 as "never times out", which saturates to a maxInt-nanosecond
;;    deadline ~585 years out -- a timespec kqueue rejects outright unless the
;;    reactor clamps its own blocking wait. Before #2395 thread-join! reached
;;    that deadline through a nanosleep loop and never handed it to the
;;    reactor; (thread-sleep! 1e18) did, and raised KP9002 "out of memory"
;;    instead of sleeping.
(let ((t (thread-start! (make-thread (lambda () (thread-sleep! 0.1) 'inf-done)))))
  (test-equal "thread-join! with an infinite timeout waits and returns the result"
              'inf-done (thread-join! t +inf.0)))

(let ((t (thread-start! (make-thread (lambda () (thread-sleep! +inf.0) 'slept)))))
  (thread-sleep! 0.1)
  (thread-terminate! t)
  (test-equal "an infinite thread-sleep! parks (and terminate ends it)"
              'terminated
              (guard (e ((terminated-thread-exception? e) 'terminated)
                        (#t 'other-exception))
                (thread-join! t))))

(let ((runner (test-runner-current)))
  (test-end "thread-notifier-waits-2395")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
