;; R7RS 4.3.2 syntax-rules edge-case gap tests — audit Phase 4C (macros).
;; Nested ellipses, ellipsis escapes, macro-generating macros, hygiene
;; shadowing. Spec references cite docs/errata-corrected-r7rs.pdf pp. 22-24.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "r7rs-hygiene-gaps")

;;; --- nested ellipses: structure-preserving distribution ---
(define-syntax keep2
  (syntax-rules ()
    ((_ ((a b ...) ...)) '((a (b ...)) ...))))
(test-equal "two-level ellipsis distributes per group"
  '((1 (2 3)) (4 (5)) (6 ()))
  (keep2 ((1 2 3) (4 5) (6))))

;; "They are replaced in the output by all of the elements they match in
;; the input" — doubled ellipsis flattens one level
(define-syntax flatten2
  (syntax-rules ()
    ((_ ((x ...) ...)) '(x ... ...))))
(test-equal "doubled ellipsis flattens" '(1 2 3 4 5)
  (flatten2 ((1 2) (3 4) (5))))

;;; --- (... ...) escape + macro-generating macro (p. 24 example) ---
(define-syntax be-like-begin
  (syntax-rules ()
    ((be-like-begin name)
     (define-syntax name
       (syntax-rules ()
         ((name expr (... ...)) (begin expr (... ...))))))))
(be-like-begin sequence)
(test-equal "be-like-begin (R7RS p.24 example)" 4 (sequence 1 2 3 4))

;; simple macro-generating macro
(define-syntax def-const
  (syntax-rules ()
    ((_ name val)
     (define-syntax name (syntax-rules () ((_) val))))))
(def-const seven 7)
(test-equal "macro-generating macro" 7 (seven))

;;; --- custom ellipsis identifier (second syntax-rules form) ---
(define-syntax my-list-ooo
  (syntax-rules ooo () ((_ x ooo) (list x ooo))))
(test-equal "custom ellipsis identifier" '(7 8 9) (my-list-ooo 7 8 9))

;;; --- vector patterns ---
(define-syntax vfirst (syntax-rules () ((_ #(a b ...)) 'a)))
(test-equal "vector pattern with ellipsis" 1 (vfirst #(1 2 3)))

;;; --- underscore ---
(define-syntax snd (syntax-rules () ((_ _ y) 'y)))
(test-equal "underscore matches without binding" 'kept (snd ignored kept))
(define-syntax lastish (syntax-rules () ((_ _ ... y) 'y)))
(test-equal "pattern after ellipsis (tail pattern)" 'four
  (lastish 1 2 3 four))

;;; --- recursive transformer with accumulator ---
(define-syntax rev
  (syntax-rules ()
    ((_ () (acc ...)) '(acc ...))
    ((_ (x rest ...) (acc ...)) (rev (rest ...) (x acc ...)))))
(test-equal "recursive accumulator macro" '(3 2 1) (rev (1 2 3) ()))

;;; --- hygiene: template-introduced bindings don't capture user names ---
(define-syntax swap!
  (syntax-rules () ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(test-equal "template tmp does not capture user tmp" '(2 1)
  (let ((tmp 1) (x 2)) (swap! tmp x) (list tmp x)))

;; the classic my-or hygiene test (p. 22-23): user's t is not captured
(define-syntax my-or
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e1 e2 ...) (let ((t e1)) (if t t (my-or e2 ...))))))
(test-equal "my-or does not capture user t" 7
  (let ((t 7)) (my-or #f t)))

;;; --- keyword shadowing by variables ---
(test-equal "variable may shadow a syntactic keyword" 'shadowed
  (let ((if 'shadowed)) if))
;; p. 24: "The macro transformer for cond recognizes => as a local
;; variable, and hence an expression"
(test-equal "cond => shadowed by variable (R7RS p.24 example)" 'ok
  (let ((=> #f)) (cond (#t => 'ok))))

;;; --- syntax-rules with literals honors literal position ---
(define-syntax iffy
  (syntax-rules (then else)
    ((_ c then t else e) (if c t e))))
(test-equal "literals as clause markers" 'yes (iffy #t then 'yes else 'no))

(let ((runner (test-runner-current)))
  (test-end "r7rs-hygiene-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
