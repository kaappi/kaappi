;; Regression test for #2194: thread-join! on a (kaappi fibers) fiber that
;; has been spawn'd but never dispatched hangs forever.
;;
;; thread-join!'s "never-started" path polled fiber.status in a sleepNs loop
;; without ever driving the scheduler. For a make-thread handle awaiting
;; thread-start! from outside that is exactly right (#878) -- the status
;; changes from outside. For a spawn'd fiber (sched_idx != 0; only this
;; thread's cooperative scheduler can dispatch it) the poll loop IS the
;; starvation: the status can never change, so without a timeout the join
;; hung forever on a fiber that would have completed instantly -- and with a
;; deadline it reported a timeout for that same fiber, a wrong answer rather
;; than merely a slow one. fiber-join on the very same object returned
;; immediately, which is the discriminating control below.
;;
;; Every probe is bounded (explicit deadline) so a regression fails loudly
;; with 'timed-out instead of wedging the test runner.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (srfi 64) (kaappi fibers))

(test-begin "srfi18-join-created-fiber-2194")

;; Control: fiber-join on a never-dispatched fiber already worked before the
;; fix (it drives the scheduler). Pins that the machinery itself is sound.
(test-equal "fiber-join on a never-dispatched fiber returns its value"
  'v (fiber-join (spawn (lambda () 'v))))

;; The bug: thread-join! on the same never-dispatched fiber hung forever
;; (no timeout => unbounded poll). With a bound it reported a timeout for a
;; fiber that would have completed instantly. Post-fix the scheduler
;; dispatches it and the join returns the value.
(test-equal "thread-join! on a never-dispatched fiber returns its value (was: hang)"
  'v (thread-join! (spawn (lambda () 'v)) 5 'timed-out))

;; Same shape with a second thunk: the deadline must not be hit -- the
;; fiber is dispatched and completes before the timer fires.
(test-equal "thread-join! with a deadline on a never-dispatched fiber"
  42 (thread-join! (spawn (lambda () 42)) 5 'timed-out))

;; A never-dispatched fiber whose thunk never completes must not hang the
;; join either: the fiber path bounds the park on the reactor timer and
;; reports the timeout value.
(test-equal "thread-join! on an uncompletable never-dispatched fiber times out"
  'timed-out
  (thread-join! (spawn (lambda () (channel-receive (make-channel)))) 0.5 'timed-out))

;; The other half of the sched_idx discriminator: a make-thread handle
;; joined before it is ever started must keep the #878 poll path (sched_idx
;; == 0), not fall through to the fiber path. With a deadline the poll
;; reports the timeout value; the fiber path would instead raise a deadlock
;; error (nothing local can ever complete the target), which is how the two
;; are told apart. The same handle must then start and join normally.
(test-equal "a never-started make-thread handle times out rather than taking the fiber path"
  'timed-out
  (let ((t (make-thread (lambda () 'late))))
    (thread-join! t 0.2 'timed-out)))

(test-equal "a handle that timed out unstarted starts and joins normally afterwards"
  'late
  (let ((t (make-thread (lambda () 'late))))
    (thread-join! t 0.2 'timed-out)
    (thread-start! t)
    (thread-join! t)))

;; The make-thread side of the sched_idx discriminator must keep working: a
;; handle whose OS thread has completed still joins normally.
(test-equal "thread-join! on a completed OS thread still joins"
  7 (let ((t (make-thread (lambda () 7))))
      (thread-start! t)
      (thread-join! t)))

(let ((runner (test-runner-current)))
  (test-end "srfi18-join-created-fiber-2194")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
