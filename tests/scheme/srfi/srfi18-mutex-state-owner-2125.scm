;; Regression test for #2125: mutex-state reports the owning thread's
;; internal fiber, not the thread handle the caller holds.
;;
;; Mutex.owner tracks the fiber that acquired the lock (needed by
;; abandonFiberMutexes), which for an OS-thread child is the child's own
;; heap fiber 0 -- a value the parent's GC does not own, not eq? to any
;; thread the caller holds, and a dangling-pointer hazard once the child
;; heap is freed at join. mutex-state now reports the owner thread handle
;; (the fiber make-thread returned, in the parent's heap), recorded
;; alongside the owner at lock time, so the obvious synchronisation idiom
;; `(eq? (mutex-state m) t)` works and the value stays valid past join.
;;
;; The mutex is a top-level global: sync primitives are deep-copy-rejected
;; when *captured* by a thread thunk (see srfi18-cross-thread-wait.scm).

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "srfi18-mutex-state-owner-2125")

;; The issue's exact shape: a mutex locked by a child OS thread must report
;; the thread handle, eq? to the handle the caller holds.
(define m (make-mutex 'probe))
(define t (make-thread (lambda () (mutex-lock! m) (let loop () (loop)))))
(thread-start! t)
;; Bounded poll for the child to acquire the lock; the eq? probe IS the
;; regression (pre-fix it never became true and this spun to its budget,
;; failing loudly rather than hanging).
(define (poll-owner? tries)
  (cond ((eq? (mutex-state m) t) #t)
        ((<= tries 0) #f)
        (else (thread-sleep! 0.005) (poll-owner? (- tries 1)))))
(test-assert "mutex-state on a child-held mutex returns the thread handle (was: child-heap fiber)"
  (poll-owner? 1000))
(test-assert "the returned owner is a thread"
  (thread? (mutex-state m)))
;; Capture the owner while the child holds the lock, then terminate and
;; join. The captured value must still be the parent-heap handle: pre-fix
;; it was the child's fiber, a freed child-heap pointer once the join
;; frees that heap (the #2127 quarantine was the detector-side mitigation).
(define owner-before-join (mutex-state m))
(thread-terminate! t)
(guard (e (#t #t)) (thread-join! t))
(test-equal "the owner value captured before join survives it (parent-heap handle, not a freed child-heap fiber)"
  t owner-before-join)
(test-equal "abandoned state still reported after terminate"
  'abandoned (mutex-state m))

;; Local (same-thread) ownership is unchanged: the owner is the current
;; thread itself.
(let ((ml (make-mutex 'local)))
  (mutex-lock! ml)
  (test-assert "same-thread owner is a thread"
    (thread? (mutex-state ml)))
  (test-assert "same-thread owner is eq? to current-thread"
    (eq? (mutex-state ml) (current-thread)))
  (mutex-unlock! ml)
  (test-equal "unlocked mutex is not-abandoned again"
    'not-abandoned (mutex-state ml)))

;; An explicit owner argument is reported as given (SRFI-18's optional
;; thread argument), and #f means locked-but-unowned. The owner must be a
;; LIVE thread: a terminated owner makes the mutex unlocked/abandoned per
;; SRFI-18 6.4.2 ("if T is terminated the _mutex_ becomes
;; unlocked/abandoned", #1984).
(define t-live (make-thread (lambda () (thread-sleep! 0.4) 'done)))
(thread-start! t-live)
(define m2 (make-mutex 'explicit))
(mutex-lock! m2 #f t-live)
(test-assert "explicit owner arg is what mutex-state reports"
  (eq? (mutex-state m2) t-live))
(mutex-unlock! m2)
(thread-join! t-live)
(define m3 (make-mutex 'unowned))
(mutex-lock! m3 #f #f)
(test-equal "explicit #f owner is the locked/unowned state"
  'not-owned (mutex-state m3))

(let ((runner (test-runner-current)))
  (test-end "srfi18-mutex-state-owner-2125")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
