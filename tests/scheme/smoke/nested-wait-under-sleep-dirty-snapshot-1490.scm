;; Regression test for #1490: a spawned fiber's blocking wait, nested inside
;; another fiber's own timed wait, must not let the scheduler resume the
;; ancestor from a stale mid-native-call snapshot.
;;
;; This is the same dirty-snapshot dispatch corruption class as #1487
;; (mutex-nested-dispatch-dirty-snapshot-1487.scm), but reached through a
;; distinct *trigger*: not a mutex-unlock! wake from a dispatched sibling,
;; but reactor-TIMER theft. Trace, for the channel-receive case below:
;;
;;   1. main (fiber 0) calls (thread-sleep! 0.01): status .waiting, registers
;;      a reactor timer, drives via runSchedulerStep -- its native frame now
;;      live on the Zig stack (driving = true, #1521).
;;   2. that drive dispatches the spawned fiber, which blocks in channel-
;;      receive on an empty channel and starts its OWN nested runSchedulerStep.
;;   3. the nested drive finds nothing else runnable and parks in the reactor,
;;      bounded by the nearest timer in the shared heap -- which is fiber 0's
;;      0.01s SLEEP timer, not the spawned fiber's (channel-receive here
;;      registers none).
;;   4. that timer pops, flipping fiber 0 (the ancestor, two runSchedulerStep
;;      frames up) from .waiting to .suspended.
;;   5. without the #1521 driving guard, the nested drive's own
;;      scheduleForDispatch() would now select fiber 0 and restoreFiber+
;;      runUntil it a SECOND time, from a stale IP, while its original
;;      thread-sleep! drive is still live -- corrupting frame/handler/wind
;;      bookkeeping, surfacing as `panic: integer overflow` in invokeEscape.
;;
;; The generic `driving` flag (set for the whole extent of any
;; runSchedulerStep call, excluded from scheduleForDispatch/hasRunnableFibers)
;; closes this: fiber 0 is never re-dispatched from the nested drive; its own
;; timed_out flag ends its own drive loop cleanly instead.
;;
;; Confirmed via A/B (scheduleForDispatch -> scheduleImpl(false)): every
;; scenario below crashes 15/15 without the guard and passes 15/15 with it.
;;
;; Each scenario spawns a fiber that blocks FOREVER (no sender / never-freed
;; slot / never-unlocked mutex / never-signalled condvar), then polls with a
;; thread-sleep! loop and returns a sentinel. The outer guard matches the
;; issue's minimal repro: a live exception-handler frame is what the
;; corrupted escape-continuation call reaches through, so the corruption
;; surfaces reliably (as a process-aborting panic) when the bug is present.
;; When the bug is fixed, each scenario simply returns 'ok.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (srfi 64) (kaappi fibers))

(test-begin "nested-wait-under-sleep-dirty-snapshot-1490")

;; Poll for `n` short sleeps, so the ancestor fiber holds a live thread-sleep!
;; drive (with a reactor timer) across the spawned fiber's nested wait.
(define (sleep-poll n)
  (let loop ((i 0))
    (when (< i n)
      (thread-sleep! 0.01)
      (loop (+ i 1)))))

;; Scenario A -- the issue's headline repro: plain (untimed) channel-receive.
(test-equal "channel-receive nested under thread-sleep! loop"
  'ok
  (guard (e (#t 'outer-caught))
    (let ((ch (make-channel)))
      (spawn (lambda () (channel-receive ch)))  ; blocks forever: no sender
      (sleep-poll 20)
      'ok)))

;; Scenario B -- local channel-send blocked on a full bounded channel.
(test-equal "channel-send (full bounded) nested under thread-sleep! loop"
  'ok
  (guard (e (#t 'outer-caught))
    (let ((ch (make-channel 1)))
      (channel-send ch 'fill)                    ; channel now full
      (spawn (lambda () (channel-send ch 'x)))   ; blocks forever: no receiver
      (sleep-poll 20)
      'ok)))

;; Scenario C -- mutex-lock! on a mutex held by the ancestor.
(test-equal "mutex-lock! nested under thread-sleep! loop"
  'ok
  (guard (e (#t 'outer-caught))
    (let ((m (make-mutex)))
      (mutex-lock! m)                            ; held by main; never unlocked
      (spawn (lambda () (mutex-lock! m)))        ; blocks forever
      (sleep-poll 20)
      'ok)))

;; Scenario D -- condition-variable wait (mutex-unlock! with a condvar).
(test-equal "condition-variable wait nested under thread-sleep! loop"
  'ok
  (guard (e (#t 'outer-caught))
    (let ((m (make-mutex)) (cv (make-condition-variable)))
      (spawn (lambda ()
               (mutex-lock! m)
               (mutex-unlock! m cv)))            ; waits on cv forever
      (sleep-poll 20)
      'ok)))

(let ((runner (test-runner-current)))
  (test-end "nested-wait-under-sleep-dirty-snapshot-1490")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
