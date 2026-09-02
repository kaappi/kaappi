;;; Regression tests for #2457: a top-level redefinition of apply,
;;; call-with-values, eval, call/cc or call-with-current-continuation was
;;; ignored by any procedure body compiled BEFORE the redefinition ran, in
;;; both tail and non-tail position.
;;;
;;; R7RS 5.3.1: "At the top level of a program, a definition ... has
;;; essentially the same effect as the assignment expression", so which
;;; binding a call resolves is a run-time question. The superinstruction gate
;;; (`globalBindingStillGenuine`) answered it by reading the live global
;;; environment at COMPILE time, which is wrong whenever the compilation order
;;; and the definition order differ. #2033 fixed the define-BEFORE-use order
;;; that way; the use-BEFORE-define order kept silently running the builtin.
;;;
;;; #2457's interim fix was a whole-unit pre-scan of top-level define/set!
;;; targets that declined the fast path for those names everywhere in the
;;; unit. #2469 replaced it with the honest run-time decision: every
;;; superinstruction now sits behind a `guard_builtin` opcode that compares
;;; the global's current binding against the pristine primitive at each call
;;; and falls back to an ordinary call. This file keeps asserting what both
;;; fixes had to deliver — the user's binding wins from the first call, and
;;; restoring the genuine binding makes the builtin visible again — through
;;; every whole-unit shape (a later define, a later set!, a begin-spliced
;;; define). The routes the scan could not see (`load`, `eval`, the REPL, a
;;; macro-materialized set!) are top-level-redefinition-runtime-2469.scm.
;;;
;;; `car` and `map` in the identical shape were always correct (they never had
;;; a superinstruction to bake in) and run here as the contrast.

(import (scheme base) (scheme write) (scheme eval) (srfi 64))

(define %test-fail-count 0)
(test-begin "top-level-redefinition-order-2457")

(define saved-2457-orig-apply apply)
(define saved-2457-orig-eval eval)
(define saved-2457-orig-call/cc call/cc)
(define saved-2457-orig-cwv call-with-values)
(define saved-2457-orig-ccc call-with-current-continuation)

;;; ------------------------------------------------------------------
;;; The five names, the caller defined BEFORE the redefinition runs —
;;; the reverse of #2033's order, both tail and non-tail position.
;;; ------------------------------------------------------------------

