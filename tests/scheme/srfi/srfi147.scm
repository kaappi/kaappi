;; SRFI 147 (Custom Macro Transformers) tests. Unlike SRFI 139/149, this
;; genuinely needed an engine change: compileDefineSyntax/compileLetSyntax/
;; compileLetrecSyntax (src/compiler_macro.zig) now resolve a
;; transformer-spec through resolveTransformerSpec before parsing it, so a
;; macro use that itself expands (possibly through a bare-keyword alias or
;; a begin-wrapped helper definition) to a literal (syntax-rules ...) form
;; is accepted anywhere a transformer-spec is expected. See
;; lib/srfi/147.sld's header for the full rationale and the one
;; deliberately-deferred case (aliasing a builtin special form). Part of
;; issue #1699 (SRFI macro & syntax extension libraries).
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi147.scm

(import (scheme base) (scheme process-context) (scheme eval) (scheme repl) (srfi 64) (srfi 147))

(test-begin "srfi-147")

;;; --- the spec's own worked example: syntax-rules* automatically wraps
;;; multi-form templates in begin, so a transformer-spec can be written
;;; without an explicit (begin ...) around a multi-statement body ---
(define-syntax syntax-rules*
  (syntax-rules ()
    ((_ (literal ...) ((keyword . pattern) . template) ...)
     (syntax-rules (literal ...) ((keyword . pattern) (begin . template)) ...))))

;;; --- define-syntax accepts a custom transformer ---
(define-syntax bar (syntax-rules* () ((bar a b) (+ a b) (* a b))))
(test-equal 30 (bar 5 6))

;;; --- let-syntax accepts a custom transformer, multiple bindings in one
;;; form (exercises the per-binding loop specifically) ---
(test-equal
 '(12 9)
 (let-syntax ((foo (syntax-rules* () ((foo a b) (+ a b) (* a b))))
              (baz (syntax-rules* () ((baz a) (- a) (- (- a))))))
   (list (foo 3 4) (baz 9))))

;;; --- letrec-syntax accepts a custom transformer ---
(test-equal
 20
 (letrec-syntax ((qux (syntax-rules* () ((qux a b) (+ a b) (* a b)))))
   (qux 2 10)))

;;; --- resolution loops through multiple expansion steps: an alias macro
;;; expands to a syntax-rules* call, which itself expands to a literal
;;; syntax-rules form ---
(define-syntax alias-of-syntax-rules*
  (syntax-rules () ((_ spec) (syntax-rules* () . spec))))

(test-equal
 2
 (let-syntax ((multi (alias-of-syntax-rules* (((multi a b) (+ a b) (* a b))))))
   (multi 1 2)))

