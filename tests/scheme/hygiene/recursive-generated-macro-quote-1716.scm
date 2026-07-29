;; Regression test for #1716: a macro-GENERATED macro that is self-recursive
;; and quotes one of its own pattern variables used to substitute the literal
;; pattern-variable name instead of the identifier the variable was bound to.
;;
;; The outer macro's template generates an inner `syntax-rules` transformer.
;; The inner macro's pattern variable `nm` is hygiene-renamed where it appears
;; in the PATTERN, but its template occurrence sits inside `(quote ...)`; the
;; expander used to treat every quoted identifier as inert literal data and
;; skip the rename there, splitting the two occurrences of the same variable.
;; The inner matcher then had nothing to bind to the template's `nm`, so it
;; passed through literally: `(collect a b c)` yielded `(nm nm nm)`.
;;
;; This is what SRFI 209's `define-enumeration` constructor needs, and the
;; failure was silent — a wrong symbol, never an error. Fixed in #1773.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "recursive-generated-macro-quote-1716")

;; --- The original repro shape: self-recursive, quotes its own pattern var ---

(define-syntax gen-ctor
  (syntax-rules ()
    ((_ ctor-name)
     (define-syntax ctor-name
       (syntax-rules ()
         ((_) '())
         ((_ nm rest (... ...))
          (cons 'nm (ctor-name rest (... ...)))))))))

(gen-ctor collect)

(test-equal "zero arguments" '() (collect))
(test-equal "one argument (no recursion yet)" '(a) (collect a))
(test-equal "two arguments (one recursive step)" '(a b) (collect a b))
(test-equal "three arguments" '(a b c) (collect a b c))
(test-equal "duplicates are preserved" '(a a b) (collect a a b))

;; Two independently generated constructors must not interfere with each
;; other's renames.
(gen-ctor collect2)
(test-equal "second generated constructor" '(x y) (collect2 x y))
(test-equal "first constructor still correct" '(p q) (collect p q))

;; --- Recursive call in the FIRST argument position (SRFI 209's own shape) ---

(define-syntax gen-rev
  (syntax-rules ()
    ((_ ctor-name)
     (define-syntax ctor-name
       (syntax-rules ()
         ((_) '())
         ((_ nm rest (... ...))
          (append (ctor-name rest (... ...)) (list 'nm))))))))

(gen-rev rev-collect)
(test-equal "recursive call before the quote" '(c b a) (rev-collect a b c))

;; --- The quoted pattern variable inside a larger quoted datum ---

(define-syntax gen-wrap
  (syntax-rules ()
    ((_ ctor-name)
     (define-syntax ctor-name
       (syntax-rules ()
         ((_) '())
         ((_ nm rest (... ...))
          (cons '(tag nm end) (ctor-name rest (... ...)))))))))

(gen-wrap wrap-each)
(test-equal "inert template neighbours stay unrenamed"
  '((tag a end) (tag b end)) (wrap-each a b))

(define-syntax gen-vec
  (syntax-rules ()
    ((_ ctor-name)
     (define-syntax ctor-name
       (syntax-rules ()
         ((_) '())
         ((_ nm rest (... ...))
          (cons '#(nm) (ctor-name rest (... ...)))))))))

(gen-vec vec-each)
(test-equal "quoted vector datum" '(#(a) #(b)) (vec-each a b))

;; --- Quasiquote/unquote reaches the same substitution path ---

(define-syntax gen-qq
  (syntax-rules ()
    ((_ ctor-name)
     (define-syntax ctor-name
       (syntax-rules ()
         ((_) '())
         ((_ nm rest (... ...))
          (cons `(nm . ,'nm) (ctor-name rest (... ...)))))))))

(gen-qq qq-each)
(test-equal "quasiquoted and unquoted occurrences agree"
  '((a . a) (b . b)) (qq-each a b))

;; --- Mutual recursion between two generated macros ---

(define-syntax gen-pair
  (syntax-rules ()
    ((_ evn odd)
     (begin
       (define-syntax evn
         (syntax-rules ()
           ((_) '())
           ((_ a b (... ...)) (cons (list 'e 'a) (odd b (... ...))))))
       (define-syntax odd
         (syntax-rules ()
           ((_) '())
           ((_ a b (... ...)) (cons (list 'o 'a) (evn b (... ...))))))))))

(gen-pair step-e step-o)
(test-equal "mutually recursive generated macros"
  '((e p) (o q) (e r) (o s)) (step-e p q r s))

;; --- An inner pattern variable spelled the same as an outer one ---

(define-syntax gen-shadow
  (syntax-rules ()
    ((_ ctor-name nm)
     (define-syntax ctor-name
       (syntax-rules ()
         ((_) '(nm))
         ((_ nm rest (... ...))
          (cons 'nm (ctor-name rest (... ...)))))))))

(gen-shadow shadow-collect outer-name)
(test-equal "inner pattern variable shadows the outer one of the same name"
  '(a b outer-name) (shadow-collect a b))

(let ((runner (test-runner-current)))
  (test-end "recursive-generated-macro-quote-1716")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
