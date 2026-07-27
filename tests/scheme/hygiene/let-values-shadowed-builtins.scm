;; Regression test for #1715: let-values (and let*-values) desugar
;; internally to code that invokes `list`, `apply`, and `call-with-values`
;; by name. Before the fix those were ordinary (shadowable) identifier
;; references, so a program that rebinds any of them at the top level --
;; exactly what SRFI 101 does for `list` -- could silently corrupt
;; let-values's own bookkeeping instead of the compiler always meaning the
;; true (scheme base) procedures. The observed symptom was a spurious
;; "apply: expected proper list, got #<record_instance>" error: the
;; shadowed `list` handed back something other than a real list, and the
;; (correctly-resolved) `apply` then correctly rejected it.
;;
;; Can't use (srfi 64) here: its own test-equal/test-assert macros expand
;; into code that itself calls list/apply/call-with-values, so shadowing
;; those names at the top level -- the whole point of this test -- breaks
;; the test harness too. Manual pass/fail counters sidestep that,
;; matching hygiene/template-binds-builtin-name.scm's approach to the same
;; class of bug (a builtin name shadowed at the use site).

(define fails 0)
(define (check name expected actual)
  (if (equal? expected actual)
      (begin (display "  PASS  ") (display name) (newline))
      (begin (set! fails (+ fails 1))
             (display "  FAIL  ") (display name)
             (display " expected=") (write expected)
             (display " got=") (write actual) (newline))))

(define (two-values) (values 1 2))
(define (three-values) (values 1 2 3))

;; --- `list`: the per-binding producer-collection step is always
;; compiled non-tail, so this is unconditionally at risk. A record type
;; stands in for SRFI 101's random-access-list representation: if
;; let-values's desugaring called the shadowed `list` instead of the true
;; one, it would hand `apply` a record instance instead of a proper list,
;; and `apply` would (correctly) raise a type error.
(define-record-type <fake-list>
  (make-fake-list items)
  fake-list?
  (items fake-list-items))

(define real-list list)
(set! list (lambda args (make-fake-list args)))

(check "let-values, single binding, tail position"
  3
  (let ()
    (let-values (((a b) (two-values))) (+ a b))))

(check "let-values, single binding, non-tail position"
  103
  (+ 100 (let-values (((a b) (two-values))) (+ a b))))

(check "let-values, multiple bindings (inner apply chain)"
  14
  (let-values (((a b) (two-values)) ((c d e) (three-values)))
    (+ a b c d e 5)))

(check "let-values, rest formal binds the fixed part"
  1
  (let-values (((a . rest) (three-values))) a))

(check "let-values, rest formal binds the remainder as a real list"
  '(2 3)
  (let-values (((a . rest) (three-values))) rest))

(check "let-values, single symbol captures all values as a real list"
  '(1 2 3)
  (let-values ((all (three-values))) all))

(set! list real-list)

;; --- `apply`: only the outermost occurrence's tail-ness follows
;; let-values's own is_tail; nested occurrences (count > 1) are always
;; structurally tail-called and never look `apply` up by name at all.
(define real-apply apply)
(set! apply
  (lambda (proc lst)
    (set! fails (+ fails 1))
    (display "  FAIL  shadowed apply invoked by let-values") (newline)
    (real-apply proc lst)))

(define (apply-tail-case)
  (let-values (((a b) (two-values))) (+ a b)))
(define (apply-non-tail-case)
  (+ 100 (let-values (((a b) (two-values))) (+ a b))))

(check "let-values, tail position, does not invoke shadowed apply"
  3
  (apply-tail-case))
(check "let-values, non-tail position, does not invoke shadowed apply"
  103
  (apply-non-tail-case))

(set! apply real-apply)

;; --- `call-with-values`: referenced by both let-values (producer
;; collection, always non-tail) and let*-values (its whole desugaring).
(define real-cwv call-with-values)
(set! call-with-values
  (lambda (producer consumer)
    (set! fails (+ fails 1))
    (display "  FAIL  shadowed call-with-values invoked") (newline)
    (real-cwv producer consumer)))

(define (cwv-let-values-case)
  (let-values (((a b) (two-values))) (+ a b)))
(define (cwv-letstar-tail-case)
  (let*-values (((a b) (two-values))) (+ a b)))
(define (cwv-letstar-non-tail-case)
  (+ 100 (let*-values (((a b) (two-values))) (+ a b))))
(define (cwv-letstar-sequential-case)
  (let*-values (((a b) (two-values)) ((c) (values (+ a b))))
    (+ a b c)))

(check "let-values does not invoke shadowed call-with-values"
  3
  (cwv-let-values-case))
(check "let*-values, tail position, does not invoke shadowed call-with-values"
  3
  (cwv-letstar-tail-case))
(check "let*-values, non-tail position, does not invoke shadowed call-with-values"
  103
  (cwv-letstar-non-tail-case))
(check "let*-values, sequential bindings, does not invoke shadowed call-with-values"
  6
  (cwv-letstar-sequential-case))

(set! call-with-values real-cwv)

;; --- proper tail calls must survive the fix: a tail-recursive loop
;; built on let-values/let*-values must not grow the stack.
(define (loop-let-values n acc)
  (let-values (((q r) (values (- n 1) (+ acc 1))))
    (if (= q 0) r (loop-let-values q r))))
(check "let-values tail call stays a proper tail call" 200000 (loop-let-values 200000 0))

(define (loop-let-star-values n acc)
  (let*-values (((q) (- n 1))
                ((r) (values (+ acc 1))))
    (if (= q 0) r (loop-let-star-values q r))))
(check "let*-values tail call stays a proper tail call" 200000 (loop-let-star-values 200000 0))

(when (> fails 0) (exit 1))
