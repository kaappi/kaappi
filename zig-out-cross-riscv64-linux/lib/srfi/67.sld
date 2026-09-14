;; SRFI 67: Compare Procedures
;;
;; Adapted from the reference implementation by Sebastian Egner and
;; Jens Axel Soegaard (2005).  Ported to R7RS define-library form for
;; Kaappi.  Uses syntax-rules only (no syntax-case).
;;
;; A "compare procedure" is a procedure (x y) -> {-1, 0, 1}.

(define-library (srfi 67)
  (import (scheme base)
          (scheme char)
          (scheme case-lambda)
          (srfi 27))
  (export
   ;; 3-way conditional
   if3
   ;; 2-way conditionals
   if=? if<? if>? if<=? if>=? if-not=?
   ;; comparison predicates (variable arity)
   =? <? >? <=? >=? not=?
   ;; 3-element interval tests
   </<? </<=? <=/<? <=/<=?
   >/>? >/>=? >=/>? >=/>=?
   ;; chain tests
   chain=? chain<? chain>? chain<=? chain>=?
   ;; pairwise
   pairwise-not=?
   ;; min / max / selection
   min-compare max-compare kth-largest
   ;; compare from predicates
   compare-by< compare-by> compare-by<= compare-by>=
   compare-by=/< compare-by=/>
   ;; construction macros
   refine-compare select-compare cond-compare
   ;; atomic type compares
   boolean-compare
   char-compare char-compare-ci
   string-compare string-compare-ci
   symbol-compare
   integer-compare rational-compare real-compare
   complex-compare number-compare
   ;; compound type compares
   pair-compare-car pair-compare-cdr
   pair-compare list-compare list-compare-as-vector
   vector-compare vector-compare-as-list
   ;; default
   default-compare
   ;; debug
   debug-compare)
  (begin

    ;; ----------------------------------------------------------------
    ;; Internal helpers
    ;; ----------------------------------------------------------------

    (define (compare:checked result compare . args)
      (for-each (lambda (x) (compare x x)) args)
      result)

    ;; ----------------------------------------------------------------
    ;; Type-check helper macro
    ;; ----------------------------------------------------------------

    (define-syntax compare:type-check
      (syntax-rules ()
        ((compare:type-check type? type-name x)
         (if (not (type? x))
             (error (string-append "not " type-name ":") x)))
        ((compare:type-check type? type-name x y)
         (begin (compare:type-check type? type-name x)
                (compare:type-check type? type-name y)))))

    ;; ----------------------------------------------------------------
    ;; 3-sided conditional
    ;; ----------------------------------------------------------------

    (define-syntax if3
      (syntax-rules ()
        ((if3 c less equal greater)
         (case c
           ((-1) less)
           ((0)  equal)
           ((1)  greater)
           (else (error "comparison value not in {-1,0,1}"))))))

    ;; ----------------------------------------------------------------
    ;; 2-sided conditionals
    ;; ----------------------------------------------------------------

    (define-syntax compare:if-rel?
      (syntax-rules ()
        ((compare:if-rel? c-cases a-cases c consequence)
         (compare:if-rel? c-cases a-cases c consequence (if #f #f)))
        ((compare:if-rel? c-cases a-cases c consequence alternate)
         (case c
           (c-cases consequence)
           (a-cases alternate)
           (else (error "comparison value not in {-1,0,1}"))))))

    (define-syntax if=?
      (syntax-rules ()
        ((if=? arg ...)
         (compare:if-rel? (0) (-1 1) arg ...))))

    (define-syntax if<?
      (syntax-rules ()
        ((if<? arg ...)
         (compare:if-rel? (-1) (0 1) arg ...))))

    (define-syntax if>?
      (syntax-rules ()
        ((if>? arg ...)
         (compare:if-rel? (1) (-1 0) arg ...))))

    (define-syntax if<=?
      (syntax-rules ()
        ((if<=? arg ...)
         (compare:if-rel? (-1 0) (1) arg ...))))

    (define-syntax if>=?
      (syntax-rules ()
        ((if>=? arg ...)
         (compare:if-rel? (0 1) (-1) arg ...))))

    (define-syntax if-not=?
      (syntax-rules ()
        ((if-not=? arg ...)
         (compare:if-rel? (-1 1) (0) arg ...))))

    ;; ----------------------------------------------------------------
    ;; Comparison predicates (variable arity via case-lambda)
    ;; ----------------------------------------------------------------

    ;; Helper macro that defines a predicate rel? in terms of if-rel?.
    ;; The reference uses a macro-generating-define but we expand it
    ;; inline since Kaappi's syntax-rules handles this well.

    (define =?
      (case-lambda
        (()          (lambda (x y) (if=? (default-compare x y) #t #f)))
        ((compare)   (lambda (x y) (if=? (compare x y) #t #f)))
        ((x y)       (if=? (default-compare x y) #t #f))
        ((compare x y)
         (if (procedure? compare)
             (if=? (compare x y) #t #f)
             (error "not a procedure (Did you mean =?): " compare)))))

    (define <?
      (case-lambda
        (()          (lambda (x y) (if<? (default-compare x y) #t #f)))
        ((compare)   (lambda (x y) (if<? (compare x y) #t #f)))
        ((x y)       (if<? (default-compare x y) #t #f))
        ((compare x y)
         (if (procedure? compare)
             (if<? (compare x y) #t #f)
             (error "not a procedure (Did you mean <?): " compare)))))

    (define >?
      (case-lambda
        (()          (lambda (x y) (if>? (default-compare x y) #t #f)))
        ((compare)   (lambda (x y) (if>? (compare x y) #t #f)))
        ((x y)       (if>? (default-compare x y) #t #f))
        ((compare x y)
         (if (procedure? compare)
             (if>? (compare x y) #t #f)
             (error "not a procedure (Did you mean >?): " compare)))))

    (define <=?
      (case-lambda
        (()          (lambda (x y) (if<=? (default-compare x y) #t #f)))
        ((compare)   (lambda (x y) (if<=? (compare x y) #t #f)))
        ((x y)       (if<=? (default-compare x y) #t #f))
        ((compare x y)
         (if (procedure? compare)
             (if<=? (compare x y) #t #f)
             (error "not a procedure (Did you mean <=?): " compare)))))

    (define >=?
      (case-lambda
        (()          (lambda (x y) (if>=? (default-compare x y) #t #f)))
        ((compare)   (lambda (x y) (if>=? (compare x y) #t #f)))
        ((x y)       (if>=? (default-compare x y) #t #f))
        ((compare x y)
         (if (procedure? compare)
             (if>=? (compare x y) #t #f)
             (error "not a procedure (Did you mean >=?): " compare)))))

    (define not=?
      (case-lambda
        (()          (lambda (x y) (if-not=? (default-compare x y) #t #f)))
        ((compare)   (lambda (x y) (if-not=? (compare x y) #t #f)))
        ((x y)       (if-not=? (default-compare x y) #t #f))
        ((compare x y)
         (if (procedure? compare)
             (if-not=? (compare x y) #t #f)
             (error "not a procedure (Did you mean not=?): " compare)))))

    ;; ----------------------------------------------------------------
    ;; 3-element interval tests (variable arity via case-lambda)
    ;; ----------------------------------------------------------------

    (define </<?
      (case-lambda
        (()
         (lambda (x y z)
           (if<? (default-compare x y)
                 (if<? (default-compare y z) #t #f)
                 (compare:checked #f default-compare z))))
        ((compare)
         (lambda (x y z)
           (if<? (compare x y)
                 (if<? (compare y z) #t #f)
                 (compare:checked #f compare z))))
        ((x y z)
         (if<? (default-compare x y)
               (if<? (default-compare y z) #t #f)
               (compare:checked #f default-compare z)))
        ((compare x y z)
         (if<? (compare x y)
               (if<? (compare y z) #t #f)
               (compare:checked #f compare z)))))

    (define </<=?
      (case-lambda
        (()
         (lambda (x y z)
           (if<? (default-compare x y)
                 (if<=? (default-compare y z) #t #f)
                 (compare:checked #f default-compare z))))
        ((compare)
         (lambda (x y z)
           (if<? (compare x y)
                 (if<=? (compare y z) #t #f)
                 (compare:checked #f compare z))))
        ((x y z)
         (if<? (default-compare x y)
               (if<=? (default-compare y z) #t #f)
               (compare:checked #f default-compare z)))
        ((compare x y z)
         (if<? (compare x y)
               (if<=? (compare y z) #t #f)
               (compare:checked #f compare z)))))

    (define <=/<?
      (case-lambda
        (()
         (lambda (x y z)
           (if<=? (default-compare x y)
                  (if<? (default-compare y z) #t #f)
                  (compare:checked #f default-compare z))))
        ((compare)
         (lambda (x y z)
           (if<=? (compare x y)
                  (if<? (compare y z) #t #f)
                  (compare:checked #f compare z))))
        ((x y z)
         (if<=? (default-compare x y)
                (if<? (default-compare y z) #t #f)
                (compare:checked #f default-compare z)))
        ((compare x y z)
         (if<=? (compare x y)
                (if<? (compare y z) #t #f)
                (compare:checked #f compare z)))))

    (define <=/<=?
      (case-lambda
        (()
         (lambda (x y z)
           (if<=? (default-compare x y)
                  (if<=? (default-compare y z) #t #f)
                  (compare:checked #f default-compare z))))
        ((compare)
         (lambda (x y z)
           (if<=? (compare x y)
                  (if<=? (compare y z) #t #f)
                  (compare:checked #f compare z))))
        ((x y z)
         (if<=? (default-compare x y)
                (if<=? (default-compare y z) #t #f)
                (compare:checked #f default-compare z)))
        ((compare x y z)
         (if<=? (compare x y)
                (if<=? (compare y z) #t #f)
                (compare:checked #f compare z)))))

    (define >/>?
      (case-lambda
        (()
         (lambda (x y z)
           (if>? (default-compare x y)
                 (if>? (default-compare y z) #t #f)
                 (compare:checked #f default-compare z))))
        ((compare)
         (lambda (x y z)
           (if>? (compare x y)
                 (if>? (compare y z) #t #f)
                 (compare:checked #f compare z))))
        ((x y z)
         (if>? (default-compare x y)
               (if>? (default-compare y z) #t #f)
               (compare:checked #f default-compare z)))
        ((compare x y z)
         (if>? (compare x y)
               (if>? (compare y z) #t #f)
               (compare:checked #f compare z)))))

    (define >/>=?
      (case-lambda
        (()
         (lambda (x y z)
           (if>? (default-compare x y)
                 (if>=? (default-compare y z) #t #f)
                 (compare:checked #f default-compare z))))
        ((compare)
         (lambda (x y z)
           (if>? (compare x y)
                 (if>=? (compare y z) #t #f)
                 (compare:checked #f compare z))))
        ((x y z)
         (if>? (default-compare x y)
               (if>=? (default-compare y z) #t #f)
               (compare:checked #f default-compare z)))
        ((compare x y z)
         (if>? (compare x y)
               (if>=? (compare y z) #t #f)
               (compare:checked #f compare z)))))

    (define >=/>?
      (case-lambda
        (()
         (lambda (x y z)
           (if>=? (default-compare x y)
                  (if>? (default-compare y z) #t #f)
                  (compare:checked #f default-compare z))))
        ((compare)
         (lambda (x y z)
           (if>=? (compare x y)
                  (if>? (compare y z) #t #f)
                  (compare:checked #f compare z))))
        ((x y z)
         (if>=? (default-compare x y)
                (if>? (default-compare y z) #t #f)
                (compare:checked #f default-compare z)))
        ((compare x y z)
         (if>=? (compare x y)
                (if>? (compare y z) #t #f)
                (compare:checked #f compare z)))))

    (define >=/>=?
      (case-lambda
        (()
         (lambda (x y z)
           (if>=? (default-compare x y)
                  (if>=? (default-compare y z) #t #f)
                  (compare:checked #f default-compare z))))
        ((compare)
         (lambda (x y z)
           (if>=? (compare x y)
                  (if>=? (compare y z) #t #f)
                  (compare:checked #f compare z))))
        ((x y z)
         (if>=? (default-compare x y)
                (if>=? (default-compare y z) #t #f)
                (compare:checked #f default-compare z)))
        ((compare x y z)
         (if>=? (compare x y)
                (if>=? (compare y z) #t #f)
                (compare:checked #f compare z)))))

    ;; ----------------------------------------------------------------
    ;; Chain tests (arbitrary length)
    ;; ----------------------------------------------------------------

    (define chain=?
      (case-lambda
        ((compare)
         #t)
        ((compare x1)
         (compare:checked #t compare x1))
        ((compare x1 x2)
         (if=? (compare x1 x2) #t #f))
        ((compare x1 x2 x3)
         (if=? (compare x1 x2)
               (if=? (compare x2 x3) #t #f)
               (compare:checked #f compare x3)))
        ((compare x1 x2 . x3+)
         (if=? (compare x1 x2)
               (let chain? ((head x2) (tail x3+))
                 (if (null? tail)
                     #t
                     (if=? (compare head (car tail))
                           (chain? (car tail) (cdr tail))
                           (apply compare:checked #f compare (cdr tail)))))
               (apply compare:checked #f compare x3+)))))

    (define chain<?
      (case-lambda
        ((compare)
         #t)
        ((compare x1)
         (compare:checked #t compare x1))
        ((compare x1 x2)
         (if<? (compare x1 x2) #t #f))
        ((compare x1 x2 x3)
         (if<? (compare x1 x2)
               (if<? (compare x2 x3) #t #f)
               (compare:checked #f compare x3)))
        ((compare x1 x2 . x3+)
         (if<? (compare x1 x2)
               (let chain? ((head x2) (tail x3+))
                 (if (null? tail)
                     #t
                     (if<? (compare head (car tail))
                           (chain? (car tail) (cdr tail))
                           (apply compare:checked #f compare (cdr tail)))))
               (apply compare:checked #f compare x3+)))))

    (define chain>?
      (case-lambda
        ((compare)
         #t)
        ((compare x1)
         (compare:checked #t compare x1))
        ((compare x1 x2)
         (if>? (compare x1 x2) #t #f))
        ((compare x1 x2 x3)
         (if>? (compare x1 x2)
               (if>? (compare x2 x3) #t #f)
               (compare:checked #f compare x3)))
        ((compare x1 x2 . x3+)
         (if>? (compare x1 x2)
               (let chain? ((head x2) (tail x3+))
                 (if (null? tail)
                     #t
                     (if>? (compare head (car tail))
                           (chain? (car tail) (cdr tail))
                           (apply compare:checked #f compare (cdr tail)))))
               (apply compare:checked #f compare x3+)))))

    (define chain<=?
      (case-lambda
        ((compare)
         #t)
        ((compare x1)
         (compare:checked #t compare x1))
        ((compare x1 x2)
         (if<=? (compare x1 x2) #t #f))
        ((compare x1 x2 x3)
         (if<=? (compare x1 x2)
                (if<=? (compare x2 x3) #t #f)
                (compare:checked #f compare x3)))
        ((compare x1 x2 . x3+)
         (if<=? (compare x1 x2)
                (let chain? ((head x2) (tail x3+))
                  (if (null? tail)
                      #t
                      (if<=? (compare head (car tail))
                             (chain? (car tail) (cdr tail))
                             (apply compare:checked #f compare (cdr tail)))))
                (apply compare:checked #f compare x3+)))))

    (define chain>=?
      (case-lambda
        ((compare)
         #t)
        ((compare x1)
         (compare:checked #t compare x1))
        ((compare x1 x2)
         (if>=? (compare x1 x2) #t #f))
        ((compare x1 x2 x3)
         (if>=? (compare x1 x2)
                (if>=? (compare x2 x3) #t #f)
                (compare:checked #f compare x3)))
        ((compare x1 x2 . x3+)
         (if>=? (compare x1 x2)
                (let chain? ((head x2) (tail x3+))
                  (if (null? tail)
                      #t
                      (if>=? (compare head (car tail))
                             (chain? (car tail) (cdr tail))
                             (apply compare:checked #f compare (cdr tail)))))
                (apply compare:checked #f compare x3+)))))

    ;; ----------------------------------------------------------------
    ;; Pairwise inequality
    ;; ----------------------------------------------------------------

    (define pairwise-not=?
      (let ((num= =) (num<= <=) (num< <))
        (case-lambda
          ((compare)
           #t)
          ((compare x1)
           (compare:checked #t compare x1))
          ((compare x1 x2)
           (if-not=? (compare x1 x2) #t #f))
          ((compare x1 x2 x3)
           (if-not=? (compare x1 x2)
                     (if-not=? (compare x2 x3)
                               (if-not=? (compare x1 x3) #t #f)
                               #f)
                     (compare:checked #f compare x3)))
          ((compare . x1+)
           (let unequal? ((x x1+) (n (length x1+)) (unchecked? #t))
             (if (num< n 2)
                 (if (and unchecked? (num= n 1))
                     (compare:checked #t compare (car x))
                     #t)
                 (let* ((i-pivot (random-integer n))
                        (x-pivot (list-ref x i-pivot)))
                   (let split ((i 0) (x x) (x< '()) (x> '()))
                     (if (null? x)
                         (and (unequal? x< (length x<) #f)
                              (unequal? x> (length x>) #f))
                         (if (num= i i-pivot)
                             (split (+ i 1) (cdr x) x< x>)
                             (if3 (compare (car x) x-pivot)
                                  (split (+ i 1) (cdr x) (cons (car x) x<) x>)
                                  (if unchecked?
                                      (apply compare:checked #f compare (cdr x))
                                      #f)
                                  (split (+ i 1) (cdr x) x< (cons (car x) x>)))))))))))))

    ;; ----------------------------------------------------------------
    ;; Min / Max
    ;; ----------------------------------------------------------------

    (define min-compare
      (case-lambda
        ((compare x1)
         (compare:checked x1 compare x1))
        ((compare x1 x2)
         (if<=? (compare x1 x2) x1 x2))
        ((compare x1 x2 x3)
         (if<=? (compare x1 x2)
                (if<=? (compare x1 x3) x1 x3)
                (if<=? (compare x2 x3) x2 x3)))
        ((compare x1 x2 x3 x4)
         (if<=? (compare x1 x2)
                (if<=? (compare x1 x3)
                       (if<=? (compare x1 x4) x1 x4)
                       (if<=? (compare x3 x4) x3 x4))
                (if<=? (compare x2 x3)
                       (if<=? (compare x2 x4) x2 x4)
                       (if<=? (compare x3 x4) x3 x4))))
        ((compare x1 x2 . x3+)
         (let min ((xmin (if<=? (compare x1 x2) x1 x2)) (xs x3+))
           (if (null? xs)
               xmin
               (min (if<=? (compare xmin (car xs)) xmin (car xs))
                    (cdr xs)))))))

    (define max-compare
      (case-lambda
        ((compare x1)
         (compare:checked x1 compare x1))
        ((compare x1 x2)
         (if>=? (compare x1 x2) x1 x2))
        ((compare x1 x2 x3)
         (if>=? (compare x1 x2)
                (if>=? (compare x1 x3) x1 x3)
                (if>=? (compare x2 x3) x2 x3)))
        ((compare x1 x2 x3 x4)
         (if>=? (compare x1 x2)
                (if>=? (compare x1 x3)
                       (if>=? (compare x1 x4) x1 x4)
                       (if>=? (compare x3 x4) x3 x4))
                (if>=? (compare x2 x3)
                       (if>=? (compare x2 x4) x2 x4)
                       (if>=? (compare x3 x4) x3 x4))))
        ((compare x1 x2 . x3+)
         (let max ((xmax (if>=? (compare x1 x2) x1 x2)) (xs x3+))
           (if (null? xs)
               xmax
               (max (if>=? (compare xmax (car xs)) xmax (car xs))
                    (cdr xs)))))))

    ;; ----------------------------------------------------------------
    ;; kth-largest
    ;; ----------------------------------------------------------------

    (define kth-largest
      (let ((num= =) (num< <))
        (case-lambda
          ((compare k x0)
           (case (modulo k 1)
             ((0) (compare:checked x0 compare x0))
             (else (error "bad index" k))))
          ((compare k x0 x1)
           (case (modulo k 2)
             ((0) (if<=? (compare x0 x1) x0 x1))
             ((1) (if<=? (compare x0 x1) x1 x0))
             (else (error "bad index" k))))
          ((compare k x0 x1 x2)
           (case (modulo k 3)
             ((0) (if<=? (compare x0 x1)
                         (if<=? (compare x0 x2) x0 x2)
                         (if<=? (compare x1 x2) x1 x2)))
             ((1) (if3 (compare x0 x1)
                       (if<=? (compare x1 x2)
                              x1
                              (if<=? (compare x0 x2) x2 x0))
                       (if<=? (compare x0 x2) x1 x0)
                       (if<=? (compare x0 x2)
                              x0
                              (if<=? (compare x1 x2) x2 x1))))
             ((2) (if<=? (compare x0 x1)
                         (if<=? (compare x1 x2) x2 x1)
                         (if<=? (compare x0 x2) x2 x0)))
             (else (error "bad index" k))))
          ((compare k x0 . x1+)
           (if (not (and (integer? k) (exact? k)))
               (error "bad index" k))
           (let ((n (+ 1 (length x1+))))
             (let kth ((k   (modulo k n))
                       (n   n)
                       (rev #t)
                       (x   (cons x0 x1+)))
               (let ((pivot (list-ref x (random-integer n))))
                 (let split ((x x) (x< '()) (n< 0) (x= '()) (n= 0) (x> '()) (n> 0))
                   (if (null? x)
                       (cond
                         ((num< k n<)
                          (kth k n< (not rev) x<))
                         ((num< k (+ n< n=))
                          (if rev
                              (list-ref x= (- (- n= 1) (- k n<)))
                              (list-ref x= (- k n<))))
                         (else
                          (kth (- k (+ n< n=)) n> (not rev) x>)))
                       (if3 (compare (car x) pivot)
                            (split (cdr x) (cons (car x) x<) (+ n< 1) x= n= x> n>)
                            (split (cdr x) x< n< (cons (car x) x=) (+ n= 1) x> n>)
                            (split (cdr x) x< n< x= n= (cons (car x) x>) (+ n> 1))))))))))))

    ;; ----------------------------------------------------------------
    ;; Compare from predicates
    ;; ----------------------------------------------------------------

    (define compare-by<
      (case-lambda
        ((lt)     (lambda (x y) (if (lt x y) -1 (if (lt y x)  1 0))))
        ((lt x y)               (if (lt x y) -1 (if (lt y x)  1 0)))))

    (define compare-by>
      (case-lambda
        ((gt)     (lambda (x y) (if (gt x y) 1 (if (gt y x) -1 0))))
        ((gt x y)               (if (gt x y) 1 (if (gt y x) -1 0)))))

    (define compare-by<=
      (case-lambda
        ((le)     (lambda (x y) (if (le x y) (if (le y x) 0 -1) 1)))
        ((le x y)               (if (le x y) (if (le y x) 0 -1) 1))))

    (define compare-by>=
      (case-lambda
        ((ge)     (lambda (x y) (if (ge x y) (if (ge y x) 0 1) -1)))
        ((ge x y)               (if (ge x y) (if (ge y x) 0 1) -1))))

    (define compare-by=/<
      (case-lambda
        ((eq lt)     (lambda (x y) (if (eq x y) 0 (if (lt x y) -1 1))))
        ((eq lt x y)               (if (eq x y) 0 (if (lt x y) -1 1)))))

    (define compare-by=/>
      (case-lambda
        ((eq gt)     (lambda (x y) (if (eq x y) 0 (if (gt x y) 1 -1))))
        ((eq gt x y)               (if (eq x y) 0 (if (gt x y) 1 -1)))))

    ;; ----------------------------------------------------------------
    ;; Construction macros
    ;; ----------------------------------------------------------------

    (define-syntax refine-compare
      (syntax-rules ()
        ((refine-compare)
         0)
        ((refine-compare c1)
         c1)
        ((refine-compare c1 c2 cs ...)
         (if3 c1 -1 (refine-compare c2 cs ...) 1))))

    (define-syntax select-compare
      (syntax-rules (else)
        ((select-compare x y clause ...)
         (let ((x-val x) (y-val y))
           (select-compare (x-val y-val clause ...))))
        ;; internal form
        ((select-compare (x y))
         0)
        ((select-compare (x y (else c ...)))
         (refine-compare c ...))
        ((select-compare (x y (t? c ...) clause ...))
         (let ((t?-val t?))
           (let ((tx (t?-val x)) (ty (t?-val y)))
             (if tx
                 (if ty (refine-compare c ...) -1)
                 (if ty 1 (select-compare (x y clause ...)))))))))

    (define-syntax cond-compare
      (syntax-rules (else)
        ((cond-compare)
         0)
        ((cond-compare (else cs ...))
         (refine-compare cs ...))
        ((cond-compare ((tx ty) cs ...) clause ...)
         (let ((tx-val tx) (ty-val ty))
           (if tx-val
               (if ty-val (refine-compare cs ...) -1)
               (if ty-val 1 (cond-compare clause ...)))))))

    ;; ----------------------------------------------------------------
    ;; Atomic type compare procedures
    ;; ----------------------------------------------------------------

    (define (boolean-compare x y)
      (compare:type-check boolean? "boolean" x y)
      (if x (if y 0 1) (if y -1 0)))

    (define char-compare
      (let ((char=? char=?) (char<? char<?))
        (lambda (x y)
          (if (char? x)
              (if (eq? x y)
                  0
                  (if (char? y)
                      (if (char=? x y) 0 (if (char<? x y) -1 1))
                      (error "not char:" y)))
              (error "not char:" x)))))

    (define char-compare-ci
      (let ((char-ci=? char-ci=?) (char-ci<? char-ci<?))
        (lambda (x y)
          (if (char? x)
              (if (eq? x y)
                  0
                  (if (char? y)
                      (if (char-ci=? x y) 0 (if (char-ci<? x y) -1 1))
                      (error "not char:" y)))
              (error "not char:" x)))))

    (define string-compare
      (let ((string=? string=?) (string<? string<?))
        (lambda (x y)
          (if (string? x)
              (if (eq? x y)
                  0
                  (if (string? y)
                      (if (string=? x y) 0 (if (string<? x y) -1 1))
                      (error "not string:" y)))
              (error "not string:" x)))))

    (define string-compare-ci
      (let ((string-ci=? string-ci=?) (string-ci<? string-ci<?))
        (lambda (x y)
          (if (string? x)
              (if (eq? x y)
                  0
                  (if (string? y)
                      (if (string-ci=? x y) 0 (if (string-ci<? x y) -1 1))
                      (error "not string:" y)))
              (error "not string:" x)))))

    (define (symbol-compare x y)
      (compare:type-check symbol? "symbol" x y)
      (string-compare (symbol->string x) (symbol->string y)))

    (define integer-compare
      (let ((num= =) (num< <))
        (lambda (x y)
          (if (integer? x)
              (if (eq? x y)
                  0
                  (if (integer? y)
                      (if (num= x y) 0 (if (num< x y) -1 1))
                      (error "not integer:" y)))
              (error "not integer:" x)))))

    (define rational-compare
      (let ((num= =) (num< <))
        (lambda (x y)
          (if (rational? x)
              (if (eq? x y)
                  0
                  (if (rational? y)
                      (if (num= x y) 0 (if (num< x y) -1 1))
                      (error "not rational:" y)))
              (error "not rational:" x)))))

    (define real-compare
      (let ((num= =) (num< <))
        (lambda (x y)
          (if (real? x)
              (if (eq? x y)
                  0
                  (if (real? y)
                      (if (num= x y) 0 (if (num< x y) -1 1))
                      (error "not real:" y)))
              (error "not real:" x)))))

    (define (complex-compare x y)
      (compare:type-check complex? "complex" x y)
      (if (and (real? x) (real? y))
          (real-compare x y)
          (refine-compare (real-compare (real-part x) (real-part y))
                          (real-compare (imag-part x) (imag-part y)))))

    (define (number-compare x y)
      (compare:type-check number? "number" x y)
      (complex-compare x y))

    ;; ----------------------------------------------------------------
    ;; Compound data structure compare procedures
    ;; ----------------------------------------------------------------

    (define (pair-compare-car compare)
      (lambda (x y)
        (compare (car x) (car y))))

    (define (pair-compare-cdr compare)
      (lambda (x y)
        (compare (cdr x) (cdr y))))

    (define pair-compare
      (case-lambda
        ;; dotted pair
        ((pair-compare-car pair-compare-cdr x y)
         (refine-compare (pair-compare-car (car x) (car y))
                         (pair-compare-cdr (cdr x) (cdr y))))
        ;; possibly improper lists
        ((compare x y)
         (cond-compare
          (((null? x) (null? y)) 0)
          (((pair? x) (pair? y)) (compare              (car x) (car y))
                                 (pair-compare compare (cdr x) (cdr y)))
          (else                  (compare x y))))
        ;; convenience: default-compare
        ((x y)
         (pair-compare default-compare x y))))

    (define list-compare
      (case-lambda
        ((compare x y empty? head tail)
         (cond-compare
          (((empty? x) (empty? y)) 0)
          (else (compare              (head x) (head y))
                (list-compare compare (tail x) (tail y) empty? head tail))))
        ((x y empty? head tail)
         (list-compare default-compare x y empty? head tail))
        ((compare x y)
         (list-compare compare x y null? car cdr))
        ((x y)
         (list-compare default-compare x y null? car cdr))))

    (define list-compare-as-vector
      (case-lambda
        ((compare x y empty? head tail)
         (refine-compare
          (let compare-length ((x x) (y y))
            (cond-compare
             (((empty? x) (empty? y)) 0)
             (else (compare-length (tail x) (tail y)))))
          (list-compare compare x y empty? head tail)))
        ((x y empty? head tail)
         (list-compare-as-vector default-compare x y empty? head tail))
        ((compare x y)
         (list-compare-as-vector compare x y null? car cdr))
        ((x y)
         (list-compare-as-vector default-compare x y null? car cdr))))

    (define vector-compare
      (let ((num= =))
        (case-lambda
          ((compare x y size ref)
           (let ((n (size x)) (m (size y)))
             (refine-compare
              (integer-compare n m)
              (let compare-rest ((i 0))
                (if (num= i n)
                    0
                    (refine-compare (compare (ref x i) (ref y i))
                                    (compare-rest (+ i 1))))))))
          ((x y size ref)
           (vector-compare default-compare x y size ref))
          ((compare x y)
           (vector-compare compare x y vector-length vector-ref))
          ((x y)
           (vector-compare default-compare x y vector-length vector-ref)))))

    (define vector-compare-as-list
      (let ((num= =))
        (case-lambda
          ((compare x y size ref)
           (let ((nx (size x)) (ny (size y)))
             (let ((n (min nx ny)))
               (let compare-rest ((i 0))
                 (if (num= i n)
                     (integer-compare nx ny)
                     (refine-compare (compare (ref x i) (ref y i))
                                     (compare-rest (+ i 1))))))))
          ((x y size ref)
           (vector-compare-as-list default-compare x y size ref))
          ((compare x y)
           (vector-compare-as-list compare x y vector-length vector-ref))
          ((x y)
           (vector-compare-as-list default-compare x y vector-length vector-ref)))))

    ;; ----------------------------------------------------------------
    ;; default-compare
    ;; ----------------------------------------------------------------

    (define (default-compare x y)
      (select-compare
       x y
       (null?    0)
       (pair?    (default-compare (car x) (car y))
                 (default-compare (cdr x) (cdr y)))
       (boolean? (boolean-compare x y))
       (char?    (char-compare    x y))
       (string?  (string-compare  x y))
       (symbol?  (symbol-compare  x y))
       (number?  (number-compare  x y))
       (vector?  (vector-compare default-compare x y))
       (else (error "unrecognized type in default-compare" x y))))

    ;; ----------------------------------------------------------------
    ;; debug-compare
    ;; ----------------------------------------------------------------

    (define (debug-compare c)

      (define (checked-value c x y)
        (let ((c-xy (c x y)))
          (if (or (eqv? c-xy -1) (eqv? c-xy 0) (eqv? c-xy 1))
              c-xy
              (error "compare value not in {-1,0,1}" c-xy (list c x y)))))

      (define (random-boolean)
        (zero? (random-integer 2)))

      (let ((z? #f) (z #f))
        (lambda (x y)
          (let ((c-xx (checked-value c x x))
                (c-yy (checked-value c y y))
                (c-xy (checked-value c x y))
                (c-yx (checked-value c y x)))
            (if (not (zero? c-xx))
                (error "compare error: not reflexive" c x))
            (if (not (zero? c-yy))
                (error "compare error: not reflexive" c y))
            (if (not (zero? (+ c-xy c-yx)))
                (error "compare error: not anti-symmetric" c x y))
            (if z?
                (let ((c-xz (checked-value c x z))
                      (c-zx (checked-value c z x))
                      (c-yz (checked-value c y z))
                      (c-zy (checked-value c z y)))
                  (if (not (zero? (+ c-xz c-zx)))
                      (error "compare error: not anti-symmetric" c x z))
                  (if (not (zero? (+ c-yz c-zy)))
                      (error "compare error: not anti-symmetric" c y z)))
                (set! z? #t))
            (set! z (if (random-boolean) x y))
            c-xy))))))
