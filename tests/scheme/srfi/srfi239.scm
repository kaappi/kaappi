;; SRFI-239 (Destructuring Lists) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi239.scm

(import (scheme base) (scheme process-context) (srfi 239) (srfi 64))

(test-begin "srfi-239")

;;; --- the spec's own type-of example ---
(define (type-of obj)
  (list-case obj
    ((_ . _) 'pair)
    (() 'null)
    (_ 'atom)))
(test-equal "list-case: dispatches on pair" 'pair (type-of '(1 2)))
(test-equal "list-case: dispatches on null" 'null (type-of '()))
(test-equal "list-case: dispatches on atom" 'atom (type-of 5))
(test-equal "list-case: an improper list's tail is an atom" 'atom (type-of (cdr '(1 . 2))))

;;; --- real bindings in the pair clause ---
(test-equal "list-case: binds car and cdr" '(1 . (2 3)) (list-case '(1 2 3) ((a . d) (cons a d))))

;;; --- one-sided underscore ---
(test-equal "list-case: (_ . d) ignores car" '(2 3) (list-case '(1 2 3) ((_ . d) d)))
(test-equal "list-case: (a . _) ignores cdr" 1 (list-case '(1 2 3) ((a . _) a)))

;;; --- the spec's own tail-recursive fold example ---
(define (my-fold proc seed ls)
  (let f ((acc seed) (ls ls))
    (list-case ls
      ((h . t) (f (proc h acc) t))
      (() acc)
      (_ (error "not a list" ls)))))
(test-equal "list-case: spec's fold example" '(3 2 1) (my-fold cons '() '(1 2 3)))

;;; --- clause order doesn't matter ---
(test-equal "list-case: clauses may appear in any order"
  'null
  (list-case '() (_ 'atom) ((a . d) 'pair) (() 'null)))

;;; --- missing clause on a value that would need it signals an error ---
(test-equal "list-case: unmatched pair without a pair clause errors"
  'caught
  (guard (e (#t 'caught)) (list-case '(1 2) (() 'null))))
(test-equal "list-case: unmatched null without a null clause errors"
  'caught
  (guard (e (#t 'caught)) (list-case '() ((a . d) 'pair))))
(test-equal "list-case: unmatched atom without an atom clause errors"
  'caught
  (guard (e (#t 'caught)) (list-case 5 (() 'null))))

;;; --- duplicate clauses of the same shape are a reportable mistake ---
;; Regression: a second clause of the same shape used to silently
;; overwrite the first one instead of signaling a mistake.
(test-equal "list-case: two (a . d) clauses signals an error"
  'caught
  (guard (e (#t 'caught))
    (list-case '(1 2)
      ((a . d) 'first)
      ((a . d) 'second))))
(test-equal "list-case: two () clauses signals an error"
  'caught
  (guard (e (#t 'caught))
    (list-case '()
      (() 'first)
      (() 'second))))
(test-equal "list-case: two atom clauses signals an error"
  'caught
  (guard (e (#t 'caught))
    (list-case 5
      (_ 'first)
      (_ 'second))))
;; Duplicate detection must not misfire on legitimate distinct-shape
;; clauses regardless of the order they're given in.
(test-equal "list-case: one clause per shape in any order still works"
  'null
  (list-case '() (_ 'atom) (() 'null) ((a . d) 'pair)))

(let ((runner (test-runner-current)))
  (test-end "srfi-239")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
