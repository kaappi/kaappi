;; Regression test for #1458: a child OS thread that dies while holding a
;; mutex allocated in the *parent's* heap (shared via a top-level global)
;; must abandon that mutex.
;;
;; Each SRFI-18 OS thread has its own GC heap. A mutex created before any
;; thread is spawned lives in the parent heap. The old abandonFiberMutexes
;; scanned only the dying child's own heap for mutexes it owned, so it never
;; found the parent-heap mutex: mutex-state stayed 'not-abandoned, m.owner
;; kept dangling at the (soon-freed) dead child fiber, and a subsequent
;; mutex-lock! from the parent raised the generic deadlock error or hung
;; instead of abandoned-mutex-exception. Tracking held mutexes on the fiber
;; itself lets the child abandon the mutex regardless of which heap owns it.
;;
;; The shared mutexes are top-level globals and the thunks reference them by
;; name: sync primitives are deep-copy-rejected when *captured* by a thread
;; thunk's closure, so globals (shared by reference across threads) are the
;; only supported way to share one — see srfi18-cross-thread-wait.scm.

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

;; Spawn `thunk` in a child thread and join it, swallowing the uncaught
;; exception a dying thunk surfaces. Joining guarantees the child fully
;; finished — i.e. it already ran its self-abandon — before we inspect the
;; mutex. Wrapped so the top-level call's value is discarded (no stray print).
(define (spawn-and-join thunk)
  (let ((t (make-thread thunk)))
    (thread-start! t)
    (guard (e (#t #t)) (thread-join! t))
    (if #f #f)))

(define m (make-mutex 'shared))
(define m2 (make-mutex 'shared-2))

(define (die-holding-m) (mutex-lock! m) (error "boom"))
(define (die-holding-m2) (mutex-lock! m2) (error "boom"))

;; ---- child errors out while holding a parent-heap mutex ----
(let ()
  (spawn-and-join die-holding-m)
  (check "mutex-state is 'abandoned after child dies holding it"
         (mutex-state m) 'abandoned)
  ;; Per SRFI-18, re-locking an abandoned mutex raises
  ;; abandoned-mutex-exception (and leaves the mutex held by this thread).
  (check-true "mutex-lock! on the abandoned mutex raises abandoned-mutex-exception"
    (guard (e ((abandoned-mutex-exception? e) #t) (#t #f))
      (mutex-lock! m)
      #f)))

;; ---- a second, independently shared mutex is abandoned the same way ----
;; Guards against a fix that only works for the first mutex a thread touches.
(let ()
  (spawn-and-join die-holding-m2)
  (check "second parent-heap mutex also abandoned across heaps"
         (mutex-state m2) 'abandoned))

;; ---- thread-terminate! on a thread holding a parent-heap mutex ----
;; thread-terminate! on an OS thread does NOT abandon the mutex from the
;; parent (its owned-mutexes list is maintained on the child's own thread);
;; the child abandons it itself when it observes the terminate flag and
;; unwinds. Joining after terminating waits for that to happen.
(define mt (make-mutex 'terminated))
(define (hold-mt-forever) (mutex-lock! mt) (let loop () (loop)))
(let ((t (make-thread hold-mt-forever)))
  (thread-start! t)
  (thread-sleep! 0.1)                   ; let it acquire mt
  (thread-terminate! t)
  (guard (e (#t #t)) (thread-join! t))
  (check "parent-heap mutex abandoned after thread-terminate!"
         (mutex-state mt) 'abandoned))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
