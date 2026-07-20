;; SRFI 248: Minimal Delimited Continuations
;; https://srfi.schemers.org/srfi-248/srfi-248.html
;;
;; with-unwind-handler extends the exception system with delimited
;; continuations: the handler installed over a thunk receives the raised object
;; *and* a delimited continuation representing the rest of the guarded thunk's
;; computation, up to and including the with-unwind-handler call.
;;
;; Implementation notes
;; --------------------
;; The delimiter is a Filinski-style shift/reset built on Kaappi's stack-copying
;; call/cc (see reset*/unwind-shift* below).  A pure-Scheme encoding is not enough on
;; its own: Kaappi's raise-continuable pops the current handler in the VM before
;; invoking it, so a continuation captured while the handler runs would not
;; include the handler and could not re-arm the prompt on resume.  The VM
;; primitive %call-with-unwind-handler installs a *sticky* handler that
;; raise/raise-continuable invoke without popping, so the shift-captured slice
;; snapshots it and resuming re-establishes the prompt (reset0 semantics) — this
;; is what makes the coroutine-generator idiom work across many yields.
;;
;; Limitations:
;;   * A delimited continuation is effectively single-shot: resuming the *same*
;;     k more than once crosses the sticky-handler native frame, which Kaappi's
;;     stack-copying continuations cannot re-enter after it returns (the same
;;     restriction as continuations captured under native drivers — see the
;;     "Continuations" note in README.md).  Every SRFI 248 idiom — coroutine
;;     generators, for-each->fold, effect handlers — invokes each captured k at
;;     most once, so this does not affect them.
;;   * The handler runs at the raise point (before the guarded thunk's
;;     dynamic-wind after-thunks), not after unwinding to with-unwind-handler as
;;     the SRFI's "dynamic environment of the call" wording implies.  The
;;     captured delimited continuation and the after-thunks are still correct;
;;     only the relative order of a handler side effect and an after-thunk
;;     differs, and only when the guarded thunk raises from inside a
;;     dynamic-wind.
;;   * Like every delimited-control system layered on undelimited call/cc, this
;;     shares a single metacontinuation cell (*meta-k* below), one per VM — i.e.
;;     per OS thread, since each thread gets its own VM.  It is NOT fiber-local:
;;     within a thread, fibers share the VM and hence this cell, so a
;;     with-unwind-handler / guard body must not span a fiber suspension point
;;     (e.g. a blocking channel op or parked I/O) — if another fiber runs
;;     delimited control while this one is parked mid-shift, the shared cell is
;;     clobbered.  Likewise, mixing these operators with user call/cc captures
;;     that cross a with-unwind-handler boundary is unsupported.  The intended
;;     use is exception-style generators and effect handlers within a fiber.
(define-library (srfi 248)
  (import (except (scheme base) guard)
          (srfi 248 primitives))
  (export with-unwind-handler
          empty-continuation?
          guard
          ;; Re-exported unchanged from R7RS-small (SRFI 248 §"Specification").
          with-exception-handler
          raise
          raise-continuable)
  (begin

    ;; ---- Filinski shift/reset over call/cc + a metacontinuation cell ----

    (define *meta-k*
      (lambda (v) (error "srfi 248: no enclosing delimiter")))

    (define (*abort* thunk)
      (let ((v (thunk)))
        (*meta-k* v)))

    (define (reset* thunk)
      (call-with-current-continuation
       (lambda (k)
         (let ((mc *meta-k*))
           (set! *meta-k*
                 (lambda (v)
                   (set! *meta-k* mc)
                   (k v)))
           (*abort* thunk)))))

    ;; The shift for this library.  Once the delimited continuation has been
    ;; captured (the call/cc snapshot carries the sticky handler, so a resume
    ;; re-arms the prompt), drop the sticky handler from the *live* stack before
    ;; running the user handler body, so a re-raise there escapes to the outer
    ;; handler instead of re-entering this one.
    (define (unwind-shift* f)
      (call-with-current-continuation
       (lambda (k)
         (%pop-unwind-handler!)
         (*abort*
          (lambda ()
            (f (lambda vals
                 (reset* (lambda () (apply k vals))))))))))

    ;; ---- delimited continuation objects (carry the empty? predicate) ----

    ;; A private, unforgeable token: applying a delimited continuation to it
    ;; queries emptiness instead of resuming.  Users cannot obtain this object,
    ;; so it never collides with a real resume value.
    (define %empty-query (list 'srfi-248-empty-query))

    (define (%make-delim-k proc empty?)
      (lambda vals
        (if (and (pair? vals) (eq? (car vals) %empty-query))
            empty?
            (apply proc vals))))

    (define (empty-continuation? k)
      (k %empty-query))

    ;; ---- with-unwind-handler ----

    (define (with-unwind-handler handler thunk)
      (if (not (procedure? handler))
          (error "with-unwind-handler: handler is not a procedure" handler))
      (if (not (procedure? thunk))
          (error "with-unwind-handler: thunk is not a procedure" thunk))
      (reset*
       (lambda ()
         (%call-with-unwind-handler
          (lambda (obj)
            ;; Read emptiness before shifting: %unwind-raise-empty? reflects the
            ;; raise that just reached this handler.
            (let ((empty? (%unwind-raise-empty?)))
              (unwind-shift*
               (lambda (k)
                 (handler obj (%make-delim-k k empty?))))))
          thunk))))

    ;; ---- guard ----
    ;;
    ;; SRFI 248 extends R7RS-small guard with an optional continuation variable:
    ;;   (guard (var clause ...) body)              -- R7RS-small
    ;;   (guard (var k-var clause ...) body)         -- SRFI 248
    ;; Both forms expand to with-unwind-handler; the two-variable form also binds
    ;; the captured delimited continuation to k-var.  On no match the object is
    ;; re-raised with raise-continuable and the delimited continuation is applied
    ;; to the results (SRFI 248 guard semantics).
    ;;
    ;; Caveat: because guard runs on with-unwind-handler (whose handler runs at
    ;; the raise point, not after unwinding — see the header), clauses run before
    ;; a dynamic-wind after-thunk of the guarded body, whereas R7RS-small runs
    ;; them after.  This differs only when the guarded body raises from inside a
    ;; dynamic-wind and a clause observes the after-thunk's effect.

    ;; Distinguish an identifier (the optional continuation variable) from a
    ;; parenthesised cond clause.
    (define-syntax %id?
      (syntax-rules ()
        ((%id? (a . b) then els) els)
        ((%id? atom then els) then)))

    ;; cond clauses; the no-match fall-through re-raises with raise-continuable
    ;; and applies the delimited continuation k to the results.
    (define-syntax %guard-cond
      (syntax-rules (else =>)
        ((%guard-cond var k ())
         (call-with-values (lambda () (raise-continuable var)) k))
        ((%guard-cond var k ((else e1 e2 ...)))
         (begin e1 e2 ...))
        ((%guard-cond var k ((test => proc) rest ...))
         (let ((t test)) (if t (proc t) (%guard-cond var k (rest ...)))))
        ((%guard-cond var k ((test) rest ...))
         (let ((t test)) (if t t (%guard-cond var k (rest ...)))))
        ((%guard-cond var k ((test e1 e2 ...) rest ...))
         (if test (begin e1 e2 ...) (%guard-cond var k (rest ...))))))

    (define-syntax %guard-uw
      (syntax-rules ()
        ((%guard-uw var k (clause ...) (body ...))
         (with-unwind-handler
          (lambda (var k) (%guard-cond var k (clause ...)))
          (lambda () body ...)))))

    (define-syntax %guard-dispatch
      (syntax-rules ()
        ((%guard-dispatch var () bodies)
         (%guard-uw var ignored-k () bodies))
        ((%guard-dispatch var (x . more) bodies)
         (%id? x
               (%guard-uw var x more bodies)
               (%guard-uw var ignored-k (x . more) bodies)))))

    (define-syntax guard
      (syntax-rules ()
        ((guard (var . spec) body1 body2 ...)
         (%guard-dispatch var spec (body1 body2 ...)))))))
