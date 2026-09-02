;;; Regression tests for #2469: the builtin-superinstruction gate is a
;;; run-time decision.
;;;
;;; `apply` / `call-with-values` (any position) and `eval` / `call/cc` /
;;; `call-with-current-continuation` (tail position) compile to a
;;; superinstruction. R7RS 5.3.1 makes a top-level definition essentially an
;;; assignment, so which binding a call reaches is a run-time question. #2033
;;; answered it by reading the global environment at compile time and #2457
;;; by pre-scanning the whole compilation unit for later definitions; both
;;; baked the answer into bytecode compiled before the redefinition ran, and
;;; the scan could not see a redefinition arriving through `load`, `eval`, the
;;; REPL, or a `set!` a macro materializes. Every superinstruction now sits
;;; behind a `guard_builtin` opcode that compares the global's current
;;; binding against the pristine primitive and falls back to an ordinary
;;; call — so this file's every section redefines a name through a route the
;;; scan was blind to, from a body compiled before the redefinition existed.
;;;
;;; The whole-unit shapes (#2457's own file) and the define-before-use order
;;; (#2033's) keep their own suites; this one covers only the routes #2469
;;; listed as still baking the builtin in.

(import (scheme base) (scheme write) (scheme eval) (scheme load) (scheme file)
        (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "top-level-redefinition-runtime-2469")

(define saved-2469-orig-apply apply)
(define saved-2469-orig-eval eval)
(define saved-2469-orig-call/cc call/cc)
(define saved-2469-orig-cwv call-with-values)
(define saved-2469-orig-ccc call-with-current-continuation)

;;; ------------------------------------------------------------------
;;; eval: the redefinition and the caller both live inside an `eval`'d
;;; `begin`, compiled as one per-form unit with no future knowledge.
;;; ------------------------------------------------------------------

(eval '(begin (define (nt-eval-apply) (apply + (list 1 2)))
              (define (apply f xs) 'eval-user))
      (interaction-environment))
(test-eq "eval: use-before-define of apply inside one eval'd begin honours it"
  'eval-user (nt-eval-apply))
(define apply saved-2469-orig-apply)
(test-eq "eval: genuine apply restored" 3 (nt-eval-apply))

;;; A caller compiled by THIS file, redefined by a later eval.
(define (t-eval-cwv) (call-with-values (lambda () 1) (lambda (x) x)))
(eval '(define (call-with-values p c) 'eval-user-cwv) (interaction-environment))
(test-eq "eval: a redefinition eval'd later reaches a body this file compiled"
  'eval-user-cwv (t-eval-cwv))
(define call-with-values saved-2469-orig-cwv)
(test-eq "eval: genuine call-with-values restored" 1 (t-eval-cwv))

;;; ------------------------------------------------------------------
;;; load: the loaded file's own use-before-define order. The loaded file is
;;; compiled form by form as it is read, so its first body has no knowledge
;;; of the define that follows.
;;; ------------------------------------------------------------------

(define load-path-2469
  (string-append "kaappi-2469-load-" (number->string (exact (floor (current-second)))) ".scm"))
(when (file-exists? load-path-2469) (delete-file load-path-2469))
(with-output-to-file load-path-2469
  (lambda ()
    (write '(define (nt-loaded) (apply + (list 1 2))))
    (newline)
    (write '(define (apply f xs) 'loaded-user))
    (newline)
    (write '(define loaded-result (nt-loaded)))
    (newline)))
(load load-path-2469)
(delete-file load-path-2469)
(test-eq "load: the loaded file's use-before-define of apply honours it"
  'loaded-user loaded-result)
(test-eq "load: the loaded redefinition reaches this file's later calls too"
  'loaded-user (nt-loaded))
(define apply saved-2469-orig-apply)
(test-eq "load: genuine apply restored" 3 (nt-loaded))

;;; ------------------------------------------------------------------
;;; A set! that only materializes when a macro expands, targeting the
;;; use-site name: invisible to any structure-only scan of the source.
;;; ------------------------------------------------------------------

(define (nt-macro-apply) (let ((v (apply + (list 1 2)))) v))
(define (t-macro-eval) (eval '(+ 1 2) (interaction-environment)))
(define (t-macro-callcc) (call/cc (lambda (k) 1)))
(define (t-macro-ccc) (call-with-current-continuation (lambda (k) 1)))
(define-syntax redef!
  (syntax-rules ()
    ((_ name value) (set! name value))))
(redef! apply (lambda (f xs) 'macro-set-apply))
(redef! eval (lambda (x . env) 'macro-set-eval))
(redef! call/cc (lambda (r) 'macro-set-callcc))
(redef! call-with-current-continuation (lambda (r) 'macro-set-ccc))
(test-eq "macro set!: apply (non-tail)" 'macro-set-apply (nt-macro-apply))
(test-eq "macro set!: apply at the use site too" 'macro-set-apply (apply + '(1 2)))
(test-eq "macro set!: eval (tail)" 'macro-set-eval (t-macro-eval))
(test-eq "macro set!: call/cc (tail)" 'macro-set-callcc (t-macro-callcc))
(test-eq "macro set!: call-with-current-continuation (tail)" 'macro-set-ccc (t-macro-ccc))
(define apply saved-2469-orig-apply)
(define eval saved-2469-orig-eval)
(define call/cc saved-2469-orig-call/cc)
(define call-with-current-continuation saved-2469-orig-ccc)
(test-equal "macro set!: all four genuine bindings restored"
  '(3 3 1 1)
  (list (nt-macro-apply) (t-macro-eval) (t-macro-callcc) (t-macro-ccc)))

;;; ------------------------------------------------------------------
;;; The redefinition happens WHILE a caller is on the stack: the guard reads
;;; the binding at each call, not once per body.
;;; ------------------------------------------------------------------

(define (twice thunk) (let ((first (thunk))) (list first (thunk))))
(define (flip-then-apply)
  (twice (lambda ()
           (let ((v (apply + (list 1 2))))
             (set! apply (lambda (f xs) 'flipped))
             v))))
(test-equal "mid-flight set!: the second call in the same body sees the new binding"
  '(3 flipped) (flip-then-apply))
(define apply saved-2469-orig-apply)

;;; ------------------------------------------------------------------
;;; A library body's own use-before-define order: `apply` is excluded from
;;; the import so the library's later define is a fresh binding, and the
;;; first body was compiled before it existed.
;;; ------------------------------------------------------------------

(define-library (kaappi-2469 lib)
  (import (except (scheme base) apply))
  (export lib-use lib-apply)
  (begin
    (define (lib-use) (apply + (list 1 2)))
    (define (apply f xs) 'lib-user)
    (define lib-apply apply)))
(import (kaappi-2469 lib))
(test-eq "library body: use-before-define of a library-local apply honours it"
  'lib-user (lib-use))
(test-eq "library body: the program's own apply is untouched" 3 (apply + '(1 2)))

;;; ------------------------------------------------------------------
;;; A non-procedure rebinding through eval reports the ordinary call's type
;;; error rather than running the builtin.
;;; ------------------------------------------------------------------

(define (t-nonproc) (call/cc (lambda (k) 1)))
(eval '(define call/cc 42) (interaction-environment))
(test-assert "eval: call/cc rebound to a non-procedure raises, not the builtin"
  (guard (e (#t (error-object? e))) (t-nonproc) #f))
(define call/cc saved-2469-orig-call/cc)
(test-eq "eval: genuine call/cc restored" 1 (t-nonproc))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "top-level-redefinition-runtime-2469")
(if (> %test-fail-count 0) (exit 1))
