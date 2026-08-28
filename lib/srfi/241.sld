;;; SRFI 241 — Match
;;;
;;; An er-macro-transformer port of the Wright-Cartwright-Shinn matcher
;;; (KEP-0006 step 5). The previous port was pure syntax-rules and had to
;;; give every helper macro a custom ellipsis identifier (%%%) so the
;;; literal three-dot token could be pattern-matched as data; the whole
;;; pattern language is now compiled by ordinary list processing inside one
;;; procedural transformer, which lifted the port's four documented
;;; limitations:
;;;
;;;  - Ellipsis-repeated sub-patterns may be arbitrary patterns (including
;;;    nested ellipses, catas, vectors), not just ,var / ,_ / ,(var).
;;;  - Ellipses may be followed by further mandatory patterns before the
;;;    tail, e.g. (,x ... ,y ,z) and (,x ... ,y . ,rest); vector patterns
;;;    support the full #(p1 ... pk pe ellipsis pm+1 ... pn) grammar with a
;;;    mandatory prefix and suffix around the ellipsis segment.
;;;  - The SRFI's ellipsis-aware quasiquote is bound inside match clause
;;;    bodies (via a let-syntax around each body): a subtemplate followed by
;;;    ellipses iterates its unquoted expressions the way a syntax-rules
;;;    template iterates pattern variables, and (... tpl) escapes. Guard
;;;    expressions keep the ordinary (scheme base) quasiquote.
;;;  - Cata operators are evaluated only after the clause's guard passes
;;;    (the spec's order); the structural match binds hidden temporaries and
;;;    the cata procedures run afterwards, so a rejected guard no longer
;;;    triggers cata side effects.
;;;
;;; Remaining scope notes, relative to the full SRFI:
;;;  - Square-bracket clause notation isn't available (Kaappi's reader has
;;;    no bracket syntax); write clauses and cata patterns with plain
;;;    parens, e.g. (,(f -> x y) ...) rather than [,[f -> x y] ...].
;;;  - Only match is exported. The auxiliary keywords (unquote, ..., _,
;;;    guard, ->) are recognized by hygiene-stripped name comparison (the
;;;    strength of this engine's ER compare — see kaappi#2388), so
;;;    exporting bindings for them would not change what is matched.
;;;  - If a match form is produced by another macro's syntax-rules
;;;    template, that template's own ellipsis processing applies before
;;;    match sees the form (escape nested ellipses with (... ...)), and
;;;    quasiquote symbols renamed by such a template resolve to the
;;;    built-in quasiquote rather than the match-body one.

(define-library (srfi 241)
  (import (scheme base)
          (srfi 211 explicit-renaming))
  (export match)
  (begin

    ;; ------------------------------------------------------------------
    ;; Runtime helpers (referenced from expansions via rename).
    ;; ------------------------------------------------------------------

    (define (%match-fail val)
      (error "match: no matching clause" val))

    ;; Split VAL into (prefix . rest): rest holds VAL's final K pairs plus
    ;; any improper tail, prefix is a fresh list of the leading elements.
    ;; #f when VAL has fewer than K pairs.
    (define (%match-split val k)
      (let count ((v val) (n 0))
        (if (pair? v)
            (count (cdr v) (+ n 1))
            (and (>= n k)
                 (let loop ((v val) (m (- n k)) (acc '()))
                   (if (zero? m)
                       (cons (reverse acc) v)
                       (loop (cdr v) (- m 1) (cons (car v) acc))))))))

    ;; Apply cata operator OP to VAL nested DEPTH ellipsis levels deep.
    ;; Returns the list of NVARS results; at depth > 0 the per-element
    ;; result lists are transposed so each cata variable receives one
    ;; (nested) list.
    (define (%match-cata op val depth nvars)
      (if (zero? depth)
          (call-with-values (lambda () (op val)) list)
          (let ((rows (map (lambda (v) (%match-cata op v (- depth 1) nvars))
                           val)))
            (let transpose ((i (- nvars 1)) (acc '()))
              (if (< i 0)
                  acc
                  (transpose (- i 1)
                             (cons (map (lambda (r) (list-ref r i)) rows)
                                   acc)))))))

    ;; ------------------------------------------------------------------
    ;; The ellipsis-aware quasiquote bound inside match clause bodies.
    ;; A subtemplate followed by K ellipses iterates its unquoted
    ;; expressions (map at depth 1, flattened once per extra ellipsis);
    ;; (... tpl) makes ellipses inside tpl literal; nested quasiquote
    ;; levels behave as in R7RS.
    ;; ------------------------------------------------------------------

    (define %match-qq
      (er-macro-transformer
       (lambda (form rename compare)
         (define r-quote (rename 'quote))
         (define r-cons (rename 'cons))
         (define r-append (rename 'append))
         (define r-map (rename 'map))
         (define r-apply (rename 'apply))
         (define r-lambda (rename 'lambda))
         (define r-list->vector (rename 'list->vector))

         (define (kw? x sym) (and (symbol? x) (compare x (rename sym))))
         (define (ell? x) (kw? x '...))
         (define (head-kw? x sym)
           (and (pair? x) (kw? (car x) sym) (list? (cdr x))
                (pair? (cdr x))))
         (define (unq? x) (head-kw? x 'unquote))
         (define (unqs? x) (head-kw? x 'unquote-splicing))
         (define (qq? x) (head-kw? x 'quasiquote))
         (define (escape? x eok)        ; (... tpl)
           (and eok (pair? x) (ell? (car x))
                (pair? (cdr x)) (null? (cddr x))))

         (define counter 0)
         (define (fresh)
           (set! counter (+ counter 1))
           (rename (string->symbol
                    (string-append "%qq" (number->string counter)))))

         (define (verr msg what)
           (error (string-append "match quasiquote: " msg) what))

         ;; No unquote/unquote-splicing/ellipsis marker anywhere: literal.
         (define (pure? tpl)
           (cond
            ((symbol? tpl)
             (not (or (kw? tpl 'unquote) (kw? tpl 'unquote-splicing)
                      (ell? tpl))))
            ((pair? tpl) (and (pure? (car tpl)) (pure? (cdr tpl))))
            ((vector? tpl)
             (let loop ((i 0))
               (or (= i (vector-length tpl))
                   (and (pure? (vector-ref tpl i)) (loop (+ i 1))))))
            (else #t)))

         ;; exp : template x nesting-level x ellipsis-active? -> expression
         (define (exp tpl lvl eok)
           (cond
            ((pure? tpl) (list r-quote tpl))
            ((unq? tpl)
             (if (zero? lvl)
                 (if (null? (cddr tpl))
                     (cadr tpl)
                     (verr "multi-expression unquote outside list context"
                           tpl))
                 (list r-cons (list r-quote (car tpl))
                       (exp (cdr tpl) (- lvl 1) eok))))
            ((unqs? tpl)
             (if (zero? lvl)
                 (verr "unquote-splicing outside list context" tpl)
                 (list r-cons (list r-quote (car tpl))
                       (exp (cdr tpl) (- lvl 1) eok))))
            ((qq? tpl)
             (list r-cons (list r-quote (car tpl))
                   (exp (cdr tpl) (+ lvl 1) eok)))
            ((escape? tpl eok)
             (exp (cadr tpl) lvl #f))
            ((pair? tpl) (exp-list tpl lvl eok))
            ((vector? tpl)
             (list r-list->vector (exp (vector->list tpl) lvl eok)))
            (else (list r-quote tpl))))

         (define (exp-list tpl lvl eok)
           (let ((head (car tpl)) (tail (cdr tpl)))
             (cond
              ;; head followed by one or more ellipses, at level 0
              ((and eok (zero? lvl) (pair? tail) (ell? (car tail))
                    (not (escape? tpl eok)))
               (let count ((tl tail) (k 0))
                 (if (and (pair? tl) (ell? (car tl)))
                     (count (cdr tl) (+ k 1))
                     (let ((seg (exp-ellipsis head k eok)))
                       (if (null? tl)
                           seg
                           (list r-append seg (exp tl lvl eok)))))))
              ;; splicing element: (unquote-splicing e ...)
              ((and (zero? lvl) (unqs? head))
               (append (list r-append) (cdr head)
                       (list (exp tail lvl eok))))
              ;; multi-expression unquote element: (unquote e1 e2 ...)
              ((and (zero? lvl) (unq? head) (not (null? (cddr head))))
               (let loop ((es (cdr head)))
                 (if (null? es)
                     (exp tail lvl eok)
                     (list r-cons (car es) (loop (cdr es))))))
              (else
               (list r-cons (exp head lvl eok) (exp tail lvl eok))))))

         ;; HEAD iterated by K ellipses at level 0: replace each of its
         ;; level-0 unquoted expressions by a fresh variable, map a lambda
         ;; of those variables over the expressions, and flatten once per
         ;; extra ellipsis.
         (define (exp-ellipsis head k eok)
           (let ((subs '()))            ; (var . expr), newest first
             (define (sub! e)
               (let ((v (fresh)))
                 (set! subs (cons (cons v e) subs))
                 v))
             (define (peel tpl lvl eok)
               (cond
                ((and (or (unq? tpl) (unqs? tpl)) (zero? lvl))
                 (cons (car tpl) (map sub! (cdr tpl))))
                ((or (unq? tpl) (unqs? tpl))
                 (cons (car tpl) (peel (cdr tpl) (- lvl 1) eok)))
                ((qq? tpl)
                 (cons (car tpl) (peel (cdr tpl) (+ lvl 1) eok)))
                ((escape? tpl eok)
                 (list (car tpl) (peel (cadr tpl) lvl #f)))
                ((pair? tpl)
                 (cons (peel (car tpl) lvl eok) (peel (cdr tpl) lvl eok)))
                ((vector? tpl)
                 (list->vector
                  (map (lambda (x) (peel x lvl eok)) (vector->list tpl))))
                (else tpl)))
             (let ((tpl2 (peel head 0 eok)))
               (if (null? subs)
                   (verr "no unquoted expressions under ellipsis" head)
                   (let* ((pairs (reverse subs))
                          (body (exp tpl2 0 eok))
                          (seg0 (append
                                 (list r-map
                                       (list r-lambda (map car pairs) body))
                                 (map cdr pairs))))
                     (let extra ((k k) (seg seg0))
                       (if (<= k 1)
                           seg
                           (extra (- k 1)
                                  (list r-apply r-append seg)))))))))

         (if (and (pair? (cdr form)) (null? (cddr form)))
             (exp (cadr form) 0 #t)
             (error "match quasiquote: bad form" form)))))

    ;; ------------------------------------------------------------------
    ;; match itself: a pattern compiler.
    ;; ------------------------------------------------------------------

    (define-syntax match
      (er-macro-transformer
       (lambda (form rename compare)
         (define r-if (rename 'if))
         (define r-let (rename 'let))
         (define r-letrec (rename 'letrec))
         (define r-lambda (rename 'lambda))
         (define r-quote (rename 'quote))
         (define r-and (rename 'and))
         (define r-car (rename 'car))
         (define r-cdr (rename 'cdr))
         (define r-pair? (rename 'pair?))
         (define r-null? (rename 'null?))
         (define r-equal? (rename 'equal?))
         (define r-vector? (rename 'vector?))
         (define r-vector->list (rename 'vector->list))
         (define r-cons (rename 'cons))
         (define r-reverse (rename 'reverse))
         (define r-apply (rename 'apply))
         (define r-let-syntax (rename 'let-syntax))
         (define r-fail (rename '%match-fail))
         (define r-split (rename '%match-split))
         (define r-cata (rename '%match-cata))
         (define r-qq (rename '%match-qq))

         ;; Keyword recognition is name-based compare (kaappi#2388).
         (define (kw? x sym) (and (symbol? x) (compare x (rename sym))))
         (define (ell? x) (kw? x '...))
         (define (uscore? x) (kw? x '_))
         (define (arrow? x) (kw? x '->))
         (define (unquote-form? x)
           (and (pair? x) (kw? (car x) 'unquote)))

         (define counter 0)
         (define (fresh base)
           (set! counter (+ counter 1))
           (rename (string->symbol
                    (string-append "%m" (number->string counter)
                                   "." base))))

         (define (verr msg what)
           (error (string-append "match: " msg) what))

         ;; Compile one clause against value T; SELF is the whole-match
         ;; procedure (for default catas), KF the clause-failure thunk.
         (define (compile-clause clause t self kf)
           (if (not (and (pair? clause) (list? clause)
                         (pair? (cdr clause))))
               (verr "invalid clause" clause))
           (let* ((pat (car clause))
                  (rest (cdr clause))
                  (has-guard (and (pair? (car rest))
                                  (kw? (car (car rest)) 'guard)
                                  (pair? (cdr rest))))
                  (guard-tests (if has-guard (cdr (car rest)) #f))
                  (body (if has-guard (cdr rest) rest))
                  (svars '())      ; structurally bound ids, newest first
                  (catas '()))     ; (tmp op vars depth), op #f = default

             (define (record-var! v) (set! svars (cons v svars)))
             (define (vars-since mark)   ; oldest-first delta
               (let loop ((s svars) (acc '()))
                 (if (eq? s mark) acc (loop (cdr s) (cons (car s) acc)))))

             ;; Record a cata: bind a hidden temporary now, apply the
             ;; operator only after the guard passes.
             (define (cata val op cvs depth sk)
               (if (not (list? cvs)) (verr "invalid cata pattern" cvs))
               (for-each (lambda (v)
                           (if (not (symbol? v))
                               (verr "invalid cata variable" v)))
                         cvs)
               (let ((tmp (fresh "c")))
                 (record-var! tmp)
                 (set! catas (cons (list tmp op cvs depth) catas))
                 (list r-let (list (list tmp val)) (sk))))

             ;; cp : pattern x value-id x success-thunk x failure-expr x
             ;;      ellipsis-depth -> expression
             ;; SK is invoked exactly once, at the innermost success
             ;; point, after every variable on the path is recorded.
             (define (cp pat val sk fk depth)
               (cond
                ((unquote-form? pat)
                 (if (not (and (pair? (cdr pat)) (null? (cddr pat))))
                     (verr "invalid unquote pattern" pat))
                 (let ((sub (cadr pat)))
                   (cond
                    ((uscore? sub) (sk))
                    ((symbol? sub)
                     (record-var! sub)
                     (list r-let (list (list sub val)) (sk)))
                    ((pair? sub)
                     (if (and (pair? (cdr sub)) (arrow? (cadr sub)))
                         (cata val (car sub) (cddr sub) depth sk)
                         (cata val #f sub depth sk)))
                    (else (verr "invalid unquote pattern" pat)))))
                ((and (pair? pat) (pair? (cdr pat)) (ell? (cadr pat)))
                 (cp-ellipsis (car pat) (cddr pat) val sk fk depth))
                ((pair? pat)
                 (if (ell? (car pat)) (verr "misplaced ellipsis" pat))
                 (let ((a (fresh "a")) (d (fresh "d")))
                   (list r-if (list r-pair? val)
                         (list r-let
                               (list (list a (list r-car val))
                                     (list d (list r-cdr val)))
                               (cp (car pat) a
                                   (lambda ()
                                     (cp (cdr pat) d sk fk depth))
                                   fk depth))
                         fk)))
                ((null? pat)
                 (list r-if (list r-null? val) (sk) fk))
                ((vector? pat)
                 (let ((lst (fresh "v")))
                   (list r-if (list r-vector? val)
                         (list r-let
                               (list (list lst (list r-vector->list val)))
                               (cp (vector->list pat) lst sk fk depth))
                         fk)))
                (else
                 (list r-if (list r-equal? val (list r-quote pat))
                       (sk) fk))))

             ;; (sub ... . rest) — REST may contain further mandatory
             ;; patterns before the tail. Split off the final K pairs,
             ;; loop SUB over the prefix accumulating its variables, then
             ;; match REST against the remainder.
             (define (cp-ellipsis sub rest val sk fk depth)
               (if (ell? sub) (verr "misplaced ellipsis" sub))
               (let count ((r rest) (k 0))
                 (cond
                  ((and (pair? r) (not (unquote-form? r)))
                   (if (ell? (car r))
                       (verr "multiple ellipses in one list" rest))
                   (count (cdr r) (+ k 1)))
                  (else
                   (let* ((sp (fresh "sp")) (pre (fresh "pre"))
                          (tailv (fresh "tl")) (loop (fresh "lp"))
                          (in (fresh "in")) (e (fresh "e"))
                          (mark svars)
                          (accs '())    ; (var . acc-id)
                          (elem-code
                           (cp sub e
                               (lambda ()
                                 (let ((evars (vars-since mark)))
                                   (set! accs
                                         (map (lambda (v)
                                                (cons v (fresh "ac")))
                                              evars))
                                   (cons loop
                                         (cons (list r-cdr in)
                                               (map (lambda (p)
                                                      (list r-cons (car p)
                                                            (cdr p)))
                                                    accs)))))
                               fk (+ depth 1)))
                          (rest-code (cp rest tailv sk fk depth)))
                     (list r-let (list (list sp (list r-split val k)))
                           (list r-if sp
                                 (list r-let
                                       (list (list pre (list r-car sp))
                                             (list tailv (list r-cdr sp)))
                                       (list r-let loop
                                             (cons (list in pre)
                                                   (map (lambda (p)
                                                          (list (cdr p)
                                                                (list r-quote '())))
                                                        accs))
                                             (list r-if (list r-null? in)
                                                   (list r-let
                                                         (map (lambda (p)
                                                                (list (car p)
                                                                      (list r-reverse (cdr p))))
                                                              accs)
                                                         rest-code)
                                                   (list r-let
                                                         (list (list e (list r-car in)))
                                                         elem-code))))
                                 fk)))))))

             ;; Success: guard first, then catas, then the body with the
             ;; ellipsis-aware quasiquote in scope.
             (define (finish)
               (let* ((body-code
                       (cons r-let-syntax
                             (cons (list (list 'quasiquote r-qq))
                                   body)))
                      (cata-code
                       (let loop ((cs catas) (e body-code))
                         (if (null? cs)
                             e
                             (let* ((c (car cs))
                                    (tmp (car c)) (op (cadr c))
                                    (cvs (car (cddr c)))
                                    (d (cadr (cddr c))))
                               (loop (cdr cs)
                                     (list r-apply
                                           (list r-lambda cvs e)
                                           (list r-cata
                                                 (or op self) tmp
                                                 d (length cvs)))))))))
                 (if has-guard
                     (list r-if (cons r-and guard-tests)
                           cata-code (list kf))
                     cata-code)))

             (cp pat t finish (list kf) 0)))

         ;; ---- transformer entry ----
         (if (not (pair? (cdr form)))
             (verr "missing expression" form))
         (let ((expr (cadr form))
               (clauses (cddr form))
               (self (fresh "self"))
               (t (fresh "t")))
           (define (compile-clauses clauses)
             (if (null? clauses)
                 (list r-fail t)
                 (let ((kf (fresh "kf")))
                   (list r-let
                         (list (list kf
                                     (list r-lambda '()
                                           (compile-clauses (cdr clauses)))))
                         (compile-clause (car clauses) t self kf)))))
           (list r-letrec
                 (list (list self
                             (list r-lambda (list t)
                                   (compile-clauses clauses))))
                 (list self expr))))))))
