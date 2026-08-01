;;; Audit: lib/srfi/189.sld (SRFI 189 — Maybe and Either)
;;; Systematic audit v2, Phase 3.9 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 189, https://srfi.schemers.org/srfi-189/srfi-189.html
;;;
;;; SRFI 189 specifies 82 identifiers. lib/srfi/189.sld exports 24, of which
;;; 23 are spec names — 59 are missing, and several of the 23 present ones
;;; have a narrower signature than the spec requires. `(cond-expand (srfi-189
;;; ...))` and `(cond-expand ((library (srfi 189)) ...))` both answer yes, so
;;; portable code has no way to detect the gap. Filed as #2087; the assertions
;;; that pin it are disabled below.
;;;
;;; What IS implemented is asserted here against the spec, including the three
;;; monad laws as properties (left identity, right identity, associativity)
;;; rather than case by case.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi189-audit.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 189))

(test-begin "srfi189 audit")

(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k #t)) (lambda () (thunk) #f)))))

;;; ------------------------------------------------------------------
;;; Constructors and predicates
;;; ------------------------------------------------------------------

(test-assert "just? on a Just" (just? (just 1)))
(test-assert "just? on Nothing" (not (just? (nothing))))
(test-assert "nothing? on Nothing" (nothing? (nothing)))
(test-assert "nothing? on a Just" (not (nothing? (just 1))))
(test-assert "maybe? on a Just" (maybe? (just 1)))
(test-assert "maybe? on Nothing" (maybe? (nothing)))
(test-assert "maybe? on a plain value" (not (maybe? 1)))
(test-assert "maybe? on an Either" (not (maybe? (right 1))))
;; "There is only one Nothing object."
(test-assert "the Nothing object is unique" (eq? (nothing) (nothing)))
(test-assert "a Just is not eq? to another Just of the same payload"
             (not (eq? (just 1) (just 1))))
(test-assert "right? on a Right" (right? (right 1)))
(test-assert "right? on a Left" (not (right? (left 1))))
(test-assert "left? on a Left" (left? (left 1)))
(test-assert "left? on a Right" (not (left? (right 1))))
(test-assert "either? on a Right" (either? (right 1)))
(test-assert "either? on a Left" (either? (left 1)))
(test-assert "either? on a plain value" (not (either? 1)))
(test-assert "either? on a Maybe" (not (either? (just 1))))
(test-assert "a Just can hold #f" (just? (just #f)))
(test-assert "a Just holding #f is not Nothing" (not (nothing? (just #f))))
(test-assert "a Left can hold #f" (left? (left #f)))

;;; ------------------------------------------------------------------
;;; Accessors
;;; ------------------------------------------------------------------

(test-equal "maybe-ref on a Just yields the payload" 5 (maybe-ref (just 5)))
(test-assert "maybe-ref on Nothing raises" (raises? (lambda () (maybe-ref (nothing)))))
(test-equal "maybe-ref/default on a Just" 5 (maybe-ref/default (just 5) 0))
(test-equal "maybe-ref/default on Nothing" 0 (maybe-ref/default (nothing) 0))
(test-equal "maybe-ref/default on a Just holding #f" #f (maybe-ref/default (just #f) 0))
(test-equal "either-ref on a Right yields the payload" 5 (either-ref (right 5)))
(test-assert "either-ref on a Left raises" (raises? (lambda () (either-ref (left 'e)))))
(test-equal "either-ref/default on a Right" 5 (either-ref/default (right 5) 0))
(test-equal "either-ref/default on a Left" 0 (either-ref/default (left 'e) 0))

;; The spec's signatures are (maybe-ref maybe failure [success]) and
;; (either-ref either failure [success]) — the failure argument is REQUIRED
;; and the success argument transforms the payload.
;; FAIL: #2087 (maybe-ref/either-ref take only the container)
;; (test-equal "maybe-ref calls failure on Nothing"
;;             'gone (maybe-ref (nothing) (lambda () 'gone)))
;; FAIL: #2087
;; (test-equal "maybe-ref applies success to the payload of a Just"
;;             10 (maybe-ref (just 5) (lambda () 'gone) (lambda (x) (* x 2))))
;; FAIL: #2087
;; (test-equal "either-ref passes the Left payload to failure"
;;             'e (either-ref (left 'e) (lambda (x) x)))
;; FAIL: #2087
;; (test-equal "either-ref applies success to the payload of a Right"
;;             10 (either-ref (right 5) (lambda (x) x) (lambda (x) (* x 2))))

;;; ------------------------------------------------------------------
;;; Monad laws, asserted as properties rather than case by case.
;;;   left identity   (bind (unit a) f)   == (f a)
;;;   right identity  (bind m unit)       == m
;;;   associativity   (bind (bind m f) g) == (bind m (lambda (x) (bind (f x) g)))
;;; ------------------------------------------------------------------

(define (mdouble x) (just (* 2 x)))
(define (minc x) (just (+ 1 x)))
(define (mfail x) (nothing))
(define (edouble x) (right (* 2 x)))
(define (einc x) (right (+ 1 x)))
(define (efail x) (left 'boom))

(define (maybe-same? a b)
  (or (and (nothing? a) (nothing? b))
      (and (just? a) (just? b) (equal? (maybe-ref a) (maybe-ref b)))))
(define (either-same? a b)
  (or (and (left? a) (left? b) (equal? (either-ref/default a 'L) (either-ref/default b 'L)))
      (and (right? a) (right? b) (equal? (either-ref b) (either-ref a)))))

(for-each
 (lambda (v)
   (let ((label (number->string v)))
     (test-assert (string-append "Maybe left identity at " label)
                  (maybe-same? (maybe-bind (just v) mdouble) (mdouble v)))
     (test-assert (string-append "Maybe left identity with a failing mproc at " label)
                  (maybe-same? (maybe-bind (just v) mfail) (mfail v)))
     (test-assert (string-append "Maybe right identity at " label)
                  (maybe-same? (maybe-bind (just v) just) (just v)))
     (test-assert (string-append "Maybe associativity at " label)
                  (maybe-same? (maybe-bind (maybe-bind (just v) mdouble) minc)
                               (maybe-bind (just v) (lambda (x) (maybe-bind (mdouble x) minc)))))
     (test-assert (string-append "Maybe associativity with a failing first step at " label)
                  (maybe-same? (maybe-bind (maybe-bind (just v) mfail) minc)
                               (maybe-bind (just v) (lambda (x) (maybe-bind (mfail x) minc)))))
     (test-assert (string-append "Maybe associativity with a failing second step at " label)
                  (maybe-same? (maybe-bind (maybe-bind (just v) mdouble) mfail)
                               (maybe-bind (just v) (lambda (x) (maybe-bind (mdouble x) mfail)))))
     (test-assert (string-append "Either left identity at " label)
                  (either-same? (either-bind (right v) edouble) (edouble v)))
     (test-assert (string-append "Either left identity with a failing mproc at " label)
                  (either-same? (either-bind (right v) efail) (efail v)))
     (test-assert (string-append "Either right identity at " label)
                  (either-same? (either-bind (right v) right) (right v)))
     (test-assert (string-append "Either associativity at " label)
                  (either-same? (either-bind (either-bind (right v) edouble) einc)
                                (either-bind (right v) (lambda (x) (either-bind (edouble x) einc)))))
     (test-assert (string-append "Either associativity with a failing first step at " label)
                  (either-same? (either-bind (either-bind (right v) efail) einc)
                                (either-bind (right v) (lambda (x) (either-bind (efail x) einc)))))))
 '(0 1 2 7 100))

;; Functor laws, likewise as properties.
(for-each
 (lambda (v)
   (let ((label (number->string v)))
     (test-assert (string-append "maybe-map preserves identity at " label)
                  (maybe-same? (maybe-map (lambda (x) x) (just v)) (just v)))
     (test-assert (string-append "maybe-map composes at " label)
                  (maybe-same? (maybe-map (lambda (x) (+ 1 (* 2 x))) (just v))
                               (maybe-map (lambda (x) (+ 1 x)) (maybe-map (lambda (x) (* 2 x)) (just v)))))
     (test-assert (string-append "either-map preserves identity at " label)
                  (either-same? (either-map (lambda (x) x) (right v)) (right v)))
     (test-assert (string-append "either-map composes at " label)
                  (either-same? (either-map (lambda (x) (+ 1 (* 2 x))) (right v))
                                (either-map (lambda (x) (+ 1 x))
                                            (either-map (lambda (x) (* 2 x)) (right v)))))))
 '(0 1 2 7 100))

;;; ------------------------------------------------------------------
;;; bind / map short-circuiting
;;; ------------------------------------------------------------------

(test-assert "maybe-bind on Nothing does not call the mproc"
             (nothing? (maybe-bind (nothing) (lambda (x) (error "should not run")))))
(test-assert "either-bind on a Left does not call the mproc"
             (left? (either-bind (left 'e) (lambda (x) (error "should not run")))))
;; The Left payload cannot be read back at all through the exported surface:
;; either-ref/default returns its own default for a Left, and the two spec
;; procedures that WOULD expose it (either-ref with a failure procedure, and
;; either-swap) are among the 59 missing names -- see #2087.
(test-equal "either-ref/default on a Left returns the default, not the payload"
            'other (either-ref/default (either-bind (left 'e) right) 'other))
(test-assert "maybe-map on Nothing does not call the proc"
             (nothing? (maybe-map (lambda (x) (error "should not run")) (nothing))))
(test-assert "either-map on a Left does not call the proc"
             (left? (either-map (lambda (x) (error "should not run")) (left 'e))))
(test-assert "either-map returns a Left unchanged, by identity"
             (let ((l (left 'e))) (eq? l (either-map (lambda (x) x) l))))
(test-assert "either-bind returns a Left unchanged, by identity"
             (let ((l (left 'e))) (eq? l (either-bind l right))))
(test-equal "maybe-map applies the proc to a Just" 6 (maybe-ref (maybe-map (lambda (x) (* 2 x)) (just 3))))
(test-equal "either-map applies the proc to a Right" 6 (either-ref (either-map (lambda (x) (* 2 x)) (right 3))))

;; FAIL: #2087 (maybe-bind/either-bind accept only one mproc)
;; (test-equal "maybe-bind chains several mprocs"
;;             7 (maybe-ref (maybe-bind (just 3) mdouble minc)))
;; FAIL: #2087
;; (test-equal "either-bind chains several mprocs"
;;             7 (either-ref (either-bind (right 3) edouble einc)))

;; Discriminating control: chaining by hand through nested single-mproc binds
;; gives the value the variadic form would.
(test-equal "chaining two binds by hand yields the same value"
            7 (maybe-ref (maybe-bind (maybe-bind (just 3) mdouble) minc)))

;;; ------------------------------------------------------------------
;;; filter
;;; ------------------------------------------------------------------

(test-assert "maybe-filter keeps a Just whose payload passes"
             (just? (maybe-filter even? (just 2))))
(test-equal "maybe-filter keeps the payload" 2 (maybe-ref (maybe-filter even? (just 2))))
(test-assert "maybe-filter drops a Just whose payload fails"
             (nothing? (maybe-filter even? (just 3))))
(test-assert "maybe-filter on Nothing is Nothing" (nothing? (maybe-filter even? (nothing))))
(test-assert "either-filter keeps a Right whose payload passes"
             (right? (either-filter even? (right 2))))
(test-assert "either-filter turns a failing Right into a Left"
             (left? (either-filter even? (right 3))))
(test-assert "either-filter on a Left is a Left" (left? (either-filter even? (left 'e))))

;; The spec's signature is (either-filter pred either obj) — obj is the payload
;; of the Left produced when the predicate fails.
;; FAIL: #2087 (either-filter takes no Left payload; it synthesises its own)
;; (test-equal "either-filter uses the supplied object as the Left payload"
;;             'nope (either-ref/default (either-filter even? (right 3) 'nope) 'other))

;;; ------------------------------------------------------------------
;;; Values conversion
;;; ------------------------------------------------------------------

(test-equal "maybe->values on a Just yields one value"
            '(5) (call-with-values (lambda () (maybe->values (just 5))) list))
(test-equal "maybe->values on Nothing yields no values"
            '() (call-with-values (lambda () (maybe->values (nothing))) list))
(test-equal "values->maybe of one value is a Just" 5 (maybe-ref (values->maybe 5)))
(test-assert "values->maybe of no values is Nothing" (nothing? (values->maybe)))
(test-assert "values->maybe round trips a Just"
             (maybe-same? (just 5) (call-with-values (lambda () (maybe->values (just 5))) values->maybe)))
(test-assert "values->maybe round trips Nothing"
             (maybe-same? (nothing)
                          (call-with-values (lambda () (maybe->values (nothing))) values->maybe)))
(test-equal "either->values on a Right yields one value"
            '(5) (call-with-values (lambda () (either->values (right 5))) list))
(test-equal "either->values on a Left yields no values"
            '() (call-with-values (lambda () (either->values (left 5))) list))

;;; ------------------------------------------------------------------
;;; Export completeness. SRFI 189 specifies 82 identifiers; 59 are absent.
;;; Each disabled assertion below names one representative from a distinct
;;; group of the spec's own table of contents.
;;; ------------------------------------------------------------------

;; FAIL: #2087 (maybe= / either= — the "Predicates" group)
;; (test-assert "maybe= compares two Maybes" (maybe= eqv? (just 1) (just 1)))
;; FAIL: #2087 (maybe-join / either-join — the "Join and bind" group)
;; (test-equal "maybe-join flattens a nested Just" 1 (maybe-ref (maybe-join (just (just 1)))))
;; FAIL: #2087 (either-swap — the "Constructors" group)
;; (test-assert "either-swap turns a Right into a Left" (left? (either-swap (right 1))))
;; FAIL: #2087 (maybe->either / either->maybe — protocol conversion between the two types)
;; (test-assert "maybe->either converts a Just to a Right" (right? (maybe->either (just 1) 'e)))
;; FAIL: #2087 (list->maybe / maybe->list — the list protocol)
;; (test-equal "list->maybe of a one-element list is a Just" 1 (maybe-ref (list->maybe '(1))))
;; FAIL: #2087 (maybe-length / either-length — the "Sequence operations" group)
;; (test-equal "maybe-length of a Just is 1" 1 (maybe-length (just 1)))
;; FAIL: #2087 (maybe-fold / maybe-unfold / maybe-for-each — the "Map, fold, unfold" group)
;; (test-equal "maybe-fold folds over the payload" 6 (maybe-fold + 5 (just 1)))
;; FAIL: #2087 (maybe-if / maybe-and / maybe-or / maybe-let* — the "Syntax" group)
;; (test-equal "maybe-if branches on a Just" 'yes (maybe-if (just 1) 'yes 'no))
;; FAIL: #2087 (tri-not / tri=? / tri-and / tri-or / tri-merge — the "Trivalent logic" group)
;; (test-assert "tri-not negates a Just #t" (not (maybe-ref (tri-not (just #t)))))
;; FAIL: #2087 (exception->either — the "Protocol conversion" group)
;; (test-assert "exception->either catches a raise into a Left"
;;              (left? (exception->either error? (lambda () (error "boom")))))

;; Discriminating control: the SRFI answers "available" to both feature tests,
;; so a portable program cannot detect the missing 59 names.
(test-assert "cond-expand reports the srfi-189 feature identifier"
             (cond-expand (srfi-189 #t) (else #f)))
(test-assert "cond-expand reports (library (srfi 189)) as available"
             (cond-expand ((library (srfi 189)) #t) (else #f)))

;;; `either` appears in the library's export clause but is never defined in its
;;; body, so it is a phantom export: Kaappi silently skips an export naming an
;;; identifier that is not in lib_env, and a program that imports it gets an
;;; undefined-variable error at the point of USE, not of import. Part of #2087.
;; FAIL: #2087 (`either` is exported but never defined)
;; (test-assert "the exported `either` is bound" (procedure? either))

(let ((runner (test-runner-current)))
  (test-end "srfi189 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
