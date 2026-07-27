;; Regression test for #1719: define-values did not support letrec*-style
;; mutual/forward reference the way plain `define` does inside a body — a
;; define-values clause could not reference a name bound by a LATER
;; define-values (or define) clause in the same body, even though the
;; reference is only ever evaluated after that later binding is
;; initialized. R7RS draws no distinction between `define` and
;; `define-values` for a body's letrec* scoping (5.3.2/5.3.3).
;;
;; Root cause: scanBodyDefs's leading-defines prescan (the mechanism that
;; gives plain `define` its letrec*-style forward visibility) only
;; recognized `define` and `define-record-type`; a `define-values` clause
;; fell through to being compiled as an ordinary sequential expression,
;; so names it bound were not yet declared as locals while compiling an
;; EARLIER sibling clause's init expression.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "define-values-letrec-1719")

;; The issue's own repro, verbatim shape: two mutually-recursive procedures,
;; each bound by its own define-values clause inside a procedure body.
(define (mutual-in-lambda-body)
  (define-values (ev?) (lambda (n) (if (= n 0) #t (od? (- n 1)))))
  (define-values (od?) (lambda (n) (if (= n 0) #f (ev? (- n 1)))))
  (ev? 10))
(test-assert "mutual recursion via define-values in a lambda body"
  (mutual-in-lambda-body))

;; Same shape, but the outer procedure is an explicit `(lambda ...)` value
;; bound by a plain `define` rather than the `(define (name) ...)`
;; shorthand -- exercises compileLambdaWithIR, a second, independent copy
;; of the same body-scanning/compiling logic used by the shorthand form.
(define mutual-longhand
  (lambda ()
    (define-values (ev?) (lambda (n) (if (= n 0) #t (od? (- n 1)))))
    (define-values (od?) (lambda (n) (if (= n 0) #f (ev? (- n 1)))))
    (ev? 11)))
(test-equal "mutual recursion via define-values, explicit lambda value"
  #f (mutual-longhand))

;; Same shape inside a `let` body -- exercises compileBodyForms directly
;; (compileLetBody), a third call site sharing the scanBodyDefs prescan.
(test-assert "mutual recursion via define-values in a let body"
  (let ()
    (define-values (ev?) (lambda (n) (if (= n 0) #t (od? (- n 1)))))
    (define-values (od?) (lambda (n) (if (= n 0) #f (ev? (- n 1)))))
    (ev? 12)))

;; Immediately-invoked bare lambda (no enclosing define at all).
(test-assert "mutual recursion via define-values in a bare invoked lambda"
  ((lambda ()
     (define-values (ev?) (lambda (n) (if (= n 0) #t (od? (- n 1)))))
     (define-values (od?) (lambda (n) (if (= n 0) #f (ev? (- n 1)))))
     (ev? 6))))

;; A define-values clause forward-referencing a name bound by a LATER
;; plain `define`.
(test-equal "define-values forward-referencing a later plain define"
  13
  (let ()
    (define-values (get-a) (lambda () a))
    (define a 13)
    (get-a)))

;; A plain `define` forward-referencing a name bound by a LATER
;; define-values clause.
(test-equal "plain define forward-referencing a later define-values"
  14
  (let ()
    (define (get-b) b)
    (define-values (b) 14)
    (get-b)))

;; Three definitions interleaved (define, define-values, define), each
;; referencing a name from another, in different directions.
(test-equal "interleaved define/define-values/define, mutual references"
  13
  (let ()
    (define (helper x) (other x))
    (define-values (a b) (values 1 2))
    (define (other x) (+ x a b))
    (helper 10)))

;; Two names bound by the SAME define-values clause, one referencing the
;; other -- both must already be visible while compiling the shared init.
(test-equal "define-values clause where one bound name calls another"
  42
  (let ()
    (define-values (f g) (values (lambda () (g)) (lambda () 42)))
    (f)))

;; A zero-name define-values clause (evaluated only for effect) sandwiched
;; between other definitions must not disturb the surrounding letrec*
;; sequencing, scoping, or evaluation order.
(test-equal "zero-name define-values clause between other definitions"
  '(first second)
  (let ((log '()))
    (define (mark! x) (set! log (cons x log)))
    (define-values () (mark! 'first))
    (define (dummy) 'unused)
    (define-values () (mark! 'second))
    (reverse log)))

;; A define-values body consisting of nothing but a single zero-name
;; clause must still compile and run without crashing.
(test-equal "define-values body with only a zero-name clause"
  'done
  (let ((result #f))
    (define-values () (set! result 'done))
    result))

;; Rest-only (single symbol) formals shape, forward-referenced from a plain
;; `define` compiled earlier in the same body.
(test-equal "rest-only define-values forward-referenced by an earlier define"
  #t
  (let ()
    (define (odd-ref n) (if (= n 0) #f ((car all-vals) (- n 1))))
    (define-values all-vals
      (values (lambda (n) (if (= n 0) #t (odd-ref (- n 1)))) 99))
    ((car all-vals) 10)))

;; Mixed fixed names + rest, referenced forward from earlier definitions.
(test-equal "mixed fixed+rest define-values forward-referenced"
  '(1 (2 3))
  (let ()
    (define (getp) p)
    (define (getqs) qs)
    (define-values (p . qs) (values 1 2 3))
    (list (getp) (getqs))))

;; Sanity checks that were already correct before the fix (top level and a
;; single, non-mutual define-values) must keep working.
(define-values (top-a top-b) (values 10 20))
(test-equal "top-level define-values still works" 30 (+ top-a top-b))

(test-equal "single-name define-values still works" 42
  (let ()
    (define-values (x) (values 42))
    x))

(let ((runner (test-runner-current)))
  (test-end "define-values-letrec-1719")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
