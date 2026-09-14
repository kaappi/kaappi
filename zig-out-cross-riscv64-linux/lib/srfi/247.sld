;;; SRFI 247 — Syntactic Monads
;;;
;;; `define-syntactic-monad name formal ...` defines a keyword `name`
;;; that implicitly threads a fixed set of "state variables" (the
;;; formals) through procedure definitions and calls at compile time,
;;; avoiding the runtime cost of dynamic parameters. `name` then accepts
;;; exactly six use-site shapes: lambda, define, case-lambda,
;;; let*-values, a procedure call (with optional per-state-variable
;;; bindings), and a named-let loop. The spec's own sample implementation
;;; is R6RS syntax-case only (its source isn't inlined in the document);
;;; this is an independent syntax-rules implementation.
;;;
;;; The core mechanism needed for the call and let-loop forms — given a
;;; specific, statically-known state-variable name, either find a
;;; matching binding among the ones a use site supplied or default to a
;;; bare reference to that same name — is built from a small technique:
;;; a macro can generate a nested `letrec-syntax`-bound transformer whose
;;; *literals list* contains one of its own outer pattern variables
;;; (holding a specific identifier captured earlier in the expansion).
;;; That inner transformer's literal-identifier matching does the actual
;;; "is this the state variable named exactly `a`?" comparison — the
;;; same hygienic hook `cond`'s `else`/`=>` rely on, just constructed
;;; per-expansion instead of fixed at one macro's own definition.
;;;
;;; `define-syntactic-monad` itself can't use that same trick for its own
;;; six-way dispatch on lambda/define/case-lambda/let*-values/let: a
;;; nested syntax-rules definition (one define-syntax's template
;;; containing another define-syntax) whose *own* literals list includes
;;; `let` specifically fails to recognize `let` at the use site, even
;;; though the identical shape works correctly for every other literal
;;; tried (lambda, define, case-lambda, let*-values) — empirically
;;; confirmed with a minimal repro isolating exactly this. Routing the
;;; dispatch through a second, separately (non-nested) defined macro
;;; sidesteps it: `name`'s own generated body immediately delegates
;;; everything to %sm-dispatch, and %sm-dispatch's own `let` literal,
;;; since it's declared directly rather than inside another macro's
;;; template, matches correctly.
;;;
;;; A separate, unrelated limitation: `(name define (f . args) body)`
;;; only works as a *top-level* definition. Used internally (inside a
;;; lambda/procedure body, alongside other expressions), it silently
;;; fails to introduce `f` at all, because Kaappi's internal-body scanner
;;; recognizes a definition only by a literal leading define/
;;; define-record-type/define-syntax token — since the actual head token
;;; here is the monad's own name, not `define`, the scanner never expands
;;; it far enough to see that it produces one. (name let loop ...) has no
;;; such restriction, since a named-let is an ordinary expression, not a
;;; definition — prefer it for recursion inside a body.

(define-library (srfi 247)
  (export define-syntactic-monad)
  (import (scheme base))
  (begin

    (define-syntax define-syntactic-monad
      (syntax-rules ()
        ((_ name formal ...)
         (define-syntax name
           (syntax-rules ()
             ((_ . rest) (%sm-dispatch (formal ...) . rest)))))))

    (define-syntax %sm-dispatch
      (syntax-rules (lambda define case-lambda let*-values let)
        ((_ (formal ...) lambda fmls body ...)
         (%sm-lambda (formal ...) fmls body ...))
        ((_ (formal ...) define (dname . dfmls) body ...)
         (define dname (%sm-dispatch (formal ...) lambda dfmls body ...)))
        ((_ (formal ...) case-lambda (clfmls clbody ...) ...)
         (%sm-case-lambda (formal ...) (clfmls clbody ...) ...))
        ((_ (formal ...) let*-values (lvclause ...) body ...)
         (%sm-let*-values (formal ...) (lvclause ...) body ...))
        ((_ (formal ...) let loop-name (clause ...) body ...)
         (%sm-let-loop (formal ...) loop-name (clause ...) body ...))
        ((_ (formal ...) proc (binding ...) arg ...)
         (%sm-call (formal ...) proc (binding ...) (arg ...)))
        ((_ (formal ...) proc)
         (%sm-dispatch (formal ...) proc ()))))

    ;; --- 1. lambda ---------------------------------------------------------
    ;; A state variable that's also one of fmls's own names is dropped
    ;; from the threaded prefix (the spec's own examples rely on this:
    ;; the local parameter shadows the state variable of the same name,
    ;; which a naive (formal ... . fmls) prefix would instead turn into
    ;; an invalid lambda with a duplicate parameter name).

    (define-syntax %sm-lambda
      (syntax-rules ()
        ((_ (formal ...) fmls body ...)
         (%sm-filter (formal ...) fmls %sm-lambda-emit fmls body ...))))

    (define-syntax %sm-lambda-emit
      (syntax-rules ()
        ((_ (kept ...) fmls body ...) (lambda (kept ... . fmls) body ...))))

    ;; --- 3. case-lambda ------------------------------------------------------
    ;; Each clause is filtered independently, since different clauses may
    ;; shadow different state variables. case-lambda doesn't macro-expand
    ;; its own clause positions before parsing them, so every clause must
    ;; be fully built by the time this reaches case-lambda itself, hence
    ;; the explicit accumulate-then-emit loop.

    (define-syntax %sm-case-lambda
      (syntax-rules ()
        ((_ formals (clfmls clbody ...) ...)
         (%sm-cl-loop formals ((clfmls clbody ...) ...) ()))))

    (define-syntax %sm-cl-loop
      (syntax-rules ()
        ((_ formals () (done ...)) (case-lambda done ...))
        ((_ formals ((clfmls clbody ...) . more) (done ...))
         (%sm-filter formals clfmls %sm-cl-continue formals clfmls (clbody ...) more (done ...)))))

    (define-syntax %sm-cl-continue
      (syntax-rules ()
        ((_ (kept ...) formals clfmls (clbody ...) more (done ...))
         (%sm-cl-loop formals more (done ... ((kept ... . clfmls) clbody ...))))))

    ;; --- 4. let*-values --------------------------------------------------------
    ;; Same per-clause filtering as case-lambda.

    (define-syntax %sm-let*-values
      (syntax-rules ()
        ((_ formals (clause ...) body ...)
         (%sm-lv-loop formals (clause ...) () body ...))))

    (define-syntax %sm-lv-loop
      (syntax-rules ()
        ((_ formals () (done ...) body ...) (let*-values (done ...) body ...))
        ((_ formals ((lvfmls init) . more) (done ...) body ...)
         (%sm-filter formals lvfmls %sm-lv-continue formals lvfmls init more (done ...) body ...))))

    (define-syntax %sm-lv-continue
      (syntax-rules ()
        ((_ (kept ...) formals lvfmls init more (done ...) body ...)
         (%sm-lv-loop formals more (done ... ((kept ... . lvfmls) init)) body ...))))

    ;; --- shared: filter state variables shadowed by a formals shape -------------
    ;; %sm-occurs?: does `target` appear anywhere in `fmls` (a lambda-style
    ;; formals: proper list, dotted list, or bare identifier)? then/else
    ;; are syntax fragments, not values.
    (define-syntax %sm-occurs?
      (syntax-rules ()
        ((_ target () then else) else)
        ((_ target (v . more) then else)
         (letrec-syntax
             ((%t (syntax-rules (target)
                    ((_ target) then)
                    ((_ other) (%sm-occurs? target more then else)))))
           (%t v)))
        ((_ target v then else)
         (letrec-syntax
             ((%t (syntax-rules (target)
                    ((_ target) then)
                    ((_ other) else))))
           (%t v)))))

    ;; %sm-filter: removes every formal that occurs in `fmls` from
    ;; `(formal ...)`, then expands to (k (kept ...) . rest).
    (define-syntax %sm-filter
      (syntax-rules ()
        ((_ (formal ...) fmls k . rest)
         (%sm-filter-loop (formal ...) fmls () k . rest))))

    (define-syntax %sm-filter-loop
      (syntax-rules ()
        ((_ () fmls (kept ...) k . rest) (k (kept ...) . rest))
        ((_ (formal . more) fmls (kept ...) k . rest)
         (%sm-occurs? formal fmls
           (%sm-filter-loop more fmls (kept ...) k . rest)
           (%sm-filter-loop more fmls (kept ... formal) k . rest)))))

    ;; --- 5. procedure call, with optional per-state-variable bindings ----------
    ;; Resolves one formal at a time (rather than a single (%sm-lookup
    ;; formal bindings) ... template) since re-collecting one ellipsis
    ;; variable wholesale from inside a different, sibling ellipsis's own
    ;; per-iteration template doesn't expand correctly here.

    (define-syntax %sm-call
      (syntax-rules ()
        ((_ (formal ...) proc bindings (arg ...))
         (%sm-call-loop (formal ...) bindings proc () (arg ...)))))

    (define-syntax %sm-call-loop
      (syntax-rules ()
        ((_ () bindings proc (resolved ...) (arg ...)) (proc resolved ... arg ...))
        ((_ (formal . more) bindings proc (resolved ...) (arg ...))
         (%sm-call-loop more bindings proc (resolved ... (%sm-lookup formal bindings)) (arg ...)))))

    ;; --- 6. let loop -------------------------------------------------------------

    (define-syntax %sm-let-loop
      (syntax-rules ()
        ((_ (formal ...) loop-name clauses body ...)
         (%sm-let-loop-slots (formal ...) (formal ...) () loop-name clauses body ...))))

    (define-syntax %sm-let-loop-slots
      (syntax-rules ()
        ((_ () orig-formals (slot ...) loop-name clauses body ...)
         (%sm-let-loop-others orig-formals clauses (slot ...) loop-name body ...))
        ((_ (formal . more) orig-formals (slot ...) loop-name clauses body ...)
         (%sm-let-loop-slots more orig-formals (slot ... (formal (%sm-lookup formal clauses))) loop-name clauses body ...))))

    (define-syntax %sm-let-loop-others
      (syntax-rules ()
        ((_ orig-formals () (slot ...) loop-name body ...)
         (let loop-name (slot ...) body ...))
        ((_ orig-formals ((name init) . more) (slot ...) loop-name body ...)
         (%sm-if-member name orig-formals
           (%sm-let-loop-others orig-formals more (slot ...) loop-name body ...)
           (%sm-let-loop-others orig-formals more (slot ... (name init)) loop-name body ...)))))

    ;; --- shared identifier-comparison primitives --------------------------------

    ;; Search `clauses` (a list of (name init) pairs) for one whose name is
    ;; exactly `target`; expand to that init, or to `target` itself (a bare
    ;; reference, i.e. this state variable falls back to whatever's
    ;; lexically in scope by that name) if none matches.
    (define-syntax %sm-lookup
      (syntax-rules ()
        ((_ target clauses)
         (letrec-syntax
             ((%search
                (syntax-rules (target)
                  ((_ ()) target)
                  ((_ ((target init) . rest)) init)
                  ((_ ((other-name other-init) . rest)) (%search rest)))))
           (%search clauses)))))

    ;; Syntactic if: expand to `then` if `name` is exactly one of `names`,
    ;; else to `else` -- both are syntax fragments, not values, so this
    ;; controls what gets generated, not a runtime branch.
    (define-syntax %sm-if-member
      (syntax-rules ()
        ((_ name () then else) else)
        ((_ name (one . more) then else)
         (letrec-syntax
             ((%test
                (syntax-rules (one)
                  ((_ one) then)
                  ((_ other) (%sm-if-member other more then else)))))
           (%test name)))))))
