;;; Audit: lib/srfi/189.sld (SRFI 189 — Maybe and Either)
;;; Systematic audit v2, Phase 3.9 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 189, https://srfi.schemers.org/srfi-189/srfi-189.html
;;;
;;; SRFI 189 specifies 82 identifiers; lib/srfi/189.sld exports all 82 with the
;;; spec's signatures (as of #2087). The audit previously pinned a 59-name gap,
;;; four wrong signatures, and a phantom `either` export; those assertions are
;;; now live regression tests. The three monad laws (left identity, right
;;; identity, associativity) and both functor laws are asserted as properties
;;; rather than case by case.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi189-audit.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 189))

(test-begin "srfi189 audit")

(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k #t)) (lambda () (thunk) #f)))))

(define (ok? thunk) (guard (e (#t #f)) (thunk) #t))

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

(test-equal "maybe-ref on a Just yields the payload"
            5 (maybe-ref (just 5) (lambda () 'gone)))
(test-equal "maybe-ref on Nothing calls failure"
            'gone (maybe-ref (nothing) (lambda () 'gone)))
(test-equal "maybe-ref/default on a Just" 5 (maybe-ref/default (just 5) 0))
(test-equal "maybe-ref/default on Nothing" 0 (maybe-ref/default (nothing) 0))
(test-equal "maybe-ref/default on a Just holding #f" #f (maybe-ref/default (just #f) 0))
(test-equal "either-ref on a Right yields the payload"
            5 (either-ref (right 5) (lambda (x) x)))
(test-equal "either-ref on a Left calls failure with the payload"
            'e (either-ref (left 'e) (lambda (x) x)))
(test-equal "either-ref/default on a Right" 5 (either-ref/default (right 5) 0))
(test-equal "either-ref/default on a Left" 0 (either-ref/default (left 'e) 0))

;; The spec's signatures are (maybe-ref maybe failure [success]) and
;; (either-ref either failure [success]) — the failure argument is REQUIRED
;; and the success argument transforms the payload.
(test-equal "maybe-ref calls failure on Nothing"
            'gone (maybe-ref (nothing) (lambda () 'gone)))
(test-equal "maybe-ref applies success to the payload of a Just"
            10 (maybe-ref (just 5) (lambda () 'gone) (lambda (x) (* x 2))))
(test-equal "either-ref passes the Left payload to failure"
            'e (either-ref (left 'e) (lambda (x) x)))
(test-equal "either-ref applies success to the payload of a Right"
            10 (either-ref (right 5) (lambda (x) x) (lambda (x) (* x 2))))

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
      (and (just? a) (just? b)
           (equal? (maybe-ref a (lambda () 'gone)) (maybe-ref b (lambda () 'gone))))))
(define (either-same? a b)
  (or (and (left? a) (left? b) (equal? (either-ref/default a 'L) (either-ref/default b 'L)))
      (and (right? a) (right? b)
           (equal? (either-ref a (lambda (x) x)) (either-ref b (lambda (x) x))))))

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
;; either-ref/default returns its own default for a Left; the payload is read
;; back with (either-ref either failure) or either-swap, both asserted below.
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
(test-equal "maybe-map applies the proc to a Just"
            6 (maybe-ref (maybe-map (lambda (x) (* 2 x)) (just 3)) (lambda () 'gone)))
(test-equal "either-map applies the proc to a Right"
            6 (either-ref (either-map (lambda (x) (* 2 x)) (right 3)) (lambda (x) x)))

;; The spec's signatures are (maybe-bind maybe mproc1 mproc2 ...) and
;; (either-bind either mproc1 mproc2 ...) — bind is variadic in the mprocs.
(test-equal "maybe-bind chains several mprocs"
            7 (maybe-ref (maybe-bind (just 3) mdouble minc) (lambda () 'gone)))
(test-equal "either-bind chains several mprocs"
            7 (either-ref (either-bind (right 3) edouble einc) (lambda (x) x)))
(test-assert "maybe-bind on Nothing with several mprocs is Nothing"
             (nothing? (maybe-bind (nothing) mdouble minc)))
(test-assert "either-bind on a Left with several mprocs returns the Left"
             (left? (either-bind (left 'e) edouble einc)))
(test-equal "maybe-compose composes mprocs"
            11 (maybe-ref ((maybe-compose mdouble minc) 5) (lambda () 'gone)))
(test-equal "either-compose composes mprocs"
            11 (either-ref ((either-compose edouble einc) 5) (lambda (x) x)))
(test-assert "maybe-compose short-circuits on Nothing"
             (nothing? ((maybe-compose mdouble mfail minc) 5)))
(test-assert "either-compose short-circuits on a Left"
             (left? ((either-compose edouble efail einc) 5)))

;; Chaining by hand through nested single-mproc binds gives the value the
;; variadic form would.
(test-equal "chaining two binds by hand yields the same value"
            7 (maybe-ref (maybe-bind (maybe-bind (just 3) mdouble) minc) (lambda () 'gone)))

;;; ------------------------------------------------------------------
;;; filter
;;; ------------------------------------------------------------------

(test-assert "maybe-filter keeps a Just whose payload passes"
             (just? (maybe-filter even? (just 2))))
(test-equal "maybe-filter keeps the payload"
            2 (maybe-ref (maybe-filter even? (just 2)) (lambda () 'gone)))
(test-assert "maybe-filter drops a Just whose payload fails"
             (nothing? (maybe-filter even? (just 3))))
(test-assert "maybe-filter on Nothing is Nothing" (nothing? (maybe-filter even? (nothing))))
(test-assert "maybe-remove drops a Just whose payload passes"
             (nothing? (maybe-remove even? (just 2))))
(test-assert "maybe-remove keeps a Just whose payload fails"
             (just? (maybe-remove even? (just 3))))
(test-assert "maybe-remove on Nothing is Nothing" (nothing? (maybe-remove even? (nothing))))
(test-assert "either-filter keeps a Right whose payload passes"
             (right? (either-filter even? (right 2))))
(test-assert "either-filter turns a failing Right into a Left"
             (left? (either-filter even? (right 3))))
(test-assert "either-filter on a Left is a Left" (left? (either-filter even? (left 'e))))

;; The spec's signature is (either-filter pred either obj ...) — the objs are
;; the payload of the Left produced when the predicate fails.
(test-equal "either-filter uses the supplied object as the Left payload"
            'nope (either-ref (either-filter even? (right 3) 'nope) (lambda (x) x)))
(test-equal "either-filter without objs makes an empty Left"
            'other (either-ref/default (either-filter even? (right 3)) 'other))
(test-assert "either-remove turns a passing Right into a Left of the objs"
             (left? (either-remove even? (right 2) 'nope)))
(test-assert "either-remove keeps a failing Right"
             (right? (either-remove even? (right 3) 'nope)))

;;; ------------------------------------------------------------------
;;; Values conversion
;;; ------------------------------------------------------------------

(test-equal "maybe->values on a Just yields one value"
            '(5) (call-with-values (lambda () (maybe->values (just 5))) list))
(test-equal "maybe->values on Nothing yields no values"
            '() (call-with-values (lambda () (maybe->values (nothing))) list))
;; The spec's signature is (values->maybe producer) — it invokes the producer
;; and wraps whatever values it returns.
(test-equal "values->maybe of a one-value producer is a Just"
            5 (maybe-ref (values->maybe (lambda () 5)) (lambda () 'gone)))
(test-assert "values->maybe of a zero-value producer is Nothing"
             (nothing? (values->maybe (lambda () (values)))))
(test-assert "values->maybe round trips a Just"
             (maybe-same? (just 5) (values->maybe (lambda () (maybe->values (just 5))))))
(test-assert "values->maybe round trips Nothing"
             (maybe-same? (nothing) (values->maybe (lambda () (maybe->values (nothing))))))
(test-equal "either->values on a Right yields one value"
            '(5) (call-with-values (lambda () (either->values (right 5))) list))
(test-equal "either->values on a Left yields no values"
            '() (call-with-values (lambda () (either->values (left 5))) list))
(test-equal "values->either of a one-value producer is a Right"
            5 (either-ref (values->either (lambda () 5) 'nope) (lambda (x) x)))
(test-assert "values->either of a zero-value producer is a Left of the objs"
             (left? (values->either (lambda () (values)) 'nope)))

;;; ------------------------------------------------------------------
;;; Export completeness. SRFI 189 specifies 82 identifiers; lib/srfi/189.sld
;;; exports all of them (as of #2087). One representative assertion per group
;;; of the spec's own table of contents pins the surface; the group bodies are
;;; exercised above and in this section.
;;; ------------------------------------------------------------------

(test-assert "maybe= compares two Maybes" (maybe= eqv? (just 1) (just 1)))
(test-assert "either= compares two Eithers" (either= eqv? (right 1) (right 1)))
(test-assert "maybe-join flattens a nested Just"
             (maybe-same? (maybe-join (just (just 1))) (just 1)))
(test-assert "either-join flattens a nested Right"
             (either-same? (either-join (right (right 1))) (right 1)))
(test-assert "maybe-join on Nothing is Nothing" (nothing? (maybe-join (nothing))))
(test-assert "maybe-join on a non-Maybe payload raises"
             (raises? (lambda () (maybe-join (just 5)))))
(test-assert "either-swap turns a Right into a Left" (left? (either-swap (right 1))))
(test-equal "either-swap exposes a Left's payload"
            5 (either-ref (either-swap (left 5)) (lambda (x) x)))
(test-assert "maybe->either converts a Just to a Right"
             (right? (maybe->either (just 1) 'e)))
(test-equal "maybe->either turns Nothing into a Left of the objs"
            'e (either-ref (maybe->either (nothing) 'e) (lambda (x) x)))
(test-assert "either->maybe converts a Right to a Just"
             (just? (either->maybe (right 1))))
(test-assert "either->maybe turns a Left into Nothing"
             (nothing? (either->maybe (left 1))))
(test-equal "list->maybe of a one-element list is a Just"
            1 (maybe-ref (list->maybe '(1)) (lambda () 'gone)))
(test-assert "list->maybe of the empty list is Nothing" (nothing? (list->maybe '())))
(test-assert "list->either of the empty list is a Left of the objs"
             (left? (list->either '() 'nope)))
(test-assert "list->right wraps the elements" (right? (list->right '(1 2))))
(test-assert "list->left wraps the elements" (left? (list->left '(1 2))))
(test-equal "maybe->list of a Just is its payload"
            '(1 2) (maybe->list (just 1 2)))
(test-equal "maybe->list of Nothing is the empty list" '() (maybe->list (nothing)))
(test-equal "mutating a maybe->list result does not corrupt the Just"
            '(1 2) (let ((m (just 1 2)))
                    (set-car! (maybe->list m) 'x)
                    (maybe->list m)))
(test-equal "either->list of a Left is its payload" '(1 2) (either->list (left 1 2)))
(test-equal "maybe->truth of a Just is the payload" 5 (maybe->truth (just 5)))
(test-assert "maybe->truth of Nothing is #f" (not (maybe->truth (nothing))))
(test-assert "truth->maybe of #f is Nothing" (nothing? (truth->maybe #f)))
(test-equal "truth->maybe of a value is a Just"
            7 (maybe-ref (truth->maybe 7) (lambda () 'gone)))
(test-assert "truth->either of #f is a Left of the objs"
             (left? (truth->either #f 'nope)))
(test-equal "maybe->list-truth of a Just is its payload" '(1) (maybe->list-truth (just 1)))
(test-assert "maybe->list-truth of Nothing is #f" (not (maybe->list-truth (nothing))))
(test-equal "list-truth->maybe of a list is a Just of its elements"
            '(1 2) (maybe->list (list-truth->maybe '(1 2))))
(test-assert "list-truth->either of #f is a Left of the objs"
             (left? (list-truth->either #f 'nope)))
(test-equal "maybe->generation of a Just is the payload" 5 (maybe->generation (just 5)))
(test-assert "maybe->generation of Nothing is an eof-object"
             (eof-object? (maybe->generation (nothing))))
(test-assert "generation->maybe of an eof-object is Nothing"
             (nothing? (generation->maybe (eof-object))))
(test-equal "generation->either of an eof-object is a Left of the objs"
            'nope (either-ref (generation->either (eof-object) 'nope) (lambda (x) x)))
(test-equal "maybe->two-values of a Just is payload and #t"
            '(5 #t) (call-with-values (lambda () (maybe->two-values (just 5))) list))
(test-equal "maybe->two-values of Nothing is #f and #f"
            '(#f #f) (call-with-values (lambda () (maybe->two-values (nothing))) list))
(test-equal "two-values->maybe of a true second value is a Just"
            5 (maybe-ref (two-values->maybe (lambda () (values 5 #t))) (lambda () 'gone)))
(test-assert "two-values->maybe of a false second value is Nothing"
             (nothing? (two-values->maybe (lambda () (values 5 #f)))))
(test-assert "exception->either catches a matching raise into a Left"
             (left? (exception->either error-object? (lambda () (error "boom")))))
(test-assert "exception->either reraises a non-matching raise"
             (raises? (lambda () (exception->either (lambda (e) #f) (lambda () (raise 'x))))))
(test-equal "maybe-length of a Just is 1" 1 (maybe-length (just 1)))
(test-equal "maybe-length of Nothing is 0" 0 (maybe-length (nothing)))
(test-equal "either-length of a Right is 1" 1 (either-length (right 1)))
(test-equal "either-length of a Left is 0" 0 (either-length (left 1)))
(test-equal "maybe-fold folds over the payload" 6 (maybe-fold + 5 (just 1)))
(test-equal "maybe-fold on Nothing returns nil" 5 (maybe-fold + 5 (nothing)))
(test-equal "either-fold folds over the payload" 6 (either-fold + 5 (right 1)))
(test-assert "maybe-unfold stops with Nothing"
             (nothing? (maybe-unfold (lambda (x) (= x 1)) (lambda (x) x)
                                     (lambda (x) x) 1)))
(test-equal "maybe-unfold maps the seed when the successor stops"
            20 (maybe-ref (maybe-unfold (lambda (x) (> x 1)) (lambda (x) (* x 20))
                                        (lambda (x) (+ x 1)) 1)
                          (lambda () 'gone)))
(test-assert "maybe-for-each applies proc to a Just"
             (let ((seen '())) (maybe-for-each (lambda (x) (set! seen x)) (just 9))
               (eq? seen 9)))
(test-assert "either-for-each applies proc to a Right"
             (let ((seen '())) (either-for-each (lambda (x) (set! seen x)) (right 9))
               (eq? seen 9)))
(test-equal "maybe-if branches on a Just" 'yes (maybe-if (just 1) 'yes 'no))
(test-equal "maybe-if branches on Nothing" 'no (maybe-if (nothing) 'yes 'no))
(test-assert "maybe-if raises on a non-Maybe"
             (raises? (lambda () (maybe-if 5 'yes 'no))))
(test-equal "maybe-and returns the last Just"
            2 (maybe-ref (maybe-and (just 1) (just 2)) (lambda () 'gone)))
(test-assert "maybe-and with no args is a Just" (just? (maybe-and)))
(test-assert "maybe-and short-circuits on Nothing"
             (nothing? (maybe-and (just 1) (nothing) (error "no"))))
(test-equal "maybe-or returns the first Just"
            1 (maybe-ref (maybe-or (nothing) (just 1)) (lambda () 'gone)))
(test-assert "maybe-or with no args is Nothing" (nothing? (maybe-or)))
(test-equal "either-and returns the last Right"
            2 (either-ref (either-and (right 1) (right 2)) (lambda (x) x)))
(test-assert "either-and with no args is a Right" (right? (either-and)))
(test-assert "either-or returns the first Right"
             (right? (either-or (left 'a) (right 1))))
(test-assert "either-or with no args is a Left" (left? (either-or)))
(test-equal "maybe-let* binds and wraps the body"
            7 (maybe-ref (maybe-let* ((x (just 3)) (y (just (+ x 1)))) (+ x y))
                         (lambda () 'gone)))
(test-assert "maybe-let* short-circuits on Nothing"
             (nothing? (maybe-let* ((x (just 3)) (y (nothing))) (+ x y))))
(test-equal "either-let* binds and wraps the body"
            7 (either-ref (either-let* ((x (right 3)) (y (right (+ x 1)))) (+ x y))
                          (lambda (x) x)))
(test-equal "maybe-let*-values binds formals"
            3 (maybe-ref (maybe-let*-values (((a b) (just 1 2))) (+ a b))
                         (lambda () 'gone)))
(test-equal "either-let*-values binds formals"
            3 (either-ref (either-let*-values (((a b) (right 1 2))) (+ a b))
                          (lambda (x) x)))
(test-assert "either-guard catches a matching raise into a Left"
             (left? (either-guard error-object? (error "boom"))))
(test-equal "either-guard wraps body values in a Right"
            3 (either-ref (either-guard error-object? (+ 1 2)) (lambda (x) x)))
(test-assert "either-guard reraises a non-matching raise"
             (raises? (lambda () (either-guard (lambda (e) #f) (raise 'x)))))
(test-assert "tri-not negates a Just #t"
             (not (maybe-ref (tri-not (just #t)) (lambda () 'gone))))
(test-equal "tri-not on Nothing is Nothing"
            'gone (maybe-ref (tri-not (nothing)) (lambda () 'gone)))
(test-assert "tri=? on equal truth values is Just #t"
             (maybe-ref (tri=? (just #t) (just 1)) (lambda () 'gone)))
(test-equal "tri-and of true values is Just #t"
            #t (maybe-ref (tri-and (just 1) (just 2)) (lambda () 'gone)))
(test-assert "tri-or of false values is Just #f"
             (not (maybe-ref (tri-or (just #f) (just #f)) (lambda () 'gone))))
(test-assert "tri-and returns the first false"
             (let ((r (tri-and (just #t) (just #f))))
               (and (just? r) (not (maybe-ref r (lambda () 'gone))))))
(test-assert "tri-merge returns the first Just"
             (just? (tri-merge (nothing) (just 1))))
(test-assert "tri-merge of all Nothings is Nothing"
             (nothing? (tri-merge (nothing) (nothing))))
(test-equal "maybe-sequence collects a list of Justs"
            '((1) (2))
            (maybe-ref (maybe-sequence (list (just 1) (just 2)) map list)
                       (lambda () 'gone)))
(test-assert "maybe-sequence short-circuits on Nothing"
             (nothing? (maybe-sequence (list (just 1) (nothing)) map list)))
(test-equal "either-sequence collects a list of Rights"
            '((1) (2))
            (either-ref (either-sequence (list (right 1) (right 2)) map list)
                        (lambda (x) x)))
(test-assert "either-sequence short-circuits on a Left"
             (left? (either-sequence (list (right 1) (left 'e)) map list)))

;; Discriminating control: the SRFI answers "available" to both feature tests,
;; so feature detection cannot distinguish a partial implementation.
(test-assert "cond-expand reports the srfi-189 feature identifier"
             (cond-expand (srfi-189 #t) (else #f)))
(test-assert "cond-expand reports (library (srfi 189)) as available"
             (cond-expand ((library (srfi 189)) #t) (else #f)))

;;; `either` used to appear in the library's export clause without ever being
;;; defined in its body — a phantom export that Kaappi silently skipped, so a
;;; program importing it failed with `undefined variable 'either'` at the point
;;; of USE. Fixed in #2087; the name is no longer exported.
(test-assert "the phantom `either` is no longer exported"
             (not (ok? (lambda () either))))

(let ((runner (test-runner-current)))
  (test-end "srfi189 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
