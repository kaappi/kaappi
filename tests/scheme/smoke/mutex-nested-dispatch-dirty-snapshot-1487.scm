;; Regression test for #1487: mutex-lock! sets a fiber .waiting and then
;; keeps nested-driving other fibers in the same native frame (the
;; while(true) + runSchedulerStep loop in mutexLockFn). If something wakes
;; that fiber while its own nested drive is still live -- deeper on the Zig
;; call stack, inside a *different* fiber's own nested drive -- the fiber
;; becomes visible to schedule()'s round-robin before its real call has
;; returned. A different fiber's own nested schedule() call could then
;; dispatch its stale, mid-call register snapshot, resuming bytecode past
;; the in-flight (mutex-lock! m) call with the destination register never
;; written. This is the identical corruption class already fixed for
;; channel-receive in PR #1485, just reachable here through mutex-lock!/
;; mutex-unlock!+condvar instead of channelReceiveShared.
;;
;; Shape: fiber b parks on mutex m1 (held by d) and starts its own nested
;; drive, which dispatches c. c parks on mutex m2 (also held by d) and
;; starts its own nested drive one level deeper, which repeatedly
;; redispatches d as d alternates unlocking and yielding. When d unlocks m1
;; (waking b) without yet unlocking m2, it is c's own loop -- not b's --
;; that next calls schedule(). Before the fix, schedule() could select b
;; right there; with the fix (a generic `driving` flag that schedule()/
;; hasRunnableFibers() never select/count, set for the whole extent of a
;; fiber's own runSchedulerStep call), b's own loop is the only thing that
;; ever consumes its wake.
;;
;; Confirmed via git-stash A/B: without the fix, `b`'s result comes back
;; corrupted (not #t) instead of raising or hanging.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64) (kaappi fibers))

(test-begin "mutex-nested-dispatch-dirty-snapshot-1487")

(define m1 (make-mutex 'm1))
(define m2 (make-mutex 'm2))

(define d
  (spawn (lambda ()
           (mutex-lock! m1)
           (mutex-lock! m2)
           (thread-yield!)
           (mutex-unlock! m1)
           (thread-yield!)
           (mutex-unlock! m2)
           'd-done)))

(define b (spawn (lambda () (mutex-lock! m1))))
(define c (spawn (lambda () (mutex-lock! m2))))

;; Drives d (and, as a side effect of d's yields, b and c) to completion.
(test-equal "d completes normally" 'd-done (fiber-join d))
(test-equal "b's mutex-lock! returns #t, not a corrupted snapshot" #t (fiber-join b))
(test-equal "c's mutex-lock! returns #t, not a corrupted snapshot" #t (fiber-join c))

(let ((runner (test-runner-current)))
  (test-end "mutex-nested-dispatch-dirty-snapshot-1487")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
