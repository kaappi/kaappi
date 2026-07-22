;;; SRFI 165 — The Environment Monad
;;;
;;; Models computations that read from, extend, and locally override a
;;; shared environment (the Reader monad). No reference implementation
;;; is inlined in the spec (only a link to an external, dependency-heavy
;;; sample); this is an independent implementation of the specified
;;; semantics.
;;;
;;; Environments are a plain association list wrapped in a record (keyed
;;; by the environment-variable object itself, via eq?): looking up an
;;; unbound variable falls back to its own default, and a "copy" is a
;;; new record sharing the same list structure (correct and O(1), since
;;; updates only ever prepend a new pair rather than mutating existing
;;; ones — computation-forked's per-branch copies never see each other's
;;; extensions). A computation wraps a plain (environment -> results)
;;; procedure directly, rather than only the make-computation-style
;;; (compute-procedure -> results) surface API, since ask/local/fn/with
;;; all need direct environment access that the compute-only interface
;;; can't provide.
;;;
;;; Not implemented: define-computation-type (an O(1)-access variant of
;;; environment variables for a statically-known set — a pure
;;; optimization over what's here, not new observable behavior).

(define-library (srfi 165)
  (export make-computation-environment-variable
          make-computation-environment
          computation-environment?
          computation-environment-ref
          computation-environment-update
          computation-environment-update!
          computation-environment-copy
          computation?
          make-computation
          computation-run
          computation-ask
          computation-local
          computation-pure
          computation-each
          computation-each-in-list
          computation-bind
          computation-sequence
          computation-forked
          computation-bind/forked
          computation-fn
          computation-with
          computation-with!
          default-computation)
  (import (scheme base))
  (begin

    ;; --- environment variables and environments --------------------------

    (define-record-type <computation-environment-variable>
      (make-computation-environment-variable name default immutable?)
      %env-var?
      (name %env-var-name)
      (default %env-var-default)
      (immutable? %env-var-immutable?))

    (define-record-type <computation-environment>
      (%make-env alist)
      computation-environment?
      (alist %env-alist %env-set-alist!))

    (define (make-computation-environment) (%make-env '()))

    (define (computation-environment-ref env var)
      (let ((entry (assq var (%env-alist env))))
        (if entry (cdr entry) (%env-var-default var))))

    (define (%alist-with-pairs alist args)
      (if (null? args)
          alist
          (%alist-with-pairs (cons (cons (car args) (cadr args)) alist) (cddr args))))

    (define (computation-environment-update env . args)
      (%make-env (%alist-with-pairs (%env-alist env) args)))

    (define (computation-environment-update! env var val)
      (%env-set-alist! env (cons (cons var val) (%env-alist env))))

    (define (computation-environment-copy env) (%make-env (%env-alist env)))

    ;; --- computations ------------------------------------------------------

    (define-record-type <computation>
      (%make-computation runner)
      computation?
      (runner %computation-runner))

    (define (%run comp env)
      (cond
        ((computation? comp) ((%computation-runner comp) env))
        ((procedure? comp) (comp (lambda (other) (%run other env))))
        (else (%run ((computation-environment-ref env default-computation) comp) env))))

    (define default-computation
      (make-computation-environment-variable
        'default-computation
        (lambda (obj) (error "default-computation: no handler installed for a non-computation, non-procedure value" obj))
        #f))

    (define (make-computation proc)
      (%make-computation (lambda (env) (proc (lambda (other) (%run other env))))))

    (define (computation-run comp) (%run comp (make-computation-environment)))

    (define (computation-ask) (%make-computation (lambda (env) env)))

    (define (computation-local updater comp)
      (%make-computation (lambda (env) (%run comp (updater env)))))

    ;; --- derived monadic procedures -----------------------------------------

    (define (computation-pure . objs)
      (%make-computation (lambda (env) (apply values objs))))

    (define (computation-each . comps)
      (%make-computation
        (lambda (env)
          (let loop ((cs comps))
            (if (null? (cdr cs))
                (%run (car cs) env)
                (begin (%run (car cs) env) (loop (cdr cs))))))))

    (define (computation-each-in-list lst) (apply computation-each lst))

    (define (computation-bind comp . procs)
      (let loop ((c comp) (ps procs))
        (if (null? ps)
            c
            (loop
              (%make-computation
                (lambda (env)
                  (call-with-values
                    (lambda () (%run c env))
                    (lambda vals (%run (apply (car ps) vals) env)))))
              (cdr ps)))))

    (define (computation-sequence lst)
      (%make-computation (lambda (env) (map (lambda (c) (%run c env)) lst))))

    (define (computation-forked . comps)
      (%make-computation
        (lambda (env)
          (let loop ((cs comps))
            (if (null? (cdr cs))
                (%run (car cs) env)
                (begin (%run (car cs) (computation-environment-copy env)) (loop (cdr cs))))))))

    (define (computation-bind/forked comp . procs)
      (apply computation-bind
        (%make-computation (lambda (env) (%run comp (computation-environment-copy env))))
        procs))

    ;; --- derived syntax ------------------------------------------------------

    (define-syntax computation-fn
      (syntax-rules ()
        ((_ (clause ...) body1 body2 ...)
         (%make-computation (lambda (env) (%computation-fn-body env (clause ...) body1 body2 ...))))))

    (define-syntax %computation-fn-body
      (syntax-rules ()
        ((_ env () body1 body2 ...)
         (%run (begin body1 body2 ...) env))
        ((_ env ((var init) . more) body1 body2 ...)
         (let ((var (computation-environment-ref env init))) (%computation-fn-body env more body1 body2 ...)))
        ((_ env (var . more) body1 body2 ...)
         (let ((var (computation-environment-ref env var))) (%computation-fn-body env more body1 body2 ...)))))

    (define-syntax computation-with
      (syntax-rules ()
        ((_ (clause ...) expr1 expr2 ...)
         (%make-computation (lambda (env) (%computation-with-body env (clause ...) expr1 expr2 ...))))))

    (define-syntax %computation-with-body
      (syntax-rules ()
        ((_ env () expr1 expr2 ...)
         (%run (computation-each expr1 expr2 ...) env))
        ((_ env ((var init) . more) expr1 expr2 ...)
         (%computation-with-body (computation-environment-update env var init) more expr1 expr2 ...))))

    (define-syntax computation-with!
      (syntax-rules ()
        ((_ (var init) ...)
         (%make-computation (lambda (env) (computation-environment-update! env var init) ... (values))))))))
