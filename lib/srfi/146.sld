(define-library (srfi 146)
  (import (scheme base) (scheme case-lambda) (srfi 1) (srfi 128))
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

    ;; Internal: sorted alist of (key . value) pairs
    (define-record-type <mapping>
      (%make-mapping comparator entries)
      mapping?
      (comparator %mapping-comparator)
      (entries %mapping-entries %set-mapping-entries!))

    (define (%cmp< m) (comparator-ordering-predicate (%mapping-comparator m)))
    (define (%cmp= m) (comparator-equality-predicate (%mapping-comparator m)))

    (define (%sorted-insert entries key val lt eq)
      (cond
        ((null? entries) (list (cons key val)))
        ((eq key (caar entries)) (cons (cons key val) (cdr entries)))
        ((lt key (caar entries)) (cons (cons key val) entries))
        (else (cons (car entries) (%sorted-insert (cdr entries) key val lt eq)))))

    (define (%sorted-adjoin entries key val lt eq)
      (cond
        ((null? entries) (list (cons key val)))
        ((eq key (caar entries)) entries)
        ((lt key (caar entries)) (cons (cons key val) entries))
        (else (cons (car entries) (%sorted-adjoin (cdr entries) key val lt eq)))))

    (define (%sorted-delete entries key lt eq)
      (cond
        ((null? entries) '())
        ((eq key (caar entries)) (cdr entries))
        ((lt key (caar entries)) entries)
        (else (cons (car entries) (%sorted-delete (cdr entries) key lt eq)))))

    (define (%sorted-lookup entries key lt eq)
      (cond
        ((null? entries) #f)
        ((eq key (caar entries)) (car entries))
        ((lt key (caar entries)) #f)
        (else (%sorted-lookup (cdr entries) key lt eq))))

    (define (%make-empty cmp) (%make-mapping cmp '()))

    ;;; Constructors

    (define (mapping comparator . args)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let loop ((args args) (entries '()))
          (if (null? args) (%make-mapping comparator entries)
              (if (null? (cdr args)) (error "mapping: odd number of arguments")
                  (loop (cddr args)
                        (%sorted-insert entries (car args) (cadr args) lt eq)))))))

    (define mapping/ordered mapping)

    (define (mapping-unfold stop? mapper successor seed comparator)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let loop ((seed seed) (entries '()))
          (if (stop? seed) (%make-mapping comparator entries)
              (let-values (((key val) (mapper seed)))
                (loop (successor seed)
                      (%sorted-insert entries key val lt eq)))))))

    (define mapping-unfold/ordered mapping-unfold)

    ;;; Predicates

    (define (mapping-contains? m key)
      (if (%sorted-lookup (%mapping-entries m) key (%cmp< m) (%cmp= m)) #t #f))

    (define (mapping-empty? m) (null? (%mapping-entries m)))

    (define (mapping-disjoint? m1 m2)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (let loop ((entries (%mapping-entries m1)))
          (cond
            ((null? entries) #t)
            ((%sorted-lookup (%mapping-entries m2) (caar entries) lt eq) #f)
            (else (loop (cdr entries)))))))

    ;;; Accessors

    (define mapping-ref
      (case-lambda
        ((m key)
         (let ((entry (%sorted-lookup (%mapping-entries m) key (%cmp< m) (%cmp= m))))
           (if entry (cdr entry) (error "mapping-ref: key not found" key))))
        ((m key failure)
         (let ((entry (%sorted-lookup (%mapping-entries m) key (%cmp< m) (%cmp= m))))
           (if entry (cdr entry) (failure))))
        ((m key failure success)
         (let ((entry (%sorted-lookup (%mapping-entries m) key (%cmp< m) (%cmp= m))))
           (if entry (success (cdr entry)) (failure))))))

    (define (mapping-ref/default m key default)
      (let ((entry (%sorted-lookup (%mapping-entries m) key (%cmp< m) (%cmp= m))))
        (if entry (cdr entry) default)))

    (define (mapping-key-comparator m) (%mapping-comparator m))

    ;;; Updaters

    (define (mapping-set m . args)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (let loop ((args args) (entries (%mapping-entries m)))
          (if (null? args) (%make-mapping (%mapping-comparator m) entries)
              (loop (cddr args)
                    (%sorted-insert entries (car args) (cadr args) lt eq))))))

    (define mapping-set! mapping-set)

    (define (mapping-adjoin m . args)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (let loop ((args args) (entries (%mapping-entries m)))
          (if (null? args) (%make-mapping (%mapping-comparator m) entries)
              (loop (cddr args)
                    (%sorted-adjoin entries (car args) (cadr args) lt eq))))))

    (define mapping-adjoin! mapping-adjoin)

    (define (mapping-replace m key val)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (if (%sorted-lookup (%mapping-entries m) key lt eq)
            (%make-mapping (%mapping-comparator m)
                           (%sorted-insert (%mapping-entries m) key val lt eq))
            m)))

    (define mapping-replace! mapping-replace)

    (define (mapping-delete m . keys)
      (mapping-delete-all m keys))

    (define mapping-delete! mapping-delete)

    (define (mapping-delete-all m key-list)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (let loop ((keys key-list) (entries (%mapping-entries m)))
          (if (null? keys) (%make-mapping (%mapping-comparator m) entries)
              (loop (cdr keys) (%sorted-delete entries (car keys) lt eq))))))

    (define mapping-delete-all! mapping-delete-all)

    (define (mapping-intern m key failure)
      (let ((entry (%sorted-lookup (%mapping-entries m) key (%cmp< m) (%cmp= m))))
        (if entry
            (values m (cdr entry))
            (let ((val (failure)))
              (values (mapping-set m key val) val)))))

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
         (let ((entry (%sorted-lookup (%mapping-entries m) key (%cmp< m) (%cmp= m))))
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
             (let ((entry (car (%mapping-entries m))))
               (values (mapping-delete m (car entry))
                       (car entry) (cdr entry)))))))

    (define mapping-pop! mapping-pop)

    (define (mapping-search m key failure success)
      (let ((entry (%sorted-lookup (%mapping-entries m) key (%cmp< m) (%cmp= m))))
        (if entry
            (success (car entry) (cdr entry)
              (lambda (new-key new-val obj) (values (mapping-set (mapping-delete m key) new-key new-val) obj))
              (lambda (obj) (values (mapping-delete m key) obj)))
            (failure
              (lambda (val obj) (values (mapping-set m key val) obj))
              (lambda (obj) (values m obj))))))

    (define mapping-search! mapping-search)

    ;;; Whole mapping

    (define (mapping-size m) (length (%mapping-entries m)))

    (define (mapping-find pred m failure)
      (let loop ((entries (%mapping-entries m)))
        (cond
          ((null? entries) (failure))
          ((pred (caar entries) (cdar entries))
           (values (caar entries) (cdar entries)))
          (else (loop (cdr entries))))))

    (define (mapping-count pred m)
      (let loop ((entries (%mapping-entries m)) (n 0))
        (if (null? entries) n
            (loop (cdr entries)
                  (if (pred (caar entries) (cdar entries)) (+ n 1) n)))))

    (define (mapping-any? pred m)
      (let loop ((entries (%mapping-entries m)))
        (cond
          ((null? entries) #f)
          ((pred (caar entries) (cdar entries)) #t)
          (else (loop (cdr entries))))))

    (define (mapping-every? pred m)
      (let loop ((entries (%mapping-entries m)))
        (cond
          ((null? entries) #t)
          ((not (pred (caar entries) (cdar entries))) #f)
          (else (loop (cdr entries))))))

    (define (mapping-keys m) (map car (%mapping-entries m)))
    (define (mapping-values m) (map cdr (%mapping-entries m)))
    (define (mapping-entries m)
      (values (map car (%mapping-entries m)) (map cdr (%mapping-entries m))))

    ;;; Mapping and folding

    (define (mapping-map proc comparator m)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let loop ((entries (%mapping-entries m)) (result '()))
          (if (null? entries)
              (%make-mapping comparator result)
              (let-values (((new-key new-val) (proc (caar entries) (cdar entries))))
                (loop (cdr entries)
                      (%sorted-insert result new-key new-val lt eq)))))))

    (define (mapping-map->list proc m)
      (map (lambda (e) (proc (car e) (cdr e))) (%mapping-entries m)))

    (define (mapping-for-each proc m)
      (for-each (lambda (e) (proc (car e) (cdr e))) (%mapping-entries m)))

    (define (mapping-fold proc nil m)
      (let loop ((entries (%mapping-entries m)) (acc nil))
        (if (null? entries) acc
            (loop (cdr entries) (proc (caar entries) (cdar entries) acc)))))

    (define (mapping-filter pred m)
      (%make-mapping (%mapping-comparator m)
        (filter (lambda (e) (pred (car e) (cdr e))) (%mapping-entries m))))

    (define mapping-filter! mapping-filter)

    (define (mapping-remove pred m)
      (%make-mapping (%mapping-comparator m)
        (filter (lambda (e) (not (pred (car e) (cdr e)))) (%mapping-entries m))))

    (define mapping-remove! mapping-remove)

    (define (mapping-partition pred m)
      (let loop ((entries (%mapping-entries m)) (yes '()) (no '()))
        (cond
          ((null? entries)
           (values (%make-mapping (%mapping-comparator m) (reverse yes))
                   (%make-mapping (%mapping-comparator m) (reverse no))))
          ((pred (caar entries) (cdar entries))
           (loop (cdr entries) (cons (car entries) yes) no))
          (else
           (loop (cdr entries) yes (cons (car entries) no))))))

    (define mapping-partition! mapping-partition)

    ;;; Copy and conversion

    (define (mapping-copy m)
      (%make-mapping (%mapping-comparator m) (list-copy (%mapping-entries m))))

    (define (mapping->alist m) (list-copy (%mapping-entries m)))

    (define (alist->mapping comparator alist)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let loop ((alist alist) (entries '()))
          (if (null? alist) (%make-mapping comparator entries)
              (loop (cdr alist)
                    (%sorted-adjoin entries (caar alist) (cdar alist) lt eq))))))

    (define (alist->mapping! m alist)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (let loop ((alist alist) (entries (%mapping-entries m)))
          (if (null? alist) (%make-mapping (%mapping-comparator m) entries)
              (loop (cdr alist)
                    (%sorted-adjoin entries (caar alist) (cdar alist) lt eq))))))

    (define alist->mapping/ordered alist->mapping)
    (define alist->mapping/ordered! alist->mapping!)

    ;;; Comparisons

    (define (%mapping=? vcmp m1 m2)
      (let ((eq (%cmp= m1))
            (veq (comparator-equality-predicate vcmp)))
        (and (= (mapping-size m1) (mapping-size m2))
             (let loop ((e1 (%mapping-entries m1)) (e2 (%mapping-entries m2)))
               (cond
                 ((null? e1) #t)
                 ((not (eq (caar e1) (caar e2))) #f)
                 ((not (veq (cdar e1) (cdar e2))) #f)
                 (else (loop (cdr e1) (cdr e2))))))))

    (define (%mapping<=? vcmp m1 m2)
      (let ((veq (comparator-equality-predicate vcmp))
            (lt (%cmp< m1)) (eq (%cmp= m1)))
        (let loop ((entries (%mapping-entries m1)))
          (cond
            ((null? entries) #t)
            (else
             (let ((found (%sorted-lookup (%mapping-entries m2) (caar entries) lt eq)))
               (and found (veq (cdar entries) (cdr found))
                    (loop (cdr entries)))))))))

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
        (let loop ((rest rest) (entries (%mapping-entries m1)))
          (if (null? rest) (%make-mapping (%mapping-comparator m1) entries)
              (let inner ((e2 (%mapping-entries (car rest))) (acc entries))
                (if (null? e2) (loop (cdr rest) acc)
                    (inner (cdr e2) (%sorted-adjoin acc (caar e2) (cdar e2) lt eq))))))))

    (define mapping-union! mapping-union)

    (define (mapping-intersection m1 . rest)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (let loop ((rest rest) (entries (%mapping-entries m1)))
          (if (null? rest) (%make-mapping (%mapping-comparator m1) entries)
              (loop (cdr rest)
                    (filter (lambda (e)
                              (%sorted-lookup (%mapping-entries (car rest))
                                              (car e) lt eq))
                            entries))))))

    (define mapping-intersection! mapping-intersection)

    (define (mapping-difference m1 . rest)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (let loop ((rest rest) (entries (%mapping-entries m1)))
          (if (null? rest) (%make-mapping (%mapping-comparator m1) entries)
              (loop (cdr rest)
                    (filter (lambda (e)
                              (not (%sorted-lookup (%mapping-entries (car rest))
                                                   (car e) lt eq)))
                            entries))))))

    (define mapping-difference! mapping-difference)

    (define (mapping-xor m1 m2)
      (let ((lt (%cmp< m1)) (eq (%cmp= m1)))
        (let* ((only1 (filter (lambda (e)
                                (not (%sorted-lookup (%mapping-entries m2) (car e) lt eq)))
                              (%mapping-entries m1)))
               (only2 (filter (lambda (e)
                                (not (%sorted-lookup (%mapping-entries m1) (car e) lt eq)))
                              (%mapping-entries m2))))
          (let loop ((entries only2) (acc only1))
            (if (null? entries)
                (%make-mapping (%mapping-comparator m1) acc)
                (loop (cdr entries)
                      (%sorted-insert acc (caar entries) (cdar entries) lt eq)))))))

    (define mapping-xor! mapping-xor)

    ;;; Ordered key operations

    (define (mapping-min-key m)
      (if (mapping-empty? m) (error "mapping-min-key: empty mapping")
          (caar (%mapping-entries m))))

    (define (mapping-max-key m)
      (if (mapping-empty? m) (error "mapping-max-key: empty mapping")
          (let loop ((entries (%mapping-entries m)))
            (if (null? (cdr entries)) (caar entries)
                (loop (cdr entries))))))

    (define (mapping-min-value m)
      (if (mapping-empty? m) (error "mapping-min-value: empty mapping")
          (cdar (%mapping-entries m))))

    (define (mapping-max-value m)
      (if (mapping-empty? m) (error "mapping-max-value: empty mapping")
          (let loop ((entries (%mapping-entries m)))
            (if (null? (cdr entries)) (cdar entries)
                (loop (cdr entries))))))

    (define (mapping-min-entry m)
      (if (mapping-empty? m) (error "mapping-min-entry: empty mapping")
          (let ((e (car (%mapping-entries m)))) (values (car e) (cdr e)))))

    (define (mapping-max-entry m)
      (if (mapping-empty? m) (error "mapping-max-entry: empty mapping")
          (let loop ((entries (%mapping-entries m)))
            (if (null? (cdr entries))
                (values (caar entries) (cdar entries))
                (loop (cdr entries))))))

    (define (mapping-key-predecessor m obj failure)
      (let ((lt (%cmp< m)))
        (let loop ((entries (%mapping-entries m)) (prev #f))
          (cond
            ((null? entries) (if prev prev (failure)))
            ((not (lt (caar entries) obj)) (if prev prev (failure)))
            (else (loop (cdr entries) (caar entries)))))))

    (define (mapping-key-successor m obj failure)
      (let ((lt (%cmp< m)))
        (let loop ((entries (%mapping-entries m)))
          (cond
            ((null? entries) (failure))
            ((lt obj (caar entries)) (caar entries))
            (else (loop (cdr entries)))))))

    (define (mapping-range= m obj)
      (let ((eq (%cmp= m)))
        (%make-mapping (%mapping-comparator m)
          (filter (lambda (e) (eq (car e) obj)) (%mapping-entries m)))))

    (define (mapping-range< m obj)
      (let ((lt (%cmp< m)))
        (%make-mapping (%mapping-comparator m)
          (let loop ((entries (%mapping-entries m)))
            (cond
              ((null? entries) '())
              ((lt (caar entries) obj) (cons (car entries) (loop (cdr entries))))
              (else '()))))))

    (define (mapping-range> m obj)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (%make-mapping (%mapping-comparator m)
          (let loop ((entries (%mapping-entries m)))
            (cond
              ((null? entries) '())
              ((or (lt (caar entries) obj) (eq (caar entries) obj))
               (loop (cdr entries)))
              (else entries))))))

    (define (mapping-range<= m obj)
      (let ((lt (%cmp< m)) (eq (%cmp= m)))
        (%make-mapping (%mapping-comparator m)
          (let loop ((entries (%mapping-entries m)))
            (cond
              ((null? entries) '())
              ((or (lt (caar entries) obj) (eq (caar entries) obj))
               (cons (car entries) (loop (cdr entries))))
              (else '()))))))

    (define (mapping-range>= m obj)
      (let ((lt (%cmp< m)))
        (%make-mapping (%mapping-comparator m)
          (let loop ((entries (%mapping-entries m)))
            (cond
              ((null? entries) '())
              ((lt (caar entries) obj) (loop (cdr entries)))
              (else entries))))))

    (define mapping-range=! mapping-range=)
    (define mapping-range<! mapping-range<)
    (define mapping-range>! mapping-range>)
    (define mapping-range<=! mapping-range<=)
    (define mapping-range>=! mapping-range>=)

    (define (mapping-split m obj)
      (values (mapping-range< m obj)
              (mapping-range<= m obj)
              (mapping-range= m obj)
              (mapping-range>= m obj)
              (mapping-range> m obj)))

    (define mapping-split! mapping-split)

    (define (mapping-catenate comparator m1 key value m2)
      (let ((lt (comparator-ordering-predicate comparator))
            (eq (comparator-equality-predicate comparator)))
        (let loop ((entries (%mapping-entries m2))
                   (acc (%sorted-insert (%mapping-entries m1) key value lt eq)))
          (if (null? entries) (%make-mapping comparator acc)
              (loop (cdr entries)
                    (%sorted-insert acc (caar entries) (cdar entries) lt eq))))))

    (define mapping-catenate! mapping-catenate)

    (define (mapping-map/monotone proc comparator m)
      (%make-mapping comparator
        (map (lambda (e)
               (let-values (((k v) (proc (car e) (cdr e)))) (cons k v)))
             (%mapping-entries m))))

    (define mapping-map/monotone! mapping-map/monotone)

    (define (mapping-fold/reverse proc nil m)
      (let loop ((entries (reverse (%mapping-entries m))) (acc nil))
        (if (null? entries) acc
            (loop (cdr entries) (proc (caar entries) (cdar entries) acc)))))

    ;;; Comparator

    (define (make-mapping-comparator vcmp)
      (make-comparator mapping?
        (lambda (m1 m2) (%mapping=? vcmp m1 m2))
        #f #f))

    (define mapping-comparator
      (make-mapping-comparator (make-default-comparator)))

    ))
