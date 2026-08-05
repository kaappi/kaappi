;; Regression test for #2129: thread-join! frees the joined thread's GC/VM
;; while a thread it spawned is still starting -- SIGSEGV / Zig panic; makes
;; (srfi 120) unusable from a thread.
;;
;; threadEntryFn's prologue dereferences the spawning thread's VM/GC
;; (GC.initForThread's shared symbol tables, then the shared maps), and every
;; later symbol interning goes through those tables for the thread's whole
;; life. freeChildResources had no interlock: joining a thread that had
;; itself spawned a thread freed its GC/VM out from under the grandchild,
;; which was still (or forever after) reading freed memory. The fix chains
;; every thread's shared state to the ROOT VM/GC -- which lives for the whole
;; process -- so a join can never free anything a descendant references.
;;
;; The discriminating shape (from the issue): a thread that spawns a thread
;; and returns without joining it -- a worker that kicks off a background
;; task and reports back. Run it many times: pre-fix this crashed the
;; process on the vast majority of runs (the grandchild's prologue interned
;; symbols into the middle thread's freed table); post-fix it never does.
;; A regression crashes the whole runner loudly (a process abort, not a
;; Scheme condition).
;;
;; KNOWN RESIDUAL (#2129 stays open): each iteration leaves one un-joinable
;; grandchild OS thread behind -- its child resources are never reaped (no
;; one may join it) and, pre-existing since before this PR, the grandchild
;; dereferences its middle-heap handle (terminate_flag/status) for its whole
;; life, which the middle's join frees. Silent under the default allocator,
;; a live use-after-free under Guard Malloc. This test therefore pins only
;; the half this PR fixed (the prologue/symbol-table crash); the iterations
;; are kept small so the contained leak does not tax the suite.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "srfi18-join-spawn-grandchild-2129")

(define (run-shape child-thunk)
  (let ((t (make-thread
            (lambda ()
              (let ((g (make-thread child-thunk)))
                (thread-start! g)
                'plain)))))      ; middle returns WITHOUT joining g
    (thread-start! t)
    (thread-join! t)))

(define failures 0)
(let loop ((n 12))
  (when (> n 0)
    (unless (eq? (run-shape (lambda () (thread-sleep! 0.3) 'g)) 'plain)
      (set! failures (+ failures 1)))
    (loop (- n 1))))
(test-equal "12 middle threads each spawning an unjoined grandchild all return 'plain"
  0 failures)

;; CONTROL: the middle joining its own child first is clean -- the child is
;; reaped before the middle returns, so nothing is freed under a live
;; descendant. Pins that thread-join! on a returning thread in general is
;; not the problem.
(test-equal "middle that joins its own child first returns"
  'plain
  (let ((t (make-thread
            (lambda ()
              (let ((g (make-thread (lambda () 'g))))
                (thread-start! g)
                (thread-join! g)
                'plain)))))
    (thread-start! t)
    (thread-join! t)))

;; CONTROL: a middle that spawns nothing is clean.
(test-equal "plain middle thread returns"
  'plain
  (let ((t (make-thread (lambda () 'plain))))
    (thread-start! t)
    (thread-join! t)))

(let ((runner (test-runner-current)))
  (test-end "srfi18-join-spawn-grandchild-2129")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
