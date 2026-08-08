;; SRFI-46 (Basic Syntax-rules Extensions) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi46.scm
;;
;; Both extensions this SRFI specifies (custom ellipsis identifiers, tail
;; patterns) are already native to Kaappi's syntax-rules — see the header
;; of lib/srfi/46.sld. These tests exercise the spec's own examples using
;; syntax-rules imported via (srfi 46), to confirm the re-export path works
;; and that the underlying engine really does conform.
;;
;; Grown in audit v2 Phase 3.8 from 6 assertions. The additions cover the
;; consequences of a custom ellipsis that the spec's own example does not
;; reach -- the default "..." becoming ordinary data in both pattern and
;; template, the (<ellipsis> <ellipsis>) escape re-spelled for the custom
;; identifier, and a nested syntax-rules that goes back to the default --
;; plus the tail-pattern shapes beyond one fixed tail: several fixed tails,
;; an improper (dotted) pattern, a compound tail, nesting, and the vector
;; form of each.

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

;;; --- Extension 2: more than one fixed element after the ellipsis ---
(define-syntax two-tails
  (syntax-rules ()
    ((_ a b ... y z) (list a (list b ...) y z))))

(test-equal "tail pattern: two fixed tail elements"
  '(1 (2 3) 4 5) (two-tails 1 2 3 4 5))
(test-equal "tail pattern: two fixed tails with an empty middle"
  '(1 () 2 3) (two-tails 1 2 3))
(test-error "tail pattern: two fixed tails need at least three arguments"
  (eval '(let-syntax ((tt (syntax-rules () ((_ a b ... y z) (list a y z)))))
           (tt 1 2))
        (environment '(scheme base) '(srfi 46))))

;;; --- Extension 2: the fixed tail may itself be a compound pattern ---
(define-syntax compound-tail
  (syntax-rules ()
    ((_ a ... (x y)) (list (list a ...) x y))))

(test-equal "tail pattern: the tail is itself a compound pattern"
  '((1 2) 3 4) (compound-tail 1 2 (3 4)))
(test-equal "tail pattern: compound tail with an empty middle"
  '(() 3 4) (compound-tail (3 4)))

;;; --- Extension 2: an improper (dotted) pattern with a tail ---
(define-syntax improper-tail
  (syntax-rules ()
    ((_ a ... z . r) (list (list a ...) z 'r))))

(test-equal "tail pattern: improper pattern, empty dotted rest"
  '((1 2) 3 ()) (improper-tail 1 2 3))

;;; --- Extension 2: tail patterns nest ---
(define-syntax nested-tails
  (syntax-rules ()
    ((_ (a ... z) ...) (list (list (list a ...) z) ...))))

(test-equal "tail pattern: nested inside an outer ellipsis"
  '(((1 2) 3) ((4) 5)) (nested-tails (1 2 3) (4 5)))

;;; --- Extension 2: two fixed tails inside a vector pattern ---
(define-syntax vector-two-tails
  (syntax-rules ()
    ((_ #(a b ... y z)) (list a (list b ...) y z))))

(test-equal "vector tail pattern: two fixed tail elements"
  '(1 (2 3) 4 5) (vector-two-tails #(1 2 3 4 5)))

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

;;; --- Extension 1: the custom ellipsis really does drive repetition ---
(define-syntax custom-ellipsis
  (syntax-rules ::: ()
    ((_ x :::) (list x :::))))

(test-equal "a custom ellipsis identifier drives repetition"
  '(1 2 3) (custom-ellipsis 1 2 3))
(test-equal "a custom ellipsis identifier matches zero elements"
  '() (custom-ellipsis))

;;; a custom ellipsis coexists with a literals list
(define-syntax custom-with-literals
  (syntax-rules ::: (else)
    ((_ else x :::) (list 'else x :::))
    ((_ x :::) (list 'other x :::))))

(test-equal "custom ellipsis with a literals list: literal branch"
  '(else 1 2) (custom-with-literals else 1 2))
(test-equal "custom ellipsis with a literals list: fallback branch"
  '(other 1 2) (custom-with-literals 1 2))

;;; --- Extension 1's real consequence: once the ellipsis is renamed, the
;;; default "..." is an ordinary identifier in BOTH pattern and template ---

(define-syntax dots-as-template-data
  (syntax-rules ::: ()
    ((_ x :::) '(x ::: ...))))

(test-equal "with a custom ellipsis, ... is ordinary data in the template"
  '(1 2 ...) (dots-as-template-data 1 2))

(define-syntax dots-as-pattern-literal
  (syntax-rules ::: ()
    ((_ a ... b) '(got a b))))

(test-equal "with a custom ellipsis, ... is an ordinary pattern element"
  '(got 1 2) (dots-as-pattern-literal 1 ... 2))

;;; the R7RS (<ellipsis> <ellipsis>) escape, re-spelled for the custom one
(define-syntax escaped-custom
  (syntax-rules ::: ()
    ((_ x) '(x (::: :::)))))

(test-equal "the ellipsis escape works with a custom ellipsis identifier"
  '(z :::) (escaped-custom z))

;;; a nested syntax-rules may go back to the default ellipsis
(define-syntax outer-custom
  (syntax-rules ::: ()
    ((_ x :::)
     (let-syntax ((inner (syntax-rules () ((_ y ...) '(inner y ...)))))
       (inner x :::)))))

(test-equal "a nested syntax-rules may use the default ellipsis again"
  '(inner 1 2) (outer-custom 1 2))

;;; both extensions at once: a custom ellipsis with a tail pattern
(define-syntax custom-ellipsis-tail
  (syntax-rules ::: ()
    ((_ a b ::: z) '(a (b :::) z))))

(test-equal "a custom ellipsis composes with a tail pattern"
  '(1 (2 3) 4) (custom-ellipsis-tail 1 2 3 4))

;;; --- the boundary SRFI 46 does NOT move: R7RS 4.3.2's pattern grammar
;;; still admits at most ONE ellipsis per list or vector pattern. The tail
;;; patterns above widen what may FOLLOW that ellipsis; they do not add a
;;; second one. This expander previously accepted two and split the input
;;; arbitrarily -- the trailing pattern always took the last two elements,
;;; because the surplus ellipsis tokens were counted as fixed tail
;;; elements (#2082). chibi 0.12 and Guile 3.0 reject the define-syntax
;;; outright.
;;;
;;; Fixed by kaappi#2082: the define-syntax itself is now a syntax error,
;;; so each case is probed through `eval` (a literal call would abort the
;;; enclosing test form at compile time rather than raise inside it). The
;;; two test-equal pins that asserted the arbitrary split were removed.

(test-error "two ellipses in one list pattern is a syntax error (#2082)"
  (eval '(let-syntax ((m (syntax-rules () ((_ a ... b ...) (list (list a ...) (list b ...))))))
           (m 1 2 3))
        (environment '(scheme base))))

(test-error "three ellipses in one list pattern is a syntax error (#2082)"
  (eval '(let-syntax ((m (syntax-rules () ((_ a ... b ... c ...) (list (list a ...) (list b ...) (list c ...))))))
           (m 1 2 3 4 5))
        (environment '(scheme base))))

(test-error "two ellipses in one vector pattern is a syntax error (#2082)"
  (eval '(let-syntax ((m (syntax-rules () ((_ #(a ... b ...)) (list (list a ...) (list b ...))))))
           (m #(1 2 3)))
        (environment '(scheme base))))

;;; the ellipsis-as-literal carve-out: when the ellipsis identifier is
;;; listed in <literals>, it is an ordinary pattern element, so two of
;;; them are just two fixed elements -- still legal (#2082).
(test-equal "two ellipsis-named literals in one pattern stay legal (#2082)"
  '(1 2)
  (eval '(let-syntax ((m (syntax-rules ... (...)
                           ((_ a ... b) (list a b)))))
           (m 1 ... 2))
        (environment '(scheme base))))

;;; --- the derived cond-expand feature id (#1649) ---
(test-equal "cond-expand srfi-46" 'yes (cond-expand (srfi-46 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-46")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