(define (nt-apply) (let ((v (apply + (list 1 2)))) v))
(define (t-apply) (apply + (list 1 2)))
(define (apply f xs) 'user-apply)
(test-eq "apply: body compiled before the redefinition honours it (non-tail)"
  'user-apply (nt-apply))
(test-eq "apply: body compiled before the redefinition honours it (tail)"
  'user-apply (t-apply))
(define apply saved-2457-orig-apply)
(test-eq "apply: genuine binding restored" 3 (nt-apply))

(define (nt-cwv)
  (let ((v (call-with-values (lambda () 1) (lambda (x) x)))) v))
(define (t-cwv) (call-with-values (lambda () 1) (lambda (x) x)))
(define (call-with-values p c) 'user-cwv)
(test-eq "call-with-values: body compiled before the redefinition honours it (non-tail)"
  'user-cwv (nt-cwv))
(test-eq "call-with-values: body compiled before the redefinition honours it (tail)"
  'user-cwv (t-cwv))
(define call-with-values saved-2457-orig-cwv)
(test-eq "call-with-values: genuine binding restored" 1 (nt-cwv))

(define (nt-eval) (let ((v (eval '(+ 1 2) (interaction-environment)))) v))
(define (t-eval) (eval '(+ 1 2) (interaction-environment)))
(define (eval x . env) 'user-eval)
(test-eq "eval: body compiled before the redefinition honours it (non-tail)"
  'user-eval (nt-eval))
(test-eq "eval: body compiled before the redefinition honours it (tail)"
  'user-eval (t-eval))
(define eval saved-2457-orig-eval)
(test-eq "eval: genuine binding restored" 3 (nt-eval))

(define (nt-callcc) (let ((v (call/cc (lambda (k) 1)))) v))
(define (t-callcc) (call/cc (lambda (k) 1)))
(define (call/cc f) 'user-callcc)
(test-eq "call/cc: body compiled before the redefinition honours it (non-tail)"
  'user-callcc (nt-callcc))
(test-eq "call/cc: body compiled before the redefinition honours it (tail)"
  'user-callcc (t-callcc))
(define call/cc saved-2457-orig-call/cc)
(test-eq "call/cc: genuine binding restored" 1 (nt-callcc))

(define (nt-ccc)
  (let ((v (call-with-current-continuation (lambda (k) 1)))) v))
(define (t-ccc) (call-with-current-continuation (lambda (k) 1)))
(define (call-with-current-continuation f) 'user-ccc)
(test-eq "call-with-current-continuation: body compiled before the redefinition honours it (non-tail)"
  'user-ccc (nt-ccc))
(test-eq "call-with-current-continuation: body compiled before the redefinition honours it (tail)"
  'user-ccc (t-ccc))
(define call-with-current-continuation saved-2457-orig-ccc)
(test-eq "call-with-current-continuation: genuine binding restored" 1 (nt-ccc))

;;; ------------------------------------------------------------------
;;; A set! in a later top-level form is the same hazard as a define in a
;;; later form (R7RS 5.3.1 again), and the unit scan covers it the same way.
;;; ------------------------------------------------------------------

(define (nt-apply-set) (let ((v (apply + (list 1 2)))) v))
(set! apply (lambda (f xs) 'set-user))
(test-eq "apply: body compiled before a later set! honours it"
  'set-user (nt-apply-set))
(define apply saved-2457-orig-apply)
(test-eq "apply: genuine binding restored after the set! test" 3 (nt-apply-set))

;;; ------------------------------------------------------------------
;;; A redefinition nested in a top-level begin splices as top-level forms
;;; (R7RS 5.1), so the scan sees it and the whole unit declines.
;;; ------------------------------------------------------------------

(define (nt-apply-begin) (let ((v (apply + (list 1 2)))) v))
(begin
  (define (apply f xs) 'begin-user)
  'ignored)
(test-eq "apply: body compiled before a begin-spliced redefinition honours it"
  'begin-user (nt-apply-begin))
(define apply saved-2457-orig-apply)

;;; ------------------------------------------------------------------
;;; The contrast: car and map never had a fast path to bake in, and stay
;;; correct in the identical shape (their calls always resolved by name).
;;; ------------------------------------------------------------------

(define (nt-car) (let ((v (car (list 1 2)))) v))
(define (nt-map) (let ((v (map (lambda (x) x) (list 1 2)))) v))
(define (car xs) 'user-car)
(define (map f xs) 'user-map)
(test-eq "car: control — always honoured" 'user-car (nt-car))
(test-eq "map: control — always honoured" 'user-map (nt-map))

;;; ------------------------------------------------------------------
;;; #2033's original order (define BEFORE the caller) keeps working — the
;;; unit scan only ever declines more; the by-name route resolves the user's
;;; binding the same way the live-global read did.
;;; ------------------------------------------------------------------

(define (call-with-values p c) 'user-cwv-first)
(define (cwv-first) (call-with-values (lambda () 1) (lambda (x) x)))
(test-eq "call-with-values: define-first order still honoured"
  'user-cwv-first (cwv-first))
(define call-with-values saved-2457-orig-cwv)

;;; ------------------------------------------------------------------
;;; A redefinition to a non-procedure must not run the builtin either: the
;;; declined path is an ordinary by-name call and reports the type error.
;;; ------------------------------------------------------------------

(define (t-apply-nonproc) (apply + (list 1 2)))
(define apply 42)
(test-assert "apply: redefined to a non-procedure raises, not the builtin"
  (guard (e (#t (error-object? e))) (t-apply-nonproc)))
(define apply saved-2457-orig-apply)
(test-eq "apply: genuine binding restored after the non-procedure test"
  3 (t-apply-nonproc))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "top-level-redefinition-order-2457")
(if (> %test-fail-count 0) (exit 1))
