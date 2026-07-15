;; Regression test for #1520: a closure that crosses a thread-start! boundary
;; and then CALLS a separately-defined library top-level procedure used to
;; hang forever.
;;
;; Root cause (shared with #1479): GC.deepCopy copied the thread thunk to the
;; child OS thread's heap but set new_func.env = null, dropping the closure's
;; defining lib_env. The child then resolved names through the shared globals
;; map instead. A library top-level helper lives in the library's lib_env, not
;; in globals, so the child could not find the helper it was supposed to call:
;; it died silently and the parent, parked on (channel-receive reply), never
;; woke -- a pure hang, no error surfaced. Fixed in #1526 (new_func.env =
;; func.env).
;;
;; The identical logic INLINED into the thunk (no separate helper) always
;; worked, even before the fix -- that inlined-vs-helper contrast is the tell,
;; and both forms are asserted below.
;;
;; NAMING, DO NOT "SIMPLIFY": the library helper is named worker-loop and the
;; program-level helper is named prog-worker-loop *on purpose*. Before the fix
;; the child fell back to globals; if a program top-level (define (worker-loop
;; ...)) existed there, the child would resolve THAT by coincidence and the
;; library hang would be masked -- the guard would silently stop guarding.
;; Keep the two helper names distinct.
;;
;; Distinct from #1479's regression test, which calls into ANOTHER library's
;; export and reads the result back via thread-join!. Here the helper is
;; same-library and the hang is the parent parking on a channel -- the exact
;; shape reported in #1520.
(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (kaappi fibers) (srfi 64) (lib1520 pool))

;; Watchdog: if the library case regresses to a hang, fail fast (exit 1)
;; instead of stalling run-all.sh for its full 60s per-file timeout. A passing
;; run finishes in milliseconds and exits before this fires; kaappi tears the
;; sleeping watchdog down on main-thread exit.
(define _watchdog
  (thread-start!
    (make-thread
      (lambda ()
        (thread-sleep! 20)
        (display "TIMEOUT: #1520 regression -- a cross-thread named-helper ")
        (display "call hung (child could not resolve the helper)\n")
        (exit 1)))))

;; --- Program-level (bare-script) worker: helper and inlined forms ---
;; prog-worker-loop is a program top-level define; the thunk calls it after
;; crossing thread-start!. Program top-level defines DO land in globals, so the
;; child's globals fallback resolved this even before the fix -- this form is
;; documentation/contrast, not the regression trigger.
(define (prog-worker-loop tasks)
  (let loop ((msg (channel-receive tasks)))
    (unless (eof-object? msg)
      (let ((thunk (car msg)) (reply (cdr msg)))
        (channel-send reply (thunk)))
      (loop (channel-receive tasks)))))

(define (prog-drive spawn)
  (let ((tasks (make-channel))
        (reply (make-channel)))
    (let ((worker (spawn tasks)))
      (channel-send tasks (cons (lambda () (* 6 7)) reply))
      (let ((result (channel-receive reply)))
        (channel-close! tasks)
        (thread-join! worker)
        result))))

(define (prog-run/helper)
  (prog-drive (lambda (tasks)
                (thread-start!
                  (make-thread (lambda () (prog-worker-loop tasks)))))))

(define (prog-run/inlined)
  (prog-drive (lambda (tasks)
                (thread-start!
                  (make-thread
                    (lambda ()
                      (let loop ((msg (channel-receive tasks)))
                        (unless (eof-object? msg)
                          (let ((thunk (car msg)) (reply (cdr msg)))
                            (channel-send reply (thunk)))
                          (loop (channel-receive tasks))))))))))

(test-begin "library-thread-named-helper-1520")

;; Library-level: the helper form HUNG before #1526 (the actual regression
;; guard); the inlined form is the contrast that always worked.
(test-equal "library thunk calling a named library helper returns the result"
            42 (run-pool/helper))
(test-equal "library thunk with the loop inlined returns the result"
            42 (run-pool/inlined))

;; Program-level: both worked before and after the fix (globals fallback).
(test-equal "program-level thunk calling a named helper returns the result"
            42 (prog-run/helper))
(test-equal "program-level thunk with the loop inlined returns the result"
            42 (prog-run/inlined))

(let ((runner (test-runner-current)))
  (test-end "library-thread-named-helper-1520")
  (exit (if (> (test-runner-fail-count runner) 0) 1 0)))
