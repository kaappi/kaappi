;; Regression tests for two expander bugs that broke Alex Shinn's
;; portable syntax-rules match (and any macro using the classic
;; let-syntax identifier/ellipsis detection tricks):
;;
;; 1. Outer pattern variables were filtered out of nested syntax-rules
;;    forms instead of substituted into them. R7RS template semantics
;;    substitute pattern variables everywhere, including nested
;;    syntax-rules patterns — that substitution is what makes the
;;    Kiselyov/Campbell "is this an identifier?" trick work.
;;
;; 2. instantiateLetBindings did not handle ellipsis in template
;;    binding lists, so (let ((var value) ...) . body) in a template
;;    failed to expand.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "nested-syntax-rules-subst")

;; --- Bug 1: substitution into nested syntax-rules patterns ---

;; Oleg Kiselyov's identifier test: x is substituted into the inner
;; pattern. An identifier acts as a pattern variable (matches the probe
;; symbol); a datum becomes a datum pattern (fails to match it).
(define-syntax check-id
  (syntax-rules ()
    ((_ x sk fk)
     (let-syntax ((sym? (syntax-rules () ((sym? x k1 k2) k1) ((sym? y k1 k2) k2))))
       (sym? abracadabra sk fk)))))

(test-equal "identifier detected" 'is-id (check-id foo 'is-id 'not-id))
(test-equal "number is not an identifier" 'not-id (check-id 0 'is-id 'not-id))
(test-equal "string is not an identifier" 'not-id (check-id "s" 'is-id 'not-id))
(test-equal "list is not an identifier" 'not-id (check-id (a b) 'is-id 'not-id))

;; Taylor Campbell's ellipsis test: if id is `...` the inner pattern
;; (foo id) becomes (foo ...) and matches a 3-element list.
(define-syntax check-ellipsis
  (syntax-rules ()
    ((_ id sk fk)
     (let-syntax ((ell? (syntax-rules ()
                          ((ell? (foo id) k1 k2) k1)
                          ((ell? other k1 k2) k2))))
       (ell? (a b c) sk fk)))))

(test-equal "ellipsis detected" 'yes (check-ellipsis ... 'yes 'no))
(test-equal "plain symbol is not ellipsis" 'no (check-ellipsis blah 'yes 'no))

;; Bound-identifier membership via substituted literals list (the
;; new-sym? trick from match.scm): ids substitute into the inner
;; literals list, and x into the pattern.
(define-syntax known-id?
  (syntax-rules ()
    ((_ x (id ...) sk fk)
     (let-syntax ((mem? (syntax-rules (id ...)
                          ((mem? x k1 k2) k2)
                          ((mem? y k1 k2) k1))))
       (mem? probe-symbol sk fk)))))

(test-equal "member of id list" 'known (known-id? b (a b c) 'known 'new))
(test-equal "not member of id list" 'new (known-id? z (a b c) 'known 'new))
(test-equal "empty id list" 'new (known-id? z () 'known 'new))

;; A generated inner transformer's own ellipsis must be preserved, not
;; consumed by outer instantiation (review finding on #1411; x references
;; no outer binding, so the outer expander used to emit zero repetitions).
(define-syntax gen-inner
  (syntax-rules ()
    ((_ arg)
     (let-syntax ((inner (syntax-rules ()
                           ((inner (x ...)) 'preserved)
                           ((inner other) 'lost))))
       (inner arg)))))

(test-equal "inner ellipsis pattern preserved" 'preserved (gen-inner (a b c)))
(test-equal "inner ellipsis pattern preserved (empty list)" 'preserved (gen-inner ()))
(test-equal "inner non-list still falls through" 'lost (gen-inner 5))

;; Inner ellipsis in both pattern and template, combined with outer
;; scalar substitution into the inner template.
(define-syntax gen-adder
  (syntax-rules ()
    ((_ base)
     (let-syntax ((sum (syntax-rules () ((sum (x ...)) (+ base x ...)))))
       (sum (1 2 3))))))

(test-equal "inner ellipsis template preserved with outer substitution" 16
  (gen-adder 10))

;; --- Bug 2: ellipsis inside template let binding lists ---

(define-syntax my-let
  (syntax-rules ()
    ((_ ((var value) ...) . body)
     (let ((var value) ...) . body))))

(test-equal "template let with ellipsis bindings" 3
  (my-let ((x 1) (y 2)) (+ x y)))

(define-syntax my-let*
  (syntax-rules ()
    ((_ ((var value) ...) body ...)
     (let* ((var value) ...) body ...))))

(test-equal "template let* with ellipsis bindings" 30
  (my-let* ((x 10) (y (* x 2))) (+ x y)))

(define-syntax mixed-let
  (syntax-rules ()
    ((_ ((var value) ...) . body)
     (let ((first 100) (var value) ...) (+ first (begin . body))))))

(test-equal "fixed binding before ellipsis bindings" 103
  (mixed-let ((x 1) (y 2)) (+ x y)))

(test-equal "zero repetitions in binding list" 42
  (my-let () 42))

;; Fixed binding after the ellipsis group (exercises the tail-append path)
(define-syntax tail-let
  (syntax-rules ()
    ((_ ((var value) ...) body)
     (let ((var value) ... (z 99)) (+ z body)))))

(test-equal "fixed binding after ellipsis bindings" 102
  (tail-let ((x 1) (y 2)) (+ x y)))

;; Two independent ellipsis groups in one binding list
(define-syntax two-groups
  (syntax-rules ()
    ((_ ((a av) ...) ((b bv) ...) body)
     (let ((a av) ... (b bv) ...) body))))

(test-equal "two ellipsis groups in one binding list" 6
  (two-groups ((x 1)) ((y 2) (w 3)) (+ x y w)))

;; letrec and named-let templates with ellipsis binding lists
(define-syntax my-letrec
  (syntax-rules ()
    ((_ ((var value) ...) body)
     (letrec ((var value) ...) body))))

(test-equal "template letrec with ellipsis bindings" 120
  (my-letrec ((f (lambda (n) (if (< n 2) 1 (* n (f (- n 1))))))) (f 5)))

(define-syntax my-loop
  (syntax-rules ()
    ((_ name ((var init) ...) body ...)
     (let name ((var init) ...) body ...))))

(test-equal "template named let with ellipsis bindings" 10
  (my-loop go ((i 0) (acc 0)) (if (= i 5) acc (go (+ i 1) (+ acc i)))))

;; Double ellipsis in a binding list flattens depth-2 groups (R7RS 4.3.2)
(define-syntax flat-let
  (syntax-rules ()
    ((_ (((var value) ...) ...) body)
     (let ((var value) ... ...) body))))

(test-equal "double ellipsis flattens binding groups" 6
  (flat-let (((x 1) (y 2)) ((z 3))) (+ x y z)))

;; Repeated template-introduced binders keep binding-position hygiene
;; (review finding on #1411): exp below must be gensym-renamed even though
;; a builtin of the same name exists, so the use-site (exp 0) still calls
;; the builtin.
(define-syntax capture-test
  (syntax-rules ()
    ((_ (value ...) body)
     (let ((exp value) ...) body))))

(test-equal "repeated builtin-named binder is renamed" 1.0
  (capture-test (1) (exp 0)))

;; Two groups where the first is longer: while the first group's three
;; repetitions instantiate, the second group (count 1) must not be
;; indexed past its own count.
(test-equal "longer first group instantiates independently" 17
  (two-groups ((x 1) (y 2) (p 4)) ((q 10)) (+ x y p q)))

;; Hygiene across the nested syntax-rules boundary: an outer
;; template-introduced binding (tmp) referenced from the inner template
;; must resolve to the outer expansion's rename.
(define-syntax outer-hyg
  (syntax-rules ()
    ((_ v)
     (let ((tmp v))
       (let-syntax ((probe (syntax-rules () ((probe tmp2) (* tmp2 tmp)))))
         (probe 10))))))

(test-equal "outer hygienic binding visible from inner template" 40
  (outer-hyg 4))

(let ((runner (test-runner-current)))
  (test-end "nested-syntax-rules-subst")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
