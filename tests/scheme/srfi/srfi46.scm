;; SRFI-46 (Basic Syntax-rules Extensions) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi46.scm
;;
;; Both extensions this SRFI specifies (custom ellipsis identifiers, tail
;; patterns) are already native to Kaappi's syntax-rules — see the header
;; of lib/srfi/46.sld. These tests exercise the spec's own examples using
;; syntax-rules imported via (srfi 46), to confirm the re-export path works
;; and that the underlying engine really does conform.

(import (scheme base) (scheme process-context) (srfi 46) (srfi 64))

(test-begin "srfi-46")

;;; --- Extension 2: tail patterns (spec's own "foo" example) ---
(let-syntax
    ((foo (syntax-rules ()
            ((foo ?x ?y ... ?z)
             (list ?x (list ?y ...) ?z)))))
  (test-equal "tail pattern: head, middle, tail" '(1 (2 3 4) 5) (foo 1 2 3 4 5))
  (test-equal "tail pattern: empty middle" '(1 () 5) (foo 1 5)))

;;; --- Extension 2: tail patterns on vectors ---
(let-syntax
    ((vfoo (syntax-rules ()
             ((vfoo #(?x ?y ... ?z)) (list ?x (list ?y ...) ?z)))))
  (test-equal "vector tail pattern" '(1 (2 3 4) 5) (vfoo #(1 2 3 4 5))))

;;; --- Extension 2: spec's own fake-begin example ---
(let-syntax
    ((fake-begin (syntax-rules ()
                   ((fake-begin ?body ... ?tail)
                    (let* ((ignored ?body) ...) ?tail)))))
  (define fake-begin-log '())
  (define (fake-begin-record! x) (set! fake-begin-log (cons x fake-begin-log)))
  (define fake-begin-result
    (fake-begin (fake-begin-record! 'a) (fake-begin-record! 'b) 42))
  (test-equal "fake-begin: returns the tail expression" 42 fake-begin-result)
  (test-equal "fake-begin: sequences side effects in order" '(b a) fake-begin-log))

;;; --- Extension 1: ellipsis-identifier hygiene (spec's own example) ---
;; A ":::" token supplied as ordinary DATA from an outer scope must not be
;; reinterpreted as the ellipsis token by an inner macro that happens to
;; redefine ellipsis to ":::" — hygiene keeps the binding scoped to that
;; inner transformer's own rules.
(test-equal "ellipsis identifier is hygienic, not textual"
  '((1) 2 (3) (4))
  (let-syntax
      ((f (syntax-rules ()
            ((f ?e)
             (let-syntax
                 ((g (syntax-rules ::: ()
                       ((g (??x ?e) (??y :::))
                        (list (list ??x) ?e (list ??y) :::)))))
               (g (1 2) (3 4)))))))
    (f :::)))

(let ((runner (test-runner-current)))
  (test-end "srfi-46")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
