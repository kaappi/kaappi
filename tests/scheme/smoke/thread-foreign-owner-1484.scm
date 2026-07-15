;; Regression test for #1484: fiber (thread) primitives reject a *foreign*
;; thread handle -- one reached from another OS thread through a shared global
;; -- the same way channel-send/channel-receive reject a foreign channel.
;;
;; Part 1 (the safety fix): a fiber can only be shared across OS threads via a
;; global. Fibers are uncopyable (gc_deep_copy's `.fiber` arm), so they never
;; ride a thread thunk or a channel message; and a child thread's own
;; (current-thread) is a distinct fiber that ensureScheduler allocated on the
;; child heap. So `owner != gc.id` is exactly the concurrent-thread-join!
;; hazard: two threads both clearing the same os_thread and double-
;; `thread.join()`ing it (pthread UB), or the loser reading target.result
;; before the winner stored it. It is now a clean, catchable diagnostic.
;;
;; Part 2 (the design decision, KEP-0002 invariant 4): a channel reached
;; through a shared global and then *raised or returned* by a child thread is
;; refused, not silently voided. The exception/result copy runs on the child,
;; which does not own the channel, so Envelope.create rejects it and
;; thread-join! surfaces a descriptive error. This is the principled reading of
;; invariant 4 (the only legal cross-thread handle is a locally owned stub made
;; by deepCopy through a thunk or a message) -- restoring the old owner-, and
;; order-, dependent parity would reopen exactly the sharing this model forbids.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (kaappi fibers) (srfi 64))

(test-begin "thread-foreign-owner-1484")

;; `worker` is a genuine top-level define -> a real global resolved through
;; vm.globals, so a child thread's thunk that names it does NOT capture it as
;; an upvalue (which, being a fiber, would be rejected as uncopyable right at
;; thread-start! and exercise the wrong path). The child reads the shared
;; global at run time and gets the parent-owned fiber -- foreign to it. The
;; owner check is state-independent, so whether `worker` is still sleeping or
;; already finished when a child reaches it, the rejection is identical.
(define worker (make-thread (lambda () (thread-sleep! 0.2) 'worker-done)))
;; test-assert (not a bare top-level expression) so the fiber thread-start!
;; returns is not echoed by the file runner as stray stdout.
(test-assert "worker thread starts on its owning thread"
  (thread? (thread-start! worker)))

;; Runs `body-thunk` on a fresh child thread and returns whatever the child
;; reports back through `report` -- a channel captured (and so legally
;; promoted) into the child. The child guards its body so a foreign-owner
;; rejection comes back as the error's message string instead of crashing the
;; child. `body-thunk` closes over nothing but the `worker` global, so it
;; deep-copies into the child cleanly.
(define (observe-on-child body-thunk)
  (let ((report (make-channel)))
    (let ((child (make-thread
                   (lambda ()
                     (guard (e (#t (channel-send report
                                     (if (error-object? e)
                                         (error-object-message e)
                                         'non-error-condition))))
                       (body-thunk)
                       (channel-send report 'no-error-raised))))))
      (thread-start! child)
      (thread-join! child)
      (channel-receive report))))

(define (foreign-thread-error? msg)
  (and (string? msg) (string-contains msg "another OS thread")))

;; --- Part 1: foreign fiber handles are refused across OS threads ---

(test-assert "cross-thread thread-join! on a foreign handle is refused"
  (foreign-thread-error? (observe-on-child (lambda () (thread-join! worker)))))

(test-assert "cross-thread thread-terminate! on a foreign handle is refused"
  (foreign-thread-error? (observe-on-child (lambda () (thread-terminate! worker)))))

(test-assert "cross-thread thread-start! on a foreign handle is refused"
  (foreign-thread-error? (observe-on-child (lambda () (thread-start! worker)))))

(test-assert "cross-thread thread-specific on a foreign handle is refused"
  (foreign-thread-error? (observe-on-child (lambda () (thread-specific worker)))))

(test-assert "cross-thread thread-specific-set! on a foreign handle is refused"
  (foreign-thread-error?
    (observe-on-child (lambda () (thread-specific-set! worker 'x)))))

(test-assert "cross-thread thread-name on a foreign handle is refused"
  (foreign-thread-error? (observe-on-child (lambda () (thread-name worker)))))

;; --- Part 1 positive controls: same-thread use is completely unaffected ---

;; The terminate/start attempts above were all refused, so `worker` was never
;; touched by another thread and still runs to completion; its owner reaps it
;; normally.
(test-equal "the owning thread can still join its own thread"
  'worker-done
  (thread-join! worker))

(test-equal "the owning thread can still set and read thread-specific"
  'payload
  (let ((t (make-thread (lambda () #t))))
    (thread-specific-set! t 'payload)
    (thread-specific t)))

;; --- Part 2: shared-global channel refused at the exception/result boundary ---

;; Raised: threadEntryFn builds the exception envelope on the child, which does
;; not own `raised-ch`, so the copy fails and thread-join! reports an
;; uncaught-exception whose reason names the foreign-channel cause -- never a
;; silently voided join reason (the pre-#1483 wart this locks shut).
(define raised-ch (make-channel))
(test-assert "child raising a shared-global channel surfaces a descriptive error at join"
  (guard (e ((uncaught-exception? e)
             (let ((reason (uncaught-exception-reason e)))
               (and (error-object? reason)
                    (string-contains (error-object-message reason) "another thread")))))
    (thread-join! (thread-start! (make-thread (lambda () (raise raised-ch)))))
    #f))

;; Returned: the join-result copy likewise runs on the non-owning child, so
;; thread-join! raises "result contains ... a channel owned by another thread"
;; rather than handing back a corrupt cross-heap alias.
(define returned-ch (make-channel))
(test-assert "child returning a shared-global channel surfaces a descriptive error at join"
  (guard (e ((error-object? e)
             (string-contains (error-object-message e) "another thread")))
    (thread-join! (thread-start! (make-thread (lambda () returned-ch))))
    #f))

;; A channel legally shared through the thunk (captured, hence promoted) still
;; crosses back as a result untouched -- Part 2 refuses only the shared-global
;; path, not the sanctioned one.
(test-equal "a channel captured by the thunk still returns across the join"
  'ok
  (let* ((t (make-thread (lambda ()
                           (let ((inner (make-channel)))
                             (channel-send inner 'ok)
                             inner)))))
    (thread-start! t)
    (channel-receive (thread-join! t))))

(let ((runner (test-runner-current)))
  (test-end "thread-foreign-owner-1484")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
