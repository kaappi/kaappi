;; Regression test for kaappi#1870: srfi120.scm's assertions must survive a
;; slow machine between their own setup steps.
;;
;; srfi120.scm went red on `windows-x64-test` and later, with different
;; assertions, on `netbsd-test` -- twice in one day on two structurally
;; unrelated PRs. Every failure was the test racing a deadline it had chosen
;; itself. A green run of srfi120.scm on an idle laptop proves nothing about
;; that: an idle machine gives 0/N failures for the racy shape and the fixed
;; shape alike. This file reproduces the *mechanism* instead.
;;
;; Each block below mirrors one of the five blocks in srfi120.scm that used
;; to race, and injects an artificial `thread-sleep!` at exactly the point
;; where an emulated leg was slow. The delay is chosen per block to exceed
;; the margin the OLD shape allowed, so each of these assertions FAILS
;; against the pre-#1870 srfi120.scm and PASSES against the current one.
;;
;;   block            old margin   injected   new margin
;;   task-remove       300 ms       400 ms      800 ms
;;   reschedule       1000 ms       400 ms     1000 ms   (unchanged; pinned)
;;   period-0           40 ms       200 ms     2000 ms
;;   timer-cancel!      30 ms       200 ms      600 ms
;;   no-handler         30 ms       200 ms      none (nothing follows)
;;
;; The injected delays are what make this file deterministic, so do not
;; remove them to "speed it up" -- without them the file asserts nothing the
;; laptop would not pass either way. They are also why the negative waits
;; here are short (0.4 s): a value that leaked past a broken margin is
;; already queued in the channel and comes back immediately, so these waits
;; are measuring the race, not the detection window that srfi120.scm's own
;; longer negative waits provide.

(import (scheme base) (scheme write) (srfi 18) (kaappi fibers) (srfi 64) (srfi 120))

(test-begin "srfi-120-slow-setup")

;;; --- timer-task-exists? / timer-task-remove! ------------------------------
;; OLD: the task was scheduled 300 ms out and the test then had to run
;; timer-task-exists? and timer-task-remove! before it fired.

(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'fired)) 800)))
  (thread-sleep! 0.4)
  (test-assert "slow setup: the task is still pending 400 ms later"
    (timer-task-exists? t id))
  (test-assert "slow setup: it can still be removed 400 ms later"
    (timer-task-remove! t id))
  (test-equal "slow setup: and the removed task still never fires"
              'timeout (channel-receive sig 0.4 'timeout))
  (timer-cancel! t))

;;; --- timer-reschedule! ----------------------------------------------------
;; This block's 1000 ms margin was already generous and is unchanged; the
;; assertion exists so a later edit cannot quietly shrink it.

(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'fired)) 1000)))
  (thread-sleep! 0.4)
  (test-equal "slow setup: reschedule still reaches a pending task 400 ms later"
              id (timer-reschedule! t id 50))
  (test-equal "slow setup: and it fires at the new time"
              'fired (channel-receive sig 3.0 'timeout))
  (timer-cancel! t))

;;; --- period-0 reschedule --------------------------------------------------
;; OLD: the periodic task was left running on a 40 ms period while the test
;; received one tick and then rescheduled, so extra ticks queued in the
;; unbounded channel and the "no further firing" assertion saw one of them.

(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'tick)) 2000 40)))
  (thread-sleep! 0.2)
  (timer-reschedule! t id 50 0)
  (test-equal "slow setup: period-0 reschedule still fires once"
              'tick (channel-receive sig 3.0 'timeout))
  (test-equal "slow setup: period-0 reschedule still fires only once"
              'timeout (channel-receive sig 0.4 'timeout))
  (timer-cancel! t))

;;; --- timer-cancel! --------------------------------------------------------
;; OLD: one periodic 30/30 task, so ticks queued between the first receive
;; and the cancel. This is the shape that produced netbsd-test's
;; "timer-cancel!: no further firings after cancellation".

(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'late)) 600)
  (timer-schedule! t (lambda () (channel-send sig 'early)) 30)
  (test-equal "slow setup: a task fires before cancellation"
              'early (channel-receive sig 3.0 'timeout))
  (thread-sleep! 0.2)
  (timer-cancel! t)
  (test-equal "slow setup: still no further firings after a delayed cancellation"
              'timeout (channel-receive sig 0.4 'timeout)))

;;; --- unhandled task error stops the timer ---------------------------------
;; OLD: the erroring task was scheduled FIRST, 30 ms out, and the test then
;; had to get its second timer-schedule! in before the timer stopped. This
;; is the shape that produced netbsd-test's
;; "srfi120.scm:153 error[KP3000]: timer-schedule!: timer is not responding".
;; The fix is ordering, not headroom: nothing calls into the timer after the
;; erroring task is queued, so the delay below cannot break it however long
;; it is.

(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'should-not-fire)) 600)
  (thread-sleep! 0.2)
  (test-assert "slow setup: scheduling the erroring task last never raises"
    (guard (c (#t #f))
      (timer-schedule! t (lambda () (error "srfi-120 test: unhandled")) 30)
      #t))
  (test-equal "slow setup: the timer still stops, so the later task never fires"
              'timeout (channel-receive sig 1.0 'timeout))
  (test-assert "slow setup: timer-cancel! still re-raises the preserved error"
    (guard (c (#t (and (error-object? c)
                       (string=? (error-object-message c) "srfi-120 test: unhandled"))))
      (timer-cancel! t)
      #f)))

(let ((runner (test-runner-current)))
  (test-end "srfi-120-slow-setup")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
