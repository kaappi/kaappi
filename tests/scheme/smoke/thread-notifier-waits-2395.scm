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
;;
;;    Signalled in a retry loop rather than once after a fixed delay. A
;;    signal that lands before the child has snapshotted the generation
;;    inside mutex-unlock! reaches no waiter at all, and a fixed delay makes
;;    that unlikely rather than impossible -- the child would then sit out
;;    its whole cv timeout and this would fail on a loaded machine for a
;;    reason unrelated to what it tests. Extra signals are harmless: each is
;;    a generation bump the child has either already accounted for or is
;;    about to observe.
;;
;;    The retry cannot mask a lost wake, which is the point. The wait is
;;    parked on the notifier with no poll cadence to fall back on, so
;;    without the ring the child never wakes however many times we signal --
;;    it runs out its own 15s cv timeout and reports 'cv-timed-out, which
;;    fails this assertion rather than hanging the suite.
;;
;;    Signalled WITHOUT holding m2, departing from the usual SRFI-18
;;    convention on purpose: it is the retry loop, not the mutex, that
;;    closes the lost-wakeup window here, and taking m2 would make this
;;    thread's own mutex-unlock! ring the notifier -- masking the thing
;;    under test. Measured: with the ring in condition-variable-signal!
;;    removed, the mutex-held version of this loop still passed.
(define m2 (make-mutex))
(define cv (make-condition-variable))
(let ((t (thread-start! (make-thread (lambda ()
                                       (mutex-lock! m2)
                                       (if (mutex-unlock! m2 cv 15) 'signaled 'cv-timed-out))))))
  (let loop ((tries 0))
    (let ((r (thread-join! t 0.2 'still-waiting)))
      (cond ((not (eq? r 'still-waiting))
             (test-equal "child wakes from the condition variable when signaled"
                         'signaled r))
            ((< tries 40)
             (condition-variable-signal! cv)
             (loop (+ tries 1)))
            (else
             ;; Out of retries (~8s): collect whatever the child ends up
             ;; reporting so the failure names the cause.
             (test-equal "child wakes from the condition variable when signaled"
                         'signaled (thread-join! t 20 'never-finished)))))))

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

;; 8. A wait that BECOMES cross-thread after it has already parked (PR #2428
;;    review). At the moment each of these enters its wait no OS thread
;;    exists, so a wait that decided whether to enrol from
;;    crossThreadWaitPossible() at entry would not enrol -- and would then
;;    park with no cap at all, because runSchedulerStep evaluates pollCapNs
;;    once and the deadline timer keeps the reactor non-empty. The sibling
;;    fiber that this very drive dispatches starts the process's first OS
;;    thread, whose unlock/signal rings a registry the wait never joined:
;;    measured at `#f` after the full 2s, for a hand-off that happened at
;;    0.1s. Enrolling unconditionally is what closes it.
(define m3 (make-mutex))
(let ()
  (mutex-lock! m3)
  (spawn (lambda ()
           (thread-start! (make-thread (lambda () (thread-sleep! 0.1) (mutex-unlock! m3))))))
  (let ((r (elapsed (lambda () (mutex-lock! m3 2)))))
    (test-equal "timed mutex-lock! sees an unlock from the first OS thread started mid-wait"
                #t (car r))
    (test-assert "and sees it promptly, not at its deadline" (< (cdr r) 1.5))))

(define m4 (make-mutex))
(define cv4 (make-condition-variable))
(let ()
  (mutex-lock! m4)
  (spawn (lambda ()
           (thread-start! (make-thread (lambda ()
                                         (thread-sleep! 0.1)
                                         (condition-variable-broadcast! cv4))))))
  ;; start_gen is snapshotted inside mutex-unlock! before it releases m4 and
  ;; before the drive can dispatch the sibling, so the broadcast below cannot
  ;; be missed -- only the enrolment timing is under test here.
  (let ((r (elapsed (lambda () (mutex-unlock! m4 cv4 3)))))
    (test-equal "condvar wait sees a signal from the first OS thread started mid-wait"
                #t (car r))
    (test-assert "and sees it promptly, not at its deadline" (< (cdr r) 2))))

;; 9. A "never" deadline is a real reactor park, not an error. SRFI-18 reads
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
