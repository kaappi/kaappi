;; Regression test for #1829: an `em-syntax-rules` (SRFI 148) macro whose
;; expansion defines a fresh top-level binding and reads it back in the
;; same generated `begin` got the WRONG value back — it read a previous
;; expansion's same-spelled binding instead of its own.
;;
;; Unlike a `syntax-rules` template (whose introduced top-level `define`
;; is hygienically renamed), the CK machine builds its output as plain
;; data, so `holder`/`slot` below land under their bare names and are real
;; globals by the time the NEXT use expands. That made the template's own
;; reference a free reference to an already-bound non-procedure global,
;; which used to be deliberately left UNRENAMED so an injected alias could
;; pierce use-site shadowing (R7RS 4.3.1 referential transparency). The
;; bare reference was then indistinguishable from the parent's own
;; same-spelled symbol that the `=>` query threads back in — the same
;; collision as #1832 (see free-global-vs-arg-1832.scm), reached through a
;; macro-generated top-level define instead of a pattern variable.
;;
;; Note both macros below share ONE global per spelling: every type's
;; `:secret` hands back the same bare symbol, so "the parent's value" is
;; whatever that single global holds at the moment of expansion. Each
;; parent-having use therefore directly follows its intended parent, and
;; the assertions say nothing about re-targeting an earlier one.
(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 148))

(test-begin "macro-fresh-global-readback-1829")

;; Read-backs are recorded through a PROCEDURE on purpose: procedures are
;; excluded from the free-global alias mechanism under test, so the
;; recorder itself cannot perturb what is being measured.
(define collected '())
(define (record! x) (set! collected (cons x collected)))
(define (take-collected!)
  (let ((r (reverse collected)))
    (set! collected '())
    r))

(define-syntax :secret
  (syntax-rules () ((_ . args) (syntax-error "misuse"))))

;; Resolves a type-spec into (name parent-value-expr): with a parent,
;; queries the parent's own :secret protocol for a reference to ITS OWN
;; storage variable; with no parent, #f.
(define-syntax parse-type
  (em-syntax-rules ()
    ((parse-type '(name parent))
     ((parent ':secret) => 'parent-value)
     `(name parent-value))
    ((parse-type 'name) '(name #f))))

;; --- Case 1: the storage name already exists as a user global ----------
;; The tightest form of the bug: with `slot` bound before any use, the
;; free-global path fires on the very FIRST parent-having use, so pre-fix
;; `(defslot (childS parentS))` read back parentS's value instead of its
;; own. (The macro-introduced `define slot` overwrites the user's binding
;; in both builds — that is the pre-existing unhygienic-top-level-define
;; behavior this test does not assert on.)
(define slot '(user-slot))

(define-syntax defslot
  (em-syntax-rules ()
    ((defslot type-spec)
     ((parse-type 'type-spec) => '(name parent-expr))
     `(begin
        (define slot (list 'slot-named 'name 'with-parent parent-expr))
        (record! slot)
        (define-syntax name
          (em-syntax-rules ::: ()
            ((name ':secret) 'slot)
            ((name 'arg :::) (em-error "bad"))))))))

(defslot parentS)
(defslot (childS parentS))

(test-equal "storage name pre-bound: child reads back its own fresh define"
  '((slot-named parentS with-parent #f)
    (slot-named childS with-parent (slot-named parentS with-parent #f)))
  (take-collected!))

;; --- Case 2: the issue's reported sequence -----------------------------
;; `holder` is NOT pre-bound here, so the first use creates it and the
;; failure surfaces only on the parent-having branch's SECOND use, which
;; queries a macro the branch's first use did not query. Pre-fix, the
;; fourth read-back came back as parentB's own holder.
(define-syntax deftype
  (em-syntax-rules ()
    ((deftype type-spec)
     ((parse-type 'type-spec) => '(name parent-expr))
     `(begin
        (define holder (list 'type-named 'name 'with-parent parent-expr))
        (record! holder)
        (define-syntax name
          (em-syntax-rules ::: ()
            ((name ':secret) 'holder)
            ((name 'arg :::) (em-error "bad"))))))))

(deftype parentA)
(deftype (childA parentA))
(deftype parentB)
(deftype (childB parentB))

(test-equal "fresh top-level define reads back as itself, not a prior expansion's"
  '((type-named parentA with-parent #f)
    (type-named childA with-parent (type-named parentA with-parent #f))
    (type-named parentB with-parent #f)
    (type-named childB with-parent (type-named parentB with-parent #f)))
  (take-collected!))

(let ((runner (test-runner-current)))
  (test-end "macro-fresh-global-readback-1829")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
