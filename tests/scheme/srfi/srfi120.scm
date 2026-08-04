;; SRFI-120 (Timer APIs) conformance test.
;;
;; A scheduled thunk runs on the timer's own dedicated thread, which has an
;; independent GC heap from the thread that called timer-schedule! (see
;; lib/srfi/120.sld's header comment) -- so every test here observes task
;; execution through a (kaappi fibers) channel, never through mutating a
;; pair/box the calling thread also holds. `(channel-receive sig timeout
;; 'timeout)` is used throughout so a bug that makes a task never fire
;; times out instead of hanging the whole suite.
;;
;; ---------------------------------------------------------------------
;; Timing discipline (kaappi#1870, audit v2 phase 5E)
;;
;; This file was the flakiest in the tree: it went red on `windows-x64-test`
;; and later, with different assertions, on `netbsd-test` -- twice in one day
;; on two structurally unrelated PRs. Every one of those failures was the
;; test racing a deadline it had chosen itself, not a defect in (srfi 120).
;; Three rules, each of which a block below used to break:
;;
;;   R1. Never let the test's own next statement race a deadline the test
;;       just set. Either schedule the deadline-bearing task LAST, or make
;;       its delay so much larger than the intervening work that no
;;       plausible slowdown can close the gap. The intervening work is
;;       synchronous request/reply over a channel -- ~0.1 ms healthy -- so
;;       the delays below (800-2000 ms) leave a margin of several thousand
;;       times, not the ~300x a 30 ms delay left.
;;
;;       "Schedule it LAST" removes the following *calls*, never the
;;       deadlines already set. A block whose last statement schedules
;;       nothing can still be racing an earlier task's delay -- which is
;;       what the timer-cancel! and no-error-handler blocks below were
;;       still doing at 570 ms each, the two smallest margins in the file
;;       and the two assertions netbsd-test actually went red on, long
;;       after the ordering fix. Both were found by injecting a delay at
;;       each block's racy point and bisecting for the value that breaks
;;       it; the margins are measured, not assumed, and every one is
;;       pinned in srfi120-slow-setup.scm.
;;
;;   R2. Never observe a PERIODIC task through a channel and then assert
;;       "nothing more arrives". `make-channel` with no capacity argument is
;;       unbounded, so every tick that fires between the first receive and
;;       the cancel/reschedule is already queued and will be handed to the
;;       next receive. Use one-shot tasks for those assertions; there is
;;       then nothing to queue.
;;
;;   R3. A negative ("must NOT fire") wait has to outlast the deadline it is
;;       disproving, or it proves nothing. Each one below is longer than the
;;       delay of the task it claims never fires.
;;
;; The rules are exercised directly by srfi120-slow-setup.scm, which inserts
;; artificial delays at exactly the points that used to race and asserts the
;; outcomes are unchanged.
;; ---------------------------------------------------------------------

(import (scheme base) (scheme write) (srfi 18) (kaappi fibers) (srfi 64) (srfi 120))

(test-begin "srfi-120")

;;; --- make-timer-delta / timer-delta? ---------------------------------

(test-assert "timer-delta?: a constructed delta satisfies the predicate"
  (timer-delta? (make-timer-delta 1 'seconds)))
(test-assert "timer-delta?: a plain integer does not satisfy the predicate"
  (not (timer-delta? 5)))

;; SRFI 120's required baseline vocabulary is the abbreviated symbols, not
;; the full words -- accept both, but the abbreviated ones are the spec
;; contract.
(for-each
  (lambda (unit) (test-assert (string-append "make-timer-delta: accepts required unit '" (symbol->string unit))
                   (timer-delta? (make-timer-delta 1 unit))))
  '(h m s ms us ns))

(test-assert "make-timer-delta: rejects a genuinely unknown unit"
  (guard (c (#t #t)) (make-timer-delta 1 'fortnights) #f))

;; A negative timer-delta is rejected only once actually used (%delta->ms
;; runs at timer-schedule!/timer-reschedule! call time, not construction
;; time) -- construction itself never inspects n.
(let ((t (make-timer)))
  (test-assert "timer-schedule!: a negative timer-delta is rejected"
    (guard (c (#t #t)) (timer-schedule! t (lambda () #f) (make-timer-delta -1 's)) #f))
  (timer-cancel! t))

;;; --- timer? ------------------------------------------------------------

(let ((t (make-timer)))
  (test-assert "timer?: a constructed timer satisfies the predicate" (timer? t))
  (test-assert "timer?: a plain value does not satisfy the predicate" (not (timer? 5)))
  (timer-cancel! t))

;;; --- one-shot scheduling -------------------------------------------------

(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'fired)) 100)
  (test-equal "timer-schedule!: a one-shot task fires within its window"
              'fired (channel-receive sig 3.0 'timeout))
  (timer-cancel! t))

(test-assert "timer-schedule!: returns a readable datum (here, an exact integer id)"
  (let* ((t (make-timer))
         (id (timer-schedule! t (lambda () #f) 1000)))
    (timer-cancel! t)
    (and (integer? id) (exact? id))))

;; A make-timer-delta value must be accepted in place of a plain integer.
(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'fired)) (make-timer-delta 100 'milliseconds))
  (test-equal "timer-schedule!: accepts a timer-delta for `when`"
              'fired (channel-receive sig 3.0 'timeout))
  (timer-cancel! t))

;;; --- periodic scheduling -------------------------------------------------

(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'tick)) 40 40)
  (test-equal "timer-schedule!: periodic task fires a 1st time"
              'tick (channel-receive sig 3.0 'timeout))
  (test-equal "timer-schedule!: periodic task fires a 2nd time"
              'tick (channel-receive sig 3.0 'timeout))
  (test-equal "timer-schedule!: periodic task fires a 3rd time"
              'tick (channel-receive sig 3.0 'timeout))
  (timer-cancel! t))

;;; --- timer-task-exists? / timer-task-remove! ------------------------------

;; R1: the task must still be PENDING while the three queries below run, so
;; its delay has to outlast them. They are synchronous channel round trips
;; (~0.1 ms healthy); 800 ms leaves a margin of several thousand times,
;; where the 300 ms this block used to allow left a few hundred.
;; R3: the negative wait (1.2 s) outlasts that 800 ms delay, so it would
;; genuinely observe a removal that silently did nothing.
(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'fired)) 800)))
  (test-assert "timer-task-exists?: #t right after scheduling"
    (timer-task-exists? t id))
  (test-assert "timer-task-remove!: #t when the task was pending"
    (timer-task-remove! t id))
  (test-assert "timer-task-exists?: #f after removal"
    (not (timer-task-exists? t id)))
  (test-equal "timer-task-remove!: the removed task never fires"
              'timeout (channel-receive sig 1.2 'timeout))
  (test-assert "timer-task-remove!: #f for an id that is no longer pending"
    (not (timer-task-remove! t id)))
  (timer-cancel! t))

;;; --- timer-reschedule! ---------------------------------------------------

;; R1: the reschedule must reach a still-pending task, so the original delay
;; (1000 ms) has to outlast one channel round trip. It does, by ~10000x.
(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'fired)) 1000)))
  ;; SRFI 120: "the procedure returns given id" on success.
  (test-equal "timer-reschedule!: returns the id when the task was pending"
              id (timer-reschedule! t id 50))
  (test-equal "timer-reschedule!: the task fires at the NEW time, not the original"
              'fired (channel-receive sig 3.0 'timeout))
  (test-assert "timer-reschedule!: #f for an id that no longer exists"
    (not (timer-reschedule! t id 50)))
  (timer-cancel! t))

;; The spec's documented idiom: reschedule with period 0 turns a periodic
;; task into a one-shot.
;;
;; R2: this block used to let the periodic task fire first, receive one tick,
;; and then assert that nothing more arrived -- but the 40 ms period kept
;; queueing ticks into the unbounded channel in the meantime, so the "no
;; further firing" receive could hand back a tick that predated the
;; reschedule. Rescheduling a task that has NOT fired yet (2000 ms initial
;; delay, R1) tests the same guarantee with nothing in the channel to
;; confuse it: after the reschedule the task must fire exactly once, at the
;; new time, and never again.
(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'tick)) 2000 40)))
  (timer-reschedule! t id 50 0)
  (test-equal "period-0 reschedule: the task fires once at the new time"
              'tick (channel-receive sig 3.0 'timeout))
  ;; R3: had period 0 been ignored, the next firing would be 40 ms later;
  ;; 0.5 s covers a dozen of them.
  (test-equal "period-0 reschedule: no further periodic firing follows"
              'timeout (channel-receive sig 0.5 'timeout))
  (timer-cancel! t))

;;; --- timer-cancel! -------------------------------------------------------

;; R2: this used to be one periodic 30/30 task, so ticks queued in the
;; unbounded channel between the first receive and the timer-cancel! and the
;; "no further firings" assertion could observe one of them -- which is
;; exactly what went red on netbsd-test (kaappi#1870). Two one-shots give
;; the same two guarantees with nothing to queue: `early` proves the timer
;; was genuinely running, `late` proves cancellation stopped it.
;; R1: `late` is scheduled LAST, once `early` has already been received. It
;; used to be scheduled first, which put the `early` receive inside its
;; margin alongside the cancel and left 570 ms for both -- the smallest
;; margin in the file, guarding the very assertion netbsd-test went red on.
;; Scheduling it here empties that window of deadlines altogether: injecting
;; a 1.4 s stall between the receive and this schedule now changes nothing,
;; where 0.6 s used to fail. The only work left inside `late`'s 1200 ms is
;; timer-cancel! itself.
;; R3: the negative wait (1.5 s) outlasts `late`'s 1200 ms delay, so a
;; cancellation that failed to stop the timer would be caught.
(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'early)) 30)
  (test-equal "timer-cancel!: at least one firing happens before cancellation"
              'early (channel-receive sig 3.0 'timeout))
  (timer-schedule! t (lambda () (channel-send sig 'late)) 1200)
  (timer-cancel! t)
  (test-equal "timer-cancel!: no further firings after cancellation"
              'timeout (channel-receive sig 1.5 'timeout)))

;;; --- error-handler ---------------------------------------------------------

(let* ((sig (make-channel))
       (t (make-timer (lambda (condition) (channel-send sig 'handled)))))
  (timer-schedule! t (lambda () (error "srfi-120 test: deliberate task error")) 30)
  (test-equal "error-handler: invoked when a task's thunk raises"
              'handled (channel-receive sig 3.0 'timeout))
  ;; Safe to schedule after the error here (unlike the no-handler case
  ;; below): a handled error leaves the timer running, and the receive above
  ;; has already established that the handler ran.
  (timer-schedule! t (lambda () (channel-send sig 'still-alive)) 30)
  (test-equal "error-handler: the timer keeps running after a handled error"
              'still-alive (channel-receive sig 3.0 'timeout))
  (timer-cancel! t))

;; No handler at all: the timer must stop after the first task error rather
;; than silently continuing (observed indirectly -- a task scheduled after
;; the failing one must never fire once the timer has stopped).
;; R1: the erroring task is scheduled LAST. Once it is queued, the timer may
;; stop at any moment and every further timer-schedule! would raise
;; "timer is not responding" -- which is precisely what went red on
;; netbsd-test (kaappi#1870, srfi120.scm:153 on PR #2076): the old order
;; scheduled the erroring task first, at 30 ms, and then needed its own next
;; line to beat that 30 ms deadline.
;;
;; That ordering removed the "not responding" failure mode but NOT every
;; deadline, and this comment used to claim it had ("nothing follows the
;; erroring schedule now, so there is no deadline left to lose"). It is the
;; general R1 trap: `should-not-fire` still has to outlast the erroring
;; timer-schedule! that is meant to stop the timer first. At 600 ms that
;; left 570 ms, and injecting 0.6 s here failed the block for real -- with
;; `should-not-fire` arriving, not with "not responding", so the ordering
;; fix was genuinely intact and simply did not cover this. 1200 ms brings
;; the margin into line with the rest of the file.
;; R3: the should-not-fire task's 1200 ms delay is still inside the 1.5 s
;; negative wait, so a timer that failed to stop would be caught.
(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'should-not-fire)) 1200)
  (timer-schedule! t (lambda () (error "srfi-120 test: unhandled")) 30)
  (test-equal "no error-handler: the timer stops, so later tasks never fire"
              'timeout (channel-receive sig 1.5 'timeout))
  ;; SRFI 120: "the procedure raises the preserved error if there is" --
  ;; timer-cancel! on an already-stopped-by-error timer must re-raise it.
  (test-assert "timer-cancel!: raises the preserved error from an unhandled task failure"
    (guard (c (#t (and (error-object? c)
                        (string=? (error-object-message c) "srfi-120 test: unhandled"))))
      (timer-cancel! t)
      #f)))

;; A handler that itself re-raises is exactly the same "otherwise" case as
;; no handler at all -- the re-raised condition (not the original task
;; error) is what gets preserved. The handler signals right before its own
;; (error ...) call so the test waits for that to actually happen instead
;; of guessing a fixed delay.
(let* ((sig (make-channel))
       (t (make-timer (lambda (original-condition)
                         (channel-send sig 'handler-ran)
                         (error "srfi-120 test: handler re-raised")))))
  (timer-schedule! t (lambda () (error "srfi-120 test: original")) 30)
  (test-equal "error-handler: a re-raising handler still runs"
              'handler-ran (channel-receive sig 3.0 'timeout))
  (test-assert "timer-cancel!: raises the handler's re-raised condition, not the original"
    (guard (c (#t (and (error-object? c)
                        (string=? (error-object-message c) "srfi-120 test: handler re-raised"))))
      (timer-cancel! t)
      #f)))

;; A normal cancellation (no task ever errored) must NOT raise anything.
(let ((t (make-timer)))
  (timer-schedule! t (lambda () #f) 1000)
  (test-assert "timer-cancel!: a normal cancellation does not raise"
    (guard (c (#t #f)) (timer-cancel! t) #t)))

;; R7RS `raise` accepts any object, including #f -- a task that (raise #f)s
;; with no handler must still have timer-cancel! re-raise it, not confuse
;; it with the "nothing preserved" case (both would otherwise look like
;; plain #f). The thunk signals immediately before raising so the test
;; waits for that instead of guessing a fixed delay.
(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'about-to-raise) (raise #f)) 30)
  (test-equal "no error-handler: the task runs before we attempt to cancel"
              'about-to-raise (channel-receive sig 3.0 'timeout))
  (test-assert "timer-cancel!: re-raises a preserved condition that is itself #f"
    (guard (c ((not c) #t) (#t #f)) (timer-cancel! t) #f)))

;; Same hazard, but with the exact symbol this library's own internal
;; "no error" sentinel used to be, before timer-cancel!'s reply was changed
;; to a tagged ('ok . #f) / ('error . condition) pair specifically to make
;; this class of collision structurally impossible rather than merely an
;; unlikely name choice.
(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'about-to-raise) (raise 'srfi-120-no-error)) 30)
  (test-equal "no error-handler: the task runs before we attempt to cancel (sentinel-lookalike case)"
              'about-to-raise (channel-receive sig 3.0 'timeout))
  (test-assert "timer-cancel!: re-raises a preserved condition equal to the old sentinel symbol"
    (guard (c ((eq? c 'srfi-120-no-error) #t) (#t #f)) (timer-cancel! t) #f)))

(let ((runner (test-runner-current)))
  (test-end "srfi-120")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
