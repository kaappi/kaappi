(define-library (srfi 146)
  (import (scheme base) (scheme case-lambda) (scheme cxr) (srfi 1) (srfi 128))
  (export
    mapping mapping-unfold mapping/ordered mapping-unfold/ordered
    mapping? mapping-contains? mapping-empty? mapping-disjoint?
    mapping-ref mapping-ref/default mapping-key-comparator
    mapping-adjoin mapping-adjoin! mapping-set mapping-set!
    mapping-replace mapping-replace! mapping-delete mapping-delete!
    mapping-delete-all mapping-delete-all!
    mapping-intern mapping-intern!
    mapping-update mapping-update! mapping-update/default mapping-update!/default
    mapping-pop mapping-pop! mapping-search mapping-search!
    mapping-size mapping-find mapping-count mapping-any? mapping-every?
    mapping-keys mapping-values mapping-entries
    mapping-map mapping-map->list mapping-for-each mapping-fold
    mapping-filter mapping-filter! mapping-remove mapping-remove!
    mapping-partition mapping-partition!
    mapping-copy mapping->alist
    alist->mapping alist->mapping! alist->mapping/ordered alist->mapping/ordered!
    mapping=? mapping<? mapping>? mapping<=? mapping>=?
    mapping-union mapping-intersection mapping-difference mapping-xor
    mapping-union! mapping-intersection! mapping-difference! mapping-xor!
    mapping-min-key mapping-max-key mapping-min-value mapping-max-value
    mapping-min-entry mapping-max-entry
    mapping-key-predecessor mapping-key-successor
    mapping-range= mapping-range< mapping-range> mapping-range<= mapping-range>=
    mapping-range=! mapping-range<! mapping-range>! mapping-range<=! mapping-range>=!
    mapping-split mapping-split!
    mapping-catenate mapping-catenate!
    mapping-map/monotone mapping-map/monotone!
    mapping-fold/reverse
    make-mapping-comparator mapping-comparator)
  (begin

    ;;; Functional red-black tree (Okasaki)
    ;;; Node: () = empty, (color left key value right) where color is 'R or 'B

    (define %empty '())
    (define (%node c l k v r) (list c l k v r))
    (define (%rbt-empty? t) (null? t))
    (define (%rbt-color t) (car t))
    (define (%rbt-left t) (cadr t))
    (define (%rbt-key t) (caddr t))
    (define (%rbt-val t) (cadddr t))
    (define (%rbt-right t) (car (cddddr t)))

    (define (%rbt-balance c l k v r)
      (cond
        ((and (eq? c 'B) (not (%rbt-empty? l)) (eq? (%rbt-color l) 'R)
              (not (%rbt-empty? (%rbt-left l))) (eq? (%rbt-color (%rbt-left l)) 'R))
         (let ((ll (%rbt-left l)))
           (%node 'R (%node 'B (%rbt-left ll) (%rbt-key ll) (%rbt-val ll) (%rbt-right ll))
                    (%rbt-key l) (%rbt-val l)
                    (%node 'B (%rbt-right l) k v r))))
        ((and (eq? c 'B) (not (%rbt-empty? l)) (eq? (%rbt-color l) 'R)
              (not (%rbt-empty? (%rbt-right l))) (eq? (%rbt-color (%rbt-right l)) 'R))
         (let ((lr (%rbt-right l)))
           (%node 'R (%node 'B (%rbt-left l) (%rbt-key l) (%rbt-val l) (%rbt-left lr))
                    (%rbt-key lr) (%rbt-val lr)
                    (%node 'B (%rbt-right lr) k v r))))
        ((and (eq? c 'B) (not (%rbt-empty? r)) (eq? (%rbt-color r) 'R)
              (not (%rbt-empty? (%rbt-left r))) (eq? (%rbt-color (%rbt-left r)) 'R))
         (let ((rl (%rbt-left r)))
           (%node 'R (%node 'B l k v (%rbt-left rl))
                    (%rbt-key rl) (%rbt-val rl)
                    (%node 'B (%rbt-right rl) (%rbt-key r) (%rbt-val r) (%rbt-right r)))))
        ((and (eq? c 'B) (not (%rbt-empty? r)) (eq? (%rbt-color r) 'R)
              (not (%rbt-empty? (%rbt-right r))) (eq? (%rbt-color (%rbt-right r)) 'R))
         (let ((rr (%rbt-right r)))
           (%node 'R (%node 'B l k v (%rbt-left r))
                    (%rbt-key r) (%rbt-val r)
                    (%node 'B (%rbt-left rr) (%rbt-key rr) (%rbt-val rr) (%rbt-right rr)))))
        (else (%node c l k v r))))

    (define (%rbt-insert t key val lt eq)
      (define (ins t)
        (if (%rbt-empty? t) (%node 'R %empty key val %empty)
            (let ((k (%rbt-key t)) (v (%rbt-val t))
                  (l (%rbt-left t)) (r (%rbt-right t)) (c (%rbt-color t)))
              (cond
                ((eq key k) (%node c l key val r))
                ((lt key k) (%rbt-balance c (ins l) k v r))
                (else (%rbt-balance c l k v (ins r)))))))
      (let ((t2 (ins t)))
        (%node 'B (%rbt-left t2) (%rbt-key t2) (%rbt-val t2) (%rbt-right t2))))

    (define (%rbt-adjoin t key val lt eq)
      (define (ins t)
        (if (%rbt-empty? t) (%node 'R %empty key val %empty)
            (let ((k (%rbt-key t)) (v (%rbt-val t))
                  (l (%rbt-left t)) (r (%rbt-right t)) (c (%rbt-color t)))
              (cond
                ((eq key k) t)
                ((lt key k) (%rbt-balance c (ins l) k v r))
                (else (%rbt-balance c l k v (ins r)))))))
      (let ((t2 (ins t)))
        (%node 'B (%rbt-left t2) (%rbt-key t2) (%rbt-val t2) (%rbt-right t2))))

    (define (%rbt-lookup t key lt eq)
      (if (%rbt-empty? t) #f
          (cond
            ((eq key (%rbt-key t)) (cons (%rbt-key t) (%rbt-val t)))
            ((lt key (%rbt-key t)) (%rbt-lookup (%rbt-left t) key lt eq))
            (else (%rbt-lookup (%rbt-right t) key lt eq)))))

    (define (%rbt-delete t key lt eq)
      (define (%rbt-min t)
        (if (%rbt-empty? (%rbt-left t)) (cons (%rbt-key t) (%rbt-val t))
            (%rbt-min (%rbt-left t))))
      (define (del t)
        (if (%rbt-empty? t) %empty
            (cond
              ((eq key (%rbt-key t))
               (if (%rbt-empty? (%rbt-right t)) (%rbt-left t)
                   (let ((succ (%rbt-min (%rbt-right t))))
                     (%rbt-balance (%rbt-color t) (%rbt-left t) (car succ) (cdr succ)
                                   (del-min (%rbt-right t))))))
              ((lt key (%rbt-key t))
               (%rbt-balance (%rbt-color t) (del (%rbt-left t))
                             (%rbt-key t) (%rbt-val t) (%rbt-right t)))
              (else
               (%rbt-balance (%rbt-color t) (%rbt-left t) (%rbt-key t) (%rbt-val t)
                             (del (%rbt-right t)))))))
      (define (del-min t)
        (if (%rbt-empty? (%rbt-left t)) (%rbt-right t)
            (%rbt-balance (%rbt-color t) (del-min (%rbt-left t))
                          (%rbt-key t) (%rbt-val t) (%rbt-right t))))
      (let ((t2 (del t)))
        (if (%rbt-empty? t2) %empty
            (%node 'B (%rbt-left t2) (%rbt-key t2) (%rbt-val t2) (%rbt-right t2)))))

    (define (%rbt-fold proc nil t)
      (if (%rbt-empty? t) nil
          (%rbt-fold proc
                     (proc (%rbt-key t) (%rbt-val t)
                           (%rbt-fold proc nil (%rbt-left t)))
                     (%rbt-right t))))

    (define (%rbt-fold-right proc nil t)
      (if (%rbt-empty? t) nil
          (%rbt-fold-right proc
                           (proc (%rbt-key t) (%rbt-val t)
                                 (%rbt-fold-right proc nil (%rbt-right t)))
                           (%rbt-left t))))

    (define (%rbt-size t)
      (if (%rbt-empty? t) 0
          (+ 1 (%rbt-size (%rbt-left t)) (%rbt-size (%rbt-right t)))))

    (define (%rbt-min t)
      (if (%rbt-empty? (%rbt-left t)) (cons (%rbt-key t) (%rbt-val t))
          (%rbt-min (%rbt-left t))))

    (define (%rbt-max t)
      (if (%rbt-empty? (%rbt-right t)) (cons (%rbt-key t) (%rbt-val t))
          (%rbt-max (%rbt-right t))))

    (define (%rbt->alist t)
      (%rbt-fold-right (lambda (k v acc) (cons (cons k v) acc)) '() t))

    ;;; Mapping record — now backed by RB tree

    (define-record-type <mapping>
      (%make-mapping comparator tree)
      mapping?
      (comparator %mapping-comparator)
      (tree %mapping-tree))

    (define (%cmp< m) (comparator-ordering-predicate (%mapping-comparator m)))
    (define (%cmp= m) (comparator-equality-predicate (%mapping-comparator m)))

    ;;; Constructors

    (define (mapping comparator . args)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let loop ((args args) (t %empty))
          (if (null? args) (%make-mapping comparator t)
              (loop (cddr args) (%rbt-insert t (car args) (cadr args) lt eq))))))

    (define mapping/ordered mapping)

    (define (mapping-unfold stop? mapper successor seed comparator)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let loop ((seed seed) (t %empty))
          (if (stop? seed) (%make-mapping comparator t)
              (let-values (((key val) (mapper seed)))
                (loop (successor seed) (%rbt-insert t key val lt eq)))))))

    (define mapping-unfold/ordered mapping-unfold)

    ;;; Predicates

    (define (mapping-contains? m key)
      (if (%rbt-lookup (%mapping-tree m) key (%cmp< m) (%cmp= m)) #t #f))

    (define (mapping-empty? m) (%rbt-empty? (%mapping-tree m)))

    (define (mapping-disjoint? m1 m2)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (%rbt-fold (lambda (k v acc) (and acc (not (%rbt-lookup (%mapping-tree m2) k lt eq))))
                   #t (%mapping-tree m1))))

    ;;; Accessors

    (define mapping-ref
      (case-lambda
        ((m key)
         (let ((entry (%rbt-lookup (%mapping-tree m) key (%cmp< m) (%cmp= m))))
           (if entry (cdr entry) (error "mapping-ref: key not found" key))))
        ((m key failure)
         (let ((entry (%rbt-lookup (%mapping-tree m) key (%cmp< m) (%cmp= m))))
           (if entry (cdr entry) (failure))))
        ((m key failure success)
         (let ((entry (%rbt-lookup (%mapping-tree m) key (%cmp< m) (%cmp= m))))
           (if entry (success (cdr entry)) (failure))))))

    (define (mapping-ref/default m key default)
      (let ((entry (%rbt-lookup (%mapping-tree m) key (%cmp< m) (%cmp= m))))
        (if entry (cdr entry) default)))

    (define (mapping-key-comparator m) (%mapping-comparator m))

    ;;; Updaters

    (define (mapping-set m . args)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (let loop ((args args) (t (%mapping-tree m)))
          (if (null? args) (%make-mapping (%mapping-comparator m) t)
              (loop (cddr args) (%rbt-insert t (car args) (cadr args) lt eq))))))
    (define mapping-set! mapping-set)

    (define (mapping-adjoin m . args)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (let loop ((args args) (t (%mapping-tree m)))
          (if (null? args) (%make-mapping (%mapping-comparator m) t)
              (loop (cddr args) (%rbt-adjoin t (car args) (cadr args) lt eq))))))
    (define mapping-adjoin! mapping-adjoin)

    (define (mapping-replace m key val)
      (if (mapping-contains? m key) (mapping-set m key val) m))
    (define mapping-replace! mapping-replace)

    (define (mapping-delete m . keys) (mapping-delete-all m keys))
    (define mapping-delete! mapping-delete)

    (define (mapping-delete-all m key-list)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (let loop ((keys key-list) (t (%mapping-tree m)))
          (if (null? keys) (%make-mapping (%mapping-comparator m) t)
              (loop (cdr keys) (%rbt-delete t (car keys) lt eq))))))
    (define mapping-delete-all! mapping-delete-all)

    (define (mapping-intern m key failure)
      (let ((entry (%rbt-lookup (%mapping-tree m) key (%cmp< m) (%cmp= m))))
        (if entry (values m (cdr entry))
            (let ((val (failure))) (values (mapping-set m key val) val)))))
    (define mapping-intern! mapping-intern)

    (define mapping-update
      (case-lambda
        ((m key updater)
         (mapping-update m key updater
                         (lambda () (error "mapping-update: key not found" key))
                         (lambda (v) v)))
        ((m key updater failure)
         (mapping-update m key updater failure (lambda (v) v)))
        ((m key updater failure success)
         (let ((entry (%rbt-lookup (%mapping-tree m) key (%cmp< m) (%cmp= m))))
           (if entry
               (mapping-set m key (updater (success (cdr entry))))
               (mapping-set m key (updater (failure))))))))
    (define mapping-update! mapping-update)

    (define (mapping-update/default m key updater default)
      (mapping-set m key (updater (mapping-ref/default m key default))))
    (define mapping-update!/default mapping-update/default)

    (define mapping-pop
      (case-lambda
        ((m) (mapping-pop m (lambda () (error "mapping-pop: empty mapping"))))
        ((m failure)
         (if (mapping-empty? m) (failure)
             (let ((entry (%rbt-min (%mapping-tree m))))
               (values (mapping-delete m (car entry)) (car entry) (cdr entry)))))))
    (define mapping-pop! mapping-pop)

    (define (mapping-search m key failure success)
      (let ((entry (%rbt-lookup (%mapping-tree m) key (%cmp< m) (%cmp= m))))
        (if entry
            (success (car entry) (cdr entry)
              (lambda (new-key new-val obj) (values (mapping-set (mapping-delete m key) new-key new-val) obj))
              (lambda (obj) (values (mapping-delete m key) obj)))
            (failure
              (lambda (val obj) (values (mapping-set m key val) obj))
              (lambda (obj) (values m obj))))))
    (define mapping-search! mapping-search)

    ;;; Whole mapping

    (define (mapping-size m) (%rbt-size (%mapping-tree m)))

    (define (mapping-find pred m failure)
      (%rbt-fold (lambda (k v acc)
                   (if (eq? acc 'not-found)
                       (if (pred k v) (cons k v) acc)
                       acc))
                 'not-found (%mapping-tree m))
      (let ((result (%rbt-fold (lambda (k v acc)
                                 (if (pair? acc) acc
                                     (if (pred k v) (cons k v) acc)))
                               #f (%mapping-tree m))))
        (if result (values (car result) (cdr result)) (failure))))

    (define (mapping-count pred m)
      (%rbt-fold (lambda (k v acc) (if (pred k v) (+ acc 1) acc)) 0 (%mapping-tree m)))

    (define (mapping-any? pred m)
      (%rbt-fold (lambda (k v acc) (or acc (pred k v))) #f (%mapping-tree m)))

    (define (mapping-every? pred m)
      (%rbt-fold (lambda (k v acc) (and acc (pred k v))) #t (%mapping-tree m)))

    (define (mapping-keys m) (%rbt-fold-right (lambda (k v acc) (cons k acc)) '() (%mapping-tree m)))
    (define (mapping-values m) (%rbt-fold-right (lambda (k v acc) (cons v acc)) '() (%mapping-tree m)))
    (define (mapping-entries m)
      (values (mapping-keys m) (mapping-values m)))

    ;;; Mapping and folding

    (define (mapping-map proc comparator m)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (%rbt-fold (lambda (k v acc)
                     (let-values (((nk nv) (proc k v)))
                       (%rbt-insert acc nk nv lt eq)))
                   %empty (%mapping-tree m))
        (%make-mapping comparator
          (%rbt-fold (lambda (k v acc)
                       (let-values (((nk nv) (proc k v)))
                         (%rbt-insert acc nk nv lt eq)))
                     %empty (%mapping-tree m)))))

    (define (mapping-map->list proc m)
      (%rbt-fold-right (lambda (k v acc) (cons (proc k v) acc)) '() (%mapping-tree m)))

    (define (mapping-for-each proc m)
      (%rbt-fold (lambda (k v acc) (proc k v) acc) #f (%mapping-tree m)))

    (define (mapping-fold proc nil m)
      (%rbt-fold proc nil (%mapping-tree m)))

    (define (mapping-filter pred m)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (%make-mapping (%mapping-comparator m)
          (%rbt-fold (lambda (k v acc) (if (pred k v) (%rbt-insert acc k v lt eq) acc))
                     %empty (%mapping-tree m)))))
    (define mapping-filter! mapping-filter)

    (define (mapping-remove pred m)
      (mapping-filter (lambda (k v) (not (pred k v))) m))
    (define mapping-remove! mapping-remove)

    (define (mapping-partition pred m)
      (values (mapping-filter pred m) (mapping-remove pred m)))
    (define mapping-partition! mapping-partition)

    ;;; Copy and conversion

    (define (mapping-copy m)
      (%make-mapping (%mapping-comparator m) (%mapping-tree m)))

    (define (mapping->alist m) (%rbt->alist (%mapping-tree m)))

    (define (alist->mapping comparator alist)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let loop ((al alist) (t %empty))
          (if (null? al) (%make-mapping comparator t)
              (loop (cdr al) (%rbt-adjoin t (caar al) (cdar al) lt eq))))))

    (define (alist->mapping! m alist)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (let loop ((al alist) (t (%mapping-tree m)))
          (if (null? al) (%make-mapping (%mapping-comparator m) t)
              (loop (cdr al) (%rbt-adjoin t (caar al) (cdar al) lt eq))))))

    (define alist->mapping/ordered alist->mapping)
    (define alist->mapping/ordered! alist->mapping!)

    ;;; Comparisons

    (define (%mapping=? vcmp m1 m2)
      (let ((veq (comparator-equality-predicate vcmp))
            (a1 (mapping->alist m1)) (a2 (mapping->alist m2)))
        (and (= (length a1) (length a2))
             (let loop ((a a1) (b a2))
               (or (null? a)
                   (and ((%cmp= m1) (caar a) (caar b))
                        (veq (cdar a) (cdar b))
                        (loop (cdr a) (cdr b))))))))

    (define (%mapping<=? vcmp m1 m2)
      (let ((veq (comparator-equality-predicate vcmp))
            (lt (%cmp< m1)) (eq (%cmp= m1)))
        (%rbt-fold (lambda (k v acc)
                     (and acc
                          (let ((entry (%rbt-lookup (%mapping-tree m2) k lt eq)))
                            (and entry (veq v (cdr entry))))))
                   #t (%mapping-tree m1))))

    (define mapping=?
      (case-lambda
        ((vcmp m1 m2) (%mapping=? vcmp m1 m2))
        ((vcmp m1 m2 . rest) (and (%mapping=? vcmp m1 m2) (apply mapping=? vcmp m2 rest)))))

    (define mapping<?
      (case-lambda
        ((vcmp m1 m2) (and (%mapping<=? vcmp m1 m2) (not (%mapping=? vcmp m1 m2))))
        ((vcmp m1 m2 . rest) (and (mapping<? vcmp m1 m2) (apply mapping<? vcmp m2 rest)))))

    (define mapping>?
      (case-lambda
        ((vcmp m1 m2) (mapping<? vcmp m2 m1))
        ((vcmp m1 m2 . rest) (and (mapping>? vcmp m1 m2) (apply mapping>? vcmp m2 rest)))))

    (define mapping<=?
      (case-lambda
        ((vcmp m1 m2) (%mapping<=? vcmp m1 m2))
        ((vcmp m1 m2 . rest) (and (%mapping<=? vcmp m1 m2) (apply mapping<=? vcmp m2 rest)))))

    (define mapping>=?
      (case-lambda
        ((vcmp m1 m2) (%mapping<=? vcmp m2 m1))
        ((vcmp m1 m2 . rest) (and (mapping>=? vcmp m1 m2) (apply mapping>=? vcmp m2 rest)))))

    ;;; Set theory

    (define (mapping-union m1 . rest)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (fold (lambda (m2 acc)
                (%make-mapping (%mapping-comparator m1)
                  (%rbt-fold (lambda (k v t) (%rbt-adjoin t k v lt eq))
                             (%mapping-tree acc) (%mapping-tree m2))))
              m1 rest)))
    (define mapping-union! mapping-union)

    (define (mapping-intersection m1 . rest)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (%make-mapping (%mapping-comparator m1)
          (%rbt-fold (lambda (k v acc)
                       (if (every (lambda (m2) (%rbt-lookup (%mapping-tree m2) k lt eq)) rest)
                           (%rbt-insert acc k v lt eq) acc))
                     %empty (%mapping-tree m1)))))
    (define mapping-intersection! mapping-intersection)

    (define (mapping-difference m1 . rest)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (%make-mapping (%mapping-comparator m1)
          (%rbt-fold (lambda (k v acc)
                       (if (any (lambda (m2) (%rbt-lookup (%mapping-tree m2) k lt eq)) rest)
                           acc (%rbt-insert acc k v lt eq)))
                     %empty (%mapping-tree m1)))))
    (define mapping-difference! mapping-difference)

    (define (mapping-xor m1 m2)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (let* ((t1 (%rbt-fold (lambda (k v acc)
                                (if (%rbt-lookup (%mapping-tree m2) k lt eq) acc
                                    (%rbt-insert acc k v lt eq)))
                              %empty (%mapping-tree m1)))
               (t2 (%rbt-fold (lambda (k v acc)
                                (if (%rbt-lookup (%mapping-tree m1) k lt eq) acc
                                    (%rbt-insert acc k v lt eq)))
                              t1 (%mapping-tree m2))))
          (%make-mapping (%mapping-comparator m1) t2))))
    (define mapping-xor! mapping-xor)

    ;;; Ordered key operations

    (define (mapping-min-key m)
      (if (mapping-empty? m) (error "mapping-min-key: empty")
          (car (%rbt-min (%mapping-tree m)))))

    (define (mapping-max-key m)
      (if (mapping-empty? m) (error "mapping-max-key: empty")
          (car (%rbt-max (%mapping-tree m)))))

    (define (mapping-min-value m)
      (if (mapping-empty? m) (error "mapping-min-value: empty")
          (cdr (%rbt-min (%mapping-tree m)))))

    (define (mapping-max-value m)
      (if (mapping-empty? m) (error "mapping-max-value: empty")
          (cdr (%rbt-max (%mapping-tree m)))))

    (define (mapping-min-entry m)
      (if (mapping-empty? m) (error "mapping-min-entry: empty")
          (let ((e (%rbt-min (%mapping-tree m)))) (values (car e) (cdr e)))))

    (define (mapping-max-entry m)
      (if (mapping-empty? m) (error "mapping-max-entry: empty")
          (let ((e (%rbt-max (%mapping-tree m)))) (values (car e) (cdr e)))))

    (define (mapping-key-predecessor m obj failure)
      (let ((lt (%cmp< m)))
        (%rbt-fold (lambda (k v acc)
                     (if (lt k obj) k acc))
                   (failure) (%mapping-tree m))))

    (define (mapping-key-successor m obj failure)
      (let ((lt (%cmp< m)))
        (%rbt-fold-right (lambda (k v acc)
                           (if (lt obj k) k acc))
                         (failure) (%mapping-tree m))))

    (define (mapping-range= m obj)
      (let ((eq (%cmp= m)) (lt (%cmp< m)))
        (%make-mapping (%mapping-comparator m)
          (%rbt-fold (lambda (k v acc) (if (eq k obj) (%rbt-insert acc k v lt eq) acc))
                     %empty (%mapping-tree m)))))

    (define (mapping-range< m obj)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (%make-mapping (%mapping-comparator m)
          (%rbt-fold (lambda (k v acc) (if (lt k obj) (%rbt-insert acc k v lt eq) acc))
                     %empty (%mapping-tree m)))))

    (define (mapping-range> m obj)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (%make-mapping (%mapping-comparator m)
          (%rbt-fold (lambda (k v acc) (if (lt obj k) (%rbt-insert acc k v lt eq) acc))
                     %empty (%mapping-tree m)))))

    (define (mapping-range<= m obj)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (%make-mapping (%mapping-comparator m)
          (%rbt-fold (lambda (k v acc) (if (or (lt k obj) (eq k obj)) (%rbt-insert acc k v lt eq) acc))
                     %empty (%mapping-tree m)))))

    (define (mapping-range>= m obj)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (%make-mapping (%mapping-comparator m)
          (%rbt-fold (lambda (k v acc) (if (or (lt obj k) (eq k obj)) (%rbt-insert acc k v lt eq) acc))
                     %empty (%mapping-tree m)))))

    (define mapping-range=! mapping-range=)
    (define mapping-range<! mapping-range<)
    (define mapping-range>! mapping-range>)
    (define mapping-range<=! mapping-range<=)
    (define mapping-range>=! mapping-range>=)

    (define (mapping-split m obj)
      (values (mapping-range< m obj) (mapping-range<= m obj)
              (mapping-range= m obj) (mapping-range>= m obj) (mapping-range> m obj)))
    (define mapping-split! mapping-split)

    (define (mapping-catenate comparator m1 key value m2)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let ((t (%rbt-insert (%mapping-tree m1) key value lt eq)))
          (%make-mapping comparator
            (%rbt-fold (lambda (k v acc) (%rbt-insert acc k v lt eq)) t (%mapping-tree m2))))))
    (define mapping-catenate! mapping-catenate)

    (define (mapping-map/monotone proc comparator m)
      (%make-mapping comparator
        (%rbt-fold (lambda (k v acc)
                     (let-values (((nk nv) (proc k v)))
                       (%rbt-insert acc nk nv
                         (comparator-ordering-predicate comparator)
                         (comparator-equality-predicate comparator))))
                   %empty (%mapping-tree m))))
    (define mapping-map/monotone! mapping-map/monotone)

    (define (mapping-fold/reverse proc nil m)
      (%rbt-fold-right proc nil (%mapping-tree m)))

    ;;; Comparator

    (define (make-mapping-comparator vcmp)
      (make-comparator mapping? (lambda (m1 m2) (%mapping=? vcmp m1 m2)) #f #f))

    (define mapping-comparator (make-mapping-comparator (make-default-comparator)))

    ))
