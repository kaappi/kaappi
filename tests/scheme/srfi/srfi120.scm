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
  ;; SRFI 120: "the procedure returns given id" on success.
  (test-equal "timer-reschedule!: returns the id when the task was pending"
              id (timer-reschedule! t id 50))
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
  (test-equal "timer-cancel!: at least one firing happens before cancellation"
              'tick (channel-receive sig 1.0 'timeout))
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
              'timeout (channel-receive sig 1.0 'timeout))
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
              'handler-ran (channel-receive sig 2.0 'timeout))
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
              'about-to-raise (channel-receive sig 2.0 'timeout))
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
              'about-to-raise (channel-receive sig 2.0 'timeout))
  (test-assert "timer-cancel!: re-raises a preserved condition equal to the old sentinel symbol"
    (guard (c ((eq? c 'srfi-120-no-error) #t) (#t #f)) (timer-cancel! t) #f)))

(let ((runner (test-runner-current)))
  (test-end "srfi-120")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
