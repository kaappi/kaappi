;; Regression test for #651: internal define-syntax leaks macro binding
;; past the body's scope.

(import (scheme base) (scheme write) (scheme process-context))

(define fail-count 0)
(define pass-count 0)

(define-syntax check
  (syntax-rules ()
    ((check name expected actual)
     (let ((e expected) (a actual))
       (if (equal? e a)
           (begin (set! pass-count (+ pass-count 1))
                  (display "  PASS  ") (display name) (newline))
           (begin (set! fail-count (+ fail-count 1))
                  (display "  FAIL  ") (display name)
                  (display " expected=") (write e)
                  (display " got=") (write a) (newline)))))))

;; 1. Leak define-syntax named "bar" from an unrelated scope
(let ()
  (define-syntax bar
    (syntax-rules ()
      ((bar x) 'leaked))))

;; 2. Now use bar as an ordinary internal-define procedure — must NOT
;;    see the leaked macro from the previous let.
(check "bar as procedure after prior macro scope"
  8
  (let ((x 5))
    (define foo (lambda (y) (bar x y)))
    (define bar (lambda (a b) (+ a b)))
    (foo 3)))

;; 3. Internal define-syntax should work within its own body
(check "internal define-syntax visible in body"
  'expanded
  (let ()
    (define-syntax my-mac
      (syntax-rules ()
        ((my-mac) 'expanded)))
    (my-mac)))

;; 4. Internal define-syntax should not leak to a later top-level expression
(check "internal define-syntax does not leak"
  42
  (let ()
    (define my-mac 42)
    my-mac))

;; 5. Mixed internal defines and define-syntax
(check "mixed internal define and define-syntax"
  15
  (let ()
    (define x 10)
    (define-syntax add-x
      (syntax-rules ()
        ((add-x y) (+ x y))))
    (add-x 5)))

;; 6. define-syntax in nested let bodies
(check "define-syntax in nested let does not leak to outer"
  99
  (begin
    (let ()
      (define-syntax zz
        (syntax-rules ()
          ((zz) 'inner))))
    (let ()
      (define zz 99)
      zz)))

;; 7. Multiple define-syntax in same body
(check "multiple define-syntax in same body"
  '(a b)
  (let ()
    (define-syntax mac-a
      (syntax-rules ()
        ((mac-a) 'a)))
    (define-syntax mac-b
      (syntax-rules ()
        ((mac-b) 'b)))
    (list (mac-a) (mac-b))))

;; 8. After the let, mac-a and mac-b should not exist as macros
(check "multiple define-syntax do not leak"
  '(1 2)
  (let ()
    (define mac-a 1)
    (define mac-b 2)
    (list mac-a mac-b)))

(newline)
(display pass-count) (display " pass, ")
(display fail-count) (display " fail") (newline)
(when (> fail-count 0) (exit 1))
