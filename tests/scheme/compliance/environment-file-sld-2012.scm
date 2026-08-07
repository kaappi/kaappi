;;; #2012 regression: (environment '(srfi N)) on a file-backed .sld must not
;;; abandon the rest of the enclosing top-level form.
;;;
;;; The FIRST top-level form whose evaluation loads a file-backed .sld
;;; through (environment ...) used to be silently abandoned partway through:
;;; side effects performed before the load persisted, everything after it
;;; (including the form's own define or display) never happened, with no
;;; error and exit 0. The second, byte-identical form worked, because the
;;; library was loaded by then — so a program either behaved correctly or
;;; silently lost a whole top-level form depending on whether some earlier
;;; form had touched the same library.
;;;
;;; Root cause: the .sld file-load path in vm_library (tryLoadLibraryFromFile
;;; -> loadLibrarySource) re-entered vm.execute to run the library body, and
;;; vm.execute's resetExecutionState destroyed the enclosing top-level form's
;;; frame. The nested call "succeeded", so the outer runUntil loop then saw
;;; frame_count == 0 and exited cleanly, abandoning the rest of the form.
;;; Fixed by routing every nested-entry top-level thunk through
;;; runTopLevelFunction (vm_eval.zig, the #1500 re-entrant-safe path), which
;;; pushes a frame above the live ones instead of resetting them away.
;;;
;;; Every probe below performs the FIRST file-backed .sld load of its
;;; library inside a top-level form with observable work after the load. On
;;; the buggy build the defining form is abandoned at the load, so its
;;; binding never happens and the assertion errors with "undefined variable"
;;; (exit nonzero) — a loud failure, not a silent pass.
;;;
;;; Deliberately no (import (srfi 158))/(import (srfi 181)) here: importing
;;; them would load the libraries before any probe runs, and a probe then
;;; touches an already-registered library, which never triggered the bug.
;;; (srfi 64) is imported because the runner needs it, but its own
;;; import-time load is a different library and completes via the native
;;; merge path, which the bug never affected.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/compliance/environment-file-sld-2012.scm

(import (scheme base) (scheme write) (scheme eval) (scheme repl) (srfi 64))

(test-begin "environment-file-sld-2012")

;; Probe 1 — the issue's minimal shape: the load happens inside a top-level
;; define's initializer, so the define itself must complete. Buggy: the
;; initializer is abandoned after the load and the define never binds.
(define first-load-proc
  (eval 'generator (environment '(srfi 158))))
(test-assert "define whose initializer performs the first file-backed load completes"
  (procedure? first-load-proc))

;; Probe 2 — side effects BEFORE the load persist (they did even on the
;; buggy build), but the form must also complete past the load.
(define n 0)
(define (bump!) (set! n (+ n 1)) n)
(define load-form-completed
  (begin
    (bump!)
    (procedure? (eval 'generator (environment '(srfi 158))))))
(test-assert "a form survives a load that follows a side effect"
  (and (= n 1) load-form-completed))

;; Probe 3 — routing the call through a helper procedure (native
;; re-entrancy) must not abandon the calling top-level form either.
(define (probe) (procedure? (eval 'generator (environment '(srfi 158)))))
(test-assert "a load reached through a helper procedure keeps the caller intact"
  (probe))

;; Probe 4 — a different file-backed library, the issue's second example.
(define second-load-proc
  (eval 'utf-8-codec (environment '(srfi 181))))
(test-assert "a second file-backed library loads without abandoning its form"
  (procedure? second-load-proc))

(let ((runner (test-runner-current)))
  (test-end "environment-file-sld-2012")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
