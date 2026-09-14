;;; SRFI 201 — Syntactic extensions to the core Scheme bindings
;;;
;;; SRFI 201 extends `lambda`, `let`, `let*`, `define`, and `or` (it does
;;; *not* touch `set!`, despite that being a natural guess). Its reference
;;; implementation is `syntax-case` throughout (Kaappi has `syntax-rules`
;;; only) and depends on a full SRFI-200-conformant pattern matcher, which
;;; Kaappi does not implement (only SRFI 241's `match`, whose internals
;;; aren't exported). This port re-implements the matching machinery from
;;; scratch with `syntax-rules`, under the SRFI's own reference names
;;; (`mlambda`, `cdefine`, `named-match-let-values`, `match-let*-values`,
;;; `or/values`) rather than shadowing `lambda`/`define`/`let`/`let*`/`or`
;;; themselves — see "Why not shadow the core bindings?" below, which is a
;;; Kaappi-specific finding, not a portability limitation of the SRFI.
;;;
;;; Scope, relative to the full SRFI:
;;;  - Parameter/binding *patterns* support plain identifiers and
;;;    quasiquote patterns (`` `(,x . ,y) `` — the exact style SRFI 201's
;;;    own examples use): nested pairs, `()`, `#(...)` fixed-length
;;;    vectors, `,var` bindings, and literal self-evaluating/symbol data
;;;    matched with `equal?`. There is no `_` wildcard (unlike SRFI 241's
;;;    `match`) — SRFI 201 never shows one, and treating `_` specially
;;;    would silently change the meaning of any formal parameter or
;;;    binding genuinely named `_`.
;;;  - SRFI 201's `let`/`let*` also generalize to SRFI-71-style multiple
;;;    values per binding (a leading `values` marker binding several
;;;    patterns from one multiple-values-returning expression). That part
;;;    is not implemented — the SRFI's own text calls mixing it with other
;;;    bindings in the same `let` something that "should be discouraged,"
;;;    and it adds a second, unrelated axis of complexity on top of pattern
;;;    matching. `named-match-let-values`/`match-let*-values` here support
;;;    pattern-matching bindings (one value per binding) only.
;;;  - `or/values` is implemented in full (it needs no pattern matching).
;;;  - Matching failure in `mlambda`/`cdefine`'s (non-bodyless) body raises
;;;    an error; a *bodyless* `mlambda`/`cdefine` becomes a predicate
;;;    returning `#t`/`#f`, per the spec.
;;;
;;; Why not shadow the core bindings?
;;;
;;; The SRFI's rationale suggests importing these under the core names
;;; (`(rename (mlambda lambda) ...)`) so they transparently replace
;;; `lambda`/`define`/etc. Testing that against Kaappi surfaced a real
;;; engine bug: a `define-syntax` whose bound name is literally `lambda`
;;; (or, presumably, any of the other names the compiler treats as a
;;; built-in special form) and whose expansion does anything beyond
;;; reproducing its input unchanged either expands forever
;;; ("macro expansion limit exceeded") or — depending on the exact shape —
;;; corrupts the GC's root-tracking stack in a way that only surfaces much
;;; later, as an unrelated `integer overflow` panic inside
;;; `handleDefineRecordType` the next time *any* library loads a
;;; `define-record-type` (confirmed with SRFI 64, which uses one for its
;;; test-runner record). This reproduces with a self-contained macro with
;;; no dependency on this library's matcher — even a two-clause
;;; `(define-syntax lambda (syntax-rules () ((_ formals) ...) ((_ formals
;;; body ...) ...)))` at a library's top level triggers it once actually
;;; used, while the exact same transformer bound to any other name does
;;; not. Because this is a compiler-level bug, not a library-level fix,
;;; this port exports the SRFI's own internal names directly instead of
;;; shadowing scheme-base's bindings: `mlambda`, `cdefine`,
;;; `named-match-let-values`, `match-let*-values`, `or/values`. A caller
;;; who wants the shadowing behavior described in the SRFI can still
;;; write `(import (rename (srfi 201) (mlambda lambda) (cdefine define)
;;; ...))` — that rename itself is unaffected by the bug (it doesn't
;;; introduce a new transformer named `lambda`, just an alias binding to
;;; an existing one) — but every test in this suite uses the plain names
;;; to stay well clear of it.

(define-library (srfi 201)
  (import (scheme base) (srfi 201 core))
  (export mlambda cdefine named-match-let-values match-let*-values or/values)
  (begin

    ;; --- mlambda: pattern-matching lambda -------------------------------

    (define-syntax mlambda
      (syntax-rules ()
        ;; body-less: predicate mode
        ((_ formals)
         (%201-core-lambda %201-args
           (%201-match-formals %201-args formals #t #f)))
        ;; normal
        ((_ formals body1 body2 ...)
         (%201-core-lambda %201-args
           (%201-match-formals %201-args formals
                                (begin body1 body2 ...)
                                (%201-fail 'mlambda %201-args))))))

    ;; --- cdefine: curried define (SRFI 219's convention) + patterns -----

    (define-syntax cdefine
      (syntax-rules ()
        ;; body-less, curried (2+ levels): a chain of predicates
        ((_ ((inner . iargs) . oargs))
         (cdefine (inner . iargs) (mlambda oargs)))
        ;; body-less, single level: a predicate
        ((_ (name . args))
         (define name (mlambda args)))
        ;; with body, curried (2+ levels)
        ((_ ((inner . iargs) . oargs) body1 body2 ...)
         (cdefine (inner . iargs) (mlambda oargs body1 body2 ...)))
        ;; with body, single level
        ((_ (name . args) body1 body2 ...)
         (define name (mlambda args body1 body2 ...)))
        ;; plain value define
        ((_ name expr)
         (define name expr))))

    ;; --- named-match-let-values / match-let*-values ---------------------
    ;; (pattern-matching bindings, single value each -- see scope note above)

    (define-syntax named-match-let-values
      (syntax-rules ()
        ((_ name ((p init) ...) body1 body2 ...)
         (letrec ((name (mlambda (p ...) body1 body2 ...)))
           (name init ...)))
        ((_ ((p init) ...) body1 body2 ...)
         ((mlambda (p ...) body1 body2 ...) init ...))))

    (define-syntax match-let*-values
      (syntax-rules ()
        ((_ () body1 body2 ...)
         (named-match-let-values () body1 body2 ...))
        ((_ ((p init) rest ...) body1 body2 ...)
         (named-match-let-values ((p init))
           (match-let*-values (rest ...) body1 body2 ...)))))

    ;; --- or/values ----------------------------------------------------
    ;; Ordinary `or` is inconsistent about propagating multiple values
    ;; from a non-final expression; `or/values` fixes that.

    (define-syntax or/values
      (syntax-rules ()
        ((_) #f)
        ((_ e) e)
        ((_ e1 e2 ...)
         (call-with-values
          (lambda () e1)
          (lambda results
            (if (and (pair? results) (car results))
                (apply values results)
                (or/values e2 ...)))))))))
