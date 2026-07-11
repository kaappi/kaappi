;; Regression test: mutex-lock! and mutex-unlock!+condition-variable must
;; block until the shared state actually changes when called from a real OS
;; thread (make-thread/thread-start!) that has nothing else locally
;; schedulable.
;;
;; Each OS thread runs its own independent FiberScheduler; mutex-unlock!/
;; condition-variable-signal!/-broadcast! called on *another* OS thread only
;; wake fibers local to that thread's own scheduler, so there is no
;; cross-thread wakeup. Before this fix, whenever nothing was locally
;; schedulable, mutex-lock! and mutex-unlock!+condvar-wait gave up
;; immediately and unconditionally reported success -- so mutex-lock! on a
;; mutex still held by a different thread returned #t at once (silently
;; corrupting the lock), and mutex-unlock!+condvar returned before any
;; signal had happened.
;;
;; Mutex/condition-variable objects are deep-copy-rejected when captured by
;; a thread thunk's closure (see srfi18.scm's "OS threads cannot capture
;; sync primitives" test) -- the supported way to share them across real OS
;; threads is via top-level globals, which is what this test does.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define (check-true name val)
  (if val
      (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;; ---- mutex-lock! blocks across OS threads until unlocked ----
(define lock-m (make-mutex))
(define lock-elapsed -1.0)

(define (lock-waiter-thunk)
  (let ((t0 (current-time)))
    (mutex-lock! lock-m)
    (set! lock-elapsed (- (time->seconds (current-time)) (time->seconds t0)))
    (mutex-unlock! lock-m)))

(mutex-lock! lock-m)
(let ((t (make-thread lock-waiter-thunk)))
  (thread-start! t)
  (thread-sleep! 0.2)
  (mutex-unlock! lock-m)
  (thread-join! t)
  (check-true "mutex-lock! blocks until the holder unlocks (not instant)"
    (>= lock-elapsed 0.15)))

;; ---- mutex-unlock!+condition-variable-signal! blocks for the signal ----
;; thread-join! already blocks correctly (it has its own OS-thread poll
;; loop), so simply checking a flag set by the signaling thread *after*
;; joining would pass even with the bug: the signaler still eventually runs
;; and sets the flag before it exits, regardless of whether the waiter's own
;; mutex-unlock!+condvar call returned instantly or genuinely waited. So this
;; measures the waiter's own elapsed time around the call, which the bug
;; made ~instant instead of spanning the signaling thread's delay.
(define cv-m (make-mutex))
(define cv-cv (make-condition-variable))
(define cv-elapsed -1.0)

(define (cv-signal-thunk)
  (thread-sleep! 0.2)
  (mutex-lock! cv-m)
  (condition-variable-signal! cv-cv)
  (mutex-unlock! cv-m))

(mutex-lock! cv-m)
(let ((t (make-thread cv-signal-thunk)))
  (thread-start! t)
  (let ((t0 (current-time)))
    (mutex-unlock! cv-m cv-cv)
    (set! cv-elapsed (- (time->seconds (current-time)) (time->seconds t0))))
  (thread-join! t)
  (check-true "mutex-unlock!+condition-variable-signal! blocks for the signal (not instant)"
    (>= cv-elapsed 0.1)))

;; ---- condition-variable-broadcast! blocks both waiters for the signal ----
;; Same reasoning as above: each waiter measures its own elapsed wait time
;; rather than relying on a flag that thread-join! would make visible anyway.
;;
;; Unlike the signal test, this broadcast isn't ordered by bc-m: main issues
;; it after a fixed sleep rather than while holding the mutex, so there's no
;; guarantee a waiter thread has already reached mutex-unlock!+cv by then.
;; If one hasn't (e.g. a slow/contended CI runner), it snapshots a
;; generation *after* the bump and then waits for a second broadcast that
;; never comes -- and a real OS thread never gives up that wait on its own
;; (crossThreadWaitPossible is unconditionally true for a spawned thread, so
;; it always assumes the main thread could still resolve it). A bounded
;; per-waiter timeout turns that race into a reported failure instead of a
;; hung CI job.
(define bc-m (make-mutex))
(define bc-cv (make-condition-variable))
(define bc-elapsed-1 -1.0)
(define bc-elapsed-2 -1.0)
(define bc-woke-1 #f)
(define bc-woke-2 #f)

(define (bc-waiter-thunk-1)
  (mutex-lock! bc-m)
  (let ((t0 (current-time)))
    (set! bc-woke-1 (mutex-unlock! bc-m bc-cv 5))
    (set! bc-elapsed-1 (- (time->seconds (current-time)) (time->seconds t0)))))

(define (bc-waiter-thunk-2)
  (mutex-lock! bc-m)
  (let ((t0 (current-time)))
    (set! bc-woke-2 (mutex-unlock! bc-m bc-cv 5))
    (set! bc-elapsed-2 (- (time->seconds (current-time)) (time->seconds t0)))))

(let ((t1 (make-thread bc-waiter-thunk-1))
      (t2 (make-thread bc-waiter-thunk-2)))
  (thread-start! t1)
  (thread-start! t2)
  (thread-sleep! 0.2)
  (condition-variable-broadcast! bc-cv)
  (thread-join! t1)
  (thread-join! t2)
  (check-true "condition-variable-broadcast! blocks waiter 1 for the signal (not instant)"
    (>= bc-elapsed-1 0.1))
  (check-true "condition-variable-broadcast! blocks waiter 2 for the signal (not instant)"
    (>= bc-elapsed-2 0.1))
  (check-true "condition-variable-broadcast! actually woke waiter 1 (not a timeout)" bc-woke-1)
  (check-true "condition-variable-broadcast! actually woke waiter 2 (not a timeout)" bc-woke-2))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
