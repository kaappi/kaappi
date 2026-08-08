;; Regression test for #1984: four SRFI-18 state-machine defects.
;;
;;   1. mutex-unlock! never cleared `abandoned` -- SRFI-18 6.4.2:
;;      "Unlocks the mutex by making it unlocked/not-abandoned". A mutex
;;      whose previous owner died stayed abandoned after a plain unlock, so
;;      the next mutex-lock! raised a spurious abandoned-mutex-exception.
;;
;;   2. thread-terminate! destroyed an already-finished thread's result --
;;      SRFI-18 6.2.3: "If the _thread_ is not already terminated". The old
;;      code set the `terminated` flag before checking the thread's status,
;;      and thread-join! tests that flag first, so terminating a thread that
;;      had already completed retroactively erased what it returned.
;;
;;   3. mutex-lock! accepted a terminated thread as owner -- SRFI-18 6.4.2:
;;      "if T is terminated the _mutex_ becomes unlocked/abandoned". The old
;;      code recorded the dead thread as owner, leaving the mutex locked by a
;;      thread that can never unlock it.
;;
;;   4. Self-termination reported the wrong exception -- thread-terminate!
;;      on the current thread must not return, and the thread's end-exception
;;      must be the 'terminated thread exception'. The old code terminated
;;      the child's *current fiber* (a distinct object from the parent-heap
;;      handle thread-join! reads), so the join surfaced uncaught-exception
;;      with a void reason instead of terminated-thread-exception.
;;
;; Mutexes shared with a child thread must be reached through TOP-LEVEL
;; globals, never captured in the thunk's closure: thread-start! deep-copies
;; the thunk, and a captured mutex would be copied into the child's envelope
;; heap instead of shared (see srfi18-cross-heap-abandoned-mutex.scm).

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "srfi18-mutex-terminate-state-1984")

