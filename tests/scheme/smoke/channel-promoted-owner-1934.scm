;; Regression test for #1934: the channel ownership check must not depend on
;; whether the channel happens to be promoted.
;;
;; KEP-0002 invariant 4 says the only legal cross-thread channel handle is a
;; locally owned stub deepCopy made from a thunk capture or a message. The
;; unpromoted arm of gc_deep_copy.zig's `.channel` case enforced that; the
;; promoted arm skipped it entirely, so *promotion state alone* decided
;; whether the invariant applied. A thread that reached a promoted channel
;; through a shared global — which every primitive refuses it directly — could
;; still hand it to a child, and that child got a working stub for a channel
;; nobody ever gave it.
;;
;; The check now runs before `shared` is even read, in the export direction (a
;; value leaving the running thread's heap into an envelope). The import
;; direction — draining an envelope built by a thread that already passed the
;; export check — stays unchecked, which is what keeps the legal hand-off at
;; the bottom of this file working.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (kaappi fibers) (srfi 64))

(test-begin "channel-promoted-owner-1934")

;; A top-level channel, promoted the legal way: a first child captures it
;; lexically (`c`, not the global name), so thread-start!'s copy runs on the
;; owning thread and promotes it there.
(define ch (make-channel))
(define first-child
  (let ((c ch))
    (make-thread (lambda () (channel-send c 'from-first) 'ok))))
(test-assert "the first child starts" (thread? (thread-start! first-child)))
(test-equal "its message arrives — ch is promoted now" 'from-first (channel-receive ch))
(test-equal "the first child joins" 'ok (thread-join! first-child))

;; The escape. This child's thunk captures NOTHING: it names the top-level
;; binding, so it reads the parent's own promoted channel object out of the
;; shared globals map at run time. Handing that to a grandchild is the copy
;; the promoted arm used to wave through.
(define escaper
  (make-thread
   (lambda ()
     (let ((stolen ch))
       (guard (e (#t 'refused))
         (let ((gt (make-thread (lambda () (channel-send stolen 'from-grandchild) 'sent))))
           (thread-start! gt)
           (list 'escaped (thread-join! gt))))))))
(test-assert "the escaping child starts" (thread? (thread-start! escaper)))
(test-equal "a grandchild cannot be handed a channel reached through a global"
            'refused (thread-join! escaper))
(test-equal "and nothing was sent into the main thread's channel"
            'nothing (channel-receive ch 0 'nothing))

;; Discriminating control for the whole fix: the same three-generation shape,
;; but with the channel handed down legally at every step. The child owns the
;; stub thread-start! copied in for it, so passing it on is entitled and must
;; keep working — this is the case an owner check written without the
;; direction distinction would break.
(define ch2 (make-channel))
(define relay
  (let ((c ch2))
    (make-thread
     (lambda ()
       (let ((gt (make-thread (lambda () (channel-send c 'from-grandchild) 'sent))))
         (thread-start! gt)
         (thread-join! gt))))))
(test-assert "the relaying child starts" (thread? (thread-start! relay)))
(test-equal "a legally captured channel still reaches a grandchild"
            'from-grandchild (channel-receive ch2))
(test-equal "the relaying child joins" 'sent (thread-join! relay))

(let ((runner (test-runner-current)))
  (test-end "channel-promoted-owner-1934")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
