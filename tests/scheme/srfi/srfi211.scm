;; SRFI 211 (Scheme Macro Libraries) tests: the three sub-libraries Kaappi
;; provides — (srfi 211 explicit-renaming), (srfi 211 define-macro), and
;; (srfi 211 syntax-parameter) — each provided whole per the SRFI's
;; conformance rule ("If it provides a library, it has to provide it as a
;; whole"). The procedural-transformer engine work is issue #1699's last
;; slice; see lib/srfi/211/explicit-renaming.sld for mechanism notes.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi211.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 211 explicit-renaming)
        (srfi 211 define-macro)
        (srfi 211 syntax-parameter))

(test-begin "srfi-211")

;;; --- explicit renaming: the classic swap! with hygienic tmp ---
(define-syntax swap!
  (er-macro-transformer
   (lambda (form rename compare)
     (let ((a (cadr form))
           (b (car (cddr form)))
           (tmp (rename 'tmp)))
       (list (rename 'let) (list (list tmp a))
             (list (rename 'set!) a b)
             (list (rename 'set!) b tmp))))))

(define sw-x 1)
(define sw-y 2)
(swap! sw-x sw-y)
(test-equal '(2 1) (list sw-x sw-y))

;; hygiene: a user variable literally named tmp survives the swap
(define tmp 'mine)
(define other 'yours)
(swap! tmp other)
(test-equal '(yours mine) (list tmp other))

;;; --- recursive ER macro (Clinger's my-or shape) ---
(define-syntax my-or
  (er-macro-transformer
   (lambda (form rename compare)
     (let ((exprs (cdr form)))
       (cond ((null? exprs) #f)
             ((null? (cdr exprs)) (car exprs))
             (else (list (rename 'let)
                         (list (list (rename 't) (car exprs)))
                         (list (rename 'if) (rename 't) (rename 't)
                               (cons (rename 'my-or) (cdr exprs))))))))))

(define t 'user-t)
(test-equal 'user-t (my-or #f #f t))
(test-equal 7 (my-or #f 7 (error "not reached")))

;;; --- rename consistency within one expansion, freshness across two ---
(define-syntax rename-same?
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote)
           (eq? (rename 'fresh-name-xyz) (rename 'fresh-name-xyz))))))
(test-equal #t (rename-same? ))

(define-syntax rename-capture
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (rename 'fresh-name-uvw)))))
(test-assert "two invocations rename to distinct gensyms"
             (not (eq? (rename-capture) (rename-capture))))

;;; --- rename accepts a whole datum: leaves renamed, structure rebuilt ---
(define-syntax tree-rename
  (er-macro-transformer
   (lambda (form rename compare)
     (rename '(let ((fresh-leaf 7)) (* fresh-leaf 2))))))
(test-equal 14 (tree-rename))

;;; --- compare: the classic else-clause detection ---
(define-syntax cond1
  (er-macro-transformer
   (lambda (form rename compare)
     (let ((clause (cadr form)))
       (if (compare (car clause) (rename 'else))
           (cons (rename 'begin) (cdr clause))
           (list (rename 'if) (car clause)
                 (cons (rename 'begin) (cdr clause))
                 (list (rename 'quote) 'no-match)))))))
(test-equal 'fell-through (cond1 (else 'fell-through)))
(test-equal 'took-it (cond1 (#t 'took-it)))
(test-equal 'no-match (cond1 (#f 'skipped)))

;;; --- compare rejects non-identifiers ---
(define-syntax compare-nums
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare 1 1)))))
(test-equal #f (compare-nums))

;;; --- identifier?: symbols (renamed or not) are identifiers ---
(test-assert "plain symbol" (identifier? 'x))
(test-assert "not a number" (not (identifier? 3)))
(test-assert "not a string" (not (identifier? "x")))
(test-assert "not a list" (not (identifier? '(x))))

;;; --- er transformer under let-syntax in a body scope ---
(define (body-er)
  (let-syntax ((double (er-macro-transformer
                        (lambda (f r c) (list (r '*) 2 (cadr f))))))
    (double 21)))
(test-equal 42 (body-er))

;;; --- a runtime transformer value bound then used as a spec (SRFI 211's
;;; constructors are real procedures returning transformer objects) ---
(define runtime-tx
  (er-macro-transformer (lambda (f r c) (list (r 'quote) 'via-value))))
(define-syntax via-value runtime-tx)
(test-equal 'via-value (via-value))

;;; --- lisp-transformer: whole macro-use datum, zero hygiene ---
(define-syntax lt-when
  (lisp-transformer
   (lambda (form)
     (list 'if (cadr form) (cons 'begin (cddr form)) #f))))
(test-equal 'yes (lt-when (> 2 1) 'yes))
(test-equal #f (lt-when (< 2 1) 'no))

;; the whole use (keyword included) is what proc receives
(define-syntax lt-head
  (lisp-transformer (lambda (form) (list 'quote (car form)))))
(test-equal 'lt-head (lt-head))

;; non-hygiene is the specified behavior: an introduced binding CAN
;; capture a use-site name (that's what old-style macros do)
(define-syntax lt-capture
  (lisp-transformer
   (lambda (form) (list 'let '((cap 'introduced)) (cadr form)))))
(test-equal 'introduced (lt-capture cap))

;;; --- define-macro, first form: (name . formals) destructures the cdr ---
(define-macro (dm-unless test . body)
  (list 'if test #f (cons 'begin body)))
(test-equal 'ran (dm-unless (= 1 2) 'ran))
(test-equal #f (dm-unless (= 1 1) 'not-run))

;; quasiquoted body, the classic defmacro idiom
(define-macro (dm-swap! a b)
  `(let ((fresh-dm-tmp ,a)) (set! ,a ,b) (set! ,b fresh-dm-tmp)))
(define dm-p 1)
(define dm-q 2)
(dm-swap! dm-p dm-q)
(test-equal '(2 1) (list dm-p dm-q))

;;; --- define-macro, second form: (name expander) ---
(define-macro dm-also-when
  (lambda (form) (list 'if (cadr form) (cons 'begin (cddr form)) #f)))
(test-equal 'w (dm-also-when #t 'w))

;;; --- variadic formals with fixed leaders ---
(define-macro (dm-list2 a b . rest)
  `(list ,b ,a ,@rest))
(test-equal '(2 1 3 4) (dm-list2 1 2 3 4))

;;; --- (srfi 211 syntax-parameter): SRFI 139's semantics under the
;;; SRFI 211 library name (forever/abort, the spec's own example) ---
(define-syntax-parameter abort
  (syntax-rules ()
    ((_ . _) (syntax-error "abort used outside of a loop"))))
(define-syntax forever
  (syntax-rules ()
    ((_ body1 body2 ...)
     (call-with-current-continuation
      (lambda (escape)
        (syntax-parameterize
            ((abort (syntax-rules () ((_ v) (escape v)))))
          (let loop () body1 body2 ... (loop))))))))
(define spin 0)
(test-equal 3 (forever (set! spin (+ spin 1))
                       (when (> spin 2) (abort spin))))

;;; --- ER macro defined in a library body: rename resolves the library's
;;; own non-exported helper at the use site ---
(define-library (t211 helperlib)
  (import (scheme base) (srfi 211 explicit-renaming))
  (export lib-twice combo)
  (begin
    (define (t211-helper x) (* x 2))
    (define-syntax lib-twice
      (er-macro-transformer
       (lambda (form rename compare)
         (list (rename 't211-helper) (cadr form)))))
    (define-syntax combo
      (syntax-rules ()
        ((_ e) (list (lib-twice e) e))))))
(import (t211 helperlib))
(test-equal 42 (lib-twice 21))
(test-equal '(20 10) (combo 10))

(let ((runner (test-runner-current)))
  (test-end "srfi-211")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
