;; Regression test for #1832: a macro template's own free reference to a
;; non-procedure global that was already bound at the macro's definition
;; time (R7RS 4.3.1 referential transparency) used to be preserved
;; UNRENAMED so it could pierce use-site shadowing. When a use site passed
;; a pattern-variable argument of the SAME spelling, the two became
;; textually indistinguishable, and whichever alias the compiler injected
;; for the template's own reference silently intercepted the argument's
;; occurrence too. This is the global counterpart of #1288's
;; captured-local fix (see arg-vs-free.scm) — the reference is now
;; hygiene-renamed like any other template-introduced identifier, and the
;; referential-transparency alias is injected under that renamed name
;; instead of the bare one.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "free-global-vs-arg-1832")

;; Core bug: pattern-variable substitution carries the use-site `a` (the
;; LET's own local, 5), but the template's free reference `a` must keep
;; reading the pre-existing GLOBAL (999) regardless.
(define a 999)
(define-syntax def2
  (syntax-rules ()
    ((def2 b) (list a b))))

(test-equal "arg same name as free global: template ref reads the global"
  999
  (car (let ((a 5)) (def2 a))))
(test-equal "arg same name as free global: argument reads the use-site local"
  5
  (cadr (let ((a 5)) (def2 a))))

;; No collision (baseline — should already work)
(test-equal "no name collision"
  (list 999 42)
  (def2 42))

;; set! combined with the same collision: the template's own set! must
;; still mutate the GLOBAL, while the pattern-variable argument of the
;; same spelling must still resolve to the use-site local, untouched.
(define counter 0)
(define-syntax bump2!
  (syntax-rules ()
    ((bump2! x) (begin (set! counter (+ counter 1)) x))))

(test-equal "set!+collision: argument still reads the untouched use-site local"
  100
  (let ((counter 100)) (bump2! counter)))
(test-equal "set!+collision: template's own set! still reached the global"
  1
  counter)

;; Two free globals, one collides with the argument (mirrors arg-vs-free's
;; "two captured locals" case).
(define p 5)
(define q 7)
(define-syntax m2
  (syntax-rules ()
    ((_ x) (list x p q))))

(test-equal "two free globals, arg collides with one"
  (list 100 5 7)
  (let ((q 100)) (m2 q)))

(let ((runner (test-runner-current)))
  (test-end "free-global-vs-arg-1832")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
