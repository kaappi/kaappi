;; SRFI-120 thread-boundary characterisation (audit v2 Phase 5A, kaappi#1890).
;;
;; Why this file exists
;; -------------------
;; lib/srfi/120.sld's header carried, in some form, a claim that a *second*
;; thread calling into a timer produced nondeterministic memory corruption,
;; "not root-caused". That claim is retired: every way a `<timer>` can reach
;; another thread is refused, and refused by a *named* mechanism. This file
;; pins those refusals, so the retirement cannot silently regress into being
;; true again.
;;
;; The two mechanisms are unrelated, and conflating them is the mistake this
;; file is designed to prevent (see docs/dev/thread-value-sharing.md, and
;; tests/scheme/srfi/srfi18-sharing-model.scm for the general matrix):
;;
;;   COPY ROUTE -- a thread-start! thunk closure, a thread-join! result, a
;;   channel message payload. Governed by gc_deep_copy.zig's fourteen-tag
;;   uncopyable list. A <timer> holds a thread handle, which is a `.fiber`,
;;   which is on that list -- so a timer is structurally uncopyable and the
;;   copy fails as a whole.
;;
;;   GLOBALS ROUTE -- a top-level binding, shared by pointer, never copied.
;;   The uncopyable list does not apply at all here. What refuses instead is
;;   the per-primitive `Object.owner` check, and only two types have one:
;;   channels (primitives_fiber.zig) and thread handles
;;   (primitives_srfi18.checkThreadOwner). A <timer>'s two fields are exactly
;;   those two types, which is the whole reason this route is covered.
;;
;; So the constraint is engine-enforced twice over, by two different guards,
;; and a change to either one on its own would leave a hole. Hence: both,
;; here, named.
;;
;; Every channel-receive below is bounded, and every thread started is
;; joined -- a wedged probe would otherwise take the whole runner down.

(import (scheme base) (scheme write) (srfi 18) (srfi 120) (srfi 64)
        (kaappi fibers))

(test-begin "srfi-120-thread-boundary")

(define (msg-of e) (if (error-object? e) (error-object-message e) e))

;; Runs THUNK on a child thread; answers its value, or (raised . message)
;; for whichever raises first -- the child itself (globals route: the
;; primitive refuses on the child) or the join (copy route: thread-start!
;; never spawns anything and the refusal surfaces at the join). Both shapes
;; reduce to one answer. Mirrors srfi18-sharing-model.scm's `on-child`.
(define (on-child thunk)
  (let ((t (make-thread
            (lambda ()
              (guard (e (#t (cons 'raised (msg-of e))))
                (thunk))))))
    (guard (e (#t (cons 'raised (msg-of e))))
      (thread-start! t)
      (thread-join! t))))

(define (raised? x) (and (pair? x) (eq? (car x) 'raised)))

(define (contains? haystack needle)
  (let ((hl (string-length haystack)) (nl (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nl) hl) #f)
            ((string=? (substring haystack i (+ i nl)) needle) #t)
            (else (loop (+ i 1)))))))

;; ---------------------------------------------------------------------
;; COPY ROUTE: a <timer> is structurally uncopyable, in every direction.
;; ---------------------------------------------------------------------

;; Captured by a child thread's thunk. thread-start! runs the copy on the
;; parent, hits the `.fiber` inside the record, and leaves the fiber
;; .errored without ever spawning an OS thread.
(let ((tmr (make-timer)))
  (let ((answer (on-child (lambda () (timer? tmr)))))
    (test-assert "copy route: a timer captured by a child thunk is refused, not delivered"
                 (raised? answer)))
  (timer-cancel! tmr))

;; As a channel message payload. Same list, different boundary, and here the
;; message names the reason outright.
;;
;; The channel must actually be shared with another thread first: a channel
;; nobody else holds is unpromoted, and a send on one enqueues the value as
;; is with no copy at all -- so the uncopyable list never runs and a timer
;; goes through. That is correct (nothing crossed a heap), and it is why the
;; local case is asserted separately below rather than left to look like a
;; missing check.
(let* ((tmr (make-timer))
       (ch (make-channel))
       (peer (make-thread (lambda () (channel-receive ch 3.0 'timeout)))))
  (thread-start! peer)          ; promotes ch; the timer now has a heap to cross
  (test-assert "copy route: sending a timer to another thread over a channel raises"
    (guard (e (#t (contains? (msg-of e) "uncopyable")))
      (channel-send ch tmr)
      #f))
  (thread-join! peer)
  (timer-cancel! tmr))

;; The control for the case above: same call, same value, no second thread.
(let ((tmr (make-timer))
      (ch (make-channel)))
  (test-assert "copy route: a send on an unshared channel does not copy, so a timer passes"
    (guard (e (#t #f))
      (channel-send ch tmr)
      (timer? (channel-receive ch 1.0 'timeout))))
  (timer-cancel! tmr))

;; Inside a task thunk. timer-schedule! ships the thunk over the control
;; channel, so a thunk closing over a *second* timer crosses the same
;; boundary -- an entry path that is easy to miss because it looks purely
;; local, with no thread-start! in sight.
(let ((a (make-timer))
      (b (make-timer)))
  (test-assert "copy route: timer-schedule! refuses a thunk that closes over another timer"
    (guard (e (#t (contains? (msg-of e) "uncopyable")))
      (timer-schedule! a (lambda () (timer? b)) 10)
      #f))
  (timer-cancel! a)
  (timer-cancel! b))

;; ---------------------------------------------------------------------
;; GLOBALS ROUTE: nothing is copied, so the uncopyable list never runs.
;; The control channel's own owner check is what refuses.
;; ---------------------------------------------------------------------

(define top-level-timer (make-timer))

(let ((answer (on-child (lambda () (timer-task-exists? top-level-timer 0)))))
  (test-assert "globals route: a query on a foreign timer raises"
               (raised? answer))
  (test-assert "globals route: and it is the CHANNEL owner check that refuses, not the copy route"
               (and (raised? answer) (contains? (cdr answer) "another thread"))))

;; timer-cancel! would also thread-join! a foreign handle -- but it sends
;; first, so the channel check is what the caller actually sees. Pinned
;; because a future refactor that reorders those two would change which
;; guard is load-bearing.
(let ((answer (on-child (lambda () (timer-cancel! top-level-timer)))))
  (test-assert "globals route: timer-cancel! on a foreign timer raises"
               (raised? answer))
  (test-assert "globals route: timer-cancel! is refused by the control channel, before the join"
               (and (raised? answer) (contains? (cdr answer) "another thread"))))

;; A timer reached through a mutable top-level *container* is the same
;; route: only the cell needs to be top-level for the record to be shared
;; by pointer. Worth its own case -- the header's rule is phrased about
;; bindings, and this shape has no timer-valued binding at all.
(define timer-cell (list #f))
(set-car! timer-cell top-level-timer)

(let ((answer (on-child (lambda () (timer-task-exists? (car timer-cell) 0)))))
  (test-assert "globals route: a timer reached through a top-level cell is refused too"
               (and (raised? answer) (contains? (cdr answer) "another thread"))))

(timer-cancel! top-level-timer)

;; ---------------------------------------------------------------------
;; What a task thunk may and may not close over. The header states this as
;; a rule; these are the two halves of it.
;; ---------------------------------------------------------------------

;; A LEXICALLY captured channel is the supported way to observe a task.
(let ((tmr (make-timer))
      (sig (make-channel)))
  (timer-schedule! tmr (lambda () (channel-send sig 'fired)) 10)
  (test-equal "task thunk: a lexically captured channel delivers"
              'fired (channel-receive sig 5.0 'timeout))
  (timer-cancel! tmr))

;; A TOP-LEVEL channel does not: the thunk is copied into the timer's heap
;; but the channel is not, so the send hits a channel this thread does not
;; own. With no error-handler the timer stops and preserves the condition,
;; and SRFI 120 has timer-cancel! re-raise it -- which is how the refusal
;; becomes visible to the caller.
(define top-level-channel (make-channel))

(let ((tmr (make-timer)))
  (timer-schedule! tmr (lambda () (channel-send top-level-channel 'fired)) 10)
  (test-equal "task thunk: a top-level channel delivers nothing"
              'timeout (channel-receive top-level-channel 2.0 'timeout))
  (test-assert "task thunk: and timer-cancel! re-raises the channel-ownership refusal"
    (guard (e (#t (contains? (msg-of e) "another thread")))
      (timer-cancel! tmr)
      #f)))

;; The inversion, which is the part of the rule people get backwards: for a
;; mutex, capture is what fails and a top-level binding is what works --
;; exactly the opposite of a channel. Both halves, so the pair is visible.
(let ((m (make-mutex))
      (tmr (make-timer)))
  (test-assert "task thunk: a lexically captured mutex is refused (copy route rejects .mutex)"
    (guard (e (#t (contains? (msg-of e) "uncopyable")))
      (timer-schedule! tmr (lambda () (mutex-lock! m)) 10)
      #f))
  (timer-cancel! tmr))

(define top-level-mutex (make-mutex))

(let ((tmr (make-timer))
      (sig (make-channel)))
  (timer-schedule! tmr
                   (lambda ()
                     (mutex-lock! top-level-mutex)
                     (mutex-unlock! top-level-mutex)
                     (channel-send sig 'locked))
                   10)
  (test-equal "task thunk: a top-level mutex IS usable from the timer thread"
              'locked (channel-receive sig 5.0 'timeout))
  (timer-cancel! tmr))

;; ---------------------------------------------------------------------
;; A task's writes are not a way to observe it -- for two different
;; reasons, depending on how the datum was reached. Both are pinned
;; because a reader who only knows one of them will draw the wrong
;; conclusion from the other.
;; ---------------------------------------------------------------------

;; Lexically captured: the thunk got its own COPY, so the caller's pair is
;; untouched. The mutation is invisible, not racy.
(let ((tmr (make-timer))
      (p (list 'untouched))
      (sig (make-channel)))
  (timer-schedule! tmr (lambda () (set-car! p 'touched) (channel-send sig (car p))) 10)
  (test-equal "task writes: the thunk sees its own copy mutated"
              'touched (channel-receive sig 5.0 'timeout))
  (test-equal "task writes: the caller's lexically captured pair is untouched (it was copied)"
              'untouched (car p))
  (timer-cancel! tmr))

;; Top-level: shared by pointer, so the write really does land in the
;; caller's heap, from a thread with its own independent collector. This is
;; the unchecked case -- asserted as it behaves so that a fix for #1924
;; fails here and this file gets updated with it, not so that anyone treats
;; it as supported.
(define shared-pair (list 'untouched))

(let ((tmr (make-timer))
      (sig (make-channel)))
  (timer-schedule! tmr (lambda () (set-car! shared-pair 'touched) (channel-send sig 'done)) 10)
  (test-equal "task writes: the task completes"
              'done (channel-receive sig 5.0 'timeout))
  (test-equal "task writes: a top-level pair IS written through (globals route, unchecked -- #1924)"
              'touched (car shared-pair))
  (timer-cancel! tmr))

;; ---------------------------------------------------------------------
;; #2129 (fixed in the v0.22.2 audit): make-timer inside a SRFI-18 thread
;; used to crash the process at that thread's join -- thread-join! freed the
;; joined thread's GC/VM while the timer thread (a grandchild) was still
;; dereferencing its fiber handle in the joined heap. 24/30 on ReleaseSafe,
;; 13/15 under -Dgc-stress=true; commented out because it aborted the whole
;; runner. The join now raises the documented "result contains an uncopyable
;; type" error (the timer record holds a thread handle) and the timer thread
;; keeps running against the RETIRED -- not freed -- middle heap (see
;; srfi18-join-spawn-grandchild-2129.scm). Asserted live: the old failure
;; mode was a process abort, so a regression must surface as a loud runner
;; failure, not a skipped block. The uncancelled timer thread leaks until
;; process exit, like any unjoined thread.
(let ((t (make-thread (lambda () (make-timer)))))
  (thread-start! t)
  (test-assert "a timer created inside a thread does not survive its join"
    (guard (e (#t #t)) (thread-join! t) #f)))

(let ((runner (test-runner-current)))
  (test-end "srfi-120-thread-boundary")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
