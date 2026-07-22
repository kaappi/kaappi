;;; SRFI 225 — Dictionaries
;;;
;;; A generic dictionary interface: a "Dictionary Type Object" (DTO) bundles
;;; the procedures needed to manipulate one concrete key/value store, and the
;;; `dict-*` procedures exported here take a DTO as their first argument and
;;; dispatch to it. Two DTOs are provided unconditionally per the SRFI
;;; (`eqv-alist-dto`, `equal-alist-dto`), plus one Kaappi addition:
;;; `hash-table-dto` / `srfi-69-dto` (two names for the same DTO — Kaappi's
;;; SRFI 69, 125, and 126 all share one native hash-table representation, so
;;; there is nothing for the two spec-mentioned names to distinguish here).
;;; `mapping-dto`/`hash-mapping-dto` (for SRFI 146) are not provided: wiring
;;; an *ordered* dict into the generic layer means also honoring the
;;; `dict-for-each`/`dict->generator` optional `start`/`end` range arguments,
;;; which is a real feature this file does not implement (see below) — adding
;;; a DTO that silently ignored its own ordering would misrepresent it.
;;;
;;; Scope decisions:
;;;
;;; - `dict-find-update!`'s four continuations (`insert`, `ignore`, `update`,
;;;   `delete`) each take a trailing "carry" value that is threaded straight
;;;   through to the second return value, e.g. `(insert value carry)` =>
;;;   `(values new-dict carry)`. The SRFI text available to this
;;;   implementation does not spell out this parameter, but some such
;;;   mechanism is required for `dict-find-update!` to serve both read
;;;   operations (which must report a value without touching the dict) and
;;;   write operations (which must report the dict's new state) through one
;;;   primitive. This is the same shape as the `set-search!`/`bag-search!`
;;;   continuations already in this codebase's `(srfi 113)`.
;;; - `dict-set!`/`dict-adjoin!` on an alist dict always *prepend* a
;;;   brand-new association, and replacing an existing key's value moves
;;;   that association to the front. This matches the SRFI's own stated rule
;;;   for alists ("associations with new keys are added to the beginning")
;;;   applied uniformly; only the exact list position of a *replaced* key
;;;   in the SRFI's own worked example could not be confirmed against the
;;;   live spec text, so a single consistent front-insertion rule is used
;;;   instead of trying to special-case it.
;;; - `start`/`end` bounds on `dict-for-each`/`dict->generator` only make
;;;   sense for an ordered dict. None of the three DTOs here are ordered, so
;;;   both procedures signal a `dictionary-error` if given either bound
;;;   rather than silently ignoring them.
;;; - `dictionary-error` raises (via `raise`) an object satisfying
;;;   `dictionary-error?`, rather than merely constructing and returning one
;;;   — matching how "the default value of failure signals an error" is
;;;   used everywhere else in this SRFI.

(define-library (srfi 225)
  (import (scheme base) (scheme case-lambda) (srfi 69) (srfi 128) (srfi 158))
  (export
    ;; DTO construction and introspection
    dto? make-dto dto-ref make-alist-dto
    eqv-alist-dto equal-alist-dto hash-table-dto srfi-69-dto

    ;; proc-id tags
    dictionary?-id dict-find-update!-id dict-comparator-id dict-map-id
    dict-pure?-id dict-remove-id dict-size-id
    dict-ref-id dict-ref/default-id dict-set!-id dict-adjoin!-id
    dict-delete!-id dict-delete-all!-id dict-replace!-id dict-intern!-id
    dict-update!-id dict-update/default!-id dict-pop!-id
    dict-contains?-id dict-empty?-id dict-count-id dict-any-id dict-every-id
    dict-keys-id dict-values-id dict-entries-id dict-fold-id dict-for-each-id
    dict-map->list-id dict-filter-id dict->alist-id dict->generator-id
    dict=?-id dict-set!-accumulator-id dict-adjoin!-accumulator-id

    ;; generic dictionary operations
    dictionary? dict-empty? dict-contains? dict=? dict-pure?
    dict-ref dict-ref/default dict-comparator
    dict-set! dict-adjoin! dict-delete! dict-delete-all!
    dict-replace! dict-intern! dict-update! dict-update/default! dict-pop!
    dict-find-update!
    dict-map dict-filter dict-remove
    dict-size dict-count dict-any dict-every
    dict-keys dict-values dict-entries dict-fold
    dict-map->list dict->alist
    dict-for-each dict->generator
    dict-set!-accumulator dict-adjoin!-accumulator

    ;; errors
    dictionary-error dictionary-error? dictionary-message dictionary-irritants)

  (begin

    ;;; ---------------------------------------------------------------
    ;;; Errors
    ;;; ---------------------------------------------------------------

    (define-record-type <dictionary-error>
      (make-dictionary-error message irritants)
      dictionary-error?
      (message dictionary-message)
      (irritants dictionary-irritants))

    (define (dictionary-error message . irritants)
      (raise (make-dictionary-error message irritants)))

    ;;; ---------------------------------------------------------------
    ;;; DTOs
    ;;; ---------------------------------------------------------------

    (define-record-type <dto>
      (%make-dto table)
      dto?
      (table %dto-table))

    (define (make-dto . args)
      (let loop ((args args) (table '()))
        (if (null? args)
            (%make-dto table)
            (loop (cddr args) (cons (cons (car args) (cadr args)) table)))))

    (define (dto-ref dto proc-id)
      (let ((entry (assq proc-id (%dto-table dto))))
        (if entry (cdr entry) #f)))

    (define (%dto-required dto proc-id who)
      (or (dto-ref dto proc-id)
          (dictionary-error
            (string-append who ": DTO is missing a required procedure")
            proc-id)))

    ;;; proc-id tags — plain symbols, used as alist keys into a DTO's table.

    (define dictionary?-id 'dictionary?)
    (define dict-find-update!-id 'dict-find-update!)
    (define dict-comparator-id 'dict-comparator)
    (define dict-map-id 'dict-map)
    (define dict-pure?-id 'dict-pure?)
    (define dict-remove-id 'dict-remove)
    (define dict-size-id 'dict-size)

    (define dict-ref-id 'dict-ref)
    (define dict-ref/default-id 'dict-ref/default)
    (define dict-set!-id 'dict-set!)
    (define dict-adjoin!-id 'dict-adjoin!)
    (define dict-delete!-id 'dict-delete!)
    (define dict-delete-all!-id 'dict-delete-all!)
    (define dict-replace!-id 'dict-replace!)
    (define dict-intern!-id 'dict-intern!)
    (define dict-update!-id 'dict-update!)
    (define dict-update/default!-id 'dict-update/default!)
    (define dict-pop!-id 'dict-pop!)
    (define dict-contains?-id 'dict-contains?)
    (define dict-empty?-id 'dict-empty?)
    (define dict-count-id 'dict-count)
    (define dict-any-id 'dict-any)
    (define dict-every-id 'dict-every)
    (define dict-keys-id 'dict-keys)
    (define dict-values-id 'dict-values)
    (define dict-entries-id 'dict-entries)
    (define dict-fold-id 'dict-fold)
    (define dict-for-each-id 'dict-for-each)
    (define dict-map->list-id 'dict-map->list)
    (define dict-filter-id 'dict-filter)
    (define dict->alist-id 'dict->alist)
    (define dict->generator-id 'dict->generator)
    (define dict=?-id 'dict=?)
    (define dict-set!-accumulator-id 'dict-set!-accumulator)
    (define dict-adjoin!-accumulator-id 'dict-adjoin!-accumulator)

    ;;; ---------------------------------------------------------------
    ;;; Generic dictionary operations
    ;;; ---------------------------------------------------------------

    (define (dictionary? dto obj)
      ((%dto-required dto dictionary?-id 'dictionary?) obj))

    (define (dict-pure? dto dict)
      ((%dto-required dto dict-pure?-id 'dict-pure?) dict))

    (define (dict-size dto dict)
      ((%dto-required dto dict-size-id 'dict-size) dict))

    (define (dict-comparator dto dict)
      ((%dto-required dto dict-comparator-id 'dict-comparator) dict))

    (define (dict-map dto proc dict)
      ((%dto-required dto dict-map-id 'dict-map) proc dict))

    (define (dict-remove dto pred dict)
      ((%dto-required dto dict-remove-id 'dict-remove) pred dict))

    (define (dict-find-update! dto dict key failure success)
      ((%dto-required dto dict-find-update!-id 'dict-find-update!)
       dict key failure success))

    (define (dict-filter dto pred dict)
      (let ((custom (dto-ref dto dict-filter-id)))
        (if custom
            (custom pred dict)
            (dict-remove dto (lambda (k v) (not (pred k v))) dict))))

    (define (dict-empty? dto dict)
      (let ((custom (dto-ref dto dict-empty?-id)))
        (if custom (custom dict) (= 0 (dict-size dto dict)))))

    ;; dict-for-each's fallback rides on the required dict-map, discarding
    ;; the rebuilt dict and keeping only the side effect of calling proc.
    (define dict-for-each
      (case-lambda
        ((dto proc dict) (dict-for-each dto proc dict #f #f))
        ((dto proc dict start) (dict-for-each dto proc dict start #f))
        ((dto proc dict start end)
         (let ((custom (dto-ref dto dict-for-each-id)))
           (cond
             (custom (custom proc dict start end))
             ((or start end)
              (dictionary-error
                "dict-for-each: this DTO's dictionaries are unordered; start/end are not supported"
                dto))
             (else
              (dict-map dto (lambda (k v) (proc k v) v) dict)
              (if #f #f)))))))

    (define (dict-fold dto proc knil dict)
      (let ((custom (dto-ref dto dict-fold-id)))
        (if custom
            (custom proc knil dict)
            (let ((acc knil))
              (dict-for-each dto (lambda (k v) (set! acc (proc k v acc))) dict)
              acc))))

    (define (dict-count dto pred dict)
      (let ((custom (dto-ref dto dict-count-id)))
        (if custom
            (custom pred dict)
            (dict-fold dto (lambda (k v acc) (if (pred k v) (+ acc 1) acc)) 0 dict))))

    (define (dict-any dto pred dict)
      (let ((custom (dto-ref dto dict-any-id)))
        (if custom
            (custom pred dict)
            (call-with-current-continuation
              (lambda (return)
                (dict-for-each dto
                  (lambda (k v) (let ((r (pred k v))) (if r (return r))))
                  dict)
                #f)))))

    (define (dict-every dto pred dict)
      (let ((custom (dto-ref dto dict-every-id)))
        (if custom
            (custom pred dict)
            (call-with-current-continuation
              (lambda (return)
                (let ((last #t))
                  (dict-for-each dto
                    (lambda (k v)
                      (let ((r (pred k v)))
                        (if r (set! last r) (return #f))))
                    dict)
                  last))))))

    (define (dict-keys dto dict)
      (let ((custom (dto-ref dto dict-keys-id)))
        (if custom
            (custom dict)
            (reverse (dict-fold dto (lambda (k v acc) (cons k acc)) '() dict)))))

    (define (dict-values dto dict)
      (let ((custom (dto-ref dto dict-values-id)))
        (if custom
            (custom dict)
            (reverse (dict-fold dto (lambda (k v acc) (cons v acc)) '() dict)))))

    (define (dict-entries dto dict)
      (let ((custom (dto-ref dto dict-entries-id)))
        (if custom
            (custom dict)
            (values (dict-keys dto dict) (dict-values dto dict)))))

    (define (dict-map->list dto proc dict)
      (let ((custom (dto-ref dto dict-map->list-id)))
        (if custom
            (custom proc dict)
            (reverse (dict-fold dto (lambda (k v acc) (cons (proc k v) acc)) '() dict)))))

    (define (dict->alist dto dict)
      (let ((custom (dto-ref dto dict->alist-id)))
        (if custom
            (custom dict)
            (reverse (dict-fold dto (lambda (k v acc) (cons (cons k v) acc)) '() dict)))))

    (define (dict-contains? dto dict key)
      (let ((custom (dto-ref dto dict-contains?-id)))
        (if custom
            (custom dict key)
            (call-with-values
              (lambda ()
                (dict-find-update! dto dict key
                  (lambda (insert ignore) (ignore #f))
                  (lambda (k v update delete) (update k v #t))))
              (lambda (new-dict found?) found?)))))

    (define dict-ref
      (case-lambda
        ((dto dict key) (dict-ref dto dict key #f #f))
        ((dto dict key failure) (dict-ref dto dict key failure #f))
        ((dto dict key failure success)
         (let ((custom (dto-ref dto dict-ref-id))
               (fail (or failure
                         (lambda () (dictionary-error "dict-ref: key not found" key))))
               (succ (or success (lambda (v) v))))
           (if custom
               (custom dict key fail succ)
               (call-with-values
                 (lambda ()
                   (dict-find-update! dto dict key
                     (lambda (insert ignore) (ignore (fail)))
                     (lambda (k v update delete) (update k v (succ v)))))
                 (lambda (new-dict result) result)))))))

    (define (dict-ref/default dto dict key default)
      (let ((custom (dto-ref dto dict-ref/default-id)))
        (if custom
            (custom dict key default)
            (dict-ref dto dict key (lambda () default) (lambda (v) v)))))

    (define (dict-set! dto dict . kvs)
      (let ((custom (dto-ref dto dict-set!-id)))
        (if custom
            (apply custom dict kvs)
            (let loop ((dict dict) (kvs kvs))
              (if (null? kvs)
                  dict
                  (let ((key (car kvs)) (value (cadr kvs)))
                    (loop
                      (call-with-values
                        (lambda ()
                          (dict-find-update! dto dict key
                            (lambda (insert ignore) (insert value dict))
                            (lambda (k v update delete) (update key value dict))))
                        (lambda (new-dict carry) new-dict))
                      (cddr kvs))))))))

    (define (dict-adjoin! dto dict . kvs)
      (let ((custom (dto-ref dto dict-adjoin!-id)))
        (if custom
            (apply custom dict kvs)
            (let loop ((dict dict) (kvs kvs))
              (if (null? kvs)
                  dict
                  (let ((key (car kvs)) (value (cadr kvs)))
                    (loop
                      (call-with-values
                        (lambda ()
                          (dict-find-update! dto dict key
                            (lambda (insert ignore) (insert value dict))
                            ;; Key already present: adjoin! leaves it alone,
                            ;; so "update" it back to its own existing value.
                            (lambda (k v update delete) (update k v dict))))
                        (lambda (new-dict carry) new-dict))
                      (cddr kvs))))))))

    (define (dict-replace! dto dict key value)
      (let ((custom (dto-ref dto dict-replace!-id)))
        (if custom
            (custom dict key value)
            (call-with-values
              (lambda ()
                (dict-find-update! dto dict key
                  (lambda (insert ignore) (ignore dict))
                  (lambda (k v update delete) (update key value dict))))
              (lambda (new-dict carry) new-dict)))))

    (define (dict-delete! dto dict . keys)
      (let ((custom (dto-ref dto dict-delete!-id)))
        (if custom
            (apply custom dict keys)
            (let loop ((dict dict) (keys keys))
              (if (null? keys)
                  dict
                  (loop
                    (call-with-values
                      (lambda ()
                        (dict-find-update! dto dict (car keys)
                          (lambda (insert ignore) (ignore dict))
                          (lambda (k v update delete) (delete dict))))
                      (lambda (new-dict carry) new-dict))
                    (cdr keys)))))))

    (define (dict-delete-all! dto dict keylist)
      (let ((custom (dto-ref dto dict-delete-all!-id)))
        (if custom
            (custom dict keylist)
            (apply dict-delete! dto dict keylist))))

    ;; dict-intern! returns exactly 2 values (dict, value) — the same shape
    ;; dict-find-update! itself returns — so the "carry" channel can be the
    ;; value directly with no further unwrapping needed.
    (define (dict-intern! dto dict key failure)
      (let ((custom (dto-ref dto dict-intern!-id)))
        (if custom
            (custom dict key failure)
            (dict-find-update! dto dict key
              (lambda (insert ignore)
                (let ((value (failure))) (insert value value)))
              (lambda (k v update delete) (update k v v))))))

    (define (dict-update! dto dict key updater . rest)
      (let ((custom (dto-ref dto dict-update!-id))
            (failure (if (pair? rest)
                         (car rest)
                         (lambda () (dictionary-error "dict-update!: key not found" key))))
            (success (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (lambda (v) v))))
        (if custom
            (custom dict key updater failure success)
            (call-with-values
              (lambda ()
                (dict-find-update! dto dict key
                  (lambda (insert ignore) (insert (updater (failure)) dict))
                  (lambda (k v update delete) (update k (updater (success v)) dict))))
              (lambda (new-dict carry) new-dict)))))

    (define (dict-update/default! dto dict key updater default)
      (let ((custom (dto-ref dto dict-update/default!-id)))
        (if custom
            (custom dict key updater default)
            (dict-update! dto dict key updater (lambda () default) (lambda (v) v)))))

    (define (dict-pop! dto dict)
      (let ((custom (dto-ref dto dict-pop!-id)))
        (if custom
            (custom dict)
            (call-with-current-continuation
              (lambda (return)
                (dict-for-each dto
                  (lambda (k v)
                    (call-with-values
                      (lambda () (dict-delete! dto dict k))
                      (lambda (new-dict) (return (values new-dict k v)))))
                  dict)
                (dictionary-error "dict-pop!: dictionary is empty"))))))

    (define (dict=? dto = dict1 dict2)
      (let ((custom (dto-ref dto dict=?-id)))
        (if custom
            (custom = dict1 dict2)
            (and (= (dict-size dto dict1) (dict-size dto dict2))
                 (dict-every dto
                   (lambda (k v)
                     (call-with-values
                       (lambda ()
                         (dict-find-update! dto dict2 k
                           (lambda (insert ignore) (ignore #f))
                           (lambda (k2 v2 update delete) (update k2 v2 (= v v2)))))
                       (lambda (new-dict2 eq-result) eq-result)))
                   dict1)))))

    (define (dict->generator dto dict . rest)
      (let ((start (if (pair? rest) (car rest) #f))
            (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) #f))
            (custom (dto-ref dto dict->generator-id)))
        (cond
          (custom (apply custom dict rest))
          ((or start end)
           (dictionary-error
             "dict->generator: this DTO's dictionaries are unordered; start/end are not supported"
             dto))
          (else (list->generator (dict->alist dto dict))))))

    (define (dict-set!-accumulator dto dict)
      (let ((custom (dto-ref dto dict-set!-accumulator-id)))
        (if custom
            (custom dict)
            (let ((state dict))
              (lambda (pair)
                (if (eof-object? pair)
                    state
                    (set! state (dict-set! dto state (car pair) (cdr pair)))))))))

    (define (dict-adjoin!-accumulator dto dict)
      (let ((custom (dto-ref dto dict-adjoin!-accumulator-id)))
        (if custom
            (custom dict)
            (let ((state dict))
              (lambda (pair)
                (if (eof-object? pair)
                    state
                    (set! state (dict-adjoin! dto state (car pair) (cdr pair)))))))))

    ;;; ---------------------------------------------------------------
    ;;; Alist DTOs (pure)
    ;;; ---------------------------------------------------------------

    (define (%proper-alist? x)
      (and (list? x)
           (let loop ((lst x))
             (or (null? lst) (and (pair? (car lst)) (loop (cdr lst)))))))

    (define (%alist-map-values proc alist)
      (map (lambda (kv) (cons (car kv) (proc (car kv) (cdr kv)))) alist))

    (define (%alist-filter-out pred alist)
      (let loop ((lst alist) (acc '()))
        (cond
          ((null? lst) (reverse acc))
          ((pred (caar lst) (cdar lst)) (loop (cdr lst) acc))
          (else (loop (cdr lst) (cons (car lst) acc))))))

    ;; Continuations follow the "carry" protocol documented at the top of
    ;; this file: each takes a trailing value threaded to the 2nd result.
    (define (%make-alist-find-update eq)
      (lambda (dict key failure success)
        (let loop ((lst dict) (acc '()))
          (cond
            ((null? lst)
             (failure
               (lambda (value carry) (values (cons (cons key value) dict) carry))
               (lambda (carry) (values dict carry))))
            ((eq (caar lst) key)
             (success (caar lst) (cdar lst)
               (lambda (new-key new-value carry)
                 ;; A true no-op (adjoin! on an existing key "updates" it to
                 ;; its own current key/value) must return the untouched
                 ;; original dict rather than a reordered rebuild.
                 (if (and (eqv? new-key (caar lst)) (equal? new-value (cdar lst)))
                     (values dict carry)
                     (values (cons (cons new-key new-value) (append (reverse acc) (cdr lst)))
                             carry)))
               (lambda (carry)
                 (values (append (reverse acc) (cdr lst)) carry))))
            (else (loop (cdr lst) (cons (car lst) acc)))))))

    (define (%make-alist-dto eq)
      (make-dto
        dictionary?-id (lambda (obj) (%proper-alist? obj))
        dict-pure?-id (lambda (dict) #t)
        dict-size-id (lambda (dict) (length dict))
        dict-comparator-id (lambda (dict) (make-comparator #t eq #f #f))
        dict-map-id (lambda (proc dict) (%alist-map-values proc dict))
        dict-remove-id (lambda (pred dict) (%alist-filter-out pred dict))
        dict-find-update!-id (%make-alist-find-update eq)
        dict-pop!-id
        (lambda (dict)
          (if (null? dict)
              (dictionary-error "dict-pop!: dictionary is empty")
              (values (cdr dict) (caar dict) (cdar dict))))
        dict->alist-id (lambda (dict) dict)
        dict-keys-id (lambda (dict) (map car dict))
        dict-values-id (lambda (dict) (map cdr dict))))

    (define (make-alist-dto eq) (%make-alist-dto eq))

    (define eqv-alist-dto (%make-alist-dto eqv?))
    (define equal-alist-dto (%make-alist-dto equal?))

    ;;; ---------------------------------------------------------------
    ;;; Hash-table DTO (impure) — shared by SRFI 69/125/126 in Kaappi
    ;;; ---------------------------------------------------------------

    (define (%hash-table-find-update dict key failure success)
      (if (hash-table-exists? dict key)
          (success key (hash-table-ref dict key)
            (lambda (new-key new-value carry)
              (if (not (eqv? new-key key)) (hash-table-delete! dict key))
              (hash-table-set! dict new-key new-value)
              (values dict carry))
            (lambda (carry)
              (hash-table-delete! dict key)
              (values dict carry)))
          (failure
            (lambda (value carry)
              (hash-table-set! dict key value)
              (values dict carry))
            (lambda (carry) (values dict carry)))))

    (define (%hash-table-comparator dict)
      (make-comparator #t (hash-table-equivalence-function dict) #f
                        (hash-table-hash-function dict)))

    (define hash-table-dto
      (make-dto
        dictionary?-id (lambda (obj) (hash-table? obj))
        dict-pure?-id (lambda (dict) #f)
        dict-size-id (lambda (dict) (hash-table-size dict))
        dict-comparator-id %hash-table-comparator
        dict-map-id
        (lambda (proc dict)
          (let ((result (make-hash-table)))
            (hash-table-walk dict
              (lambda (k v) (hash-table-set! result k (proc k v))))
            result))
        dict-remove-id
        (lambda (pred dict)
          (let ((result (make-hash-table)))
            (hash-table-walk dict
              (lambda (k v) (if (not (pred k v)) (hash-table-set! result k v))))
            result))
        dict-find-update!-id %hash-table-find-update
        dict-contains?-id (lambda (dict key) (hash-table-exists? dict key))
        dict-empty?-id (lambda (dict) (= 0 (hash-table-size dict)))
        dict-keys-id (lambda (dict) (hash-table-keys dict))
        dict-values-id (lambda (dict) (hash-table-values dict))
        dict->alist-id (lambda (dict) (hash-table->alist dict))
        dict-for-each-id
        (lambda (proc dict start end)
          (if (or start end)
              (dictionary-error
                "dict-for-each: hash tables are unordered; start/end are not supported"
                dict)
              (hash-table-walk dict proc)))))

    (define srfi-69-dto hash-table-dto)))
