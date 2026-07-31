;; Audit tests for src/primitives_srfi18.zig — SRFI-18 threads, mutexes,
;; condition variables, time. Audit campaign Phase 2.1 (#1137).
;; Complements tests/scheme/srfi/srfi18*.scm (basics, cross-thread, races).
;; Run directly and read the printed counts — run-all.sh only sees exit codes.
;;
;; RE-AUDITED in audit v2 Phase 5D (2026-08-01). Sections 1-9 below were
;; added then; everything above them is the original Phase 2.1 file, kept
;; verbatim. The file it audits grew 994 -> 1435 lines (+793/-352 over 27
;; commits) between the two campaigns, while this test did not change at all.
;;
;; Oracle: the SRFI 18 specification (https://srfi.schemers.org/srfi-18/),
;; quoted inline wherever a rule is asserted.
;;
;; ****************************************************************
;; * DETERMINISM AND SAFETY RULES FOR THIS FILE                   *
;; *                                                              *
;; * 1. No wall-clock assertions. Timeouts are asserted by their  *
;; *    RETURN VALUE (#f / timeout-val) and by relative ordering, *
;; *    never by elapsed time (the #1665 pattern).                *
;; * 2. Nothing here may hang. Every wait is either bounded by an *
;; *    explicit timeout or resolved by a thread this file joins. *
;; * 3. Shapes that ABORT the process (uncatchable @intFromFloat  *
;; *    panics) or read freed memory are COMMENTED OUT with a     *
;; *    `;; FAIL:` marker, never `test-expect-fail` — an abort    *
;; *    takes the whole runner down with it.                      *
;; * 4. Mutexes shared with a child thread are reached through    *
;; *    TOP-LEVEL bindings. A lexically captured mutex is         *
;; *    rejected by gc_deep_copy at thread-start! (kaappi#1937),  *
;; *    so a `let`-bound one would test the copy rule, not the    *
;; *    mutex.                                                    *
;; ****************************************************************

(import (scheme base) (scheme write) (srfi 18))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_srfi18 audit")

;;; --- predicates: correct domain, no crashes on wrong types ---
(test-equal #t (thread? (current-thread)))
(test-equal #f (thread? 42))
(test-equal #f (thread? "thread"))
(test-equal #f (mutex? (current-thread)))
(test-equal #t (mutex? (make-mutex)))
(test-equal #f (mutex? '()))
(test-equal #t (condition-variable? (make-condition-variable)))
(test-equal #f (condition-variable? (make-mutex)))
(test-equal #t (time? (current-time)))
(test-equal #f (time? 3.14))

;;; --- current-thread ---
(test-equal #t (eq? (current-thread) (current-thread)))

;;; --- make-thread / accessors ---
(let ((t (make-thread (lambda () 'r) 'my-name)))
  (test-equal 'my-name (thread-name t))
  (test-equal #t (begin (thread-specific-set! t '(payload)) #t))
  (test-equal '(payload) (thread-specific t)))
;; type errors are catchable, not crashes
(test-equal #t (guard (e (#t #t)) (make-thread 42)))
(test-equal #t (guard (e (#t #t)) (thread-name 42)))
(test-equal #t (guard (e (#t #t)) (thread-specific "x")))
(test-equal #t (guard (e (#t #t)) (thread-specific-set! #f 1)))
(test-equal #t (guard (e (#t #t)) (thread-start! 'not-a-thread)))
(test-equal #t (guard (e (#t #t)) (thread-join! "nope")))
(test-equal #t (guard (e (#t #t)) (thread-terminate! 5)))
(test-equal '() (thread-join! (thread-start! (make-thread list))))

;;; --- thread lifecycle ---
;; starting a thread twice is an error (SRFI-18: thread must be new)
(let ((t (make-thread (lambda () (thread-sleep! 0.2) 'done))))
  (thread-start! t)
  (test-equal #t (guard (e (#t #t)) (thread-start! t) #f))
  (test-equal 'done (thread-join! t)))
;; joining self raises
(test-equal #t (guard (e (#t #t)) (thread-join! (current-thread)) #f))
;; join timeout-val is returned instead of raising; join after completion works
(let ((t (make-thread (lambda () (thread-sleep! 0.5) 'slow-done))))
  (thread-start! t)
  (test-equal 'tv (thread-join! t 0.02 'tv))
  (test-equal 'slow-done (thread-join! t)))
;; join timeout without timeout-val raises join-timeout-exception
(let ((t (make-thread (lambda () (thread-sleep! 0.5) 'x))))
  (thread-start! t)
  (test-equal #t (guard (e (#t (join-timeout-exception? e)))
                   (thread-join! t 0.02)
                   #f))
  (test-equal 'x (thread-join! t)))

;;; --- thread-sleep! ---
(test-equal #t (begin (thread-sleep! 0) #t))            ; zero: immediate
(test-equal #t (begin (thread-sleep! -1) #t))           ; negative: immediate
(test-equal #t (begin (thread-sleep! 1/100) #t))        ; rational seconds
(test-equal #t (begin (thread-sleep! (seconds->time 0)) #t)) ; past time object
(test-equal #t (guard (e (#t #t)) (thread-sleep! "5"))) ; type error catchable
(test-equal #t (guard (e (#t #t)) (thread-sleep! #f)))

;;; --- mutexes ---
(let ((m (make-mutex 'audit-mutex)))
  (test-equal 'audit-mutex (mutex-name m))
  (test-equal 'not-abandoned (mutex-state m))
  (test-equal #t (begin (mutex-specific-set! m 'ms) #t))
  (test-equal 'ms (mutex-specific m))
  (test-equal #t (mutex-lock! m))
  (test-equal #t (thread? (mutex-state m)))              ; owner is a thread
  (test-equal #t (mutex-unlock! m))
  (test-equal 'not-abandoned (mutex-state m)))
;; unlocking an unlocked mutex is allowed (SRFI-18 places no precondition)
(let ((m (make-mutex)))
  (test-equal #t (mutex-unlock! m)))
;; unnamed mutex has some name value; accessors reject non-mutexes
(test-equal #t (guard (e (#t #t)) (mutex-name 42)))
(test-equal #t (guard (e (#t #t)) (mutex-state "m")))
(test-equal #t (guard (e (#t #t)) (mutex-lock! 'sym)))
(test-equal #t (guard (e (#t #t)) (mutex-unlock! 9)))
(test-equal #t (guard (e (#t #t)) (mutex-specific 9)))
(test-equal #t (guard (e (#t #t)) (mutex-specific-set! 9 1)))
(let ((m (make-mutex)))
  (mutex-lock! m)
  (test-equal #f (mutex-lock! m 0.05)))
(let ((m (make-mutex)))
  (mutex-lock! m #f #f)
  (test-equal 'not-owned (mutex-state m)))

;;; --- condition variables ---
(let ((cv (make-condition-variable 'audit-cv)))
  (test-equal 'audit-cv (condition-variable-name cv))
  (test-equal #t (begin (condition-variable-specific-set! cv 'cs) #t))
  (test-equal 'cs (condition-variable-specific cv))
  ;; signal/broadcast with no waiters are no-ops, not errors
  (test-equal #t (begin (condition-variable-signal! cv) #t))
  (test-equal #t (begin (condition-variable-broadcast! cv) #t)))
(test-equal #t (guard (e (#t #t)) (condition-variable-name 42)))
(test-equal #t (guard (e (#t #t)) (condition-variable-signal! 42)))
(test-equal #t (guard (e (#t #t)) (condition-variable-broadcast! "cv")))
(test-equal #t (guard (e (#t #t)) (condition-variable-specific 1)))
(test-equal #t (guard (e (#t #t)) (condition-variable-specific-set! 1 2)))
(let ((m (make-mutex)) (cv (make-condition-variable)))
  (mutex-lock! m)
  (test-equal #f (mutex-unlock! m cv 0.01)))

;;; --- time ---
(let ((t (seconds->time 123.5)))
  (test-equal #t (time? t))
  (test-equal 123.5 (time->seconds t)))
(test-equal 100.0 (time->seconds (seconds->time 100)))   ; exact input accepted
(test-equal -5.0 (time->seconds (seconds->time -5)))     ; negative allowed
(test-equal #t (> (time->seconds (current-time)) 0))
(test-equal #t (guard (e (#t #t)) (time->seconds 42)))
(test-equal #t (guard (e (#t #t)) (seconds->time "x")))

;;; --- exception predicates: #f on arbitrary values, no crashes ---
(test-equal #f (join-timeout-exception? 42))
(test-equal #f (abandoned-mutex-exception? "x"))
(test-equal #f (terminated-thread-exception? '()))
(test-equal #f (uncaught-exception? #f))
(test-equal #f (join-timeout-exception? (guard (e (#t e)) (error "plain"))))
(test-equal #t (guard (e (#t #t)) (uncaught-exception-reason 42)))
;; uncaught-exception-reason returns the raised object (deep-copied)
(let ((t (make-thread (lambda () (raise 'boom)))))
  (thread-start! t)
  (test-equal 'boom (guard (e ((uncaught-exception? e) (uncaught-exception-reason e)))
                      (thread-join! t)
                      #f)))

;; =====================================================================
;; Phase 5D additions start here.
;; =====================================================================

;; Shared helpers. `join-outcome` collapses every way thread-join! can end
;; into one comparable symbol, so an assertion never depends on which of
;; several error objects surfaces.
(define (join-outcome t)
  (guard (e ((terminated-thread-exception? e) 'TERMINATED)
            ((uncaught-exception? e) (list 'UNCAUGHT (uncaught-exception-reason e)))
            ((join-timeout-exception? e) 'JOIN-TIMEOUT)
            (#t 'OTHER-RAISE))
    (thread-join! t)))

(define (raises? thunk) (guard (e (#t #t)) (thunk) #f))

(define (every-proc? lst) (if (null? lst) #t (and (procedure? (car lst)) (every-proc? (cdr lst)))))

;; Runs `thunk` in a child and joins it, so no test leaves a live thread
;; behind for the next section (or for process exit) to trip over.
(define (run-child thunk) (let ((t (make-thread thunk))) (thread-start! t) (thread-join! t)))

;; A child that stays alive but remains promptly TERMINABLE.
;;
;; It must spin in SCHEME rather than wait in native code: the terminate
;; flag is only polled at the 1024-instruction safepoint in the bytecode
;; dispatch loop, so how fast a child notices termination is proportional
;; to the wall-clock time it spends per 1024 bytecode instructions. A child
;; parked inside a single long native wait never notices at all (see the
;; "terminate cannot interrupt a native wait" note in section 5).
;;
;; Measured cost of one thread-terminate! + thread-join! by child shape:
;;   (let lp ((i 0)) (lp (+ i 1)))            0.17 ms
;;   (let lp () (thread-yield!) (lp))         0.30 ms
;;   (let lp () (thread-sleep! 0.001) (lp))    394 ms
;;   (let lp () (thread-sleep! 0.01)  (lp))   3758 ms
;;   (thread-sleep! 60) / untimed mutex wait  never (hangs)
;; Hence the busy loop: a sleep-polling helper made this file take 39s
;; against run-all.sh's 60s per-file timeout, almost all of it in terminate.
(define (make-parked-child) (make-thread (lambda () (let lp ((i 0)) (lp (+ i 1))))))

;; Terminate and reap, returning the join outcome. Every long-lived helper
;; thread in this file goes through here so nothing is left running.
(define (stop! t) (thread-terminate! t) (join-outcome t))

;; ---------------------------------------------------------------------
;; 1. Registration-table invariants (dimension D4)
;;
;; All 34 entries in the `specs` table, checked as a set: each name is
;; bound to a procedure, and each declared arity actually rejects one
;; argument too few. This is the check that notices a spec table drifting
;; from its bodies without needing to run any of them meaningfully.
;; ---------------------------------------------------------------------

(test-assert "all 34 specs are bound procedures"
  (every-proc? (list current-thread thread? make-thread thread-name
                     thread-specific thread-specific-set! thread-start!
                     thread-yield! thread-sleep! thread-terminate! thread-join!
                     mutex? make-mutex mutex-name mutex-specific
                     mutex-specific-set! mutex-state mutex-lock! mutex-unlock!
                     condition-variable? make-condition-variable
                     condition-variable-name condition-variable-specific
                     condition-variable-specific-set! condition-variable-signal!
                     condition-variable-broadcast! current-time time->seconds
                     seconds->time join-timeout-exception?
                     abandoned-mutex-exception? terminated-thread-exception?
                     uncaught-exception? uncaught-exception-reason)))

;; exact-arity entries reject a call with one argument too many
(test-assert "current-thread arity 0" (raises? (lambda () (current-thread 1))))
(test-assert "thread-yield! arity 0"  (raises? (lambda () (thread-yield! 1))))
(test-assert "current-time arity 0"   (raises? (lambda () (current-time 1))))
(test-assert "thread? arity 1"        (raises? (lambda () (thread? 1 2))))
(test-assert "mutex? arity 1"         (raises? (lambda () (mutex? 1 2))))
(test-assert "mutex-state arity 1"    (raises? (lambda () (mutex-state 1 2))))
(test-assert "time->seconds arity 1"  (raises? (lambda () (time->seconds 1 2))))
;; and a call with one too few
(test-assert "thread? needs 1"        (raises? (lambda () (thread?))))
(test-assert "mutex-lock! needs 1"    (raises? (lambda () (mutex-lock!))))
(test-assert "seconds->time needs 1"  (raises? (lambda () (seconds->time))))
(test-assert "thread-specific-set! needs 2"
  (raises? (lambda () (thread-specific-set! (current-thread)))))

;; variadic entries accept their optional arguments
(test-assert "make-mutex 0 args"  (mutex? (make-mutex)))
(test-assert "make-mutex 1 arg"   (mutex? (make-mutex 'n)))
(test-assert "make-condition-variable 0 args" (condition-variable? (make-condition-variable)))
(test-assert "make-condition-variable 1 arg"  (condition-variable? (make-condition-variable 'n)))
(test-assert "make-thread 1 arg"  (thread? (make-thread (lambda () 1))))
(test-assert "make-thread 2 args" (thread? (make-thread (lambda () 1) 'nm)))

;; ---------------------------------------------------------------------
;; 2. Mutex state machine — the full transition matrix
;;
;; SRFI 18 mutex-state: "thread T: the mutex is in the locked/owned state
;; and thread T is the owner; symbol not-owned: locked/not-owned state;
;; symbol abandoned: unlocked/abandoned state; symbol not-abandoned:
;; unlocked/not-abandoned state."
;;
;; The four states, and every edge this file can drive deterministically.
;; ---------------------------------------------------------------------

;; -- unlocked/not-abandoned (the initial state) --
(test-equal "fresh mutex is unlocked/not-abandoned"
  'not-abandoned (mutex-state (make-mutex)))

;; -- unlocked/not-abandoned -> locked/owned -> unlocked/not-abandoned --
(define m-own (make-mutex))
(test-assert "lock returns #t" (eq? #t (mutex-lock! m-own)))
(test-assert "locked/owned state is a thread" (thread? (mutex-state m-own)))
(test-eq "locked/owned owner is the current thread" (current-thread) (mutex-state m-own))
(test-assert "unlock returns #t" (eq? #t (mutex-unlock! m-own)))
(test-equal "back to unlocked/not-abandoned" 'not-abandoned (mutex-state m-own))

;; -- unlocked/not-abandoned -> locked/not-owned -> unlocked/not-abandoned --
;; SRFI 18 mutex-lock!: "if thread is #f the mutex becomes locked/not-owned"
(define m-noown (make-mutex))
(test-assert "lock with #f owner returns #t" (eq? #t (mutex-lock! m-noown #f #f)))
(test-equal "locked/not-owned" 'not-owned (mutex-state m-noown))
(test-assert "unlock from not-owned" (mutex-unlock! m-noown))
(test-equal "not-owned -> not-abandoned" 'not-abandoned (mutex-state m-noown))

;; a locked/not-owned mutex is genuinely locked: a timed lock must fail
(define m-noown2 (make-mutex))
(mutex-lock! m-noown2 #f #f)
(test-equal "locked/not-owned blocks a timed lock" #f (mutex-lock! m-noown2 0.02))
(mutex-unlock! m-noown2)

;; -- explicit owner argument naming another (live) thread --
(define m-other (make-mutex))
(define t-other (make-parked-child))
(thread-start! t-other)
(test-assert "lock with an explicit live-thread owner" (mutex-lock! m-other #f t-other))
(test-eq "state reports that explicit owner" t-other (mutex-state m-other))
(mutex-unlock! m-other)
(test-equal "explicitly-owned mutex unlocks to not-abandoned"
  'not-abandoned (mutex-state m-other))
(test-equal "reap t-other" 'TERMINATED (stop! t-other))

;; -- timed lock on a mutex this thread already holds --
;; SRFI-18 mutexes are not reentrant, so this must time out rather than
;; re-enter. Asserted by return value, not by elapsed time.
(define m-reent (make-mutex))
(mutex-lock! m-reent)
(test-equal "non-reentrant: timed relock returns #f" #f (mutex-lock! m-reent 0.02))
(test-equal "timed-out relock left the owner intact"
  (current-thread) (mutex-state m-reent))
(mutex-unlock! m-reent)

;; -- timeout of exactly 0, and an already-past time object --
(define m-t0 (make-mutex))
(mutex-lock! m-t0)
(test-equal "timeout 0 fails immediately" #f (mutex-lock! m-t0 0))
(test-equal "past time object fails immediately" #f (mutex-lock! m-t0 (seconds->time 0)))
(mutex-unlock! m-t0)

;; -- unlocking is unconditional: not an error on an unlocked mutex --
;; SRFI 18 mutex-unlock!: "It is not an error to unlock an unlocked mutex
;; and a mutex that is owned by any thread."
(test-assert "unlock of a never-locked mutex" (mutex-unlock! (make-mutex)))
(define m-dbl (make-mutex))
(mutex-lock! m-dbl)
(mutex-unlock! m-dbl)
(test-assert "double unlock" (mutex-unlock! m-dbl))
(test-equal "double unlock leaves not-abandoned" 'not-abandoned (mutex-state m-dbl))

;; a thread may unlock a mutex owned by a different thread
(define m-foreign (make-mutex))
(define t-foreign (make-parked-child))
(thread-start! t-foreign)
(mutex-lock! m-foreign #f t-foreign)
(test-assert "unlock a mutex owned by another thread" (mutex-unlock! m-foreign))
(test-equal "and it becomes not-abandoned" 'not-abandoned (mutex-state m-foreign))
(test-equal "reap t-foreign" 'TERMINATED (stop! t-foreign))

;; ---------------------------------------------------------------------
;; 3. Abandoned mutexes
;;
;; SRFI 18 thread-terminate!: "If the thread is not already terminated,
;; all mutexes owned by the thread become unlocked/abandoned".
;; SRFI 18 mutex-lock!: an "abandoned mutex exception" is raised if the
;; mutex was unlocked/abandoned before the state change.
;;
;; Each mutex here is its own TOP-LEVEL binding: the child reaches it
;; through the shared globals map, the only path that works (kaappi#1937).
;; ---------------------------------------------------------------------

;; -- a child that dies holding a mutex abandons it --
(define ab1 (make-mutex))
(define ab1-t (make-thread (lambda () (mutex-lock! ab1) 'held-at-exit)))
(thread-start! ab1-t)
(test-equal "child completed normally" 'held-at-exit (thread-join! ab1-t))
(test-equal "a mutex held by a dead thread is abandoned" 'abandoned (mutex-state ab1))

;; -- locking an abandoned mutex raises, and CLEARS the abandonment --
(test-assert "locking an abandoned mutex raises abandoned-mutex-exception"
  (guard (e (#t (abandoned-mutex-exception? e))) (mutex-lock! ab1) #f))
;; The state change happens before the raise: the mutex is now ours.
(test-eq "after the raise the mutex is locked/owned by us"
  (current-thread) (mutex-state ab1))
(mutex-unlock! ab1)
(test-equal "and the abandonment was consumed by the lock"
  'not-abandoned (mutex-state ab1))
(test-assert "so a second lock does not re-raise"
  (not (guard (e (#t (abandoned-mutex-exception? e))) (mutex-lock! ab1) #f)))
(mutex-unlock! ab1)

;; -- a terminated (not merely completed) thread also abandons --
(define ab2 (make-mutex))
(define ab2-t (make-thread (lambda () (mutex-lock! ab2) (let lp ((i 0)) (lp (+ i 1))))))
(thread-start! ab2-t)
;; hand-shake: wait until the child has actually taken the lock, rather
;; than sleeping a guessed interval
(let spin ((n 0))
  (cond ((thread? (mutex-state ab2)) 'taken)
        ((> n 400) 'gave-up)
        (else (thread-sleep! 0.01) (spin (+ n 1)))))
(test-assert "child holds it before we terminate" (thread? (mutex-state ab2)))
(thread-terminate! ab2-t)
;; NB: the abandonment is published by the CHILD as it unwinds, not by
;; thread-terminate! (which deliberately does not touch an OS thread's own
;; owned-mutexes list, #1458). So join first, then read the state -- asserting
;; it immediately after thread-terminate! is a race, and loses.
(test-equal "joining a terminated child reports termination" 'TERMINATED (join-outcome ab2-t))
(test-equal "terminated child's mutex is abandoned once reaped"
  'abandoned (mutex-state ab2))

;; -- CONTROL: a child that unlocks before exiting abandons nothing --
(define ab3 (make-mutex))
(define ab3-t (make-thread (lambda () (mutex-lock! ab3) (mutex-unlock! ab3) 'clean)))
(thread-start! ab3-t)
(test-equal "control child" 'clean (thread-join! ab3-t))
(test-equal "an unlocked mutex is never abandoned" 'not-abandoned (mutex-state ab3))
(test-assert "control: no abandoned-mutex-exception"
  (not (guard (e (#t (abandoned-mutex-exception? e))) (mutex-lock! ab3) #f)))
(mutex-unlock! ab3)

;; -- BUG: mutex-unlock! does not clear the abandoned flag --
;; SRFI 18 mutex-unlock!: "Unlocks the mutex by making it
;; unlocked/not-abandoned."  mutexUnlockFn (primitives_srfi18.zig:1207)
;; clears `owner` and `locked` but never touches `abandoned`; the only
;; writer that clears it is tryClaimAbandoned, inside mutex-lock!.
;; Consequence: an abandoned mutex that a program explicitly resets by
;; unlocking still raises a spurious abandoned-mutex-exception on the
;; next lock.  Controls: `ab3` above (never abandoned -> not-abandoned)
;; and `ab1` above (abandonment cleared via mutex-lock!) both behave.
(define ab4 (make-mutex))
(define ab4-t (make-thread (lambda () (mutex-lock! ab4) 'held)))
(thread-start! ab4-t)
(thread-join! ab4-t)
(test-equal "subject starts abandoned" 'abandoned (mutex-state ab4))
(test-assert "unlock of an abandoned mutex returns #t" (mutex-unlock! ab4))
;; FAIL: #1984 (mutex-unlock! leaves the mutex unlocked/abandoned instead of
;;       unlocked/not-abandoned, so the next mutex-lock! raises a spurious
;;       abandoned-mutex-exception)
;; (test-equal "unlock makes it unlocked/not-abandoned"
;;   'not-abandoned (mutex-state ab4))
;; (test-assert "and the next lock does not raise"
;;   (not (guard (e (#t (abandoned-mutex-exception? e))) (mutex-lock! ab4) #f)))
;; Pin the behaviour as it stands today, so a fix has to update this file:
(test-equal "TODAY: unlock leaves it abandoned" 'abandoned (mutex-state ab4))

;; -- SRFI 18 mutex-lock! with a TERMINATED thread as the owner argument --
;; "...otherwise let T be thread ... if T is terminated the mutex becomes
;; unlocked/abandoned".
(define ab5 (make-mutex))
(define ab5-dead (make-thread (lambda () 'quick)))
(thread-start! ab5-dead)
(thread-join! ab5-dead)
(test-assert "locking with a dead thread as owner returns" (mutex-lock! ab5 #f ab5-dead))
;; FAIL: #1982 (mutex-lock! with a terminated thread as the owner argument
;;       records it as the live owner instead of making the mutex
;;       unlocked/abandoned)
;; (test-equal "dead owner => unlocked/abandoned" 'abandoned (mutex-state ab5))
;; Pin today's behaviour; the live-owner control is `m-other` in section 2.
(test-eq "TODAY: the dead thread is recorded as owner" ab5-dead (mutex-state ab5))
(mutex-unlock! ab5)

;; ---------------------------------------------------------------------
;; 4. Condition variables
;;
;; SRFI 18 mutex-unlock!: "If condition-variable is supplied, the current
;; thread is blocked and added to the condition-variable before unlocking
;; mutex ... mutex-unlock! returns #f when the timeout is reached and #t
;; otherwise."
;; ---------------------------------------------------------------------

;; -- signal/broadcast with no waiters are no-ops, and return void --
(define cv-a (make-condition-variable 'cv-a))
(test-equal "cv name" 'cv-a (condition-variable-name cv-a))
(test-assert "signal with no waiters returns void"
  (eq? (if #f #f) (condition-variable-signal! cv-a)))
(test-assert "broadcast with no waiters returns void"
  (eq? (if #f #f) (condition-variable-broadcast! cv-a)))

;; -- a wait that times out returns #f --
(define cv-m1 (make-mutex))
(define cv-1 (make-condition-variable))
(mutex-lock! cv-m1)
(test-equal "cv wait times out => #f" #f (mutex-unlock! cv-m1 cv-1 0.03))
;; SRFI 18 does NOT mandate re-acquiring the mutex on wake (unlike
;; pthreads); pin that this implementation does not.
(test-equal "cv wait does not re-acquire the mutex"
  'not-abandoned (mutex-state cv-m1))

;; -- timeout 0 and a past time object both fail immediately --
(define cv-m2 (make-mutex))
(define cv-2 (make-condition-variable))
(mutex-lock! cv-m2)
(test-equal "cv wait, timeout 0" #f (mutex-unlock! cv-m2 cv-2 0))
(mutex-lock! cv-m2)
(test-equal "cv wait, past time object" #f (mutex-unlock! cv-m2 cv-2 (seconds->time 0)))

;; -- waiting without holding the mutex is not an error --
(test-equal "cv wait while not holding the mutex"
  #f (mutex-unlock! (make-mutex) (make-condition-variable) 0.03))

;; -- a signal from another OS thread wakes the waiter (returns #t) --
;; The generous 30s timeout is a HANG GUARD, not a timing assertion: the
;; assertion is that the return value is #t (woken), which can only
;; happen via the signal.
(define cvx-m (make-mutex))
(define cvx (make-condition-variable))
(define cvx-t (make-thread (lambda ()
                             (thread-sleep! 0.05)
                             (mutex-lock! cvx-m)
                             (condition-variable-signal! cvx)
                             (mutex-unlock! cvx-m)
                             'signaled)))
(thread-start! cvx-t)
(mutex-lock! cvx-m)
(test-equal "cross-thread signal wakes the waiter => #t"
  #t (mutex-unlock! cvx-m cvx 30))
(test-equal "signaling child completed" 'signaled (thread-join! cvx-t))

;; -- broadcast likewise --
(define cvb-m (make-mutex))
(define cvb (make-condition-variable))
(define cvb-t (make-thread (lambda ()
                             (thread-sleep! 0.05)
                             (mutex-lock! cvb-m)
                             (condition-variable-broadcast! cvb)
                             (mutex-unlock! cvb-m)
                             'broadcast)))
(thread-start! cvb-t)
(mutex-lock! cvb-m)
(test-equal "cross-thread broadcast wakes the waiter => #t"
  #t (mutex-unlock! cvb-m cvb 30))
(test-equal "broadcasting child completed" 'broadcast (thread-join! cvb-t))

;; -- spurious-wakeup discipline: a signal delivered BEFORE the wait
;;    starts must not satisfy that later wait. mutexUnlockFn snapshots
;;    the condvar's signal generation while still holding the mutex, so
;;    an earlier bump cannot be mistaken for one arriving during the
;;    wait. Asserted by the #f return, not by timing.
(define cvs-m (make-mutex))
(define cvs (make-condition-variable))
(mutex-lock! cvs-m)
(condition-variable-signal! cvs)          ; no waiters yet — must be dropped
(mutex-unlock! cvs-m)
(mutex-lock! cvs-m)
(test-equal "an earlier signal does not satisfy a later wait"
  #f (mutex-unlock! cvs-m cvs 0.05))

;; -- a non-condvar second argument is silently ignored (D2 note) --
;; Every other argument slot in this file type-checks; this one does not,
;; because mutexUnlockFn gates on `isConditionVariable(args[1])` rather
;; than validating it. A typo'd wait therefore degrades to a plain unlock.
(define cvn-m (make-mutex))
(mutex-lock! cvn-m)
(test-assert "unlock with a non-condvar 2nd arg does not raise"
  (not (raises? (lambda () (mutex-unlock! cvn-m 42)))))
(test-equal "TODAY: it just unlocks" 'not-abandoned (mutex-state cvn-m))

;; -- condvar accessors reject non-condvars --
(test-assert "cv-specific rejects a mutex" (raises? (lambda () (condition-variable-specific (make-mutex)))))
(test-assert "cv-signal rejects a mutex"   (raises? (lambda () (condition-variable-signal! (make-mutex)))))
(test-assert "cv-broadcast rejects a thread" (raises? (lambda () (condition-variable-broadcast! (current-thread)))))
(test-assert "cv-name rejects a time"      (raises? (lambda () (condition-variable-name (current-time)))))

;; ---------------------------------------------------------------------
;; 5. Thread lifecycle
;; ---------------------------------------------------------------------

;; -- join twice on a normally-completed thread returns the same result --
(define lc-1 (make-thread (lambda () 'once)))
(thread-start! lc-1)
(test-equal "first join" 'once (thread-join! lc-1))
(test-equal "second join returns the same result" 'once (thread-join! lc-1))
(test-equal "third join too" 'once (thread-join! lc-1))

;; -- join twice on a thread that raised reports the same reason --
(define lc-2 (make-thread (lambda () (raise 'boom-2))))
(thread-start! lc-2)
(test-equal "first join of a raising thread" '(UNCAUGHT boom-2) (join-outcome lc-2))
(test-equal "second join of a raising thread" '(UNCAUGHT boom-2) (join-outcome lc-2))

;; -- a thread that raises a non-symbol --
(define lc-3 (make-thread (lambda () (raise (list 1 2 3)))))
(thread-start! lc-3)
(test-equal "raised list survives the join boundary"
  '(UNCAUGHT (1 2 3)) (join-outcome lc-3))

;; -- a thread that calls (error ...) --
(define lc-4 (make-thread (lambda () (error "child failed"))))
(thread-start! lc-4)
(test-assert "error object crosses as an uncaught exception"
  (guard (e ((uncaught-exception? e) (error-object? (uncaught-exception-reason e))))
    (thread-join! lc-4) #f))

;; -- joining self raises, and is not a join-timeout --
(test-assert "joining self raises" (raises? (lambda () (thread-join! (current-thread)))))
(test-assert "joining self is not reported as a join timeout"
  (guard (e (#t (not (join-timeout-exception? e))))
    (thread-join! (current-thread)) #f))

;; -- starting a thread twice --
(define lc-5 (make-thread (lambda () (thread-sleep! 0.05) 'started-once)))
(thread-start! lc-5)
(test-assert "second thread-start! raises" (raises? (lambda () (thread-start! lc-5))))
(test-equal "and the thread still runs to completion" 'started-once (thread-join! lc-5))
(test-assert "starting a completed thread raises" (raises? (lambda () (thread-start! lc-5))))

;; -- terminate a genuinely running thread --
(define lc-6 (make-parked-child))
(thread-start! lc-6)
(thread-sleep! 0.05)
(thread-terminate! lc-6)
(test-equal "terminated running thread" 'TERMINATED (join-outcome lc-6))
(test-equal "join again still reports termination" 'TERMINATED (join-outcome lc-6))

;; -- terminate twice is not an error --
(define lc-7 (make-parked-child))
(thread-start! lc-7)
(thread-sleep! 0.05)
(thread-terminate! lc-7)
(test-assert "second terminate does not raise" (not (raises? (lambda () (thread-terminate! lc-7)))))
(test-equal "still terminated" 'TERMINATED (join-outcome lc-7))

;; -- terminate a never-started thread --
(define lc-8 (make-thread (lambda () 'never-runs)))
(thread-terminate! lc-8)
(test-equal "terminated before start" 'TERMINATED (join-outcome lc-8))
(test-assert "and it cannot be started afterwards" (raises? (lambda () (thread-start! lc-8))))

;; -- BUG (HANG): thread-terminate! cannot interrupt a thread parked inside
;;    a native SRFI-18 wait.
;; SRFI 18 thread-terminate!: "the termination of the thread will occur
;; before thread-terminate! returns."
;; #880 ("thread-terminate! cannot stop a running OS thread; thread-join!
;; afterwards blocks forever") was closed by #933, which polls
;; VM.terminate_flag at the 1024-instruction safepoint in
;; vm_dispatch.runUntil. That safepoint is only reached while the child is
;; executing BYTECODE. A child parked inside threadSleepFn, mutexLockFn or
;; mutexUnlockFn's condvar branch is inside a native `while (true)` /
;; runSchedulerStep loop, none of which consults fiber.terminated -- so it
;; only notices the termination after its wait ends on its own terms.
;; With no timeout at all, thread-join! then hangs FOREVER.
;;
;; Measured (each 15s alarm, uniform across runs):
;;   thread-sleep! 60         + terminate + join -> hang
;;   mutex-lock! m 60         + terminate + join -> hang
;;   mutex-unlock! m cv 60    + terminate + join -> hang
;;   mutex-lock! m   (no timeout) + terminate + join -> hangs forever
;;   mutex-unlock! m cv (no timeout) + terminate + join -> hangs forever
;;
;; These stay COMMENTED OUT: a hang takes the runner down as surely as an
;; abort, and run-all.sh counts a per-file timeout as a failure.
;; FAIL: #1982 (thread-terminate! is not observed by a thread parked in
;;       thread-sleep!, mutex-lock! or a condvar wait; thread-join!
;;       afterwards blocks for the remainder of the wait, or forever when
;;       the wait is untimed -- residual of closed #880)
;; (define lc-9 (make-thread (lambda () (thread-sleep! 60) 'woke)))
;; (thread-start! lc-9)
;; (thread-sleep! 0.05)
;; (thread-terminate! lc-9)
;; (test-equal "terminate unblocks a sleeping thread" 'TERMINATED (join-outcome lc-9))
;;
;; (define lc-m (make-mutex))
;; (mutex-lock! lc-m)
;; (define lc-10 (make-thread (lambda () (mutex-lock! lc-m 60) 'got-it)))
;; (thread-start! lc-10)
;; (thread-sleep! 0.05)
;; (thread-terminate! lc-10)
;; (test-equal "terminate unblocks a mutex waiter" 'TERMINATED (join-outcome lc-10))
;; (mutex-unlock! lc-m)
;;
;; (define lc-cm (make-mutex))
;; (define lc-cv (make-condition-variable))
;; (define lc-11 (make-thread (lambda () (mutex-lock! lc-cm) (mutex-unlock! lc-cm lc-cv 60) 'woke)))
;; (thread-start! lc-11)
;; (thread-sleep! 0.05)
;; (thread-terminate! lc-11)
;; (test-equal "terminate unblocks a condvar waiter" 'TERMINATED (join-outcome lc-11))

;; CONTROLS (enabled) that isolate the mechanism to "parked in native code":

;; (a) A child polling in SCHEME reaches the dispatch-loop safepoint and IS
;;     terminable -- so terminate itself works.
(define lc-9 (make-parked-child))
(thread-start! lc-9)
(thread-sleep! 0.05)
(test-equal "CONTROL: a Scheme-polling child terminates promptly"
  'TERMINATED (stop! lc-9))

;; (b) A child whose wait ends on its OWN timeout then observes the flag,
;;     so the same shape with a SHORT timeout does terminate.
(define lc-m (make-mutex))
(mutex-lock! lc-m)
(define lc-10 (make-thread (lambda () (mutex-lock! lc-m 0.2) 'timed-out)))
(thread-start! lc-10)
(thread-sleep! 0.05)
(test-equal "CONTROL: a short mutex wait expires, then sees the flag"
  'TERMINATED (stop! lc-10))
(mutex-unlock! lc-m)

;; (c) The waits themselves are sound when resolved normally: a parent
;;     unlock releases a mutex waiter, and a broadcast releases a condvar
;;     waiter. So it is only the TERMINATION signal that fails to arrive.
(define lc-m2 (make-mutex))
(mutex-lock! lc-m2)
(define lc-10b (make-thread (lambda () (mutex-lock! lc-m2 30) 'acquired)))
(thread-start! lc-10b)
(thread-sleep! 0.05)
(mutex-unlock! lc-m2)
(test-equal "CONTROL: unlocking releases a blocked mutex waiter"
  'acquired (thread-join! lc-10b))

(define lc-cm (make-mutex))
(define lc-cv (make-condition-variable))
(define lc-11 (make-thread (lambda () (mutex-lock! lc-cm) (mutex-unlock! lc-cm lc-cv 30) 'woke)))
(thread-start! lc-11)
(thread-sleep! 0.05)
(mutex-lock! lc-cm)
(condition-variable-broadcast! lc-cv)
(mutex-unlock! lc-cm)
(test-equal "CONTROL: broadcasting releases a blocked condvar waiter"
  'woke (thread-join! lc-11))

;; -- BUG: thread-terminate! on an ALREADY-TERMINATED thread destroys its
;;    end-result / end-exception.
;; SRFI 18 thread-terminate!: "*If the thread is not already terminated*,
;; all mutexes owned by the thread become unlocked/abandoned and a
;; 'terminated thread exception' object is stored in the thread's
;; end-exception field."
;; SRFI 18 thread-join!: "If the thread terminated normally, returns
;; end-result."
;; threadTerminateFn (primitives_srfi18.zig:684) stores `terminated = true`
;; unconditionally, ABOVE its own `status != .completed and status !=
;; .errored` guard, and threadJoinResult (:944) tests `terminated` before
;; either the result or the exception.
(define lc-12 (make-thread (lambda () 'result-kept)))
(thread-start! lc-12)
(thread-sleep! 0.08)
(test-equal "CONTROL: joins fine before any terminate" 'result-kept (join-outcome lc-12))
(thread-terminate! lc-12)
;; FAIL: #1982 (thread-terminate! on an already-completed thread replaces its
;;       end-result with a terminated-thread-exception)
;; (test-equal "terminating a completed thread must not destroy its result"
;;   'result-kept (join-outcome lc-12))
(test-equal "TODAY: the result is lost" 'TERMINATED (join-outcome lc-12))

;; same for a thread that terminated ABNORMALLY: the original reason is lost
(define lc-13 (make-thread (lambda () (raise 'original-reason))))
(thread-start! lc-13)
(thread-sleep! 0.08)
(test-equal "CONTROL: the raised reason is available"
  '(UNCAUGHT original-reason) (join-outcome lc-13))
(thread-terminate! lc-13)
;; FAIL: #1982 (thread-terminate! on an already-errored thread replaces its
;;       end-exception, losing the original raised object)
;; (test-equal "terminating an errored thread must not lose its reason"
;;   '(UNCAUGHT original-reason) (join-outcome lc-13))
(test-equal "TODAY: the reason is lost" 'TERMINATED (join-outcome lc-13))

;; -- a child's own (current-thread) is a DISTINCT fiber from the handle --
;; Documented in CLAUDE.md ("a child's own (current-thread) is a distinct
;; fiber that ensureScheduler allocated on the child heap"). The visible
;; consequence is that name/specific set by the parent are invisible inside
;; the child. Pinned as behaviour, not asserted as correct.
(define lc-14 (make-thread (lambda () (list (thread-name (current-thread))
                                            (thread-specific (current-thread))))
                           'NAME-FROM-PARENT))
(thread-specific-set! lc-14 'SPECIFIC-FROM-PARENT)
(test-equal "parent sees the name it set" 'NAME-FROM-PARENT (thread-name lc-14))
(test-equal "parent sees the specific it set" 'SPECIFIC-FROM-PARENT (thread-specific lc-14))
(thread-start! lc-14)
(test-equal "TODAY: the child's own thread object carries neither"
  (list (if #f #f) (if #f #f)) (thread-join! lc-14))

;; -- self-termination reports as an uncaught exception, not a
;;    terminated-thread exception (same two-fiber cause as lc-14) --
(define lc-15 (make-thread (lambda () (thread-terminate! (current-thread)) 'not-reached)))
(thread-start! lc-15)
;; FAIL: #1982 (a thread that terminates itself joins as an uncaught-exception
;;       with a void reason instead of a terminated-thread-exception)
;; (test-equal "self-terminated thread joins as TERMINATED"
;;   'TERMINATED (join-outcome lc-15))
(test-equal "TODAY: self-termination surfaces as an uncaught exception"
  (list 'UNCAUGHT (if #f #f)) (join-outcome lc-15))
;; CONTROL: terminated by the parent instead — reports correctly
(define lc-16 (make-parked-child))
(thread-start! lc-16)
(thread-sleep! 0.05)
(thread-terminate! lc-16)
(test-equal "CONTROL: parent-terminated reports TERMINATED" 'TERMINATED (join-outcome lc-16))

;; ---------------------------------------------------------------------
;; 6. thread-yield!
;;
;; SRFI 18: "The current thread exits the running state as if its quantum
;; had expired. thread-yield! returns an unspecified value."
;; Never exercised at all before Phase 5D.
;; ---------------------------------------------------------------------

(test-assert "yield returns void" (eq? (if #f #f) (thread-yield!)))
(test-assert "yield is repeatable" (begin (thread-yield!) (thread-yield!) (thread-yield!) #t))
(test-equal "yield inside a child thread"
  'yielded (run-child (lambda () (thread-yield!) (thread-yield!) 'yielded)))

;; ---------------------------------------------------------------------
;; 7. Time objects
;;
;; SRFI 18 time->seconds: "Converts the time object time into an exact or
;; inexact real number representing the number of seconds elapsed since
;; some implementation dependent reference point."
;; ---------------------------------------------------------------------

(test-assert "current-time is a time object" (time? (current-time)))
(test-assert "seconds->time makes a time object" (time? (seconds->time 1)))
(test-equal "a mutex is not a time" #f (time? (make-mutex)))
(test-equal "a thread is not a time" #f (time? (current-thread)))
(test-equal "a number is not a time" #f (time? 1.5))

;; -- round trips that are exactly representable --
(test-equal "round trip 0" 0.0 (time->seconds (seconds->time 0)))
(test-equal "round trip 1" 1.0 (time->seconds (seconds->time 1)))
(test-equal "round trip -1" -1.0 (time->seconds (seconds->time -1)))
(test-equal "round trip 0.5" 0.5 (time->seconds (seconds->time 0.5)))
(test-equal "round trip -0.5" -0.5 (time->seconds (seconds->time -0.5)))
(test-equal "round trip 1.25" 1.25 (time->seconds (seconds->time 1.25)))
(test-equal "round trip -1.25" -1.25 (time->seconds (seconds->time -1.25)))
(test-equal "round trip 123.5" 123.5 (time->seconds (seconds->time 123.5)))
(test-equal "round trip 3/4 (exact rational in)" 0.75 (time->seconds (seconds->time 3/4)))
(test-equal "round trip 1/2" 0.5 (time->seconds (seconds->time 1/2)))
(test-equal "round trip -1/2" -0.5 (time->seconds (seconds->time -1/2)))
(test-equal "round trip 1e9" 1000000000.0 (time->seconds (seconds->time 1e9)))
(test-equal "round trip 1e18" 1e18 (time->seconds (seconds->time 1e18)))

;; the result is always inexact, even for an exact argument
(test-equal "time->seconds is inexact" #f (exact? (time->seconds (seconds->time 100))))
(test-equal "exact input is accepted" 100.0 (time->seconds (seconds->time 100)))

;; -- the split into seconds + nanoseconds is lossy below ~1ns, which is
;;    visible for values that are not exactly representable --
(test-assert "0.1 round trips to within 1ns"
  (< (abs (- 0.1 (time->seconds (seconds->time 0.1)))) 1e-9))
(test-assert "-0.1 round trips to within 1ns"
  (< (abs (- -0.1 (time->seconds (seconds->time -0.1)))) 1e-9))

;; -- type errors are catchable --
(test-assert "seconds->time rejects a string" (raises? (lambda () (seconds->time "x"))))
(test-assert "seconds->time rejects a boolean" (raises? (lambda () (seconds->time #t))))
(test-assert "seconds->time rejects nil" (raises? (lambda () (seconds->time '()))))
(test-assert "seconds->time rejects a mutex" (raises? (lambda () (seconds->time (make-mutex)))))
(test-assert "time->seconds rejects a fixnum" (raises? (lambda () (time->seconds 42))))
(test-assert "time->seconds rejects a thread" (raises? (lambda () (time->seconds (current-thread)))))
(test-assert "time->seconds rejects a mutex" (raises? (lambda () (time->seconds (make-mutex)))))

;; -- BUG: seconds->time ABORTS the process (uncatchable, exit 134) once
;;    floor(x) leaves i64 range.
;; secondsToTimeFn (primitives_srfi18.zig:1397) does
;;   @as(i64, @intFromFloat(@floor(secs)))
;; with no range guard, so ReleaseSafe panics "integer part of floating
;; point value out of bounds". `guard` cannot catch a panic.
;; Cliff measured: 9.2e18 is fine, 9.3e18 aborts — exactly the i64 edge.
;; These stay COMMENTED OUT: running one takes the whole test runner down.
;; FAIL: #1983 (seconds->time panics, exit 134, on +inf.0/-inf.0 and any
;;       |x| >= 2^63 — uncatchable, aborts the process)
;; (test-assert "seconds->time +inf.0 raises catchably" (raises? (lambda () (seconds->time +inf.0))))
;; (test-assert "seconds->time -inf.0 raises catchably" (raises? (lambda () (seconds->time -inf.0))))
;; (test-assert "seconds->time 1e300 raises catchably"  (raises? (lambda () (seconds->time 1e300))))
;; (test-assert "seconds->time 2^63 raises catchably"   (raises? (lambda () (seconds->time (expt 2 63)))))
;; (test-assert "seconds->time 9.3e18 raises catchably" (raises? (lambda () (seconds->time 9.3e18))))
;; CONTROL (enabled): just below the cliff, the same code path is fine.
(test-assert "CONTROL: 9.2e18 is below the i64 cliff and works"
  (time? (seconds->time 9.2e18)))
(test-assert "CONTROL: 2^62 works" (time? (seconds->time (expt 2 62))))

;; NaN is not a panic but is silently wrong: it produces the epoch.
(test-equal "TODAY: seconds->time +nan.0 collapses to 0"
  0.0 (time->seconds (seconds->time +nan.0)))

;; ---------------------------------------------------------------------
;; 8. Timeouts, expressed as bare numbers and as time objects
;;
;; Every timeout-bearing entry point parses through timeoutToDeadlineNs
;; (primitives_srfi18.zig:228), which accepts #f, a SRFI-18 time object
;; (absolute), or a number (relative seconds).
;; ---------------------------------------------------------------------

;; -- thread-join!: timeout-val is returned rather than raising --
(define to-1 (make-parked-child))
(thread-start! to-1)
(test-equal "join timeout, number, with timeout-val" 'TV (thread-join! to-1 0.03 'TV))
(test-equal "join timeout, past time object" 'TV (thread-join! to-1 (seconds->time 0) 'TV))
(test-equal "join timeout, 0" 'TV (thread-join! to-1 0 'TV))
;; an absolute time object in the near future
(test-equal "join timeout, now + 0.03 as a time object"
  'TV (thread-join! to-1 (seconds->time (+ 0.03 (time->seconds (current-time)))) 'TV))
;; -- without timeout-val it raises a join-timeout-exception --
(test-assert "join timeout without timeout-val raises join-timeout-exception"
  (guard (e (#t (join-timeout-exception? e))) (thread-join! to-1 0.03) #f))
;; #f means "no timeout" — not "timeout immediately". Checked against a
;; thread that finishes, so this cannot hang.
(test-equal "cleanup: reap to-1" 'TERMINATED (stop! to-1))

(define to-2 (make-thread (lambda () (thread-sleep! 0.05) 'finished)))
(thread-start! to-2)
(test-equal "timeout #f means block until done" 'finished (thread-join! to-2 #f 'TV))

;; -- a timeout-val is only returned on timeout, never on success --
(define to-3 (make-thread (lambda () 'real-result)))
(thread-start! to-3)
(test-equal "timeout-val is not returned when the thread completed"
  'real-result (thread-join! to-3 30 'TV))

;; -- bad timeout types are catchable type errors, on every entry point --
(define to-m (make-mutex))
(mutex-lock! to-m)
(test-assert "mutex-lock! rejects a string timeout" (raises? (lambda () (mutex-lock! to-m "soon"))))
(test-assert "mutex-lock! rejects a symbol timeout" (raises? (lambda () (mutex-lock! to-m 'soon))))
(mutex-unlock! to-m)
(test-assert "mutex-unlock! rejects a string cv timeout"
  (raises? (lambda () (mutex-unlock! (make-mutex) (make-condition-variable) "soon"))))
(define to-4 (make-thread (lambda () 'x)))
(thread-start! to-4)
(thread-join! to-4)
(test-assert "thread-join! rejects a string timeout" (raises? (lambda () (thread-join! to-4 "soon"))))

;; -- thread-sleep! accepts every numeric spelling; #f is an error --
;; SRFI 18 thread-sleep!: "It is an error for timeout to be #f."
(test-assert "sleep 0 returns" (begin (thread-sleep! 0) #t))
(test-assert "sleep negative returns immediately" (begin (thread-sleep! -1) #t))
(test-assert "sleep a rational" (begin (thread-sleep! 1/100) #t))
(test-assert "sleep a past time object" (begin (thread-sleep! (seconds->time 0)) #t))
(test-assert "sleep -inf.0 returns immediately" (begin (thread-sleep! -inf.0) #t))
(test-assert "sleep #f raises" (raises? (lambda () (thread-sleep! #f))))
(test-assert "sleep a string raises" (raises? (lambda () (thread-sleep! "5"))))
(test-assert "sleep a mutex raises" (raises? (lambda () (thread-sleep! (make-mutex)))))
(test-assert "sleep a bignum raises (not a supported spelling)"
  (raises? (lambda () (thread-sleep! (expt 2 70)))))

;; -- BUG: the same unchecked @intFromFloat aborts EVERY timeout entry
;;    point, not just seconds->time.
;; timeoutToDeadlineNs (primitives_srfi18.zig:244) does
;;   const delta_ns: u64 = @intFromFloat(@max(0.0, secs) * 1_000_000_000.0);
;; and threadSleepFn (:604) does the same for its own duration. Any
;; timeout above ~1.845e10 seconds (u64 nanoseconds) aborts the process.
;; timeoutToDeadlineNs is `pub` and is also what (kaappi fibers)
;; channel-send/channel-receive timeouts parse through, so the blast
;; radius is wider than SRFI 18.
;; Cliff measured: 1.8e10 is fine (catchable), 1.9e10 aborts.
;; FAIL: #1984 (thread-sleep! / mutex-lock! / thread-join! / mutex-unlock!+cv
;;       panic, exit 134, on +inf.0 or a timeout >= ~1.845e10 seconds)
;; (test-assert "thread-sleep! +inf.0 raises catchably" (raises? (lambda () (thread-sleep! +inf.0))))
;; (test-assert "thread-sleep! 1e300 raises catchably"  (raises? (lambda () (thread-sleep! 1e300))))
;; (test-assert "mutex-lock! +inf.0 timeout raises catchably"
;;   (raises? (lambda () (let ((m (make-mutex))) (mutex-lock! m) (mutex-lock! m +inf.0)))))
;; (test-assert "thread-join! +inf.0 timeout raises catchably"
;;   (raises? (lambda () (thread-join! (make-thread (lambda () 1)) +inf.0 'TV))))
;; (test-assert "mutex-unlock!+cv +inf.0 timeout raises catchably"
;;   (raises? (lambda () (mutex-unlock! (make-mutex) (make-condition-variable) +inf.0))))
;; CONTROL (enabled): just below the cliff the SAME conversion runs and
;; does not abort — so the failure is the conversion, not the magnitude.
;; Driven through a thread that has already completed, so the timeout is
;; parsed but never actually waited out.
(define to-5 (make-thread (lambda () 'done-immediately)))
(thread-start! to-5)
(thread-join! to-5)
(test-equal "CONTROL: a 1.8e10s timeout parses without aborting"
  'done-immediately (thread-join! to-5 1.8e10 'TV))
(test-equal "CONTROL: 1e9 seconds as a time object parses too"
  'done-immediately (thread-join! to-5 (seconds->time 1e9) 'TV))

;; -- and the TIME-OBJECT branch has its own, separate unguarded arithmetic.
;; timeoutToDeadlineNs (:234) computes
;;   const sec_ns: u64 = @as(u64, @intCast(t.seconds)) * 1_000_000_000 + ns_clamped;
;; which overflows u64 for the same ~1.845e10-second threshold, but panics
;; "integer overflow" rather than the "integer part of floating point value
;; out of bounds" the number branch produces -- two distinct sites, one
;; cliff. Measured: (seconds->time 1.8e10) is fine, (seconds->time 1.9e10)
;; aborts.
;; FAIL: #1984 (a time-object timeout whose seconds field exceeds ~1.845e10
;;       panics with "integer overflow", exit 134, in timeoutToDeadlineNs)
;; (test-assert "a huge absolute time object raises catchably"
;;   (raises? (lambda () (thread-join! to-5 (seconds->time 1e18) 'TV))))
(test-equal "CONTROL: 1.8e10 as a time object is just below that cliff"
  'done-immediately (thread-join! to-5 (seconds->time 1.8e10) 'TV))

;; ---------------------------------------------------------------------
;; 9. Exception objects and predicates (dimension D2)
;;
;; The four predicates partition the SRFI-18 error objects; each must
;; answer #t for exactly its own kind.
;; ---------------------------------------------------------------------

;; a join-timeout exception is only a join-timeout exception
(define ex-t (make-parked-child))
(thread-start! ex-t)
(define join-timeout-obj
  (guard (e (#t e)) (thread-join! ex-t 0.03) #f))
(test-assert "join-timeout-exception? on its own object" (join-timeout-exception? join-timeout-obj))
(test-equal "not an abandoned-mutex exception" #f (abandoned-mutex-exception? join-timeout-obj))
(test-equal "not a terminated-thread exception" #f (terminated-thread-exception? join-timeout-obj))
(test-equal "not an uncaught exception" #f (uncaught-exception? join-timeout-obj))
(test-equal "reap ex-t" 'TERMINATED (stop! ex-t))

;; a terminated-thread exception, likewise
(define ex-term (make-parked-child))
(thread-start! ex-term)
(thread-sleep! 0.05)
(thread-terminate! ex-term)
(define term-obj (guard (e (#t e)) (thread-join! ex-term) #f))
(test-assert "terminated-thread-exception? on its own object" (terminated-thread-exception? term-obj))
(test-equal "term: not join-timeout" #f (join-timeout-exception? term-obj))
(test-equal "term: not abandoned-mutex" #f (abandoned-mutex-exception? term-obj))
(test-equal "term: not uncaught" #f (uncaught-exception? term-obj))

;; an abandoned-mutex exception, likewise
(define ex-m (make-mutex))
(define ex-mt (make-thread (lambda () (mutex-lock! ex-m) 'held)))
(thread-start! ex-mt)
(thread-join! ex-mt)
(define ab-obj (guard (e (#t e)) (mutex-lock! ex-m) #f))
(test-assert "abandoned-mutex-exception? on its own object" (abandoned-mutex-exception? ab-obj))
(test-equal "ab: not join-timeout" #f (join-timeout-exception? ab-obj))
(test-equal "ab: not terminated-thread" #f (terminated-thread-exception? ab-obj))
(test-equal "ab: not uncaught" #f (uncaught-exception? ab-obj))
(mutex-unlock! ex-m)

;; an uncaught exception, likewise
(define ex-u (make-thread (lambda () (raise 'the-reason))))
(thread-start! ex-u)
(define unc-obj (guard (e (#t e)) (thread-join! ex-u) #f))
(test-assert "uncaught-exception? on its own object" (uncaught-exception? unc-obj))
(test-equal "unc: not join-timeout" #f (join-timeout-exception? unc-obj))
(test-equal "unc: not abandoned-mutex" #f (abandoned-mutex-exception? unc-obj))
(test-equal "unc: not terminated-thread" #f (terminated-thread-exception? unc-obj))
(test-equal "uncaught-exception-reason recovers the raised object"
  'the-reason (uncaught-exception-reason unc-obj))

;; an ordinary R7RS error object is none of the four
(define plain-err (guard (e (#t e)) (error "just an error")))
(test-equal "plain: not join-timeout" #f (join-timeout-exception? plain-err))
(test-equal "plain: not abandoned-mutex" #f (abandoned-mutex-exception? plain-err))
(test-equal "plain: not terminated-thread" #f (terminated-thread-exception? plain-err))
(test-equal "plain: not uncaught" #f (uncaught-exception? plain-err))

;; the predicates never crash on arbitrary values
(test-equal "predicates on a mutex" '(#f #f #f #f)
  (list (join-timeout-exception? (make-mutex))
        (abandoned-mutex-exception? (make-mutex))
        (terminated-thread-exception? (make-mutex))
        (uncaught-exception? (make-mutex))))
(test-equal "predicates on a vector" '(#f #f #f #f)
  (list (join-timeout-exception? (vector 1))
        (abandoned-mutex-exception? (vector 1))
        (terminated-thread-exception? (vector 1))
        (uncaught-exception? (vector 1))))

;; uncaught-exception-reason rejects everything that is not one
(test-assert "reason rejects a plain error" (raises? (lambda () (uncaught-exception-reason plain-err))))
(test-assert "reason rejects a fixnum" (raises? (lambda () (uncaught-exception-reason 42))))
(test-assert "reason rejects a join-timeout object"
  (raises? (lambda () (uncaught-exception-reason join-timeout-obj))))
(test-assert "reason rejects a terminated-thread object"
  (raises? (lambda () (uncaught-exception-reason term-obj))))

;; ---------------------------------------------------------------------
;; NOT ASSERTED HERE (probe-only — see the Phase 5D report)
;;
;;  * mutex-state returns the CHILD's own fiber while a child OS thread
;;    holds a shared mutex. After thread-join! frees the child heap that
;;    value is a dangling pointer: `thread?` flips from #t to #f and the
;;    recycled slot was observed reading back as the pair (0.0 . 0.0).
;;    This is the kaappi#1924 class reached WITHOUT any user mutation —
;;    mutex-lock! installs the pointer and mutex-state hands it out. Left
;;    out of the suite entirely because asserting it means dereferencing
;;    freed memory.
;;  * The child-side view of a shared mutex under gc-stress.
;; ---------------------------------------------------------------------

(let ((runner (test-runner-current)))
  (test-end "primitives_srfi18 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
