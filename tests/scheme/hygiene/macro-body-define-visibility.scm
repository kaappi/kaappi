;; Regression test for #1800: a macro use in body position whose expansion
;; is a bare (define x v) -- where x comes through as a pattern-variable
;; substitution of a use-site identifier, not a template-literal name --
;; must make x visible to later sibling forms in the same body, exactly as
;; if the user had written (define x v) directly at that position.
;;
;; Root cause: expandAndCompileMacroUse's post-expansion cleanup popped
;; every compiler local added while compiling the macro's final expanded
;; form back off before returning, on the assumption that everything added
;; during a macro-use compile is transient chain bookkeeping (hygienic
;; captured-local aliases). A body-scope `define` reached through the
;; expansion adds a REAL, sibling-visible local, not an alias, and must
;; survive the call returning.
;;
;; Note: compile/runtime errors abort a top-level form without setting a
;; non-zero exit code, so results are checked via flags in separate
;; top-level forms (see forward-sibling-define-ref.scm for the same
;; pattern).

(define ok1 #f)

;; let-syntax body: (m (define x 10)) expands (via pattern-variable
;; substitution, preserving the use-site identifier x unrenamed) to
;; (define x 10), which must bind x for the following (m2) reference.
(let-syntax
    ((m (syntax-rules () ((m form) form))))
  (m (define x 10))
  (if (equal? x 10)
      (set! ok1 #t)
      (begin (display "FAIL 1: expected 10, got ") (display x) (newline))))

(define ok2 #f)

;; Same pattern, but via a top-level define-syntax and a lambda/let body
;; that goes through the leading-defines pre-scanner (scanBodyDefs), not
;; let-syntax's own simpler body loop -- both paths route through the same
;; expandAndCompileMacroUse and hit the same bug.
(define-syntax n800 (syntax-rules () ((n800 form) form)))

(let ()
  (n800 (define y 20))
  (if (equal? y 20)
      (set! ok2 #t)
      (begin (display "FAIL 2: expected 20, got ") (display y) (newline))))

(if (and ok1 ok2)
    (begin (display "PASS") (newline))
    (begin (display "FAIL: macro-expanded body-position define not visible to siblings") (newline) (exit 1)))