;;; --- deliberately deferred: a bare keyword aliasing a BUILTIN special
;;; form is not supported (builtins have no Transformer value to alias to) ---
(test-equal #t (guard (e (#t #t)) (eval '(let-syntax ((my-if if)) (my-if #t 1 2)) (interaction-environment)) #f))

;;; --- a bare keyword aliasing an existing, non-builtin macro IS supported ---
(test-equal
 7
 (let-syntax ((original (syntax-rules () ((_ a) (+ a 3)))))
   (let-syntax ((alias original))
     (alias 4))))

;;; --- the em-syntax-rules-aux1/aux2 shape SRFI 148 actually needs: a
;;; macro use expands to (begin (define-syntax NAME spec) NAME) -- a
;;; private helper followed by a bare reference to it ---
(define-syntax gen-adder
  (syntax-rules ()
    ((_ n)
     (begin
       (define-syntax adder
         (syntax-rules ()
           ((_ x) (+ x n))))
       adder))))

(test-equal
 15
 (let-syntax ((add10 (gen-adder 10)))
   (add10 5)))

;;; --- begin-wrapped form works in define-syntax and letrec-syntax too,
;;; not just let-syntax ---
(define-syntax add100 (gen-adder 100))
(test-equal 105 (add100 5))

(test-equal
 106
 (letrec-syntax ((add101 (gen-adder 101)))
   (add101 5)))

;;; --- multiple internal definitions in one begin, the LAST of which is
;;; the bare-symbol tail (not the first) ---
(define-syntax gen-two
  (syntax-rules ()
    ((_ n)
     (begin
       (define-syntax unused-helper
         (syntax-rules () ((_ x) (- x))))
       (define-syntax real-helper
         (syntax-rules () ((_ x) (* x n))))
       real-helper))))

(test-equal 24 (let-syntax ((triple (gen-two 3))) (triple 8)))

;;; --- chained resolution: a begin-wrapped alias whose own helper's spec
;;; is ANOTHER macro use that resolves to a further begin-wrapped alias
;;; (simulating em-syntax-rules's own multi-stage aux1 -> aux2 chaining) ---
(define-syntax stage-inner
  (syntax-rules ()
    ((_ n)
     (begin
       (define-syntax inner-helper
         (syntax-rules () ((_ x) (* x n))))
       inner-helper))))

(define-syntax stage-outer
  (syntax-rules ()
    ((_ n)
     (begin
       (define-syntax outer-helper
         (stage-inner n))
       outer-helper))))

(test-equal 42 (let-syntax ((chained (stage-outer 7))) (chained 6)))

;;; --- a begin-internal helper referenced BY NAME from inside the FINAL
;;; transformer's own template (not aliased directly by bare symbol) must
;;; keep resolving every time the macro being defined is later invoked --
;;; this is what SRFI 148's em-syntax-rules-aux2 needs (it expands to
;;; `(begin (define-syntax o spec) o)` where the surrounding syntax-rules
;;; body ALSO calls `o` directly from within its own rules, not just as
;;; the bare tail). A helper registered only for the DURATION of resolving
;;; this transformer-spec (and gone once that resolution returns) cannot
;;; satisfy this -- it must persist in the real macro table ---
(define-syntax gen-cross-ref
  (syntax-rules ()
    ((_ n)
     (begin
       (define-syntax step1
         (syntax-rules ()
           ((_ x) (* x n))))
       (define-syntax step2
         (syntax-rules ()
           ((_ x) (step1 (+ x 1)))))
       (syntax-rules ()
         ((_ y) (step2 y)))))))

(define-syntax use-cross-ref (gen-cross-ref 3))
;; called twice: the first call alone would pass even with a transient-only
;; registration if evaluation order happened to mask the gap; a second,
;; independent call after the first has fully returned confirms the helper
;; is genuinely persistent, not a one-shot side effect.
(test-equal 15 (use-cross-ref 4))
(test-equal 21 (use-cross-ref 6))

;;; --- the same begin-internal helper NAME used by two unrelated
;;; begin-wrapped macros must not collide -- each expansion's hygienic
;;; renaming keeps them distinct even though both are permanently
;;; registered in the same macro table ---
(define-syntax gen-plus
  (syntax-rules ()
    ((_ n)
     (begin
       (define-syntax shared-name
         (syntax-rules () ((_ x) (+ x n))))
       shared-name))))

(define-syntax gen-minus
  (syntax-rules ()
    ((_ n)
     (begin
       (define-syntax shared-name
         (syntax-rules () ((_ x) (- x n))))
       shared-name))))

(define-syntax use-plus (gen-plus 1))
(define-syntax use-minus (gen-minus 1))
(test-equal '(11 9) (list (use-plus 10) (use-minus 10)))

;;; --- two sibling let-syntax bindings resolving to the exact same
;;; Transformer (a begin-wrapped helper reference, and a bare alias of
;;; that same helper) must not corrupt R7RS 4.3.1 sibling suppression --
;;; CodeRabbit-caught: this shape leaked let_syntax_peer_names/vals
;;; before the fix, since that bookkeeping was computed unconditionally
;;; per binding rather than once per underlying Transformer object. `r`'s
;;; outer (pre-let-syntax) meaning is a plain procedure, unrelated to the
;;; sibling macro of the same name that this let-syntax also introduces,
;;; so a correct result (43, not 4200) also confirms the peer snapshot
;;; itself is still right, not just leak-free ---
(define (r y) (+ y 1))
(test-equal
 43
 (let-syntax ((r (syntax-rules () ((_ y) (* y 100))))
              (p (begin (define-syntax h (syntax-rules () ((_ x) (r x)))) h))
              (q h))
   (q 42)))

;;; --- CodeRabbit-caught follow-up: reusing a persisted helper across two
;;; SEPARATE let-syntax forms (not siblings in the same one) must not leak
;;; either. The already_seen guard above only covers a repeat WITHIN one
;;; form -- a transformer aliased into some OTHER, later, unrelated form
;;; genuinely needs its own peer snapshot recomputed (that form's own
;;; siblings differ), but the recomputation itself must free whatever an
;;; earlier form's processing already set here first. `r1` is a sibling
;;; of `p` in the FIRST let-syntax only; by the second, separate form,
;;; `r1` has reverted to its outer procedure meaning, so a correct result
;;; for `(q 10)` (11, not 1000) also confirms h's own frozen peer snapshot
;;; from its true point of origin still works, unaffected by the later
;;; recomputation ---
(define (r1 y) (+ y 1))
(begin
  (let-syntax ((r1 (syntax-rules () ((_ y) (* y 100))))
               (p (begin (define-syntax h1 (syntax-rules () ((_ x) (r1 x)))) h1)))
    (p 5))
  (test-equal 11 (let-syntax ((q1 h1)) (q1 10))))

;;; --- persistent registration inside a NESTED body scope (not top level):
;;; the cross-referencing shape works the same way inside a lambda body,
;;; and two separate invocations of the same generator in two separate
;;; functions don't interfere with each other ---
(define (nested-cross-ref-1)
  (define-syntax gen-nested
    (syntax-rules ()
      ((_ n)
       (begin
         (define-syntax nested-step
           (syntax-rules () ((_ x) (* x n))))
         (syntax-rules () ((_ y) (nested-step y)))))))
  (define-syntax use-nested (gen-nested 100))
  (use-nested 3))

(define (nested-cross-ref-2)
  (define-syntax gen-nested
    (syntax-rules ()
      ((_ n)
       (begin
         (define-syntax nested-step
           (syntax-rules () ((_ x) (+ x n))))
         (syntax-rules () ((_ y) (nested-step y)))))))
  (define-syntax use-nested (gen-nested 100))
  (use-nested 3))

(test-equal 300 (nested-cross-ref-1))
(test-equal 103 (nested-cross-ref-2))

;;; --- zero internal definitions: (begin <transformer-spec>) with nothing
;;; to define first is the degenerate case of the same grammar rule ---
(define-syntax gen-plain
  (syntax-rules ()
    ((_ n)
     (begin
       (syntax-rules () ((_ x) (- x n)))))))

(test-equal 8 (let-syntax ((sub2 (gen-plain 2))) (sub2 10)))

;;; --- malformed begin body (something other than define-syntax before
;;; the final spec) is a compile error, not a silent success ---
(test-equal
 #t
 (guard (e (#t #t))
   (eval '(let-syntax ((oops (begin (define x 1) (syntax-rules () ((_ y) y)))))
            (oops 1))
         (interaction-environment))
   #f))

;;; --- a bare symbol that resolves to nothing (not a helper just defined,
;;; not any other visible macro) is a compile error ---
(test-equal
 #t
 (guard (e (#t #t))
   (eval '(let-syntax ((oops (begin (define-syntax a (syntax-rules () ((_ x) x))) b)))
            (oops 1))
         (interaction-environment))
   #f))

;;; --- a transformer-spec that resolves to neither syntax-rules nor a
;;; registered macro is a compile error, not a silent success ---
(test-equal #t (guard (e (#t #t)) (eval '(let-syntax ((oops (not-a-macro))) 1) (interaction-environment)) #f))

;;; --- a nearer ancestor scope's macro shadows a farther one, not the
;;; reverse -- the innermost scope has no local definition of its own,
;;; forcing the lookup through the full ancestor chain ---
(define-syntax mk-transformer
  (syntax-rules () ((_) (syntax-rules () ((_ x) 'top-level)))))

(define (shadow-outer)
  (define (shadow-middle)
    (define-syntax mk-transformer
      (syntax-rules () ((_) (syntax-rules () ((_ x) 'middle-level)))))
    (define (shadow-inner)
      (let-syntax ((result (mk-transformer)))
        (result 1)))
    (shadow-inner))
  (shadow-middle))

(test-equal 'middle-level (shadow-outer))

(let ((runner (test-runner-current)))
  (test-end "srfi-147")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