(define m-shared (make-mutex 'm-shared))

;; A child that errors out while holding a shared (global) mutex abandons it.
(define (die-holding-shared!)
  (mutex-lock! m-shared)
  (error "die holding"))
(define (spawn-and-join! thunk)
  (let ((t (make-thread thunk)))
    (thread-start! t)
    (guard (e (#t #f)) (thread-join! t))))

;; ---------------------------------------------------------------------------
;; 1. mutex-unlock! makes the mutex unlocked/not-abandoned
;; ---------------------------------------------------------------------------

(spawn-and-join! die-holding-shared!)
(test-equal "owner death leaves the mutex abandoned"
  'abandoned (mutex-state m-shared))
;; A plain unlock of the abandoned (but unlocked) mutex must clear the flag.
(guard (e (#t #f)) (mutex-unlock! m-shared))
(test-equal "mutex-unlock! clears the abandoned flag"
  'not-abandoned (mutex-state m-shared))
;; The next lock must NOT raise abandoned-mutex-exception.
(test-assert "relocking a properly unlocked mutex raises nothing and succeeds"
  (let ((raised #f))
    (guard (e (#t (set! raised #t)))
      (mutex-lock! m-shared))
    (and (not raised)
         ;; sanity: we own it now, and a further unlock is clean
         (begin (mutex-unlock! m-shared) #t))))

;; Control: a mutex that was never abandoned stays not-abandoned through an
;; ordinary lock/unlock cycle (pre-existing behavior, unchanged).
(define m1c (make-mutex 'm1c))
(mutex-lock! m1c)
(mutex-unlock! m1c)
(test-equal "control: ordinary unlock of a never-abandoned mutex"
  'not-abandoned (mutex-state m1c))

;; Control: a genuinely abandoned mutex still raises abandoned-mutex-exception
;; on lock, and the acquirer becomes the owner (spec: the state change happens
;; first, then the raise).
(spawn-and-join! die-holding-shared!)
(test-assert "control: locking a still-abandoned mutex raises abandoned-mutex-exception"
  (guard (e ((abandoned-mutex-exception? e) #t)
            (#t #f))
    (mutex-lock! m-shared)
    #f))
(test-equal "control: the raising lock still made the acquirer the owner"
  #t (thread? (mutex-state m-shared)))
(mutex-unlock! m-shared)

;; ---------------------------------------------------------------------------
;; 2. thread-terminate! on a finished thread is a no-op
;; ---------------------------------------------------------------------------

(define t2 (make-thread (lambda () 'result-a)))
(thread-start! t2)
(test-equal "first join returns the result"
  'result-a (thread-join! t2))
(test-equal "terminate of a completed thread returns unspecified (no error)"
  #t (guard (e (#t #f)) (thread-terminate! t2) #t))
(test-equal "second join still returns the result (not terminated)"
  'result-a (thread-join! t2))

;; Same for a thread that finished by raising: its end-exception survives.
(define t2r (make-thread (lambda () (error "boom"))))
(thread-start! t2r)
(test-assert "join of the raising thread raises uncaught-exception"
  (guard (e ((uncaught-exception? e) #t)
            (#t #f))
    (thread-join! t2r)
    #f))
(test-equal "terminate of the finished raising thread is a no-op"
  #t (guard (e (#t #f)) (thread-terminate! t2r) #t))
(test-equal "the raising thread's end-exception survives the no-op terminate"
  "boom" (guard (e ((uncaught-exception? e)
                    (error-object-message (uncaught-exception-reason e)))
                  (#t 'wrong-exception))
           (thread-join! t2r)
           'no-exception))

;; Control: terminating a RUNNING thread still works and joins as terminated.
(define t2c (make-thread (lambda () (let loop () (loop)))))
(thread-start! t2c)
(thread-terminate! t2c)
(test-assert "control: terminate of a running thread joins as terminated-thread-exception"
  (guard (e ((terminated-thread-exception? e) #t)
            (#t #f))
    (thread-join! t2c)
    #f))

;; ---------------------------------------------------------------------------
;; 3. mutex-lock! with a terminated owner: unlocked/abandoned, not dead-owner
;; ---------------------------------------------------------------------------

(define t3 (make-thread (lambda () (let loop () (loop)))))
(thread-start! t3)
(thread-terminate! t3)
(guard (e (#t #f)) (thread-join! t3)) ;; reap it; t3 is now terminated
(define m3 (make-mutex 'm3))
(test-equal "locking with a terminated owner returns #t (not abandoned before)"
  #t (mutex-lock! m3 #f t3))
(test-equal "the mutex becomes unlocked/abandoned, not owned by the dead thread"
  'abandoned (mutex-state m3))
;; A subsequent lock by a live thread hits the now-abandoned mutex.
(test-assert "a later lock of the abandoned mutex raises abandoned-mutex-exception"
  (guard (e ((abandoned-mutex-exception? e) #t)
            (#t #f))
    (mutex-lock! m3)
    #f))
(test-equal "and that acquirer is the owner (the abandoned mutex was unlocked)"
  #t (thread? (mutex-state m3)))
(mutex-unlock! m3)

;; Control: an explicit LIVE owner is still recorded.
(define t3c (make-thread (lambda () (thread-sleep! 0.3) 'done)))
(thread-start! t3c)
(define m3c (make-mutex 'm3c))
(mutex-lock! m3c #f t3c)
(test-equal "control: an explicit live owner is recorded"
  t3c (mutex-state m3c))
(thread-join! t3c)

;; Control: owner #f gives locked/not-owned.
(define m3d (make-mutex 'm3d))
(mutex-lock! m3d #f #f)
(test-equal "control: explicit #f owner gives locked/not-owned"
  'not-owned (mutex-state m3d))
(mutex-unlock! m3d)

;; ---------------------------------------------------------------------------
;; 4. self-termination joins as terminated-thread-exception
;; ---------------------------------------------------------------------------

(define t4 (make-thread (lambda ()
                          (thread-terminate! (current-thread))
                          'unreachable)))
(thread-start! t4)
(test-assert "a self-terminating thread joins as terminated-thread-exception"
  (guard (e ((terminated-thread-exception? e) #t)
            (#t #f))
    (thread-join! t4)
    #f))

;; Control: a thread that finishes normally does not join as terminated.
(define t4c (make-thread (lambda () 'fine)))
(thread-start! t4c)
(test-equal "control: a normally-finished thread joins with its result"
  'fine (thread-join! t4c))

(let ((runner (test-runner-current)))
  (test-end "srfi18-mutex-terminate-state-1984")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
