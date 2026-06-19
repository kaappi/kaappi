(define-library (srfi 146 hash)
  (import (scheme base) (scheme case-lambda) (srfi 69) (srfi 128))
  (export hashmap hashmap-unfold
          hashmap? hashmap-contains? hashmap-empty? hashmap-disjoint?
          hashmap-ref hashmap-ref/default hashmap-key-comparator
          hashmap-adjoin hashmap-adjoin! hashmap-set hashmap-set!
          hashmap-replace hashmap-replace! hashmap-delete hashmap-delete!
          hashmap-delete-all hashmap-delete-all!
          hashmap-intern hashmap-intern!
          hashmap-update hashmap-update! hashmap-update/default hashmap-update!/default
          hashmap-pop hashmap-pop! hashmap-search hashmap-search!
          hashmap-size hashmap-find hashmap-count hashmap-any? hashmap-every?
          hashmap-keys hashmap-values hashmap-entries
          hashmap-map hashmap-map->list hashmap-for-each hashmap-fold
          hashmap-filter hashmap-filter! hashmap-remove hashmap-remove!
          hashmap-partition hashmap-partition!
          hashmap-copy hashmap->alist
          alist->hashmap alist->hashmap!
          hashmap=? hashmap<? hashmap>? hashmap<=? hashmap>=?
          hashmap-union hashmap-intersection hashmap-difference hashmap-xor
          hashmap-union! hashmap-intersection! hashmap-difference! hashmap-xor!
          make-hashmap-comparator hashmap-comparator)
  (begin

    (define-record-type <hashmap>
      (%make-hashmap comparator ht)
      hashmap?
      (comparator %hm-comparator)
      (ht %hm-ht))

    (define (%hm-copy m)
      (%make-hashmap (%hm-comparator m) (hash-table-copy (%hm-ht m))))

    (define (hashmap comparator . args)
      (let ((ht (make-hash-table)))
        (let loop ((args args))
          (if (null? args) (%make-hashmap comparator ht)
              (begin (hash-table-set! ht (car args) (cadr args))
                     (loop (cddr args)))))))

    (define (hashmap-unfold stop? mapper successor seed comparator)
      (let ((ht (make-hash-table)))
        (let loop ((seed seed))
          (if (stop? seed) (%make-hashmap comparator ht)
              (let-values (((key val) (mapper seed)))
                (hash-table-set! ht key val)
                (loop (successor seed)))))))

    (define (hashmap-contains? m key) (hash-table-exists? (%hm-ht m) key))
    (define (hashmap-empty? m) (= 0 (hash-table-size (%hm-ht m))))

    (define (hashmap-disjoint? m1 m2)
      (let ((found #f))
        (hash-table-walk (%hm-ht m1)
          (lambda (k v) (if (hash-table-exists? (%hm-ht m2) k) (set! found #t))))
        (not found)))

    (define hashmap-ref
      (case-lambda
        ((m key) (hash-table-ref (%hm-ht m) key))
        ((m key failure)
         (if (hash-table-exists? (%hm-ht m) key)
             (hash-table-ref (%hm-ht m) key) (failure)))
        ((m key failure success)
         (if (hash-table-exists? (%hm-ht m) key)
             (success (hash-table-ref (%hm-ht m) key)) (failure)))))

    (define (hashmap-ref/default m key default)
      (hash-table-ref (%hm-ht m) key default))

    (define (hashmap-key-comparator m) (%hm-comparator m))

    (define (hashmap-set m . args)
      (let ((new (%hm-copy m)))
        (let loop ((args args))
          (if (null? args) new
              (begin (hash-table-set! (%hm-ht new) (car args) (cadr args))
                     (loop (cddr args)))))))
    (define hashmap-set! hashmap-set)

    (define (hashmap-adjoin m . args)
      (let ((new (%hm-copy m)))
        (let loop ((args args))
          (if (null? args) new
              (begin
                (if (not (hash-table-exists? (%hm-ht new) (car args)))
                    (hash-table-set! (%hm-ht new) (car args) (cadr args)))
                (loop (cddr args)))))))
    (define hashmap-adjoin! hashmap-adjoin)

    (define (hashmap-replace m key val)
      (if (hash-table-exists? (%hm-ht m) key)
          (let ((new (%hm-copy m)))
            (hash-table-set! (%hm-ht new) key val) new)
          m))
    (define hashmap-replace! hashmap-replace)

    (define (hashmap-delete m . keys) (hashmap-delete-all m keys))
    (define hashmap-delete! hashmap-delete)

    (define (hashmap-delete-all m key-list)
      (let ((new (%hm-copy m)))
        (let loop ((keys key-list))
          (if (null? keys) new
              (begin (hash-table-delete! (%hm-ht new) (car keys))
                     (loop (cdr keys)))))))
    (define hashmap-delete-all! hashmap-delete-all)

    (define (hashmap-intern m key failure)
      (if (hash-table-exists? (%hm-ht m) key)
          (values m (hash-table-ref (%hm-ht m) key))
          (let ((val (failure)))
            (values (hashmap-set m key val) val))))
    (define hashmap-intern! hashmap-intern)

    (define hashmap-update
      (case-lambda
        ((m key updater)
         (hashmap-update m key updater
                         (lambda () (error "hashmap-update: key not found" key))
                         (lambda (v) v)))
        ((m key updater failure)
         (hashmap-update m key updater failure (lambda (v) v)))
        ((m key updater failure success)
         (if (hash-table-exists? (%hm-ht m) key)
             (hashmap-set m key (updater (success (hash-table-ref (%hm-ht m) key))))
             (hashmap-set m key (updater (failure)))))))
    (define hashmap-update! hashmap-update)

    (define (hashmap-update/default m key updater default)
      (hashmap-set m key (updater (hashmap-ref/default m key default))))
    (define hashmap-update!/default hashmap-update/default)

    (define hashmap-pop
      (case-lambda
        ((m) (hashmap-pop m (lambda () (error "hashmap-pop: empty"))))
        ((m failure)
         (if (hashmap-empty? m) (failure)
             (let ((keys (hash-table-keys (%hm-ht m))))
               (let ((key (car keys)) (val (hash-table-ref (%hm-ht m) (car keys))))
                 (values (hashmap-delete m key) key val)))))))
    (define hashmap-pop! hashmap-pop)

    (define (hashmap-search m key failure success)
      (if (hash-table-exists? (%hm-ht m) key)
          (let ((val (hash-table-ref (%hm-ht m) key)))
            (success key val
              (lambda (new-key new-val obj) (values (hashmap-set (hashmap-delete m key) new-key new-val) obj))
              (lambda (obj) (values (hashmap-delete m key) obj))))
          (failure
            (lambda (val obj) (values (hashmap-set m key val) obj))
            (lambda (obj) (values m obj)))))
    (define hashmap-search! hashmap-search)

    (define (hashmap-size m) (hash-table-size (%hm-ht m)))

    (define (hashmap-find pred m failure)
      (let ((keys (hash-table-keys (%hm-ht m))))
        (let loop ((ks keys))
          (if (null? ks) (failure)
              (let ((v (hash-table-ref (%hm-ht m) (car ks))))
                (if (pred (car ks) v)
                    (values (car ks) v)
                    (loop (cdr ks))))))))

    (define (hashmap-count pred m)
      (let ((n 0))
        (hash-table-walk (%hm-ht m)
          (lambda (k v) (if (pred k v) (set! n (+ n 1)))))
        n))

    (define (hashmap-any? pred m)
      (let ((found #f))
        (hash-table-walk (%hm-ht m)
          (lambda (k v) (if (pred k v) (set! found #t))))
        found))

    (define (hashmap-every? pred m)
      (let ((all #t))
        (hash-table-walk (%hm-ht m)
          (lambda (k v) (if (not (pred k v)) (set! all #f))))
        all))

    (define (hashmap-keys m) (hash-table-keys (%hm-ht m)))
    (define (hashmap-values m) (hash-table-values (%hm-ht m)))
    (define (hashmap-entries m) (values (hash-table-keys (%hm-ht m)) (hash-table-values (%hm-ht m))))

    (define (hashmap-map proc comparator m)
      (let ((new (make-hash-table)))
        (hash-table-walk (%hm-ht m)
          (lambda (k v)
            (let-values (((nk nv) (proc k v)))
              (hash-table-set! new nk nv))))
        (%make-hashmap comparator new)))

    (define (hashmap-map->list proc m)
      (let ((result '()))
        (hash-table-walk (%hm-ht m)
          (lambda (k v) (set! result (cons (proc k v) result))))
        (reverse result)))

    (define (hashmap-for-each proc m)
      (hash-table-walk (%hm-ht m) (lambda (k v) (proc k v))))

    (define (hashmap-fold proc nil m)
      (let ((acc nil))
        (hash-table-walk (%hm-ht m)
          (lambda (k v) (set! acc (proc k v acc))))
        acc))

    (define (hashmap-filter pred m)
      (let ((new (make-hash-table)))
        (hash-table-walk (%hm-ht m)
          (lambda (k v) (if (pred k v) (hash-table-set! new k v))))
        (%make-hashmap (%hm-comparator m) new)))
    (define hashmap-filter! hashmap-filter)

    (define (hashmap-remove pred m)
      (hashmap-filter (lambda (k v) (not (pred k v))) m))
    (define hashmap-remove! hashmap-remove)

    (define (hashmap-partition pred m)
      (let ((yes (make-hash-table)) (no (make-hash-table)))
        (hash-table-walk (%hm-ht m)
          (lambda (k v)
            (if (pred k v) (hash-table-set! yes k v) (hash-table-set! no k v))))
        (values (%make-hashmap (%hm-comparator m) yes)
                (%make-hashmap (%hm-comparator m) no))))
    (define hashmap-partition! hashmap-partition)

    (define (hashmap-copy m) (%hm-copy m))
    (define (hashmap->alist m) (hash-table->alist (%hm-ht m)))

    (define (alist->hashmap comparator alist)
      (let ((ht (make-hash-table)))
        (let loop ((al alist))
          (if (null? al) (%make-hashmap comparator ht)
              (begin
                (if (not (hash-table-exists? ht (caar al)))
                    (hash-table-set! ht (caar al) (cdar al)))
                (loop (cdr al)))))))

    (define (alist->hashmap! m alist)
      (let ((new (%hm-copy m)))
        (let loop ((al alist))
          (if (null? al) new
              (begin
                (if (not (hash-table-exists? (%hm-ht new) (caar al)))
                    (hash-table-set! (%hm-ht new) (caar al) (cdar al)))
                (loop (cdr al)))))))

    (define (%hm=? vcmp m1 m2)
      (let ((veq (comparator-equality-predicate vcmp)))
        (and (= (hashmap-size m1) (hashmap-size m2))
             (let ((all #t))
               (hash-table-walk (%hm-ht m1)
                 (lambda (k v1)
                   (if (not (and (hash-table-exists? (%hm-ht m2) k)
                                 (veq v1 (hash-table-ref (%hm-ht m2) k))))
                       (set! all #f))))
               all))))

    (define (%hm<=? vcmp m1 m2)
      (let ((veq (comparator-equality-predicate vcmp)))
        (let ((all #t))
          (hash-table-walk (%hm-ht m1)
            (lambda (k v1)
              (if (not (and (hash-table-exists? (%hm-ht m2) k)
                            (veq v1 (hash-table-ref (%hm-ht m2) k))))
                  (set! all #f))))
          all)))

    (define hashmap=?
      (case-lambda
        ((vcmp m1 m2) (%hm=? vcmp m1 m2))
        ((vcmp m1 m2 . rest) (and (%hm=? vcmp m1 m2) (apply hashmap=? vcmp m2 rest)))))
    (define hashmap<?
      (case-lambda
        ((vcmp m1 m2) (and (%hm<=? vcmp m1 m2) (not (%hm=? vcmp m1 m2))))
        ((vcmp m1 m2 . rest) (and (hashmap<? vcmp m1 m2) (apply hashmap<? vcmp m2 rest)))))
    (define hashmap>?
      (case-lambda
        ((vcmp m1 m2) (hashmap<? vcmp m2 m1))
        ((vcmp m1 m2 . rest) (and (hashmap>? vcmp m1 m2) (apply hashmap>? vcmp m2 rest)))))
    (define hashmap<=?
      (case-lambda
        ((vcmp m1 m2) (%hm<=? vcmp m1 m2))
        ((vcmp m1 m2 . rest) (and (%hm<=? vcmp m1 m2) (apply hashmap<=? vcmp m2 rest)))))
    (define hashmap>=?
      (case-lambda
        ((vcmp m1 m2) (%hm<=? vcmp m2 m1))
        ((vcmp m1 m2 . rest) (and (hashmap>=? vcmp m1 m2) (apply hashmap>=? vcmp m2 rest)))))

    (define (hashmap-union m1 . rest)
      (let loop ((rest rest) (result (%hm-copy m1)))
        (if (null? rest) result
            (begin
              (hash-table-walk (%hm-ht (car rest))
                (lambda (k v)
                  (if (not (hash-table-exists? (%hm-ht result) k))
                      (hash-table-set! (%hm-ht result) k v))))
              (loop (cdr rest) result)))))
    (define hashmap-union! hashmap-union)

    (define (hashmap-intersection m1 . rest)
      (let ((new (make-hash-table)))
        (hash-table-walk (%hm-ht m1)
          (lambda (k v)
            (if (let loop ((rs rest))
                  (or (null? rs)
                      (and (hash-table-exists? (%hm-ht (car rs)) k)
                           (loop (cdr rs)))))
                (hash-table-set! new k v))))
        (%make-hashmap (%hm-comparator m1) new)))
    (define hashmap-intersection! hashmap-intersection)

    (define (hashmap-difference m1 . rest)
      (let ((new (make-hash-table)))
        (hash-table-walk (%hm-ht m1)
          (lambda (k v)
            (if (not (let loop ((rs rest))
                       (and (not (null? rs))
                            (or (hash-table-exists? (%hm-ht (car rs)) k)
                                (loop (cdr rs))))))
                (hash-table-set! new k v))))
        (%make-hashmap (%hm-comparator m1) new)))
    (define hashmap-difference! hashmap-difference)

    (define (hashmap-xor m1 m2)
      (let ((new (make-hash-table)))
        (hash-table-walk (%hm-ht m1)
          (lambda (k v)
            (if (not (hash-table-exists? (%hm-ht m2) k))
                (hash-table-set! new k v))))
        (hash-table-walk (%hm-ht m2)
          (lambda (k v)
            (if (not (hash-table-exists? (%hm-ht m1) k))
                (hash-table-set! new k v))))
        (%make-hashmap (%hm-comparator m1) new)))
    (define hashmap-xor! hashmap-xor)

    (define (make-hashmap-comparator vcmp)
      (make-comparator hashmap? (lambda (m1 m2) (%hm=? vcmp m1 m2)) #f #f))

    (define hashmap-comparator
      (make-hashmap-comparator (make-default-comparator)))

    ))
