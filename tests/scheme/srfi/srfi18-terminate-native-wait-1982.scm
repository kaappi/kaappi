;; Regression test for #1982: thread-terminate! cannot interrupt a thread
;; parked in a native SRFI-18 wait, so thread-join! on it hangs forever.
;;
;; The bytecode safepoint polls VM.terminate_flag every 1024 instructions
;; (#933, closing #880) -- but only while executing bytecode. thread-sleep!,
;; mutex-lock! and mutex-unlock!'s condvar branch each wait inside
;; runSchedulerStep's native loop and never executed bytecode, so the flag
;; was never observed: thread-terminate! flipped the handle's status to
;; .errored from the parent, the join's poll exited immediately, and then
;; reapOsThread's thread.join() blocked forever waiting for a child that
;; would never unwind. The fix makes runSchedulerStep consult the
;; termination flag (via the VM's terminate_flag for an OS-thread child,
;; via the fiber's own flag for a local fiber) and unwind with
;; VMError.Terminated, exactly like the safepoint.
;;
;; Shared mutexes/condvars are top-level globals, referenced by name from
;; the thunks: sync primitives are deep-copy-rejected when *captured* by a
;; thread thunk (only the globals route shares them by pointer -- see
;; srfi18-cross-thread-wait.scm), and a child that errored at thread-start!
;; would make the terminate probes pass vacuously. The CONTROL rows joining
;; normally with a value are what prove the children genuinely ran and
;; parked in the native waits.
;;
;; Every shape must terminate promptly (a regression wedges the test
;; runner, which is the failure mode being pinned).

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "srfi18-terminate-native-wait-1982")

(define (join-catch t)
  (guard (e ((terminated-thread-exception? e) 'terminated)
            (#t (list 'other e)))
    (thread-join! t)))

;; Each native-wait shape: terminate while parked, join must raise
;; terminated-thread-exception (never hang).
(test-equal "terminate a thread parked in thread-sleep!"
  'terminated
  (let ((t (make-thread (lambda () (thread-sleep! 60) 'slept))))
    (thread-start! t) (thread-sleep! 0.2) (thread-terminate! t)
    (join-catch t)))

(define m-term-timed (make-mutex 'm-term-timed))
(test-equal "terminate a thread parked in a timed mutex-lock!"
  'terminated
  (let ((t (make-thread (lambda () (mutex-lock! m-term-timed 60) (mutex-unlock! m-term-timed) 'locked))))
    (thread-start! t) (thread-sleep! 0.2) (thread-terminate! t)
    (join-catch t)))

(define m-term-cv (make-mutex 'm-term-cv))
(define cv-term (make-condition-variable 'cv-term))
(test-equal "terminate a thread parked in a condition-variable wait"
  'terminated
  (let ((t (make-thread (lambda () (mutex-lock! m-term-cv) (mutex-unlock! m-term-cv cv-term 60) (mutex-unlock! m-term-cv) 'cv-waited))))
    (thread-start! t) (thread-sleep! 0.2) (thread-terminate! t)
    (join-catch t)))

(define m-term-untimed (make-mutex 'm-term-untimed))
(mutex-lock! m-term-untimed)
(test-equal "terminate a thread parked in an untimed mutex-lock! (held by parent)"
  'terminated
  (let ((t (make-thread (lambda () (mutex-lock! m-term-untimed) (mutex-unlock! m-term-untimed) 'got-it))))
    (thread-start! t) (thread-sleep! 0.2) (thread-terminate! t)
    (join-catch t)))

;; CONTROL: the pre-existing safepoint path (Scheme spin loop) still
;; terminates -- pins that the native-wait fix did not disturb it.
(test-equal "terminate a thread running a Scheme spin loop (safepoint path)"
  'terminated
  (let ((t (make-thread (lambda () (let loop () (loop))))))
    (thread-start! t) (thread-sleep! 0.2) (thread-terminate! t)
    (join-catch t)))

;; CONTROL: a timed mutex-lock! released by the parent joins normally with
;; the thunk's value (not terminated).
(define m-ctrl (make-mutex 'm-ctrl))
(mutex-lock! m-ctrl)
(test-equal "mutex released by parent: join returns the value"
  'got-it
  (let ((t (make-thread (lambda () (mutex-lock! m-ctrl 60) 'got-it))))
    (thread-start! t) (thread-sleep! 0.2) (mutex-unlock! m-ctrl)
    (join-catch t)))

;; CONTROL: a condition-variable wait released by broadcast joins normally.
(define m-ctrl-cv (make-mutex 'm-ctrl-cv))
(define cv-ctrl (make-condition-variable 'cv-ctrl))
(test-equal "condvar broadcast: join returns the value"
  'cv-done
  (let ((t (make-thread (lambda () (mutex-lock! m-ctrl-cv) (mutex-unlock! m-ctrl-cv cv-ctrl 60) (mutex-unlock! m-ctrl-cv) 'cv-done))))
    (thread-start! t) (thread-sleep! 0.2)
    (mutex-lock! m-ctrl-cv) (condition-variable-broadcast! cv-ctrl) (mutex-unlock! m-ctrl-cv)
    (join-catch t)))

(let ((runner (test-runner-current)))
  (test-end "srfi18-terminate-native-wait-1982")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
