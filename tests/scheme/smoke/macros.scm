;;; Phase 5: Hygienic Macros Tests
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "macros")

;; 1. Simple alias macro
(define-syntax my-if
  (syntax-rules ()
    ((my-if test then else)
     (if test then else))))

(test-eqv "my-if true" 1 (my-if #t 1 2))
(test-eqv "my-if false" 2 (my-if #f 1 2))

;; 2. Constant macro
(define-syntax my-const
  (syntax-rules ()
    ((my-const) 42)))

(test-eqv "my-const" 42 (my-const))

;; 3. Ellipsis
(define-syntax my-begin
  (syntax-rules ()
    ((my-begin e1 e2 ...)
     (begin e1 e2 ...))))

(test-eqv "my-begin ellipsis" 3 (my-begin 1 2 3))

;; 4. my-list using ellipsis
(define-syntax my-list
  (syntax-rules ()
    ((my-list e ...)
     (list e ...))))

(test-equal "my-list ellipsis" '(1 2 3) (my-list 1 2 3))

;; 5. Multiple rules
(define-syntax my-and
  (syntax-rules ()
    ((my-and) #t)
    ((my-and x) x)
    ((my-and x y) (if x y #f))))

(test-eqv "my-and nullary" #t (my-and))
(test-eqv "my-and unary" 5 (my-and 5))
(test-eqv "my-and binary true" 3 (my-and 2 3))
(test-eqv "my-and binary false" #f (my-and #f 3))

;; 6. Literals
(define-syntax my-case
  (syntax-rules (is)
    ((my-case x is y)
     (if (= x y) #t #f))))

(test-eqv "my-case match" #t (my-case 3 is 3))
(test-eqv "my-case no match" #f (my-case 3 is 4))

;; 7. let-syntax
(test-eqv "let-syntax" 99
  (let-syntax ((my-const (syntax-rules () ((my-const) 99))))
    (my-const)))

;; 8. swap macro
(define-syntax my-swap
  (syntax-rules ()
    ((my-swap a b)
     (let ((tmp a))
       (set! a b)
       (set! b tmp)))))

(test-equal "swap macro" '(20 10)
  (let ((x 10) (y 20))
    (my-swap x y)
    (list x y)))

;; 9. Underscore wildcard
(define-syntax second
  (syntax-rules ()
    ((second _ x) x)))

(test-eqv "underscore wildcard" 2 (second 1 2))

;; 10. Zero ellipsis matches
(test-eqv "zero ellipsis matches" 42 (my-begin 42))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "macros")
(if (> %test-fail-count 0) (exit 1))
