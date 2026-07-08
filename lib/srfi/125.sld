(define-library (srfi 125)
  (import (scheme base)
          (rename (srfi 69)
                  (hash-table-ref srfi69-ref))
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
          hash-table-union! hash-table-intersection! hash-table-difference!
          ;; new exports
          hash-table-unfold alist->hash-table
          hash-table-exists? hash-table=? hash-table-mutable?
          hash-table-update!/default hash-table-pop! hash-table-clear!
          hash-table-map hash-table-walk hash-table-map! hash-table-prune!
          hash-table-empty-copy hash-table-merge! hash-table-xor!
          hash string-hash string-ci-hash hash-by-identity
          hash-table-equivalence-function hash-table-hash-function)
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
          (let ((v (srfi69-ref ht key)))
            (if (and (not (null? args)) (not (null? (cdr args))))
                ((cadr args) v)
                v))
          (if (null? args)
              (error "hash-table-ref: key not found" key)
              ((car args)))))

    (define (hash-table-ref/default ht key default)
      (if (hash-table-exists? ht key)
          (srfi69-ref ht key)
          default))

    (define (hash-table-update! ht key updater . args)
      (let* ((failure (if (null? args) #f (car args)))
             (success (if (or (null? args) (null? (cdr args))) #f (cadr args)))
             (old (if (hash-table-exists? ht key)
                      (let ((v (srfi69-ref ht key)))
                        (if success (success v) v))
                      (if failure
                          (failure)
                          (error "hash-table-update!: key not found" key)))))
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
      (hash-table-walk ht proc))

    (define (hash-table-fold proc init ht)
      (let ((acc init))
        (hash-table-walk ht
          (lambda (k v) (set! acc (proc k v acc))))
        acc))

    (define (hash-table-count pred ht)
      (let ((c 0))
        (hash-table-walk ht
          (lambda (k v) (if (pred k v) (set! c (+ c 1)))))
        c))

    (define (hash-table-find pred ht failure)
      (let ((found #f) (result #f))
        (hash-table-walk ht
          (lambda (k v)
            (if (not found)
                (let ((r (pred k v)))
                  (if r (begin (set! found #t) (set! result r)))))))
        (if found result (failure))))

    (define (hash-table-map->list proc ht)
      (let ((result '()))
        (hash-table-walk ht
          (lambda (k v) (set! result (cons (proc k v) result))))
        (reverse result)))

    (define (hash-table-union! ht1 ht2)
      (hash-table-walk ht2
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
      (hash-table-walk ht2
        (lambda (k v)
          (if (hash-table-exists? ht1 k)
              (hash-table-delete! ht1 k))))
      ht1)

    ;; SRFI-125 merge! is an alias for union! (ht1 values win on collision),
    ;; NOT the SRFI-69 merge! (where ht2 wins). This define shadows the import.
    (define (hash-table-merge! ht1 ht2)
      (hash-table-union! ht1 ht2))

    (define (hash-table-unfold stop? mapper successor seed comparator)
      (let ((ht (make-hash-table)))
        (let loop ((s seed))
          (if (stop? s)
              ht
              (call-with-values
                (lambda () (mapper s))
                (lambda (k v)
                  (hash-table-set! ht k v)
                  (loop (successor s))))))))

    (define (hash-table=? value-comparator ht1 ht2)
      (let ((eq (comparator-equality-predicate value-comparator)))
        (and (= (hash-table-size ht1) (hash-table-size ht2))
             (let ((result #t))
               (hash-table-walk ht1
                 (lambda (k v)
                   (if result
                       (if (hash-table-exists? ht2 k)
                           (if (not (eq v (srfi69-ref ht2 k)))
                               (set! result #f))
                           (set! result #f)))))
               result))))

    (define (hash-table-mutable? ht) #t)

    (define (hash-table-pop! ht)
      (let ((keys (hash-table-keys ht)))
        (if (null? keys)
            (error "hash-table-pop!: empty hash table")
            (let* ((k (car keys))
                   (v (srfi69-ref ht k)))
              (hash-table-delete! ht k)
              (values k v)))))

    (define (hash-table-clear! ht)
      (for-each (lambda (k) (hash-table-delete! ht k))
                (hash-table-keys ht)))

    (define (hash-table-map proc comparator ht)
      (let ((result (make-hash-table)))
        (hash-table-walk ht
          (lambda (k v) (hash-table-set! result k (proc v))))
        result))

    (define (hash-table-map! proc ht)
      (for-each
        (lambda (k) (hash-table-set! ht k (proc k (srfi69-ref ht k))))
        (hash-table-keys ht))
      ht)

    (define (hash-table-prune! proc ht)
      (for-each
        (lambda (k)
          (if (proc k (srfi69-ref ht k))
              (hash-table-delete! ht k)))
        (hash-table-keys ht)))

    (define (hash-table-empty-copy ht)
      (make-hash-table))

    (define (hash-table-xor! ht1 ht2)
      (hash-table-walk ht2
        (lambda (k v)
          (if (hash-table-exists? ht1 k)
              (hash-table-delete! ht1 k)
              (hash-table-set! ht1 k v))))
      ht1)))
