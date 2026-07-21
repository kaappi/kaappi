;;; SRFI 44 — Collections
;;;
;;; SRFI 44's reference implementation dispatches generic operations through
;;; Tiny-CLOS, an extensible generic-function/class system. Kaappi has no
;;; such object system and none of the other 100+ SRFIs in this codebase
;;; introduce one, so this library instead dispatches on a *closed* set of
;;; concrete Scheme types via runtime `case`/`cond` — the same strategy the
;;; SRFI text explicitly leaves unspecified ("a single dispatch system
;;; should be sufficient"). The practical consequence: a new collection type
;;; cannot be registered into `collection-fold-left` and friends the way a
;;; Tiny-CLOS subclass could be. The concrete types wired in are:
;;;
;;;   - list    (a Flexible Sequence, and so also a Bag)
;;;   - vector  (a Sequence, Limited, Purely Mutable, and so also a Bag)
;;;   - string  (a Sequence of characters, Limited, Purely Mutable, Bag)
;;;   - a new `alist-map` record (a Map — this SRFI's own "Association List
;;;     Maps", implemented here as a genuine multimap, matching the SRFI's
;;;     description of alist-maps as "a superset of the Map functionality")
;;;   - `(srfi 69)` hash tables (a Map)
;;;   - `(srfi 113)` sets and bags (a Set and a genuine Bag, respectively)
;;;
;;; Further scope decisions:
;;;
;;; - This file does not re-export `vector-ref`, `string-ref`, `list-ref`,
;;;   `vector-set!`, `string-set!`, `make-vector`, `make-string`, `vector`,
;;;   `string`, `list`, `make-list`, `vector-copy`, `string-copy`, or
;;;   `list-copy` under their SRFI 44 signatures (several gain an optional
;;;   absence-thunk or a return-the-collection contract). SRFI 44 predates
;;;   R7RS and its "Lists"/"Vectors"/"Strings" sections deliberately extend
;;;   those exact R5RS names — but re-exporting them here would make
;;;   `(import (scheme base) (srfi 44))` an immediate name clash for every
;;;   caller, for a library meant to be used *alongside* the standard
;;;   library rather than instead of it (contrast `(srfi 140)`, which
;;;   intentionally *does* replace `(scheme base)` string procedures because
;;;   replacement is the whole point of an immutable-string library). Every
;;;   behavior these would have added is still available under a
;;;   non-colliding generic name: `sequence-ref`/`sequence-set`/
;;;   `sequence-set!`/`sequence-copy` all accept the same collections.
;;; - `collection-fold-left`/`-right` implement the SRFI's own multi-seed,
;;;   early-exit protocol exactly as documented: `fold-function` is called
;;;   as `(fold-function value seed ...)` and must return a `proceed` flag
;;;   followed by the same number of new seeds; a false `proceed` halts
;;;   enumeration early. `collection-for-each`, `collection-find`,
;;;   `collection-any?`, and `collection-every?` are Kaappi *extensions*
;;;   layered on top (the SRFI text defines no such names) — they exist
;;;   because they are one-line specializations of fold and the task this
;;;   file was written for explicitly wants map/filter/for-each/find-style
;;;   coverage; they are exported alongside, not instead of, the spec's own
;;;   fold-based primitives.
;;; - `collection-count`'s spec wording ("*-count * value") is written for
;;;   Bag-shaped collections; applied to a Map (alist-map/hash-table) it
;;;   counts associations whose *value* — not key — equals the given value,
;;;   which is the only reading consistent with fold enumerating a map's
;;;   values (see "Core Enumeration Procedures").
;;; - `collection-clear!`/`*-clear!` (in-place emptying) are not provided.
;;; - `set-*` operations are thin adapters over the existing `(srfi 113)`
;;;   set procedures (Kaappi's only Set implementation) rather than a
;;;   reimplementation; `collection=`'s handling of two sets or two bags
;;;   likewise delegates to `(srfi 113)` `set=?`/`bag=?`, which use each
;;;   collection's own configured equivalence rather than the `elt=`
;;;   argument `collection=` takes for sequences.
;;; - `bag?`, `bag-contains?`, `bag-delete`, `bag-delete!`, `bag-delete-all`,
;;;   and `bag-delete-all!` deliberately reuse `(srfi 113)`'s exact names
;;;   for a *broader* domain (list/vector/string/bag instead of just bag) —
;;;   the same "extend, don't rename" choice the naming-convention section
;;;   of the SRFI itself describes. This library imports `(srfi 113)` with
;;;   exactly those six names excepted and privately renamed, so it never
;;;   collides with itself; but a *caller* who also wants direct,
;;;   unqualified access to `(srfi 113)` in the same file must do the same
;;;   (e.g. `(import (srfi 44) (except (srfi 113) bag? bag-contains?
;;;   bag-delete bag-delete! bag-delete-all bag-delete-all!))`), exactly as
;;;   R7RS requires whenever two libraries export the same identifier with
;;;   different meanings. `set`/`bag` (the constructors) and every `set-*`
;;;   name are untouched and safe to import from `(srfi 113)` alongside
;;;   `(srfi 44)` without qualification.

(define-library (srfi 44)
  (import (scheme base) (scheme case-lambda)
          (srfi 1) (srfi 69) (srfi 128)
          ;; bag?, bag-contains?, and the bag-delete* family get SRFI 44's
          ;; own generic definitions below (they dispatch across list,
          ;; vector, string, and bag — not just bag); the plain SRFI 113
          ;; procedures are still needed internally, so they come back in
          ;; renamed rather than being lost.
          (except (srfi 113)
                  bag? bag-contains? bag-delete bag-delete! bag-delete-all bag-delete-all!)
          (rename (only (srfi 113)
                        bag? bag-contains? bag-delete bag-delete! bag-delete-all bag-delete-all!)
                  (bag? %113-bag?)
                  (bag-contains? %113-bag-contains?)
                  (bag-delete %113-bag-delete)
                  (bag-delete! %113-bag-delete!)
                  (bag-delete-all %113-bag-delete-all)
                  (bag-delete-all! %113-bag-delete-all!)))

  (export
    ;; Dispatch / introspection
    collection? collection-name
    ordered-collection? directional-collection?
    limited-collection? purely-mutable-collection?

    ;; Base collection generics
    collection-size collection-count collection-get-any collection-empty?
    collection->list collection-copy collection-clear collection=

    ;; Enumeration (core SRFI 44 protocol)
    collection-fold-left collection-fold-right
    collection-fold-keys-left collection-fold-keys-right

    ;; Kaappi extensions built on fold (see header comment)
    collection-for-each collection-find collection-any? collection-every?

    ;; Bag family: list, vector, string, (srfi 113) bag
    bag? bag-equivalence-function bag-contains?
    bag-add bag-add! bag-delete bag-delete! bag-delete-all bag-delete-all!
    bag-add-from bag-add-from! bag-delete-from bag-delete-from!
    bag-delete-all-from bag-delete-all-from!

    ;; Set family: (srfi 113) set, adapted
    set? set-equivalence-function set-contains? set-subset?
    set-add set-add! set-delete set-delete!
    set-union set-union! set-intersection set-intersection!
    set-difference set-difference!
    set-symmetric-difference set-symmetric-difference!
    set-add-from set-add-from! set-delete-from set-delete-from!

    ;; Sequence family: list, vector, string
    sequence? sequence-ref sequence-get-left sequence-get-right
    sequence-set sequence-set! sequence-copy sequence-add

    ;; Flexible Sequence family: list
    flexible-sequence? flexible-sequence-insert flexible-sequence-delete-at
    flexible-sequence-insert-left flexible-sequence-insert-right
    flexible-sequence-delete-left flexible-sequence-delete-right

    ;; Map family: alist-map, (srfi 69) hash-table
    map? map-equivalence-function map-key-equivalence-function
    map-contains-key? map-keys->list
    map-get map-put map-put! map-update map-update!
    map-delete map-delete!
    map-add-from map-add-from! map-delete-from map-delete-from!

    ;; Concrete: Association List Maps
    make-alist-map alist-map alist-map?
    alist-map-equivalence-function
    alist-map-size alist-map-empty? alist-map-contains-key?
    alist-map-get alist-map-get-all
    alist-map-copy alist-map->list alist-map-keys->list
    alist-map-put alist-map-put!
    alist-map-delete alist-map-delete! alist-map-delete-all alist-map-delete-all!
    alist-map-fold-left alist-map-fold-right
    alist-map-fold-keys-left alist-map-fold-keys-right
    alist-map-clear alist-map-clear!
    alist-map=)

  (begin

    ;;; ---------------------------------------------------------------
    ;;; Small private helpers
    ;;; ---------------------------------------------------------------

    (define (%sublist lst start end)
      (let loop ((l (list-tail lst start)) (i start) (acc '()))
        (if (>= i end) (reverse acc) (loop (cdr l) (+ i 1) (cons (car l) acc)))))

    (define (%list-insert-at lst index value)
      (append (%sublist lst 0 index) (list value) (list-tail lst index)))

    (define (%list-delete-at lst index)
      (append (%sublist lst 0 index) (list-tail lst (+ index 1))))

    ;;; ---------------------------------------------------------------
    ;;; Concrete: Association List Maps (a genuine multimap)
    ;;; ---------------------------------------------------------------

    (define-record-type <alist-map>
      (%make-alist-map eq alist)
      alist-map?
      (eq %alist-map-eq)
      (alist %alist-map-alist %alist-map-alist-set!))

    (define (make-alist-map . args)
      (%make-alist-map (if (pair? args) (car args) eqv?) '()))

    (define (alist-map . args)
      (if (and (pair? args) (procedure? (car args)))
          (%make-alist-map (car args) (map (lambda (p) (cons (car p) (cdr p))) (cdr args)))
          (%make-alist-map eqv? (map (lambda (p) (cons (car p) (cdr p))) args))))

    (define (alist-map-equivalence-function am) (%alist-map-eq am))
    (define (alist-map-size am) (length (%alist-map-alist am)))
    (define (alist-map-empty? am) (null? (%alist-map-alist am)))

    (define (alist-map-contains-key? am key)
      (let ((eq (%alist-map-eq am)))
        ;; `any` returns the predicate's own truthy value, not a normalized
        ;; boolean — wrap it so a caller-supplied eq that doesn't return a
        ;; plain #t still yields a genuine boolean here.
        (and (any (lambda (kv) (eq (car kv) key)) (%alist-map-alist am)) #t)))

    (define alist-map-get
      (case-lambda
        ((am key) (alist-map-get am key (lambda () (error "alist-map-get: key not found" key))))
        ((am key absence-thunk)
         (let ((eq (%alist-map-eq am)))
           (cond ((find (lambda (kv) (eq (car kv) key)) (%alist-map-alist am)) => cdr)
                 (else (absence-thunk)))))))

    (define (alist-map-get-all am key)
      (let ((eq (%alist-map-eq am)))
        (map cdr (filter (lambda (kv) (eq (car kv) key)) (%alist-map-alist am)))))

    (define (alist-map-copy am) (%make-alist-map (%alist-map-eq am) (%alist-map-alist am)))

    (define (alist-map->list am) (%alist-map-alist am))
    (define (alist-map-keys->list am) (map car (%alist-map-alist am)))

    ;; alist-map-put/put! prepend unconditionally (multimap semantics: a
    ;; second association for the same key shadows, but does not erase, the
    ;; first). Returns the map and the value just inserted.
    (define (alist-map-put! am key value)
      (%alist-map-alist-set! am (cons (cons key value) (%alist-map-alist am)))
      (values am value))

    (define (alist-map-put am key value)
      (let ((copy (alist-map-copy am))) (alist-map-put! copy key value)))

    (define (alist-map-delete! am key)
      (let ((eq (%alist-map-eq am)))
        (let loop ((lst (%alist-map-alist am)) (acc '()) (deleted #f))
          (cond
            ((null? lst) (%alist-map-alist-set! am (reverse acc)) am)
            ((and (not deleted) (eq (caar lst) key))
             (%alist-map-alist-set! am (append (reverse acc) (cdr lst)))
             am)
            (else (loop (cdr lst) (cons (car lst) acc) deleted))))))

    (define (alist-map-delete am key) (alist-map-delete! (alist-map-copy am) key))

    (define (alist-map-delete-all! am key)
      (let ((eq (%alist-map-eq am)))
        (%alist-map-alist-set! am (remove (lambda (kv) (eq (car kv) key)) (%alist-map-alist am)))
        am))

    (define (alist-map-delete-all am key) (alist-map-delete-all! (alist-map-copy am) key))

    ;; fold-function is called as (fold-function value seed ...) and must
    ;; return (values proceed new-seed ...), matching collection-fold-*.
    (define (%fold-over values-list fold-function seeds)
      (let loop ((vs values-list) (seeds seeds))
        (if (null? vs)
            (apply values seeds)
            (call-with-values
              (lambda () (apply fold-function (car vs) seeds))
              (lambda (proceed . new-seeds)
                (if proceed (loop (cdr vs) new-seeds) (apply values new-seeds)))))))

    (define (alist-map-fold-left am fold-function . seeds)
      (%fold-over (%alist-map-alist am) fold-function seeds))
    (define (alist-map-fold-right am fold-function . seeds)
      (%fold-over (reverse (%alist-map-alist am)) fold-function seeds))
    (define (alist-map-fold-keys-left am fold-function . seeds)
      (%fold-over (map car (%alist-map-alist am)) fold-function seeds))
    (define (alist-map-fold-keys-right am fold-function . seeds)
      (%fold-over (reverse (map car (%alist-map-alist am))) fold-function seeds))

    (define (alist-map-clear am) (%make-alist-map (%alist-map-eq am) '()))
    (define (alist-map-clear! am) (%alist-map-alist-set! am '()) am)

    (define (alist-map= elt= . ams)
      (or (null? ams) (null? (cdr ams))
          (let ((a (car ams)))
            (and
              (every
                (lambda (b)
                  (and (= (alist-map-size a) (alist-map-size b))
                       (every
                         (lambda (kv)
                           (any (lambda (kv2) (and (equal? (car kv) (car kv2)) (elt= (cdr kv) (cdr kv2))))
                                (%alist-map-alist b)))
                         (%alist-map-alist a))))
                (cdr ams))
              (apply alist-map= elt= (cdr ams))))))

    ;;; ---------------------------------------------------------------
    ;;; Dispatch core
    ;;; ---------------------------------------------------------------

    (define (%kind obj)
      (cond
        ((list? obj) 'list)
        ((vector? obj) 'vector)
        ((string? obj) 'string)
        ((alist-map? obj) 'alist-map)
        ((hash-table? obj) 'hash-table)
        ((set? obj) 'set)
        ((%113-bag? obj) 'bag)
        (else #f)))

    (define (%require-kind obj who)
      (or (%kind obj) (error (string-append who ": not a collection recognized by (srfi 44)") obj)))

    (define (collection? obj) (if (%kind obj) #t #f))
    (define (collection-name obj) (%require-kind obj 'collection-name))

    ;;; ---------------------------------------------------------------
    ;;; Attribute markers
    ;;; ---------------------------------------------------------------

    (define (ordered-collection? obj) (%require-kind obj 'ordered-collection?) #f)

    (define (directional-collection? obj)
      (case (%require-kind obj 'directional-collection?)
        ((list vector string) #t)
        (else #f)))

    (define (limited-collection? obj)
      (case (%require-kind obj 'limited-collection?)
        ((vector string) #t)
        (else #f)))

    (define (purely-mutable-collection? obj)
      (case (%require-kind obj 'purely-mutable-collection?)
        ((vector string hash-table set bag) #t)
        (else #f)))

    ;;; ---------------------------------------------------------------
    ;;; Base collection generics
    ;;; ---------------------------------------------------------------

    (define (collection-size obj)
      (case (%require-kind obj 'collection-size)
        ((list) (length obj))
        ((vector) (vector-length obj))
        ((string) (string-length obj))
        ((alist-map) (alist-map-size obj))
        ((hash-table) (hash-table-size obj))
        ((set) (set-size obj))
        ((bag) (bag-size obj))))

    (define (collection-empty? obj)
      (case (%require-kind obj 'collection-empty?)
        ((list) (null? obj))
        ((vector) (= 0 (vector-length obj)))
        ((string) (= 0 (string-length obj)))
        ((alist-map) (alist-map-empty? obj))
        ((hash-table) (= 0 (hash-table-size obj)))
        ((set) (set-empty? obj))
        ((bag) (bag-empty? obj))))

    ;; Counts occurrences of `value` among the collection's enumerated
    ;; values (values, not keys, for a Map — see header comment).
    (define (collection-count obj value)
      (case (%require-kind obj 'collection-count)
        ((list) (count (lambda (x) (equal? x value)) obj))
        ((vector) (count (lambda (x) (equal? x value)) (vector->list obj)))
        ((string) (count (lambda (x) (equal? x value)) (string->list obj)))
        ((alist-map) (count (lambda (kv) (equal? (cdr kv) value)) (alist-map->list obj)))
        ((hash-table) (count (lambda (kv) (equal? (cdr kv) value)) (hash-table->alist obj)))
        ((set) (if (set-contains? obj value) 1 0))
        ((bag) (bag-element-count obj value))))

    (define collection-get-any
      (case-lambda
        ((obj) (collection-get-any obj (lambda () (error "collection-get-any: empty collection" obj))))
        ((obj absence-thunk)
         (case (%require-kind obj 'collection-get-any)
           ((list) (if (null? obj) (absence-thunk) (car obj)))
           ((vector) (if (= 0 (vector-length obj)) (absence-thunk) (vector-ref obj 0)))
           ((string) (if (= 0 (string-length obj)) (absence-thunk) (string-ref obj 0)))
           ((alist-map) (if (alist-map-empty? obj) (absence-thunk) (cdar (alist-map->list obj))))
           ((hash-table)
            (if (= 0 (hash-table-size obj)) (absence-thunk) (car (hash-table-values obj))))
           ((set) (set-find (lambda (x) #t) obj absence-thunk))
           ((bag) (bag-find (lambda (x) #t) obj absence-thunk))))))

    (define (collection->list obj)
      (case (%require-kind obj 'collection->list)
        ((list) obj)
        ((vector) (vector->list obj))
        ((string) (string->list obj))
        ((alist-map) (alist-map->list obj))
        ((hash-table) (hash-table->alist obj))
        ((set) (set->list obj))
        ((bag) (bag->list obj))))

    (define (collection-copy obj)
      (case (%require-kind obj 'collection-copy)
        ((list) (list-copy obj))
        ((vector) (vector-copy obj))
        ((string) (string-copy obj))
        ((alist-map) (alist-map-copy obj))
        ((hash-table) (hash-table-copy obj))
        ((set) (set-copy obj))
        ((bag) (bag-copy obj))))

    (define (collection-clear obj)
      (case (%require-kind obj 'collection-clear)
        ((list) '())
        ((vector) (vector))
        ((string) "")
        ((alist-map) (alist-map-clear obj))
        ((hash-table) (make-hash-table))
        ((set) (set (set-element-comparator obj)))
        ((bag) (bag (bag-element-comparator obj)))))

    (define (%seq->list obj)
      (case (%kind obj)
        ((list) obj)
        ((vector) (vector->list obj))
        ((string) (string->list obj))))

    (define (collection= elt= a b)
      (let ((ka (%require-kind a 'collection=)) (kb (%require-kind b 'collection=)))
        (and (eq? ka kb)
             (case ka
               ((list vector string)
                (let ((la (%seq->list a)) (lb (%seq->list b)))
                  (and (= (length la) (length lb)) (every elt= la lb))))
               ((set) (set=? a b))
               ((bag) (bag=? a b))
               ((alist-map) (alist-map= elt= a b))
               ((hash-table)
                (and (= (hash-table-size a) (hash-table-size b))
                     (every
                       (lambda (kv)
                         (and (hash-table-exists? b (car kv))
                              (elt= (cdr kv) (hash-table-ref b (car kv)))))
                       (hash-table->alist a))))))))

    ;;; ---------------------------------------------------------------
    ;;; Enumeration
    ;;; ---------------------------------------------------------------

    (define (collection-fold-left obj fold-function . seeds)
      (%fold-over (collection->list obj) fold-function seeds))

    (define (collection-fold-right obj fold-function . seeds)
      (%fold-over (reverse (collection->list obj)) fold-function seeds))

    ;; Keyed folds are defined only for Maps and Sequences: the "key" is a
    ;; 0-based index for a sequence, and the stored key for a map.
    (define (%keys-of obj)
      (case (%require-kind obj 'collection-fold-keys-left)
        ((list vector string) (iota (collection-size obj)))
        ((alist-map) (alist-map-keys->list obj))
        ((hash-table) (hash-table-keys obj))
        (else (error "collection-fold-keys: only defined for maps and sequences" obj))))

    (define (collection-fold-keys-left obj fold-function . seeds)
      (%fold-over (%keys-of obj) fold-function seeds))

    (define (collection-fold-keys-right obj fold-function . seeds)
      (%fold-over (reverse (%keys-of obj)) fold-function seeds))

    ;;; --- Kaappi extensions built on fold (see header comment) ---------

    (define (collection-for-each proc obj)
      (collection-fold-left obj (lambda (v _) (proc v) (values #t #f)) #f)
      (if #f #f))

    ;; A private sentinel (never `eq?` to anything a caller could construct)
    ;; distinguishes "found a genuine #f element" from "nothing matched" in
    ;; one pass, without misfiring the way comparing against a reused #f
    ;; accumulator would.
    (define collection-find
      (case-lambda
        ((pred obj) (collection-find pred obj (lambda () #f)))
        ((pred obj absence-thunk)
         (let ((sentinel (list 'not-found)))
           (call-with-values
             (lambda ()
               (collection-fold-left obj
                 (lambda (v acc) (if (pred v) (values #f v) (values #t acc)))
                 sentinel))
             (lambda (result) (if (eq? result sentinel) (absence-thunk) result)))))))

    (define (collection-any? pred obj)
      (call-with-values
        (lambda ()
          (collection-fold-left obj
            (lambda (v _) (if (pred v) (values #f #t) (values #t #f)))
            #f))
        (lambda (found) found)))

    (define (collection-every? pred obj)
      (call-with-values
        (lambda ()
          (collection-fold-left obj
            (lambda (v _) (if (pred v) (values #t #t) (values #f #f)))
            #t))
        (lambda (all) all)))

    ;;; ---------------------------------------------------------------
    ;;; Bag family: list, vector, string, (srfi 113) bag
    ;;; ---------------------------------------------------------------

    (define (bag? obj) (and (memv (%kind obj) '(list vector string bag)) #t))

    (define (bag-equivalence-function obj)
      (case (%require-kind obj 'bag-equivalence-function)
        ((list vector) equal?)
        ((string) char=?)
        ((bag) (comparator-equality-predicate (bag-element-comparator obj)))
        (else (error "bag-equivalence-function: not a bag" obj))))

    (define (bag-contains? obj value)
      (case (%require-kind obj 'bag-contains?)
        ((list) (and (member value obj) #t))
        ((vector) (and (member value (vector->list obj)) #t))
        ((string) (and (memv value (string->list obj)) #t))
        ((bag) (%113-bag-contains? obj value))
        (else (error "bag-contains?: not a bag" obj))))

    ;; Removes only the first matching element — *-delete is singular per
    ;; the spec ("*-delete * value => %"), distinct from *-delete-all.
    (define (%delete-first pred lst)
      (let loop ((l lst) (acc '()))
        (cond ((null? l) (reverse acc))
              ((pred (car l)) (append (reverse acc) (cdr l)))
              (else (loop (cdr l) (cons (car l) acc))))))

    (define (bag-add obj value)
      (case (%require-kind obj 'bag-add)
        ((list) (append obj (list value)))
        ((vector) (vector-append obj (vector value)))
        ((string) (string-append obj (string value)))
        ((bag) (bag-adjoin obj value))))

    (define (bag-add! obj value)
      (case (%require-kind obj 'bag-add!)
        ((bag) (bag-adjoin! obj value))
        (else (bag-add obj value))))

    (define (bag-delete obj value)
      (case (%require-kind obj 'bag-delete)
        ((list) (%delete-first (lambda (x) (equal? x value)) obj))
        ((vector) (list->vector (%delete-first (lambda (x) (equal? x value)) (vector->list obj))))
        ((string) (list->string (%delete-first (lambda (x) (equal? x value)) (string->list obj))))
        ((bag) (%113-bag-delete obj value))))

    ;; list/vector/string can't shrink in place (removing an element changes
    ;; the collection's length, which none of these representations support
    ;; mutating in place — the same limitation documented in (srfi 118)'s
    ;; header), so bag-delete!/bag-delete-all! fall back to the functional
    ;; form for them; only the (srfi 113) bag case is a true in-place update.
    (define (bag-delete! obj value)
      (case (%require-kind obj 'bag-delete!)
        ((bag) (%113-bag-delete! obj value))
        (else (bag-delete obj value))))

    (define (bag-delete-all obj value)
      (case (%require-kind obj 'bag-delete-all)
        ((list) (delete value obj))
        ((vector) (list->vector (delete value (vector->list obj))))
        ((string) (list->string (delete value (string->list obj))))
        ((bag) (%113-bag-delete-all obj value))))

    (define (bag-delete-all! obj value)
      (case (%require-kind obj 'bag-delete-all!)
        ((bag) (%113-bag-delete-all! obj value))
        (else (bag-delete-all obj value))))

    (define (bag-add-from obj source)
      (collection-fold-left source (lambda (v acc) (values #t (bag-add acc v))) obj))

    (define (bag-add-from! obj source)
      (collection-for-each (lambda (v) (bag-add! obj v)) source)
      obj)

    (define (bag-delete-from obj source)
      (collection-fold-left source (lambda (v acc) (values #t (bag-delete acc v))) obj))

    (define (bag-delete-from! obj source)
      (collection-for-each (lambda (v) (bag-delete! obj v)) source)
      obj)

    (define (bag-delete-all-from obj source)
      (collection-fold-left source (lambda (v acc) (values #t (bag-delete-all acc v))) obj))

    (define (bag-delete-all-from! obj source)
      (collection-for-each (lambda (v) (bag-delete-all! obj v)) source)
      obj)

    ;;; ---------------------------------------------------------------
    ;;; Set family: (srfi 113) set — thin adapters
    ;;; ---------------------------------------------------------------

    (define (set-equivalence-function s) (comparator-equality-predicate (set-element-comparator s)))

    (define (set-subset? s . sets) (every (lambda (s2) (set<=? s s2)) sets))

    (define (set-add s value) (set-adjoin s value))
    (define (set-add! s value) (set-adjoin! s value))

    (define (set-symmetric-difference s1 s2) (set-xor s1 s2))
    (define (set-symmetric-difference! s1 s2) (set-xor! s1 s2))

    (define (set-add-from s source)
      (collection-fold-left source (lambda (v acc) (values #t (set-add acc v))) s))
    (define (set-add-from! s source)
      (collection-for-each (lambda (v) (set-add! s v)) source) s)
    (define (set-delete-from s source)
      (collection-fold-left source (lambda (v acc) (values #t (set-delete acc v))) s))
    (define (set-delete-from! s source)
      (collection-for-each (lambda (v) (set-delete! s v)) source) s)

    ;;; ---------------------------------------------------------------
    ;;; Sequence family: list, vector, string
    ;;; ---------------------------------------------------------------

    (define (sequence? obj) (and (memv (%kind obj) '(list vector string)) #t))

    (define sequence-ref
      (case-lambda
        ((obj index)
         (sequence-ref obj index (lambda () (error "sequence-ref: index out of range" obj index))))
        ((obj index absence-thunk)
         (case (%require-kind obj 'sequence-ref)
           ((list) (if (and (>= index 0) (< index (length obj))) (list-ref obj index) (absence-thunk)))
           ((vector)
            (if (and (>= index 0) (< index (vector-length obj))) (vector-ref obj index) (absence-thunk)))
           ((string)
            (if (and (>= index 0) (< index (string-length obj))) (string-ref obj index) (absence-thunk)))
           (else (error "sequence-ref: not a sequence" obj))))))

    (define sequence-get-left
      (case-lambda
        ((obj) (sequence-get-left obj (lambda () (error "sequence-get-left: empty sequence" obj))))
        ((obj absence-thunk) (sequence-ref obj 0 absence-thunk))))

    (define sequence-get-right
      (case-lambda
        ((obj) (sequence-get-right obj (lambda () (error "sequence-get-right: empty sequence" obj))))
        ((obj absence-thunk) (sequence-ref obj (- (collection-size obj) 1) absence-thunk))))

    (define (sequence-set obj index value)
      (case (%require-kind obj 'sequence-set)
        ((list) (let ((copy (list-copy obj))) (list-set! copy index value) copy))
        ((vector) (let ((copy (vector-copy obj))) (vector-set! copy index value) copy))
        ((string) (let ((copy (string-copy obj))) (string-set! copy index value) copy))
        (else (error "sequence-set: not a sequence" obj))))

    (define (sequence-set! obj index value)
      (case (%require-kind obj 'sequence-set!)
        ((list) (list-set! obj index value) obj)
        ((vector) (vector-set! obj index value) obj)
        ((string) (string-set! obj index value) obj)
        (else (error "sequence-set!: not a sequence" obj))))

    (define sequence-copy
      (case-lambda
        ((obj) (collection-copy obj))
        ((obj start) (sequence-copy obj start (collection-size obj)))
        ((obj start end)
         (case (%require-kind obj 'sequence-copy)
           ((list) (%sublist obj start end))
           ((vector) (vector-copy obj start end))
           ((string) (string-copy obj start end))
           (else (error "sequence-copy: not a sequence" obj))))))

    (define (sequence-add obj value)
      (case (%require-kind obj 'sequence-add)
        ((list) (append obj (list value)))
        ((vector) (vector-append obj (vector value)))
        ((string) (string-append obj (string value)))
        (else (error "sequence-add: not a sequence" obj))))

    ;;; ---------------------------------------------------------------
    ;;; Flexible Sequence family: list
    ;;; ---------------------------------------------------------------

    (define (flexible-sequence? obj) (eq? (%kind obj) 'list))

    (define (flexible-sequence-insert obj index value)
      (if (eq? (%kind obj) 'list)
          (%list-insert-at obj index value)
          (error "flexible-sequence-insert: not a flexible sequence" obj)))

    (define (flexible-sequence-delete-at obj index)
      (if (eq? (%kind obj) 'list)
          (%list-delete-at obj index)
          (error "flexible-sequence-delete-at: not a flexible sequence" obj)))

    (define (flexible-sequence-insert-left obj value)
      (if (eq? (%kind obj) 'list)
          (cons value obj)
          (error "flexible-sequence-insert-left: not a flexible sequence" obj)))

    (define (flexible-sequence-insert-right obj value)
      (if (eq? (%kind obj) 'list)
          (append obj (list value))
          (error "flexible-sequence-insert-right: not a flexible sequence" obj)))

    (define (flexible-sequence-delete-left obj)
      (if (and (eq? (%kind obj) 'list) (pair? obj))
          (values (cdr obj) (car obj))
          (error "flexible-sequence-delete-left: not a non-empty flexible sequence" obj)))

    (define (flexible-sequence-delete-right obj)
      (if (and (eq? (%kind obj) 'list) (pair? obj))
          (values (%sublist obj 0 (- (length obj) 1)) (list-ref obj (- (length obj) 1)))
          (error "flexible-sequence-delete-right: not a non-empty flexible sequence" obj)))

    ;;; ---------------------------------------------------------------
    ;;; Map family: alist-map, (srfi 69) hash-table
    ;;; ---------------------------------------------------------------

    (define (map? obj) (and (memv (%kind obj) '(alist-map hash-table)) #t))

    (define (map-equivalence-function obj)
      (case (%require-kind obj 'map-equivalence-function)
        ((alist-map hash-table) equal?)
        (else (error "map-equivalence-function: not a map" obj))))

    (define (map-key-equivalence-function obj)
      (case (%require-kind obj 'map-key-equivalence-function)
        ((alist-map) (alist-map-equivalence-function obj))
        ((hash-table) (hash-table-equivalence-function obj))
        (else (error "map-key-equivalence-function: not a map" obj))))

    (define (map-contains-key? obj key)
      (case (%require-kind obj 'map-contains-key?)
        ((alist-map) (alist-map-contains-key? obj key))
        ((hash-table) (hash-table-exists? obj key))
        (else (error "map-contains-key?: not a map" obj))))

    (define (map-keys->list obj)
      (case (%require-kind obj 'map-keys->list)
        ((alist-map) (alist-map-keys->list obj))
        ((hash-table) (hash-table-keys obj))
        (else (error "map-keys->list: not a map" obj))))

    (define map-get
      (case-lambda
        ((obj key) (map-get obj key (lambda () (error "map-get: key not found" key))))
        ((obj key absence-thunk)
         (case (%require-kind obj 'map-get)
           ((alist-map) (alist-map-get obj key absence-thunk))
           ((hash-table) (hash-table-ref obj key absence-thunk))
           (else (error "map-get: not a map" obj))))))

    ;; Single-valued replace-or-insert (proper Map semantics — unlike
    ;; alist-map-put!, which is a multimap prepend).
    (define (map-put! obj key value)
      (case (%require-kind obj 'map-put!)
        ((alist-map) (alist-map-delete-all! obj key) (alist-map-put! obj key value) obj)
        ((hash-table) (hash-table-set! obj key value) obj)
        (else (error "map-put!: not a map" obj))))

    (define (map-put obj key value)
      (case (%require-kind obj 'map-put)
        ((alist-map) (map-put! (alist-map-copy obj) key value))
        ((hash-table) (map-put! (hash-table-copy obj) key value))
        (else (error "map-put: not a map" obj))))

    (define map-update
      (case-lambda
        ((obj key func) (map-update obj key func (lambda () (error "map-update: key not found" key))))
        ((obj key func absence-thunk)
         (map-put obj key (func (map-get obj key absence-thunk))))))

    (define map-update!
      (case-lambda
        ((obj key func) (map-update! obj key func (lambda () (error "map-update!: key not found" key))))
        ((obj key func absence-thunk)
         (map-put! obj key (func (map-get obj key absence-thunk))))))

    (define (map-delete obj key)
      (case (%require-kind obj 'map-delete)
        ((alist-map) (alist-map-delete-all obj key))
        ((hash-table) (let ((copy (hash-table-copy obj))) (hash-table-delete! copy key) copy))
        (else (error "map-delete: not a map" obj))))

    (define (map-delete! obj key)
      (case (%require-kind obj 'map-delete!)
        ((alist-map) (alist-map-delete-all! obj key))
        ((hash-table) (hash-table-delete! obj key) obj)
        (else (error "map-delete!: not a map" obj))))

    (define (map-add-from obj source) (%map-add-from obj source map-put))

    (define (%map-add-from obj source putter)
      (case (%kind source)
        ((alist-map)
         (fold (lambda (kv acc) (putter acc (car kv) (cdr kv))) obj (alist-map->list source)))
        ((hash-table)
         (fold (lambda (kv acc) (putter acc (car kv) (cdr kv))) obj (hash-table->alist source)))
        (else (error "map-add-from: source must be a map" source))))

    (define (map-add-from! obj source) (%map-add-from obj source map-put!))

    (define (map-delete-from obj source)
      (fold (lambda (key acc) (map-delete acc key)) obj (%map-source-keys source)))

    (define (map-delete-from! obj source)
      (for-each (lambda (key) (map-delete! obj key)) (%map-source-keys source))
      obj)

    (define (%map-source-keys source)
      (case (%kind source)
        ((alist-map) (alist-map-keys->list source))
        ((hash-table) (hash-table-keys source))
        ((set) (set->list source))
        ((bag) (bag->list source))
        ((list) source)
        ((vector) (vector->list source))
        (else (error "map-delete-from: unrecognized key source" source))))))
