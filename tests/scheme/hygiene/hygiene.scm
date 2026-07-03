;;; Hygienic macros compliance tests
;;; Tests that syntax-rules macros correctly prevent variable capture.
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "hygiene")

;; -------------------------------------------------------------------------
;; 1. Classic or/my-or hygiene: macro's internal 'temp' must not capture
;;    a user variable also called 'temp'.
;; -------------------------------------------------------------------------

(define-syntax my-or
  (syntax-rules ()
    ((my-or) #f)
    ((my-or e) e)
    ((my-or e1 e2 ...)
     (let ((temp e1))
       (if temp temp (my-or e2 ...))))))

(test-group "my-or basics"
  (test-eqv "my-or no args" #f (my-or))
  (test-eqv "my-or single arg" 1 (my-or 1))
  (test-eqv "my-or false then value" 2 (my-or #f 2))
  (test-eqv "my-or true then value" 1 (my-or 1 2))
  (test-eqv "my-or two false then value" 3 (my-or #f #f 3)))

(test-group "my-or hygiene"
  ;; KEY HYGIENE TEST: user's 'temp' must not be captured by macro's 'temp'
  (test-eqv "user temp not captured (falsy first)" 42
    (let ((temp 42))
      (my-or #f temp)))

  ;; Another capture test: temp is the truthy value
  (test-eqv "user temp not captured (truthy first)" 99
    (let ((temp 99))
      (my-or temp 0))))

;; -------------------------------------------------------------------------
;; 2. swap! hygiene: macro's internal 'tmp' must not capture user's 'tmp'.
;; -------------------------------------------------------------------------

(define-syntax swap!
  (syntax-rules ()
    ((swap! a b)
     (let ((tmp a))
       (set! a b)
       (set! b tmp)))))

;; Basic swap with distinct names (top-level defines needed for set! in swap!)
(define x 10)
(define y 20)
(swap! x y)
(test-eqv "swap x" 20 x)
(test-eqv "swap y" 10 y)

(test-group "swap! hygiene"
  ;; KEY HYGIENE TEST: swap variables named 'tmp' and 'y'
  (test-equal "swap user tmp and y" '(2 1)
    (let ((tmp 1) (y 2))
      (swap! tmp y)
      (list tmp y))))

;; -------------------------------------------------------------------------
;; 3. Nested macro expansions with hygiene
;; -------------------------------------------------------------------------

(test-group "nested expansions"
  ;; Using my-or inside my-or (via recursive expansion)
  (test-eqv "deeply nested my-or" 77
    (my-or #f #f #f 77))

  ;; Nested let with same name as macro internal
  (test-eqv "nested my-or with user temp" 100
    (let ((temp 100))
      (my-or #f (my-or #f temp)))))

;; -------------------------------------------------------------------------
;; 4. Multiple macro invocations don't interfere
;; -------------------------------------------------------------------------

(test-group "multiple invocations"
  ;; Each invocation of my-or should get its own gensym for 'temp'
  (test-equal "independent invocations" '(10 10)
    (let ((temp 10))
      (let ((a (my-or #f temp))
            (b (my-or temp #f)))
        (list a b)))))

;; -------------------------------------------------------------------------
;; 5. Macros that don't introduce bindings work unchanged
;; -------------------------------------------------------------------------

(define-syntax my-if
  (syntax-rules ()
    ((my-if test then else)
     (if test then else))))

(test-group "non-binding macros"
  (test-eqv "my-if true" 1 (my-if #t 1 2))
  (test-eqv "my-if false" 2 (my-if #f 1 2)))

;; -------------------------------------------------------------------------
;; 6. Macros with literals still work
;; -------------------------------------------------------------------------

(define-syntax my-case
  (syntax-rules (is)
    ((my-case x is y)
     (if (= x y) #t #f))))

(test-group "macros with literals"
  (test-eqv "my-case equal" #t (my-case 3 is 3))
  (test-eqv "my-case not equal" #f (my-case 3 is 4)))

;; -------------------------------------------------------------------------
;; 7. Ellipsis-based macros still work
;; -------------------------------------------------------------------------

(define-syntax my-list
  (syntax-rules ()
    ((my-list e ...)
     (list e ...))))

(define-syntax my-begin
  (syntax-rules ()
    ((my-begin e1 e2 ...)
     (begin e1 e2 ...))))

(test-group "ellipsis macros"
  (test-equal "my-list" '(1 2 3) (my-list 1 2 3))
  (test-eqv "my-begin" 3 (my-begin 1 2 3)))

;; -------------------------------------------------------------------------
;; 8. Macro-generating macros (issue #919): identifiers renamed by the outer
;;    expansion and baked into the inner macro's template must not be renamed
;;    again when the inner macro expands, and inner pattern variables must
;;    shadow outer substitutions.
;; -------------------------------------------------------------------------

(define-syntax jabberwocky
  (syntax-rules ()
    ((_ hatter)
     (begin
       (define march-hare 42)
       (define-syntax hatter
         (syntax-rules ()
           ((_) march-hare)))))))
(jabberwocky mad-hatter)

(test-group "macro-generating macros"
  (test-eqv "inner macro sees outer expansion's binding" 42 (mad-hatter))
  (test-eqv "inner pattern variable shadows outer substitution" 'x
    (let ()
      (define-syntax foo
        (syntax-rules ()
          ((foo bar y)
           (define-syntax bar
             (syntax-rules ()
               ((bar x) 'y))))))
      (foo bar x)
      (bar 1))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "hygiene")
(if (> %test-fail-count 0) (exit 1))
