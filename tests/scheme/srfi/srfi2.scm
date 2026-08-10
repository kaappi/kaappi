;; SRFI 2 (AND-LET*) conformance tests.
;;
;; Written by the systematic audit v2, Phase 3.7 (issue #1890) -- SRFI 2 had
;; no test file at all. The oracle is the SRFI's own *Formal (Denotational)
;; Semantics* section, which is unusually precise for a SRFI this small, plus
;; chibi-scheme 0.12.0, which matches it on every probe here.
;;
;; The one defect this file pins is #2073: the spec's rule
;;     eval[ (AND-LET* (CLAW) ), env] = eval_claw[ CLAW, env ]
;; requires an and-let* with claws and NO body to return the last claw's
;; value; lib/srfi/2.sld used to return #t instead, for all three claw
;; shapes, and now returns the claw value.
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi2.scm

(import (scheme base) (scheme write) (srfi 64) (srfi 2))

(test-begin "srfi-2")

;;; --------------------------------------------------------------------
;;; The two base cases the spec states directly.
;;;   eval[ (AND-LET* () ), env]            = #t
;;;   eval[ (AND-LET* () FORM1 ...), env]   = eval[ (LET* () FORM1 ...), env]
;;; --------------------------------------------------------------------

(test-equal "no claws, no body is #t" #t (and-let* ()))
(test-equal "no claws, one body form" 1 (and-let* () 1))
(test-equal "no claws, body returns last form" 2 (and-let* () 1 2))
(test-equal "no claws, body returns last form (three)" 3 (and-let* () 1 2 3))

;; The spec equates the empty-claws body with a LET* body, so internal
;; definitions must be admitted there and must not leak outward.
(test-equal "empty-claws body admits internal definitions"
            '(2)
            (list (and-let* () (define zz 1) (+ zz 1))))
(test-equal "let* control: same body shape"
            '(2)
            (list (let* () (define zz 1) (+ zz 1))))
(test-equal "non-empty-claws body admits internal definitions"
            '(2)
            (list (and-let* ((x 1)) (define zz 1) (+ zz x))))

;;; --------------------------------------------------------------------
;;; The three CLAW shapes the grammar admits, with a body present.
;;;   CLAW ::= (VARIABLE EXPRESSION) | (EXPRESSION) | BOUND-VARIABLE
;;; --------------------------------------------------------------------

(test-equal "(VARIABLE EXPRESSION) claw binds, body sees it" 1 (and-let* ((x 1)) x))
(test-equal "(EXPRESSION) claw, true" 'yes (and-let* (((> 3 2))) 'yes))
(test-equal "(EXPRESSION) claw, false short-circuits to #f" #f (and-let* (((> 2 3))) 'never))
(test-equal "BOUND-VARIABLE claw, true" 5 (let ((v 5)) (and-let* (v) v)))
(test-equal "BOUND-VARIABLE claw, false" #f (let ((v #f)) (and-let* (v) 'never)))

;; "If the result is #f, AND-LET* immediately returns #f"
(test-equal "(VARIABLE EXPRESSION) claw, false" #f (and-let* ((x #f)) 'never))
(test-equal "false claw in the middle" #f (and-let* ((a 1) (b #f) (c 2)) 'never))
(test-equal "false claw at the end" #f (and-let* ((a 1) (b 2) (c #f)) 'never))

;; "The VARIABLE is available for the rest of the CLAWS, and the BODY"
(test-equal "later claw sees an earlier claw's variable" 8
            (and-let* ((x 2) (y (* x 3))) (+ x y)))
(test-equal "body sees every claw variable" '(2 6 8)
            (and-let* ((x 2) (y (* x 3))) (list x y (+ x y))))
(test-equal "an (EXPRESSION) claw may use an earlier variable" 'yes
            (and-let* ((x 2) ((> x 1))) 'yes))

;; "The CLAWS are evaluated in the strict left-to-right order" -- so a claw
;; after a failing one must not run at all.
(test-equal "claw after a failing claw is not evaluated" 0
            (let ((n 0))
              (and-let* ((a #f) (b (begin (set! n 1) 2))))
              n))
(test-equal "body is not evaluated when a claw fails" 0
            (let ((n 0))
              (and-let* ((a #f)) (set! n 1))
              n))
(test-equal "each claw is evaluated exactly once" 3
            (let ((n 0))
              (and-let* ((a (begin (set! n (+ n 1)) 1))
                         (b (begin (set! n (+ n 1)) 2))
                         (c (begin (set! n (+ n 1)) 3)))
                n)))

;;; --------------------------------------------------------------------
;;; The SRFI's own worked examples (adapted only to return a value rather
;;; than depend on ports or on SRFI-1 helpers).
;;; --------------------------------------------------------------------

(test-equal "spec example: guarded assv lookup" '(2)
            (and-let* ((x (assv 'b '((a 1) (b 2))))) (cdr x)))
(test-equal "spec example: guarded lookup, key absent" #f
            (and-let* ((x (assv 'z '((a 1) (b 2))))) (cdr x)))
(test-equal "spec example shape: chained accessor guard" 3
            (and-let* ((lst (list 1 2 3)) ((pair? lst)) (tail (cdr lst)) ((pair? tail)))
              (car (cdr tail))))
(test-equal "spec example shape: guard fails midway" #f
            (and-let* ((lst (list 1)) ((pair? lst)) (tail (cdr lst)) ((pair? tail)))
              'never))

;;; --------------------------------------------------------------------
;;; Nesting and composition. Macro defects show up in composition more
;;; often than in isolation.
;;; --------------------------------------------------------------------

(test-equal "and-let* nested in a claw expression" 6
            (and-let* ((x (and-let* ((a 2) (b 3)) (* a b)))) x))
(test-equal "and-let* nested in the body" 'inner
            (and-let* ((x 1)) (and-let* ((y 2)) 'inner)))
(test-equal "inner and-let* failing does not fail the outer" '(#f done)
            (and-let* ((x 1)) (list (and-let* ((y #f)) 'never) 'done)))
(test-equal "and-let* inside a lambda body" 12
            ((lambda (n) (and-let* ((d (* n 2)) ((> d 0))) (* d 3))) 2))
(test-equal "and-let* inside a named let" 5
            (let loop ((n 5)) (and-let* (((> n 0))) n)))
(test-equal "and-let* inside guard, claw raises" 'caught
            (guard (e (#t 'caught)) (and-let* ((x (raise 'boom))) x)))
(test-equal "guard inside an and-let* claw" 'caught
            (and-let* ((x (guard (e (#t 'caught)) (raise 'boom)))) x))

;; A claw variable shadowing an outer binding of the same name.
(test-equal "claw variable shadows an outer binding" '(inner outer)
            (let ((x 'outer)) (list (and-let* ((x 'inner)) x) x)))

;;; --------------------------------------------------------------------
;;; Hygiene: the expansion is built from let/if/begin, so a use-site local
;;; binding of one of those names must not reach into it (R7RS 4.3.2).
;;; --------------------------------------------------------------------

(test-equal "a use-site local named `let' does not capture the expansion" 1
            (let ((let 5)) (and-let* ((x 1)) x)))
(test-equal "a use-site local named `and-let*' at an unrelated name is inert" 1
            (let ((unrelated 5)) (and-let* ((x 1)) x)))

;; FAIL: #2074 (a use-site local named after a syntactic keyword captures it
;; inside any macro template; `if' and `let' happen to be immune, `begin' is not)
;; (test-equal "a use-site local named `begin' does not capture the expansion" 1
;;             (let ((begin 5)) (and-let* ((x 1)) x)))

;;; --------------------------------------------------------------------
;;; #2073 -- an and-let* with claws and NO body must return the last claw's
;;; value, per the spec's own eval[ (AND-LET* (CLAW) ) ] = eval_claw[ CLAW ]
;;; rule. lib/srfi/2.sld now ends the recursion on the last claw, so all
;;; three claw shapes yield their value. Chibi 0.12.0 returns the claw value
;;; for every line below.
;;;
;;; The failure-path counterpart is pinned enabled just above/below, so this
;;; block isolates exactly the success value.
;;; --------------------------------------------------------------------

(test-equal "empty body, failing claw still yields #f" #f (and-let* ((x #f))))

(test-equal "empty body, (VARIABLE EXPRESSION) claw yields its value" 1
            (and-let* ((x 1))))
(test-equal "empty body, (VARIABLE EXPRESSION) claw yields a symbol" 'sym
            (and-let* ((x 'sym))))
(test-equal "empty body, (EXPRESSION) claw yields its value" 3
            (and-let* (((+ 1 2)))))
(test-equal "empty body, BOUND-VARIABLE claw yields its value" 5
            (let ((v 5)) (and-let* (v))))
(test-equal "empty body, two claws yields the last one's value" 2
            (and-let* ((x 1) (y 2))))
(test-equal "empty body, last claw is an (EXPRESSION)" 7
            (and-let* ((x 1) ((* x 7)))))
(test-equal "empty body, last claw is a BOUND-VARIABLE" 9
            (let ((v 9)) (and-let* ((x 1) v))))
;; A failing claw still short-circuits with no body: the value of a false
;; claw is #f, which is exactly what the and-let* must return.
(test-equal "empty body, failing last claw yields #f" #f
            (and-let* ((x 1) (y #f))))
(test-equal "empty body, a side-effecting (EXPRESSION) claw runs once" 1
            (let ((n 0))
              (and-let* (((begin (set! n (+ n 1)) 2))))
              n))

(let ((runner (test-runner-current)))
  (test-end "srfi-2")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
