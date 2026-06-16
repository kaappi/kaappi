(define-library (srfi 125)
  (import (scheme base)
          (rename (srfi 69)
                  (hash-table-ref srfi69-ref)
                  (hash-table-walk srfi69-walk))
          (srfi 128))
  (export make-hash-table hash-table hash-table?
          hash-table-contains? hash-table-empty? hash-table-size
          hash-table-ref hash-table-ref/default
          hash-table-set! hash-table-delete! hash-table-update!
          hash-table-intern!
          hash-table-keys hash-table-values hash-table-entries
          hash-table->alist hash-table-copy
          hash-table-for-each hash-table-fold
          hash-table-count hash-table-find
          hash-table-map->list
          hash-table-union! hash-table-intersection! hash-table-difference!)
  (begin
    (define (hash-table comparator . args)
      (let ((ht (make-hash-table)))
        (define (fill lst)
          (if (not (null? lst))
              (begin (hash-table-set! ht (car lst) (cadr lst))
                     (fill (cddr lst)))))
        (fill args)
        ht))

    (define (hash-table-contains? ht key)
      (hash-table-exists? ht key))

    (define (hash-table-empty? ht)
      (= (hash-table-size ht) 0))

    (define (hash-table-ref ht key . args)
      (if (hash-table-exists? ht key)
          (srfi69-ref ht key)
          (if (null? args)
              (error "hash-table-ref: key not found" key)
              ((car args)))))

    (define (hash-table-ref/default ht key default)
      (if (hash-table-exists? ht key)
          (srfi69-ref ht key)
          default))

    (define (hash-table-update! ht key updater . args)
      (let ((old (if (hash-table-exists? ht key)
                     (srfi69-ref ht key)
                     (if (null? args)
                         (error "hash-table-update!: key not found" key)
                         ((car args))))))
        (hash-table-set! ht key (updater old))))

    (define (hash-table-intern! ht key thunk)
      (if (hash-table-exists? ht key)
          (srfi69-ref ht key)
          (let ((val (thunk)))
            (hash-table-set! ht key val)
            val)))

    (define (hash-table-entries ht)
      (values (hash-table-keys ht) (hash-table-values ht)))

    (define (hash-table-for-each proc ht)
      (srfi69-walk ht proc))

    (define (hash-table-fold proc init ht)
      (let ((acc init))
        (srfi69-walk ht
          (lambda (k v) (set! acc (proc k v acc))))
        acc))

    (define (hash-table-count pred ht)
      (let ((c 0))
        (srfi69-walk ht
          (lambda (k v) (if (pred k v) (set! c (+ c 1)))))
        c))

    (define (hash-table-find pred ht failure)
      (let ((found #f) (result #f))
        (srfi69-walk ht
          (lambda (k v)
            (if (and (not found) (pred k v))
                (begin (set! found #t) (set! result (cons k v))))))
        (if found result (failure))))

    (define (hash-table-map->list proc ht)
      (let ((result '()))
        (srfi69-walk ht
          (lambda (k v) (set! result (cons (proc k v) result))))
        (reverse result)))

    (define (hash-table-union! ht1 ht2)
      (srfi69-walk ht2
        (lambda (k v)
          (if (not (hash-table-exists? ht1 k))
              (hash-table-set! ht1 k v))))
      ht1)

    (define (hash-table-intersection! ht1 ht2)
      (for-each
        (lambda (k)
          (if (not (hash-table-exists? ht2 k))
              (hash-table-delete! ht1 k)))
        (hash-table-keys ht1))
      ht1)

    (define (hash-table-difference! ht1 ht2)
      (srfi69-walk ht2
        (lambda (k v)
          (if (hash-table-exists? ht1 k)
              (hash-table-delete! ht1 k))))
      ht1)))
