;; Regression test: set! in a macro template targeting a free reference
;; to a global variable must mutate the global (R7RS 4.3.1 referential
;; transparency). The compiler injects a register alias for a template's
;; free non-procedure globals so references pierce use-site shadowing;
;; set! used to write only the alias register, silently losing the
;; update — the global kept its old value and no error was raised.
;; This also made counter-based test harness macros (e.g. the check
;; macro in tests/scheme/smoke/) report "0 pass, 0 fail" and never
;; flip the exit code on failure.
;;
;; check is deliberately a procedure, not a macro, so the harness
;; itself does not depend on the behavior under test.

(define fails 0)
(define (check name expected actual)
  (if (equal? expected actual)
      (begin (display "  PASS  ") (display name) (newline))
      (begin (set! fails (+ fails 1))
             (display "  FAIL  ") (display name)
             (display " expected=") (write expected)
             (display " got=") (write actual) (newline))))

;; 1. set! of a template-free global from a top-level macro use
(define count 0)
(define-syntax inc!
  (syntax-rules ()
    ((inc!) (set! count (+ count 1)))))
(inc!)
(inc!)
(check "top-level template set! of global" 2 count)

;; 2. Same expansion inside a lambda body
(define count2 0)
(define-syntax inc2!
  (syntax-rules ()
    ((inc2!) (set! count2 (+ count2 1)))))
(define (bump2) (inc2!))
(bump2)
(bump2)
(bump2)
(check "template set! of global inside lambda" 3 count2)

;; 3. Use-site shadowing: the template's set! must reach the global,
;;    and the use-site local of the same name must stay untouched
(define counter 0)
(define-syntax bump!
  (syntax-rules ()
    ((bump!) (set! counter (+ counter 1)))))
(define shadow-result
  (let ((counter 100))
    (bump!)
    counter))
(check "use-site local untouched by template set!" 100 shadow-result)
(check "global updated past use-site shadow" 1 counter)

;; 4. Read-after-write within a single expansion
(define acc 0)
(define-syntax twice!
  (syntax-rules ()
    ((twice!) (begin (set! acc (+ acc 1)) (set! acc (+ acc 1))))))
(twice!)
(check "read-after-write within one expansion" 2 acc)

;; 5. set! of a captured definition-site local keeps working
(check "template set! of sibling internal define" 2
  (let ()
    (define n 0)
    (define-syntax inc-n!
      (syntax-rules ()
        ((inc-n!) (set! n (+ n 1)))))
    (inc-n!)
    (inc-n!)
    n))

;; 6. Read of a sibling internal define from a template (the shape
;;    from tests/scheme/smoke/internal-define-syntax-scope.scm case 5)
(check "template reads sibling internal define" 15
  (let ()
    (define x 10)
    (define-syntax add-x
      (syntax-rules ()
        ((add-x y) (+ x y))))
    (add-x 5)))

(when (> fails 0) (exit 1))
