(define-library (srfi 222)
  (import (scheme base))
  (export make-compound compound? compound-subobjects
          compound-length compound-ref
          compound-map compound-map->list compound-filter
          compound-predicate compound-access)
  (begin
    (define-record-type <compound>
      (make-compound-record subobjects)
      compound?
      (subobjects %compound-subobjects))

    ;; Local helpers: `filter' and `append-map' are not (scheme base)
    ;; bindings in R7RS — kaappi resolves them only through its vm.globals
    ;; fallback for library bodies, and other R7RS implementations would not
    ;; load the library at all. The SRFI 222 reference implementation defines
    ;; its own `filter', as does lib/srfi/217.sld, so this library stays
    ;; loadable by any R7RS implementation.
    (define (filter pred lst)
      (let loop ((in lst) (out '()))
        (cond ((null? in) (reverse out))
              ((pred (car in)) (loop (cdr in) (cons (car in) out)))
              (else (loop (cdr in) out)))))

    ;; Apply f to every element and append the results, one level deep.
    (define (append-map f lst)
      (let loop ((in lst) (out '()))
        (if (null? in)
            (reverse out)
            (loop (cdr in) (append (reverse (f (car in))) out)))))

    ;; "If obj is a compound object, returns a list of its subobjects;
    ;; otherwise, returns a list containing only obj." (#2072: the bare
    ;; record accessor used to raise on a non-compound.)
    (define (compound-subobjects obj)
      (if (compound? obj)
          (%compound-subobjects obj)
          (list obj)))

    ;; Subobjects are never compounds: make-compound (and compound-map, which
    ;; builds through it) flattens nested compound objects, so a compound's
    ;; subobject list is always flat (#2072).
    (define (make-compound . objs)
      (make-compound-record
       (append-map (lambda (o)
                     (if (compound? o)
                         (compound-subobjects o)
                         (list o)))
                   objs)))

    (define (compound-length obj)
      (if (compound? obj)
          (length (compound-subobjects obj))
          1))

    (define (compound-ref obj k)
      (if (compound? obj)
          (list-ref (compound-subobjects obj) k)
          (if (= k 0)
              obj
              (error "compound-ref: index out of range" k))))

    (define (compound-map mapper obj)
      ;; Mapper results that are themselves compounds are flattened into the
      ;; result's subobjects, in sequence.
      (make-compound-record
       (append-map (lambda (o)
                     (let ((r (mapper o)))
                       (if (compound? r)
                           (compound-subobjects r)
                           (list r))))
                   (compound-subobjects obj))))

    (define (compound-map->list mapper obj)
      (map mapper (compound-subobjects obj)))

    (define (compound-filter pred obj)
      (make-compound-record (filter pred (compound-subobjects obj))))

    (define (compound-predicate pred obj)
      (if (or (pred obj)
              (and (compound? obj)
                   (let loop ((os (compound-subobjects obj)))
                     (cond ((null? os) #f)
                           ((pred (car os)) #t)
                           (else (loop (cdr os)))))))
          #t
          #f))

    (define (compound-access predicate accessor default obj)
      (cond ((predicate obj) (accessor obj))
            ((compound? obj)
             (let loop ((os (compound-subobjects obj)))
               (cond ((null? os) default)
                     ((predicate (car os)) (accessor (car os)))
                     (else (loop (cdr os))))))
            (else default)))))
