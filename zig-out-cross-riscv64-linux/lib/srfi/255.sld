;;; SRFI 255 — Restarting Conditions
;;;
;;; SRFI 255 is specified in terms of R6RS's condition-type system
;;; (define-condition-type, compound conditions, &assertion). R7RS/Kaappi
;;; has no such hierarchy — conditions raised by (error ...) or (raise ...)
;;; are plain values. This port adapts accordingly:
;;;
;;;  - &restarter is a plain record type (make-restarter etc. match the
;;;    spec exactly).
;;;  - Where the spec requires a raised restarter to be "a composite
;;;    condition... including the object raised by the triggering
;;;    exception", this implementation raises a <restartable-condition>
;;;    record instead of a true compound condition. Its accessors
;;;    (restartable-condition?, restartable-condition-restarters,
;;;    restartable-condition-original) are exported beyond the SRFI's own
;;;    surface, since an interactor needs some way to get at both.
;;;  - restartable/define-restartable offer their use-arguments restarter
;;;    for ANY exception raised during the call, not specifically R6RS
;;;    &assertion violations (Kaappi has no such distinction). The
;;;    restarter's formals field is always the symbol 'args (a rest list)
;;;    rather than mirroring the wrapped procedure's real parameter list,
;;;    since the restart invoker itself accepts any number of new
;;;    arguments — this only affects introspection, not behavior.
;;;  - No default interactive UI is provided (the spec leaves presentation
;;;    unspecified); the default current-interactor raises a clear error
;;;    listing the available restart tags, so a program must install its
;;;    own via (parameterize ((current-interactor ...)) ...) to actually
;;;    use with-current-interactor.

(define-library (srfi 255)
  (import (scheme base))
  (export
    make-restarter restarter? restarter-tag restarter-description
    restarter-who restarter-formals restarter-invoker
    restart
    current-interactor with-current-interactor
    restartable-condition? restartable-condition-restarters
    restartable-condition-original
    restarter-guard restartable define-restartable)
  (begin

    (define-record-type <restarter>
      (make-restarter tag description who formals invoker)
      restarter?
      (tag restarter-tag)
      (description restarter-description)
      (who restarter-who)
      (formals restarter-formals)
      (invoker restarter-invoker))

    (define (restart restarter . args)
      (apply (restarter-invoker restarter) args))

    (define-record-type <restartable-condition>
      (make-restartable-condition original restarters)
      restartable-condition?
      (original restartable-condition-original)
      (restarters restartable-condition-restarters))

    (define (%default-interactor con)
      (error "no current-interactor installed to handle a restartable condition"
             (map restarter-tag (restartable-condition-restarters con))))

    (define current-interactor (make-parameter %default-interactor))

    (define (with-current-interactor thunk)
      (with-exception-handler
        (lambda (con)
          (if (restartable-condition? con)
              (begin
                ((current-interactor) con)
                (error "with-current-interactor: interactor returned without restarting" con))
              (raise-continuable con)))
        thunk))

    ;; --- restarter-guard ------------------------------------------------

    ;; Builds the list of restarters for those clauses whose predicate is
    ;; true. Each restart's invoker escapes to k with the value of its body
    ;; (optionally with the triggering condition bound to condvar).
    (define-syntax %restart-invoker
      (syntax-rules ()
        ((_ k #f con formals (cbody ...))
         (lambda formals (k (begin cbody ...))))
        ((_ k condvar con formals (cbody ...))
         (lambda formals (k (let ((condvar con)) cbody ...))))))

    (define-syntax %build-restarters
      (syntax-rules ()
        ((_ k who con condvar ())
         '())
        ((_ k who con condvar (((tag . formals) desc pred cbody ...) more ...))
         (let ((rest (%build-restarters k who con condvar (more ...))))
           (if pred
               (cons (make-restarter 'tag desc who 'formals
                                      (%restart-invoker k condvar con formals (cbody ...)))
                     rest)
               rest)))))

    (define-syntax %restarter-guard-impl
      (syntax-rules ()
        ((_ who condvar (clause ...) body ...)
         (call-with-current-continuation
           (lambda (%%k)
             (with-exception-handler
               (lambda (%%con)
                 (raise-continuable
                   (make-restartable-condition
                     %%con
                     (%build-restarters %%k who %%con condvar (clause ...)))))
               (lambda () body ...)))))))

    ;; Dispatches on whether a condition-var was given: if the group's
    ;; first element is itself clause-shaped (a list headed by a list,
    ;; i.e. (tag . formals)), there's no condvar; otherwise the first
    ;; element must be the condvar identifier.
    (define-syntax restarter-guard
      (syntax-rules ()
        ((_ who (((tag . formals) desc pred cbody ...) more ...) body ...)
         (%restarter-guard-impl 'who #f (((tag . formals) desc pred cbody ...) more ...) body ...))
        ((_ who (condvar clause ...) body ...)
         (%restarter-guard-impl 'who condvar (clause ...) body ...))))

    ;; --- restartable / define-restartable --------------------------------

    (define (%make-restartable who proc)
      (lambda args
        (call-with-current-continuation
          (lambda (k)
            (with-exception-handler
              (lambda (con)
                (raise-continuable
                  (make-restartable-condition
                    con
                    (list (make-restarter 'use-arguments
                                           "Retry with new arguments."
                                           who 'args
                                           (lambda new-args (k (apply proc new-args))))))))
              (lambda () (apply proc args)))))))

    (define-syntax restartable
      (syntax-rules ()
        ((_ who expr) (%make-restartable 'who expr))))

    (define-syntax define-restartable
      (syntax-rules ()
        ((_ (name . formals) body ...)
         (define name (restartable name (lambda formals body ...))))
        ((_ name expr)
         (define name (restartable name expr)))))))
