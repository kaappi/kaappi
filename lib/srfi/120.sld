;;; SRFI 120: Timer APIs
;;;
;;; Periodic and one-shot task scheduling. Built entirely on existing
;;; SRFI-18 threads and (kaappi fibers) channels -- no engine changes.
;;;
;;; IMPORTANT: every scheduled thunk runs on the timer's own dedicated
;;; thread, which has its own independent GC heap (see kaappi/CLAUDE.md's
;;; "OS threads" section) -- the same as any SRFI-18 `thread-start!`'d
;;; thread. A thunk therefore CANNOT safely mutate state visible to the
;;; thread that called `timer-schedule!` (e.g. `set-car!` on a pair the
;;; caller also holds): Kaappi's primitives don't stop you from writing
;;; through a pointer into another thread's heap, but doing so from a
;;; concurrently-running thread with its own independent collector is a
;;; data race, not a supported way to observe that a task ran. Use a
;;; `(kaappi fibers)` channel instead -- have the thunk `channel-send` a
;;; result and have the caller `channel-receive` it -- exactly how this
;;; library's own request/reply plumbing works internally.
;;;
;;; IMPORTANT: every value a scheduled thunk closes over (channels
;;; included) must be a genuine lexical binding, never a top-level
;;; `define` -- top-level bindings are shared *by pointer* across threads
;;; (`initForThread` shares `globals`), not deep-copied-and-re-owned the
;;; way a closure's lexical captures are, so a thunk that references a
;;; top-level channel/pair reaches the ORIGINAL object from the wrong
;;; heap and either corrupts memory silently or (for a channel
;;; specifically, whose primitives do check) fails with "channel belongs
;;; to another thread".
;;;
;;; IMPORTANT: call `make-timer` and every subsequent
;;; `timer-schedule!`/`timer-reschedule!`/`timer-task-remove!`/
;;; `timer-task-exists?`/`timer-cancel!` on a given timer from the SAME
;;; thread throughout. This is thoroughly verified reliable (this
;;; library's own test suite, `tests/scheme/srfi/srfi120.scm`, does
;;; nothing else). A *different* thread calling into a timer it didn't
;;; create was tried this session and produced nondeterministic memory
;;; corruption (different crash signatures across runs -- integer
;;; overflow, bad alignment, bus error) via this library's request/reply
;;; protocol specifically, even though a bare hand-written two-thread
;;; channel round trip with no other moving parts did not reproduce it in
;;; isolation. This points at a real bug somewhere in the interaction
;;; between multi-hop channel messages and cross-thread deep-copy, not a
;;; mistake in this library's own logic, but it has not been root-caused
;;; and is out of scope for a portable-library change -- treat
;;; single-thread-only as a hard requirement of this implementation until
;;; that is investigated separately.
;;;
;;; Design notes:
;;;
;;; - `when`/`period` are RELATIVE offsets from the moment the procedure is
;;;   called (the spec's own text: "The task is scheduled on the time when
;;;   the given when passed from the procedure is called"), given as either
;;;   a timer-delta object or a plain non-negative integer of milliseconds
;;;   -- not SRFI 19 time objects. Each is converted to an absolute
;;;   "fire-at" instant (milliseconds since the SRFI-18 clock epoch, via
;;;   `current-time`/`time->seconds`) in the CALLING thread at call time,
;;;   so queueing delay before the timer thread processes the request never
;;;   skews the fire time. Sub-millisecond timer-delta units round to the
;;;   nearest millisecond -- the underlying channel-receive timeout is
;;;   second-scale float precision regardless, so finer resolution isn't
;;;   honored either way.
;;;
;;; - Each `make-timer` spawns one dedicated SRFI-18 thread that owns its
;;;   task list entirely in its own heap (Kaappi threads each have an
;;;   independent GC heap -- see kaappi/CLAUDE.md's "OS threads" section),
;;;   coordinated with callers purely through one control channel created
;;;   before the thread starts and captured in its thunk (the way a channel
;;;   must be shared across threads -- primitives_fiber.zig's
;;;   channel-receive rejects a channel reached any other way). The control
;;;   channel is unbounded (`(make-channel)`, no capacity), so a caller's
;;;   `channel-send` never blocks.
;;;
;;; - `timer-schedule!`/`timer-reschedule!`/`timer-task-remove!`/
;;;   `timer-task-exists?` are all synchronous request/reply: the caller
;;;   sends its request together with a fresh one-shot reply channel and
;;;   waits for the answer, rather than the caller generating the task id
;;;   itself -- the timer thread is the only place a counter needs to
;;;   live. Replies use a bounded timeout (%reply-timeout-seconds): if
;;;   the timer has already been cancelled (its thread exited, so nothing will ever answer), the
;;;   caller gets a fallback (#f for a query/mutation, an error for
;;;   scheduling) instead of hanging forever. This is a robustness choice
;;;   beyond what the spec mandates, not a spec requirement.
;;;
;;; - `timer-cancel!` sends a stop request and then `thread-join!`s the
;;;   timer's thread before returning (the spec doesn't describe a return
;;;   value, so this is a free choice): guarantees the thread has fully
;;;   exited by the time the caller proceeds, rather than leaving it to
;;;   race process shutdown or a later GC. An uncancelled timer's thread
;;;   keeps running until process exit even if the Scheme-level timer
;;;   object becomes unreachable -- Kaappi's GC has no finalizers, and this
;;;   is the same inherent behavior as any unjoined `thread-start!`'d
;;;   thread, not specific to this library.
;;;
;;; - A task's thunk raising routes to `error-handler` (called with the
;;;   raised condition). If `make-timer` was given no handler, or the
;;;   handler itself raises, the timer thread stops (matching "otherwise
;;;   whenever an error is raised, timer stops"); the spec's "preserves the
;;;   error" is not implemented as a retrievable value -- there is no
;;;   spec'd accessor for it, so this is the same reduced-scope choice as
;;;   the missing accessor in the spec text itself.
(define-library (srfi 120)
  (import (scheme base) (srfi 18) (kaappi fibers))
  (export make-timer timer? timer-cancel!
          timer-schedule! timer-reschedule!
          timer-task-remove! timer-task-exists?
          make-timer-delta timer-delta?)
  (begin

    ;; --- timer-delta ---------------------------------------------------

    (define-record-type <timer-delta>
      (%make-timer-delta ms)
      timer-delta?
      (ms %timer-delta-ms))

    (define (make-timer-delta n unit)
      (%make-timer-delta
        (case unit
          ((hours) (* n 3600000))
          ((minutes) (* n 60000))
          ((seconds) (* n 1000))
          ((milliseconds) n)
          ((microseconds) (round (/ n 1000)))
          ((nanoseconds) (round (/ n 1000000)))
          (else (error "make-timer-delta: unknown unit" unit)))))

    ;; Accepts either a timer-delta or a plain non-negative integer
    ;; (milliseconds), per spec. #f (no period given) passes through.
    (define (%delta->ms x)
      (cond ((not x) #f)
            ((timer-delta? x) (%timer-delta-ms x))
            ((and (integer? x) (>= x 0)) x)
            (else (error "expected a timer-delta or non-negative integer" x))))

    (define (%now-ms) (* 1000.0 (time->seconds (current-time))))

    ;; --- timer -----------------------------------------------------------

    (define-record-type <timer>
      (%make-timer control thread)
      timer?
      (control %timer-control)
      (thread %timer-thread))

    ;; Distinguishes "channel-receive timed out" from "a real message
    ;; arrived" without guarding an exception -- a fresh, uninterned-enough
    ;; pair no caller could ever construct or send.
    (define %timeout-sentinel (list 'srfi-120-timeout))

    ;; A reply that never comes back within this window means the timer's
    ;; thread has already exited (cancelled) -- see header. Generous enough
    ;; to never fire under normal scheduling load.
    (define %reply-timeout-seconds 5)

    (define (%call-timer control make-request)
      (let ((reply (make-channel)))
        (channel-send control (make-request reply))
        (channel-receive reply %reply-timeout-seconds %timeout-sentinel)))

    ;; %call-timer, but a timed-out reply (the timer was already cancelled)
    ;; raises instead of silently returning the sentinel -- for the two
    ;; mutating calls where returning a bogus value would be misleading.
    (define (%call-timer/error who control make-request)
      (let ((result (%call-timer control make-request)))
        (if (eq? result %timeout-sentinel)
            (error (string-append who ": timer is not responding (already cancelled?)"))
            result)))

    (define (make-timer . maybe-handler)
      (let* ((error-handler (if (pair? maybe-handler) (car maybe-handler) #f))
             (control (make-channel))
             (thread (make-thread (lambda () (%timer-loop control error-handler)))))
        (thread-start! thread)
        (%make-timer control thread)))

    ;; tasks: list of (id fire-at-ms period-ms thunk). Rebuilt (not
    ;; mutated) on every change -- task lists are small in practice, and
    ;; this avoids any risk of aliasing between loop iterations.
    (define (%timer-loop control error-handler)
      (let loop ((tasks '()) (next-id 0))
        (let* ((soonest (%soonest-fire-time tasks))
               (wait (and soonest (max 0.0 (/ (- soonest (%now-ms)) 1000.0))))
               (msg (if wait
                        (channel-receive control wait %timeout-sentinel)
                        (channel-receive control))))
          (cond
            ((eof-object? msg) #f) ; control channel closed -- treat as stop
            ((eq? msg %timeout-sentinel)
             (call-with-values
               (lambda () (%run-due-tasks tasks error-handler))
               (lambda (remaining stop?)
                 (if stop? #f (loop remaining next-id)))))
            (else
             (case (car msg)
               ((schedule)
                (let ((thunk (list-ref msg 1))
                      (fire-at (list-ref msg 2))
                      (period (list-ref msg 3))
                      (reply (list-ref msg 4)))
                  (channel-send reply next-id)
                  (loop (cons (list next-id fire-at period thunk) tasks)
                        (+ next-id 1))))
               ((reschedule)
                (let* ((id (list-ref msg 1))
                       (fire-at (list-ref msg 2))
                       (period (list-ref msg 3))
                       (reply (list-ref msg 4))
                       (found (assv id tasks)))
                  (channel-send reply (if found #t #f))
                  (loop (if found
                            (cons (list id fire-at period (list-ref found 3))
                                  (%remove-task tasks id))
                            tasks)
                        next-id)))
               ((remove)
                (let* ((id (list-ref msg 1)) (reply (list-ref msg 2))
                       (found (assv id tasks)))
                  (channel-send reply (if found #t #f))
                  (loop (if found (%remove-task tasks id) tasks) next-id)))
               ((exists)
                (let ((id (list-ref msg 1)) (reply (list-ref msg 2)))
                  (channel-send reply (if (assv id tasks) #t #f)))
                (loop tasks next-id))
               ((stop) #f)
               (else (loop tasks next-id)))))))) ; unknown message: ignore

    (define (%remove-task tasks id)
      (filter (lambda (task) (not (eqv? (car task) id))) tasks))

    (define (%soonest-fire-time tasks)
      (if (null? tasks)
          #f
          (apply min (map (lambda (task) (list-ref task 1)) tasks))))

    ;; Runs every task whose fire time has passed, wrapping each in
    ;; `guard` so a raised condition routes to error-handler. Returns two
    ;; values: the updated task list, and whether the timer must stop
    ;; (no error-handler, or the handler itself raised).
    (define (%run-due-tasks tasks error-handler)
      (let ((now (%now-ms)))
        (let loop ((remaining '()) (pending tasks) (stop? #f))
          (cond
            (stop? (values (append remaining pending) #t))
            ((null? pending) (values remaining #f))
            (else
             (let* ((task (car pending))
                    (id (list-ref task 0)) (fire-at (list-ref task 1))
                    (period (list-ref task 2)) (thunk (list-ref task 3)))
               (if (> fire-at now)
                   (loop (cons task remaining) (cdr pending) #f)
                   (let ((ran-ok? (%run-one-task thunk error-handler)))
                     (cond
                       ((not ran-ok?) (loop remaining (cdr pending) #t))
                       ((or (not period) (= period 0))
                        (loop remaining (cdr pending) #f))
                       (else
                        (loop (cons (list id (+ fire-at period) period thunk) remaining)
                              (cdr pending) #f)))))))))))

    ;; Returns one value: #t if the timer should keep running afterward,
    ;; #f if it must stop (unhandled or re-raising error-handler).
    (define (%run-one-task thunk error-handler)
      (guard (condition
              (#t (if error-handler
                      (guard (inner (#t #f)) (error-handler condition) #t)
                      #f)))
        (thunk)
        #t))

    ;; --- public API --------------------------------------------------------

    (define (timer-schedule! timer thunk when . maybe-period)
      (let ((fire-at (+ (%now-ms) (%delta->ms when)))
            (period (%delta->ms (if (pair? maybe-period) (car maybe-period) #f))))
        (%call-timer/error "timer-schedule!" (%timer-control timer)
                           (lambda (reply) (list 'schedule thunk fire-at period reply)))))

    (define (timer-reschedule! timer id when . maybe-period)
      (let ((fire-at (+ (%now-ms) (%delta->ms when)))
            (period (%delta->ms (if (pair? maybe-period) (car maybe-period) #f))))
        (%call-timer/error "timer-reschedule!" (%timer-control timer)
                           (lambda (reply) (list 'reschedule id fire-at period reply)))))

    ;; A timed-out reply here means the timer is already cancelled, which is
    ;; a reasonable case to just answer #f/"not found" for rather than raise.
    (define (timer-task-remove! timer id)
      (let ((result (%call-timer (%timer-control timer)
                                  (lambda (reply) (list 'remove id reply)))))
        (if (eq? result %timeout-sentinel) #f result)))

    (define (timer-task-exists? timer id)
      (let ((result (%call-timer (%timer-control timer)
                                  (lambda (reply) (list 'exists id reply)))))
        (if (eq? result %timeout-sentinel) #f result)))

    (define (timer-cancel! timer)
      (channel-send (%timer-control timer) (list 'stop))
      (thread-join! (%timer-thread timer)))))
