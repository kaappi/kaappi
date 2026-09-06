;; Regression test for #2129: thread-join! frees the joined thread's GC/VM
;; while a thread it started is still starting -- SIGSEGV / Zig panic; makes
;; (srfi 120) unusable from a thread.
;;
;; Two halves, both fixed in the v0.22.2 audit:
;;
;;   * SYMBOL-TABLE HALF (PR #2230): threadEntryFn's prologue dereferences
;;     the spawning thread's VM/GC (GC.initForThread's shared symbol tables,
;;     then the shared maps), and every later symbol interning goes through
;;     those tables for the thread's whole life. freeChildResources had no
;;     interlock: joining a thread that had itself spawned a thread freed its
;;     GC/VM out from under the grandchild. Fix: every thread chains its
;;     shared state to the ROOT VM/GC -- which lives for the whole process --
;;     so a join can never free anything a descendant references.
;;
;;   * HANDLE HALF (this PR): the grandchild's own fiber handle lives in the
;;     middle thread's heap and is dereferenced for the grandchild's whole
;;     life (the dispatch-loop safepoint polls its `terminated` flag every
;;     1024 instructions, and the terminal `status` store happens at exit) --
;;     not just in the prologue. Freeing the middle heap at its join was a
;;     use-after-free for the grandchild's entire remaining lifetime. Fix: a
;;     per-fiber live-descendant count (Fiber.live_descendants). A join of a
;;     thread with live descendants RETIRES its child-registry entry instead
;;     of freeing it; the last descendant's threadEntryFn defer frees it once
;;     the subtree drains, and the join returns immediately. The control
;;     below pins the transitive property that makes the free safe: joining g
;;     waits for g's own descendants, because g's heap holds their fibers.
;;
;; The discriminating shape (from the issue): a thread that spawns a thread
;; and returns without joining it -- a worker that kicks off a background
;; task and reports back. Run it many times: pre-fix this crashed the
;; process on the vast majority of runs; post-fix it never does, and the
;; join of the spawning thread returns without waiting for the background
;; thread. A regression crashes the whole runner loudly (a process abort,
;; not a Scheme condition), or -- for the deep-chain control -- fails the
;; gg-done assertion because the join returned before the grandchild's own
;; child completed.

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

;; Variant of the same shape where the grandchild KEEPS EXECUTING past the
;; middle's join: the dispatch-loop safepoint polls this fiber's terminate
;; flag (which lives in the middle's heap) every 1024 instructions, so the
;; whole run is a deref of the middle's retired -- not freed -- heap.
;; Allocating also interns symbols through the root's shared table (the
;; symbol-table half), so this exercises both halves at once.
;;
;; Each grandchild marks its own slot in BUSY-DONE when its allocation loop
;; finishes, and the bounded wait before test-end below drains them. The
;; unjoined shape stays -- that is the point of the test -- but the process
;; no longer exits at a race-dependent moment relative to the grandchildren:
;; before kaappi#2537, a run where the grandchildren finished just before the
;; main thread reached the exit path left their heaps in the child registry
;; (kept deliberately for a join that never comes) and the Debug build's
;; leak report over 29k retained objects blew the CI leg's whole time budget.
;; Waiting here makes the full completion path (and the exit sweep of the
;; unjoined entries) deterministic on every run instead. The slots are
;; one-element boxes, mutated with set-car! like GG-DONE below: a value a
;; grandchild stores must be an immediate into a root-heap pair.
(define busy-done (list (list #f) (list #f) (list #f) (list #f) (list #f) (list #f)))
(define (busy-done-all?)
  (let loop ((rest busy-done))
    (or (null? rest) (and (car (car rest)) (loop (cdr rest))))))
(define busy-failures 0)
(let loop ((n 6))
  (when (> n 0)
    (let ((idx (- 6 n)))
      (unless (eq? (run-shape
                    (lambda ()
                      (thread-sleep! 0.15)
                      (let lp ((i 0) (acc '()))
                        (if (< i 3000)
                            (lp (+ i 1) (cons (string->symbol (string (integer->char (+ 97 (modulo i 26))))) acc))
                            (begin (set-car! (list-ref busy-done idx) #t) 'g)))))
                   'plain)
        (set! busy-failures (+ busy-failures 1))))
    (loop (- n 1))))
(test-equal "6 grandchildren keep allocating past the join (safepoints + symbol interning)"
  0 busy-failures)

;; DEEP CHAIN -- pins the transitive wait that makes the handle-half free
;; safe. g spawns an unjoined gg that outlives g's return; the middle then
;; joins g. g's heap holds gg's fiber, so the join of g must not free g's
;; heap until gg's threadEntryFn defer has fired -- i.e. the join chain must
;; wait for gg to finish. Observable as: by the time the middle's join
;; returns, gg's terminal write has happened. Pre-fix the join of g returned
;; as soon as g itself finished, the flag was still #f, and gg was left
;; dereferencing a freed heap.
(define gg-done (list #f))
(define (gg-thunk)
  (thread-sleep! 0.3)
  (set-car! gg-done #t)
  'gg)
(define (g-thunk)
  (let ((gg (make-thread gg-thunk)))
    (thread-start! gg)
    'g))
(define (middle-thunk)
  (let ((g (make-thread g-thunk)))
    (thread-start! g)
    (thread-join! g)))
(let ((t (make-thread middle-thunk)))
  (thread-start! t)
  (test-equal "middle joins g; g had spawned an unjoined gg -- join chain returns g"
    'g (thread-join! t)))
(test-assert "gg completed before the join chain returned (transitive descendant wait)"
  (car gg-done))

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

;; Bounded drain of the busy grandchildren (see BUSY-DONE above): poll until
;; every grandchild's allocation loop has finished, so the process never
;; exits while one is mid-loop. The bound exists only so a genuinely stuck
;; grandchild fails by proceeding (the exit path handles live children
;; cheaply) instead of hanging the leg; 60s is far beyond what the loops
;; need even on a Debug build, and in practice the last flag is already set
;; by the time we get here.
(let drain ((polls 0))
  (when (and (not (busy-done-all?)) (< polls 1200))
    (thread-sleep! 0.05)
    (drain (+ polls 1))))

(let ((runner (test-runner-current)))
  (test-end "srfi18-join-spawn-grandchild-2129")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
