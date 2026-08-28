;;; SRFI 202 — Pattern-matching Variant of the and-let* Form
;;;
;;; Extends SRFI 2's and-let* with SRFI-200-style patterns. A pattern claw
;;; is written quasiquoted, e.g. (`(,x . ,y) expr) — the leading backtick is
;;; what distinguishes a pattern claw from a plain SRFI 2 variable claw
;;; (var expr), since a bare identifier is otherwise ambiguous between "bind
;;; this variable" and "match this symbol literally". Self-contained (does
;;; not import (srfi 241)): and-let* claws only ever need wildcard/variable/
;;; pair/vector/literal patterns, not 241's ellipsis or cata patterns.
;;;
;;; An er-macro-transformer port (KEP-0006 step 5): the claw list is walked
;;; by ordinary list processing and each claw compiled directly. Relative to
;;; the previous pure-syntax-rules port this also adds SRFI 2's bare
;;; BOUND-VARIABLE claw (a claw that is just an identifier, tested for
;;; truthiness) and vector patterns inside quasiquoted claws. The claw
;;; keywords (quasiquote, unquote, _, values) are recognized by
;;; hygiene-stripped name comparison — see kaappi#2388.

(define-library (srfi 202)
  (import (scheme base)
          (srfi 211 explicit-renaming))
  (export and-let*)
  (begin

    (define-syntax and-let*
      (er-macro-transformer
       (lambda (form rename compare)
         (define r-if (rename 'if))
         (define r-let (rename 'let))
         (define r-lambda (rename 'lambda))
         (define r-quote (rename 'quote))
         (define r-cwv (rename 'call-with-values))
         (define r-car (rename 'car))
         (define r-cdr (rename 'cdr))
         (define r-pair? (rename 'pair?))
         (define r-null? (rename 'null?))
         (define r-equal? (rename 'equal?))
         (define r-vector? (rename 'vector?))
         (define r-vector->list (rename 'vector->list))

         ;; Keyword recognition is binding-aware compare (kaappi#2388).
         (define (kw? x sym) (and (symbol? x) (compare x (rename sym))))
         (define (qq-form? x)
           (and (pair? x) (kw? (car x) 'quasiquote)
                (pair? (cdr x)) (null? (cddr x))))
         (define (unquote-form? x)
           (and (pair? x) (kw? (car x) 'unquote)))

         (define counter 0)
         (define (fresh base)
           (set! counter (+ counter 1))
           (rename (string->symbol
                    (string-append "%al" (number->string counter)
                                   "." base))))

         (define (verr msg what)
           (error (string-append "and-let*: " msg) what))

         ;; Structural matcher for one quasiquoted pattern. SK is a thunk
         ;; returning the success expression; failure yields #f.
         (define (qpat pat val sk)
           (cond
            ((unquote-form? pat)
             (if (not (and (pair? (cdr pat)) (null? (cddr pat))))
                 (verr "invalid unquote pattern" pat))
             (let ((sub (cadr pat)))
               (cond
                ((kw? sub '_) (sk))
                ((symbol? sub) (list r-let (list (list sub val)) (sk)))
                (else (verr "invalid unquote pattern" pat)))))
            ((pair? pat)
             (let ((a (fresh "a")) (d (fresh "d")))
               (list r-if (list r-pair? val)
                     (list r-let (list (list a (list r-car val))
                                       (list d (list r-cdr val)))
                           (qpat (car pat) a
                                 (lambda () (qpat (cdr pat) d sk))))
                     #f)))
            ((null? pat)
             (list r-if (list r-null? val) (sk) #f))
            ((vector? pat)
             (let ((lst (fresh "v")))
               (list r-if (list r-vector? val)
                     (list r-let (list (list lst (list r-vector->list val)))
                           (qpat (vector->list pat) lst sk))
                     #f)))
            (else
             (list r-if (list r-equal? val (list r-quote pat)) (sk) #f))))

         ;; Match the patterns PS (bare identifiers or quasiquoted
         ;; patterns) against successive elements of the value list LST.
         ;; Too few values fails; surplus values are bound to TAILVAR when
         ;; it is a symbol, discarded when it is #f. FIRST? applies SRFI
         ;; 202's truthiness rule to a leading bare-identifier pattern.
         (define (match-vals ps lst tailvar first? sk)
           (cond
            ((null? ps)
             (if tailvar
                 (list r-let (list (list tailvar lst)) (sk))
                 (sk)))
            (else
             (let ((p (car ps)) (a (fresh "x")) (d (fresh "r")))
               (list r-if (list r-pair? lst)
                     (list r-let (list (list a (list r-car lst))
                                       (list d (list r-cdr lst)))
                           (cond
                            ((qq-form? p)
                             (qpat (cadr p) a
                                   (lambda ()
                                     (match-vals (cdr ps) d tailvar #f sk))))
                            ((symbol? p)
                             (list r-let (list (list p a))
                                   (if first?
                                       (list r-if p
                                             (match-vals (cdr ps) d tailvar #f sk)
                                             #f)
                                       (match-vals (cdr ps) d tailvar #f sk))))
                            (else (verr "invalid claw pattern" p))))
                     #f)))))

         ;; Bind EXPR's values to a fresh rest-list and match PS over it.
         (define (values-claw ps tailvar first? expr cont)
           (let ((vals (fresh "vals")))
             (list r-cwv
                   (list r-lambda '() expr)
                   (list r-lambda vals
                         (match-vals ps vals tailvar first? cont)))))

         (define (expand-claws claws body)
           (cond
            ((null? claws)
             (if (null? body) #t (cons r-let (cons '() body))))
            ((not (pair? claws)) (verr "invalid claw list" claws))
            (else
             (let ((claw (car claws))
                   (cont (lambda () (expand-claws (cdr claws) body))))
               (cond
                ;; bare BOUND-VARIABLE claw (SRFI 2)
                ((symbol? claw) (list r-if claw (cont) #f))
                ((not (and (pair? claw) (list? claw)))
                 (verr "invalid claw" claw))
                ;; guard-only claw: (expr)
                ((null? (cdr claw))
                 (list r-if (car claw) (cont) #f))
                ;; (var expr)  [SRFI 2, truthiness applies]
                ((and (null? (cddr claw)) (symbol? (car claw)))
                 (list r-let (list (list (car claw) (cadr claw)))
                       (list r-if (car claw) (cont) #f)))
                ;; (`pat expr)  single quasiquoted pattern
                ((and (null? (cddr claw)) (qq-form? (car claw)))
                 (let ((v (fresh "t")))
                   (list r-let (list (list v (cadr claw)))
                         (qpat (cadr (car claw)) v cont))))
                ;; ((values p1 p2 ... . v*) expr)  values-collecting
                ((and (null? (cddr claw)) (pair? (car claw))
                      (kw? (car (car claw)) 'values))
                 (let split ((ps (cdr (car claw))) (acc '()))
                   (if (pair? ps)
                       (split (cdr ps) (cons (car ps) acc))
                       (let ((tailvar (cond ((null? ps) #f)
                                            ((symbol? ps) ps)
                                            (else (verr "invalid values claw"
                                                        claw)))))
                         (values-claw (reverse acc) tailvar #f
                                      (cadr claw) cont)))))
                ;; general multi-value pattern claw: (pat1 pat2 ... expr)
                (else
                 (let split ((items claw) (acc '()))
                   (if (null? (cdr items))
                       (values-claw (reverse acc) #f #t (car items) cont)
                       (split (cdr items) (cons (car items) acc))))))))))

         (if (not (and (pair? (cdr form)) (list? (cadr form))))
             (verr "invalid claw list" form))
         (expand-claws (cadr form) (cddr form)))))))
