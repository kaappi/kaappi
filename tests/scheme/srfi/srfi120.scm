;; SRFI-120 (Timer APIs) conformance test.
;;
;; A scheduled thunk runs on the timer's own dedicated thread, which has an
;; independent GC heap from the thread that called timer-schedule! (see
;; lib/srfi/120.sld's header comment) -- so every test here observes task
;; execution through a (kaappi fibers) channel, never through mutating a
;; pair/box the calling thread also holds. `(channel-receive sig timeout
;; 'timeout)` is used throughout so a bug that makes a task never fire
;; times out instead of hanging the whole suite.

(import (scheme base) (scheme write) (srfi 18) (kaappi fibers) (srfi 64) (srfi 120))

(test-begin "srfi-120")

;;; --- make-timer-delta / timer-delta? ---------------------------------

(test-assert "timer-delta?: a constructed delta satisfies the predicate"
  (timer-delta? (make-timer-delta 1 'seconds)))
(test-assert "timer-delta?: a plain integer does not satisfy the predicate"
  (not (timer-delta? 5)))

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
              'fired (channel-receive sig 2.0 'timeout))
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
              'fired (channel-receive sig 2.0 'timeout))
  (timer-cancel! t))

;;; --- periodic scheduling -------------------------------------------------

(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'tick)) 40 40)
  (test-equal "timer-schedule!: periodic task fires a 1st time"
              'tick (channel-receive sig 2.0 'timeout))
  (test-equal "timer-schedule!: periodic task fires a 2nd time"
              'tick (channel-receive sig 2.0 'timeout))
  (test-equal "timer-schedule!: periodic task fires a 3rd time"
              'tick (channel-receive sig 2.0 'timeout))
  (timer-cancel! t))

;;; --- timer-task-exists? / timer-task-remove! ------------------------------

(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'fired)) 300)))
  (test-assert "timer-task-exists?: #t right after scheduling"
    (timer-task-exists? t id))
  (test-assert "timer-task-remove!: #t when the task was pending"
    (timer-task-remove! t id))
  (test-assert "timer-task-exists?: #f after removal"
    (not (timer-task-exists? t id)))
  (test-equal "timer-task-remove!: the removed task never fires"
              'timeout (channel-receive sig 0.5 'timeout))
  (test-assert "timer-task-remove!: #f for an id that is no longer pending"
    (not (timer-task-remove! t id)))
  (timer-cancel! t))

;;; --- timer-reschedule! ---------------------------------------------------

(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'fired)) 1000)))
  (test-assert "timer-reschedule!: #t when the task was pending"
    (timer-reschedule! t id 50))
  (test-equal "timer-reschedule!: the task fires at the NEW time, not the original"
              'fired (channel-receive sig 1.0 'timeout))
  (test-assert "timer-reschedule!: #f for an id that no longer exists"
    (not (timer-reschedule! t id 50)))
  (timer-cancel! t))

;; The spec's documented idiom: reschedule with period 0 turns a periodic
;; task into a one-shot.
(let* ((sig (make-channel))
       (t (make-timer))
       (id (timer-schedule! t (lambda () (channel-send sig 'tick)) 40 40)))
  (test-equal "period-0 reschedule: the task still fires once more first"
              'tick (channel-receive sig 1.0 'timeout))
  (timer-reschedule! t id 1000 0)
  (test-equal "period-0 reschedule: no further periodic firing follows"
              'timeout (channel-receive sig 0.3 'timeout))
  (timer-cancel! t))

;;; --- timer-cancel! -------------------------------------------------------

(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (channel-send sig 'tick)) 30 30)
  (channel-receive sig 1.0 'timeout) ; let at least one firing happen
  (timer-cancel! t)
  (test-equal "timer-cancel!: no further firings after cancellation"
              'timeout (channel-receive sig 0.3 'timeout)))

;;; --- error-handler ---------------------------------------------------------

(let* ((sig (make-channel))
       (t (make-timer (lambda (condition) (channel-send sig 'handled)))))
  (timer-schedule! t (lambda () (error "srfi-120 test: deliberate task error")) 30)
  (test-equal "error-handler: invoked when a task's thunk raises"
              'handled (channel-receive sig 1.0 'timeout))
  (timer-schedule! t (lambda () (channel-send sig 'still-alive)) 30)
  (test-equal "error-handler: the timer keeps running after a handled error"
              'still-alive (channel-receive sig 1.0 'timeout))
  (timer-cancel! t))

;; No handler at all: the timer must stop after the first task error rather
;; than silently continuing (observed indirectly -- a task scheduled after
;; the failing one must never fire once the timer has stopped).
(let* ((sig (make-channel))
       (t (make-timer)))
  (timer-schedule! t (lambda () (error "srfi-120 test: unhandled")) 30)
  (timer-schedule! t (lambda () (channel-send sig 'should-not-fire)) 200)
  (test-equal "no error-handler: the timer stops, so later tasks never fire"
              'timeout (channel-receive sig 1.0 'timeout)))

(let ((runner (test-runner-current)))
  (test-end "srfi-120")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
