;;; Regression tests for #2033: a top-level redefinition of call/cc, apply,
;;; eval or call-with-values (plus call-with-current-continuation) was
;;; ignored in tail position.
;;;
;;; R7RS 5.3.1, "Top level definitions": "At the top level of a program, a
;;; definition ... has essentially the same effect as the assignment
;;; expression ... if ⟨variable⟩ is bound to a non-syntax value."
;;;
;;; compiler.zig's tail-position dispatch sent these five names to
;;; hand-written superinstructions guarded only by resolveLocal /
;;; resolveUpvalue — a *global* rebinding of the name was not consulted, so a
;;; program that redefined one of them got its own definition everywhere
;;; except in tail position, where the builtin ran instead and the user's
;;; procedure was silently discarded. The fix gates each fast path on the
;;; compile-time global binding (mirroring IR.isRedefined), so the same
;;; resolution rules apply in both positions.
;;;
;;; Also covered here: the compiler-synthesized references the
;;; let-values/let*-values/define-values/case-lambda/define-record-type
;;; desugarings mint for apply / call-with-values / list stay bound to the
;;; pristine (scheme base) procedures under a redefinition (#1715), and a
;;; hygiene-renamed macro-template reference agrees between tail and
;;; non-tail position.
;;;
;;; The originals are saved first because the file intentionally rebinds each
;;; name several times; every section restores from these saved values so the
;;; framework's own machinery (and the later sections) keep the genuine
;;; bindings.

(import (scheme base) (scheme write) (scheme eval) (scheme process-context) (srfi 64))

(test-begin "top-level-redefinition-2033")

(define saved-2033-orig-apply apply)
(define saved-2033-orig-eval eval)
(define saved-2033-orig-call/cc call/cc)
(define saved-2033-orig-cwv call-with-values)
(define saved-2033-orig-ccc call-with-current-continuation)

;;; ------------------------------------------------------------------
;;; The five names, redefined BEFORE the caller is defined: tail position
;;; must resolve the user's binding, exactly like the non-tail position
;;; that was always correct.
;;; ------------------------------------------------------------------

(define (user-apply f . rest) 'user-apply)
(define (apply f . rest) 'user-apply)
(define (apply-tail) (apply + (list 1 2)))
(define (apply-nontail) (list (apply + (list 1 2))))
(test-equal "apply: top-level redefinition wins in tail position"
            'user-apply (apply-tail))
(test-equal "apply: top-level redefinition wins in non-tail position (control)"
            '(user-apply) (apply-nontail))
(define apply saved-2033-orig-apply)

(define (user-eval x . env) 'user-eval)
(define (eval x . env) 'user-eval)
(define (eval-tail) (eval '(+ 1 2) (interaction-environment)))
(define (eval-nontail) (list (eval '(+ 1 2) (interaction-environment))))
(test-equal "eval: top-level redefinition wins in tail position"
            'user-eval (eval-tail))
(test-equal "eval: top-level redefinition wins in non-tail position (control)"
            '(user-eval) (eval-nontail))
(define eval saved-2033-orig-eval)

(define (user-call/cc f) 'user-call/cc)
(define (call/cc f) 'user-call/cc)
(define (call/cc-tail) (call/cc (lambda (k) 1)))
(define (call/cc-nontail) (list (call/cc (lambda (k) 1))))
(test-equal "call/cc: top-level redefinition wins in tail position"
            'user-call/cc (call/cc-tail))
(test-equal "call/cc: top-level redefinition wins in non-tail position (control)"
            '(user-call/cc) (call/cc-nontail))
(define call/cc saved-2033-orig-call/cc)

(define (user-cwv p c) 'user-cwv)
(define (call-with-values p c) 'user-cwv)
(define (cwv-tail) (call-with-values (lambda () 1) list))
(define (cwv-nontail) (list (call-with-values (lambda () 1) list)))
(test-equal "call-with-values: top-level redefinition wins in tail position"
            'user-cwv (cwv-tail))
(test-equal "call-with-values: top-level redefinition wins in non-tail position (control)"
            '(user-cwv) (cwv-nontail))
(define call-with-values saved-2033-orig-cwv)

(define (user-ccc f) 'user-ccc)
(define (call-with-current-continuation f) 'user-ccc)
(define (ccc-tail) (call-with-current-continuation (lambda (k) 1)))
(define (ccc-nontail) (list (call-with-current-continuation (lambda (k) 1))))
(test-equal "call-with-current-continuation: top-level redefinition wins in tail position"
            'user-ccc (ccc-tail))
(test-equal "call-with-current-continuation: redefinition wins in non-tail position (control)"
            '(user-ccc) (ccc-nontail))
(define call-with-current-continuation saved-2033-orig-ccc)

;;; ------------------------------------------------------------------
;;; A redefinition to a non-procedure value: the builtin must not run —
;;; the ordinary call path reports the type error.
;;; ------------------------------------------------------------------

(define call/cc 42)
(test-assert "call/cc: redefined to a non-procedure raises in tail position"
             (guard (e (#t (error-object? e))) ((lambda () (call/cc (lambda (k) 1))))))
(define call/cc saved-2033-orig-call/cc)
(test-equal "call/cc: genuine binding restored, tail position works again"
            42 ((lambda () (call/cc (lambda (k) 42)))))

;;; ------------------------------------------------------------------
;;; A hygiene-renamed free reference from a macro template agrees between
;;; tail and non-tail position under a top-level redefinition.
;;; ------------------------------------------------------------------

(define (call-with-current-continuation f) 'template-user)
(define-syntax tpl-2033-ref
  (syntax-rules () ((_ x) (call-with-current-continuation x))))
(define (tpl-tail x) (tpl-2033-ref x))
(define (tpl-nontail x) (list (tpl-2033-ref x)))
(test-equal "macro template free reference: tail position honours the redefinition"
            'template-user (tpl-tail 42))
(test-equal "macro template free reference: non-tail position agrees"
            '(template-user) (tpl-nontail 42))
(define call-with-current-continuation saved-2033-orig-ccc)

;;; ------------------------------------------------------------------
;;; A set! target inside the same top-level form suppresses the fast path
;;; (the compile-time global binding is still pristine, so only the set!
;;; pre-scan can see the hazard).
;;; ------------------------------------------------------------------

(test-equal "call/cc: a set! target in the enclosing form suppresses the fast path"
            'set-user (let ((f (lambda () (set! call/cc (lambda (x) 'set-user)) (call/cc 1))))
                        (f)))
(define call/cc saved-2033-orig-call/cc)
(test-equal "call/cc: restored after the set! test"
            42 ((lambda () (call/cc (lambda (k) 42)))))

;;; ------------------------------------------------------------------
;;; The compiler-synthesized references in derived-form desugarings stay
;;; bound to the pristine (scheme base) procedures even while the names are
;;; redefined at top level (#1715): let-values / let*-values / define-values
;;; / case-lambda / define-record-type must not pick up the user's
;;; redefinitions.
;;; ------------------------------------------------------------------

(define (apply f . r) 'user-apply)
(define (call-with-values p c) 'user-cwv)

(test-equal "let-values desugaring keeps pristine apply/call-with-values"
            7 (let-values (((a b) (values 3 4))) (+ a b)))
(test-equal "let*-values desugaring keeps pristine apply/call-with-values"
            30 (let*-values (((a) (values 10)) ((b) (values 20))) (+ a b)))
(test-equal "define-values (single) desugaring keeps pristine call-with-values"
            5 (let ((x 'unset)) (define-values (x) (values 5)) x))
(test-equal "define-values (multi) desugaring keeps pristine call-with-values"
            '(6 7) (let ((a 'unset) (b 'unset))
                     (define-values (a b) (values 6 7))
                     (list a b)))
(test-equal "case-lambda desugaring keeps pristine apply"
            3 ((case-lambda ((a b) (+ a b)) (a a)) 1 2))
(test-equal "case-lambda desugaring keeps pristine apply (rest-arg arm)"
            '(5) ((case-lambda ((a b) (+ a b)) (a a)) 5))
(test-equal "define-record-type desugaring keeps pristine apply"
            3 (let ()
                (define-record-type <t2033-pt> (make-t2033-pt x y) t2033-pt?
                  (x t2033-pt-x) (y t2033-pt-y))
                (define-record-type <t2033-pt3> (make-t2033-pt3 x y z) t2033-pt3?
                  (x t2033-pt3-x) (y t2033-pt3-y) (z t2033-pt3-z)
                  (parent <t2033-pt>))
                (t2033-pt3-z (make-t2033-pt3 1 2 3))))

;; The define-values single case also synthesizes a `list` consumer; that
;; immunity needs a `list` redefinition, which would corrupt SRFI-64's own
;; runner state (the runner calls the global `list`), so it is asserted
;; without the framework instead.
(define saved-2033-list list)
(define (list . r) 'user-list)
(if (equal? (let ((x 'unset)) (define-values (x) (values 5)) x) 5)
    (write 'list-consumer-immunity-ok)
    (begin (write 'list-consumer-immunity-FAIL) (exit 1)))
(newline)
(define list saved-2033-list)

(define apply saved-2033-orig-apply)
(define call-with-values saved-2033-orig-cwv)
(test-equal "genuine apply restored"
            3 (apply + (list 1 2)))
(test-equal "genuine call-with-values restored"
            '(1 2) (call-with-values (lambda () (values 1 2)) list))

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "top-level-redefinition-2033")
(if (> %test-fail-count 0) (exit 1))
