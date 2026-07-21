;;; SRFI 209 — Enums and Enum Sets
;;;
;;; A fairly direct, complete port. Two scope decisions worth noting:
;;;
;;;  - Enum sets are represented internally as a fixed-size vector of
;;;    booleans indexed by ordinal, alongside a reference to the owning
;;;    enum type. Every set/logical operation is therefore O(enum-type-size)
;;;    rather than proportional to the set's own membership count — the
;;;    right trade for the small, fixed-size enumerations ("days of the
;;;    week", "HTTP methods", ...) this SRFI targets; it would be the wrong
;;;    choice for a type with thousands of enums.
;;;  - `define-enum`/`define-enumeration` support plain name lists, matching
;;;    every worked example in the SRFI document (`(red orange yellow ...)`,
;;;    never a mix of bare names and `(name value)` pairs). `type-name`'s
;;;    generated macro dispatches on the names as literal `syntax-rules`
;;;    keywords, which only works for bare identifiers in the first place —
;;;    for enums that need explicit values, call `make-enum-type` directly
;;;    (it accepts both symbols and `(symbol value)` pairs) and skip the
;;;    `define-enum` sugar.

(define-library (srfi 209)
  (import (scheme base) (srfi 128))
  (export
    ;; enums
    enum-type? enum? enum-type-contains?
    enum=? enum<? enum>? enum<=? enum>=?
    make-enum-type
    enum-type enum-name enum-ordinal enum-value
    enum-name->enum enum-ordinal->enum
    enum-name->ordinal enum-name->value enum-ordinal->name enum-ordinal->value
    enum-type-size enum-min enum-max enum-type-enums enum-type-names enum-type-values
    enum-next enum-prev
    make-enum-comparator
    ;; enum sets
    enum-empty-set enum-type->enum-set enum-set list->enum-set
    enum-set-projection enum-set-copy
    make-enumeration enum-set-universe enum-set-constructor
    enum-set? enum-set-contains? enum-set-member? enum-set-empty? enum-set-disjoint?
    enum-set=? enum-set<? enum-set>? enum-set<=? enum-set>=?
    enum-set-subset? enum-set-any? enum-set-every?
    enum-set-type enum-set-indexer
    enum-set-adjoin enum-set-adjoin! enum-set-delete enum-set-delete!
    enum-set-delete-all enum-set-delete-all!
    enum-set-size enum-set->enum-list enum-set->list
    enum-set-count enum-set-filter enum-set-remove
    enum-set-map->list enum-set-for-each enum-set-fold
    enum-set-complement enum-set-complement!
    enum-set-union enum-set-union! enum-set-intersection enum-set-intersection!
    enum-set-difference enum-set-difference! enum-set-xor enum-set-xor!
    ;; syntax
    define-enum define-enumeration)

  (begin

    ;;; --- enum and enum-type ---
    ;;;
    ;;; An enum naturally wants to point back at its enum-type (for
    ;;; `enum-type`) while the enum-type holds a vector of all its enums —
    ;;; a direct pair of record fields would make that a reference cycle,
    ;;; and Kaappi's generic printer recurses into record fields without
    ;;; cycle detection (write/display on such a structure loops forever,
    ;;; which SRFI-64 hits immediately since it prints every expected/actual
    ;;; value it's given, pass or fail). So the back-edge is stored as a
    ;;; small integer id, resolved through a private registry, rather than
    ;;; as a direct field — the same "keep cycles behind an opaque
    ;;; indirection" fix used for cyclic hash-mapping values elsewhere in
    ;;; this codebase. `enum-type` still behaves as a plain one-argument
    ;;; accessor; only its implementation is indirect.

    (define %enum-type-registry '())
    (define %enum-type-next-id 0)

    (define-record-type <enum>
      (%make-enum type-id name ordinal value)
      enum?
      (type-id %enum-type-id-of)
      (name enum-name)
      (ordinal enum-ordinal)
      (value enum-value))

    (define-record-type <enum-type>
      (%make-enum-type-raw id enums-vec)
      enum-type?
      (id %enum-type-id)
      (enums-vec %enum-type-enums-vec))

    (define (enum-type e) (cdr (assv (%enum-type-id-of e) %enum-type-registry)))

    (define (make-enum-type entries)
      (let* ((n (length entries))
             (id %enum-type-next-id)
             (et (%make-enum-type-raw id (make-vector n #f))))
        (set! %enum-type-next-id (+ id 1))
        (set! %enum-type-registry (cons (cons id et) %enum-type-registry))
        (let loop ((entries entries) (i 0))
          (unless (null? entries)
            (let* ((entry (car entries))
                   (name (if (pair? entry) (car entry) entry))
                   (value (if (pair? entry) (cadr entry) i)))
              (vector-set! (%enum-type-enums-vec et) i (%make-enum id name i value))
              (loop (cdr entries) (+ i 1)))))
        et))

    (define (enum-type-contains? et e) (and (enum? e) (eq? (enum-type e) et)))

    (define (%check-same-enum-type who enums)
      (let ((et (enum-type (car enums))))
        (for-each (lambda (e)
                    (unless (eq? (enum-type e) et)
                      (error (string-append who ": enums belong to different types") enums)))
                  (cdr enums))))

    (define (%enum-chain-compare op enums)
      (%check-same-enum-type "enum comparison" enums)
      (let loop ((enums enums))
        (or (null? (cdr enums))
            (and (op (enum-ordinal (car enums)) (enum-ordinal (cadr enums))) (loop (cdr enums))))))

    (define (enum=? e0 e1 . more) (%enum-chain-compare = (cons e0 (cons e1 more))))
    (define (enum<? e0 e1 . more) (%enum-chain-compare < (cons e0 (cons e1 more))))
    (define (enum>? e0 e1 . more) (%enum-chain-compare > (cons e0 (cons e1 more))))
    (define (enum<=? e0 e1 . more) (%enum-chain-compare <= (cons e0 (cons e1 more))))
    (define (enum>=? e0 e1 . more) (%enum-chain-compare >= (cons e0 (cons e1 more))))

    (define (enum-name->enum et name)
      (let* ((vec (%enum-type-enums-vec et)) (n (vector-length vec)))
        (let loop ((i 0))
          (cond ((= i n) #f)
                ((eq? (enum-name (vector-ref vec i)) name) (vector-ref vec i))
                (else (loop (+ i 1)))))))

    (define (enum-ordinal->enum et ord)
      (let ((vec (%enum-type-enums-vec et)))
        (if (and (integer? ord) (>= ord 0) (< ord (vector-length vec))) (vector-ref vec ord) #f)))

    (define (enum-name->ordinal et name)
      (let ((e (enum-name->enum et name)))
        (if e (enum-ordinal e) (error "enum-name->ordinal: no such enum name" name))))

    (define (enum-name->value et name)
      (let ((e (enum-name->enum et name)))
        (if e (enum-value e) (error "enum-name->value: no such enum name" name))))

    (define (enum-ordinal->name et ord)
      (let ((e (enum-ordinal->enum et ord)))
        (if e (enum-name e) (error "enum-ordinal->name: no such ordinal" ord))))

    (define (enum-ordinal->value et ord)
      (let ((e (enum-ordinal->enum et ord)))
        (if e (enum-value e) (error "enum-ordinal->value: no such ordinal" ord))))

    (define (enum-type-size et) (vector-length (%enum-type-enums-vec et)))
    (define (enum-min et) (vector-ref (%enum-type-enums-vec et) 0))
    (define (enum-max et)
      (let ((vec (%enum-type-enums-vec et))) (vector-ref vec (- (vector-length vec) 1))))
    (define (enum-type-enums et) (vector->list (%enum-type-enums-vec et)))
    (define (enum-type-names et) (map enum-name (enum-type-enums et)))
    (define (enum-type-values et) (map enum-value (enum-type-enums et)))

    (define (enum-next e) (enum-ordinal->enum (enum-type e) (+ (enum-ordinal e) 1)))
    (define (enum-prev e) (enum-ordinal->enum (enum-type e) (- (enum-ordinal e) 1)))

    (define (make-enum-comparator et)
      (make-comparator
        (lambda (obj) (enum-type-contains? et obj))
        (lambda (a b) (= (enum-ordinal a) (enum-ordinal b)))
        (lambda (a b) (< (enum-ordinal a) (enum-ordinal b)))
        (lambda (e) (enum-ordinal e))))

    ;;; --- enum sets: a boolean membership vector indexed by ordinal ---

    (define-record-type <enum-set>
      (%make-enum-set type membership)
      enum-set?
      (type enum-set-type)
      (membership %enum-set-membership))

    (define (enum-empty-set et) (%make-enum-set et (make-vector (enum-type-size et) #f)))
    (define (enum-type->enum-set et) (%make-enum-set et (make-vector (enum-type-size et) #t)))

    (define (enum-set-copy s) (%make-enum-set (enum-set-type s) (vector-copy (%enum-set-membership s))))

    (define (enum-set et . enums)
      (let ((s (enum-empty-set et)))
        (for-each (lambda (e)
                    (unless (enum-type-contains? et e) (error "enum-set: enum not of this type" e))
                    (vector-set! (%enum-set-membership s) (enum-ordinal e) #t))
                  enums)
        s))

    (define (list->enum-set et lst) (apply enum-set et lst))

    (define (%as-enum-type x) (if (enum-type? x) x (enum-set-type x)))

    (define (enum-set-projection target-type-or-set source-set)
      (let* ((target-type (%as-enum-type target-type-or-set))
             (result (enum-empty-set target-type)))
        (for-each
          (lambda (e)
            (let ((target-enum (enum-name->enum target-type (enum-name e))))
              (unless target-enum
                (error "enum-set-projection: no enum with this name in the target type" (enum-name e)))
              (vector-set! (%enum-set-membership result) (enum-ordinal target-enum) #t)))
          (enum-set->enum-list source-set))
        result))

    ;; --- R6RS-flavored constructors ---

    (define (make-enumeration symbols)
      (enum-type->enum-set (make-enum-type (map (lambda (s) (list s s)) symbols))))

    (define (enum-set-universe s) (enum-type->enum-set (enum-set-type s)))

    (define (enum-set-constructor s)
      (let ((et (enum-set-type s)))
        (lambda (names)
          (list->enum-set et
            (map (lambda (name)
                   (or (enum-name->enum et name)
                       (error "enum-set-constructor: no such enum name" name)))
                 names)))))

    ;;; --- predicates ---

    (define (%check-same-set-type who s1 s2)
      (unless (eq? (enum-set-type s1) (enum-set-type s2))
        (error (string-append who ": enum sets belong to different types") s1 s2)))

    (define (enum-set-contains? s e)
      (unless (eq? (enum-set-type s) (enum-type e))
        (error "enum-set-contains?: enum does not belong to this set's type" s e))
      (vector-ref (%enum-set-membership s) (enum-ordinal e)))

    (define (enum-set-member? name s)
      (let ((e (enum-name->enum (enum-set-type s) name)))
        (and e (vector-ref (%enum-set-membership s) (enum-ordinal e)))))

    (define (enum-set-empty? s)
      (let ((m (%enum-set-membership s)))
        (let loop ((i 0))
          (cond ((= i (vector-length m)) #t)
                ((vector-ref m i) #f)
                (else (loop (+ i 1)))))))

    (define (enum-set-disjoint? s1 s2)
      (%check-same-set-type "enum-set-disjoint?" s1 s2)
      (let ((m1 (%enum-set-membership s1)) (m2 (%enum-set-membership s2)))
        (let loop ((i 0))
          (cond ((= i (vector-length m1)) #t)
                ((and (vector-ref m1 i) (vector-ref m2 i)) #f)
                (else (loop (+ i 1)))))))

    (define (%enum-set-subset-same-type? s1 s2)
      (let ((m1 (%enum-set-membership s1)) (m2 (%enum-set-membership s2)))
        (let loop ((i 0))
          (cond ((= i (vector-length m1)) #t)
                ((and (vector-ref m1 i) (not (vector-ref m2 i))) #f)
                (else (loop (+ i 1)))))))

    (define (enum-set=? s1 s2)
      (%check-same-set-type "enum-set=?" s1 s2)
      (and (%enum-set-subset-same-type? s1 s2) (%enum-set-subset-same-type? s2 s1)))

    (define (enum-set<? s1 s2)
      (%check-same-set-type "enum-set<?" s1 s2)
      (and (%enum-set-subset-same-type? s1 s2) (not (%enum-set-subset-same-type? s2 s1))))

    (define (enum-set>? s1 s2) (enum-set<? s2 s1))

    (define (enum-set<=? s1 s2)
      (%check-same-set-type "enum-set<=?" s1 s2)
      (%enum-set-subset-same-type? s1 s2))

    (define (enum-set>=? s1 s2) (enum-set<=? s2 s1))

    ;; enum-set-subset? compares by NAME, so the two sets may be different types
    (define (enum-set-subset? s1 s2)
      (let loop ((names (enum-set->list s1)))
        (or (null? names) (and (enum-set-member? (car names) s2) (loop (cdr names))))))

    (define (enum-set-any? pred s)
      (let loop ((lst (enum-set->enum-list s)))
        (and (pair? lst) (or (pred (car lst)) (loop (cdr lst))))))

    (define (enum-set-every? pred s)
      (let loop ((lst (enum-set->enum-list s)))
        (or (null? lst) (and (pred (car lst)) (loop (cdr lst))))))

    (define (enum-set-indexer s)
      (let ((et (enum-set-type s)))
        (lambda (name) (let ((e (enum-name->enum et name))) (and e (enum-ordinal e))))))

    ;;; --- mutators (functional; the `!` names are the same procedures) ---

    (define (enum-set-adjoin s . enums)
      (let ((result (enum-set-copy s)))
        (for-each (lambda (e)
                    (unless (eq? (enum-type e) (enum-set-type s))
                      (error "enum-set-adjoin: enum does not belong to this set's type" e))
                    (vector-set! (%enum-set-membership result) (enum-ordinal e) #t))
                  enums)
        result))
    (define enum-set-adjoin! enum-set-adjoin)

    (define (enum-set-delete s . enums)
      (let ((result (enum-set-copy s)))
        (for-each (lambda (e) (vector-set! (%enum-set-membership result) (enum-ordinal e) #f)) enums)
        result))
    (define enum-set-delete! enum-set-delete)

    (define (enum-set-delete-all s lst) (apply enum-set-delete s lst))
    (define enum-set-delete-all! enum-set-delete-all)

    ;;; --- whole-set operations ---

    (define (enum-set-size s)
      (let ((m (%enum-set-membership s)))
        (let loop ((i 0) (n 0))
          (if (= i (vector-length m)) n (loop (+ i 1) (if (vector-ref m i) (+ n 1) n))))))

    (define (enum-set->enum-list s)
      (let ((et (enum-set-type s)) (m (%enum-set-membership s)))
        (let ((vec (%enum-type-enums-vec et)))
          (let loop ((i (- (vector-length m) 1)) (acc '()))
            (cond ((< i 0) acc)
                  ((vector-ref m i) (loop (- i 1) (cons (vector-ref vec i) acc)))
                  (else (loop (- i 1) acc)))))))

    (define (enum-set->list s) (map enum-name (enum-set->enum-list s)))

    (define (enum-set-count pred s)
      (let loop ((lst (enum-set->enum-list s)) (n 0))
        (cond ((null? lst) n)
              ((pred (car lst)) (loop (cdr lst) (+ n 1)))
              (else (loop (cdr lst) n)))))

    (define (enum-set-filter pred s)
      (let ((result (enum-empty-set (enum-set-type s))))
        (for-each (lambda (e) (when (pred e) (vector-set! (%enum-set-membership result) (enum-ordinal e) #t)))
                  (enum-set->enum-list s))
        result))

    (define (enum-set-remove pred s) (enum-set-filter (lambda (e) (not (pred e))) s))

    (define (enum-set-map->list proc s) (map proc (enum-set->enum-list s)))
    (define (enum-set-for-each proc s) (for-each proc (enum-set->enum-list s)))

    (define (enum-set-fold proc nil s)
      (let loop ((lst (enum-set->enum-list s)) (acc nil))
        (if (null? lst) acc (loop (cdr lst) (proc (car lst) acc)))))

    ;;; --- logical operations ---

    (define (%enum-set-zip-with op s1 s2 who)
      (%check-same-set-type who s1 s2)
      (let* ((et (enum-set-type s1)) (m1 (%enum-set-membership s1)) (m2 (%enum-set-membership s2))
             (result (enum-empty-set et)) (rm (%enum-set-membership result)))
        (let loop ((i 0))
          (when (< i (vector-length m1))
            (vector-set! rm i (op (vector-ref m1 i) (vector-ref m2 i)))
            (loop (+ i 1))))
        result))

    (define (enum-set-complement s)
      (let* ((et (enum-set-type s)) (m (%enum-set-membership s))
             (result (enum-empty-set et)) (rm (%enum-set-membership result)))
        (let loop ((i 0))
          (when (< i (vector-length m))
            (vector-set! rm i (not (vector-ref m i)))
            (loop (+ i 1))))
        result))
    (define enum-set-complement! enum-set-complement)

    (define (enum-set-union s1 s2) (%enum-set-zip-with (lambda (a b) (or a b)) s1 s2 "enum-set-union"))
    (define enum-set-union! enum-set-union)

    (define (enum-set-intersection s1 s2)
      (%enum-set-zip-with (lambda (a b) (and a b)) s1 s2 "enum-set-intersection"))
    (define enum-set-intersection! enum-set-intersection)

    (define (enum-set-difference s1 s2)
      (%enum-set-zip-with (lambda (a b) (and a (not b))) s1 s2 "enum-set-difference"))
    (define enum-set-difference! enum-set-difference)

    (define (enum-set-xor s1 s2)
      (%enum-set-zip-with (lambda (a b) (if a (not b) b)) s1 s2 "enum-set-xor"))
    (define enum-set-xor! enum-set-xor)

    ;;; --- define-enum / define-enumeration ---
    ;;;
    ;;; `type-name` and `ctor-name` both need to accept bare (unquoted) enum
    ;;; names at their use sites, so both must be syntax-rules macros, not
    ;;; procedures. `type-name`'s clauses use the enum names themselves as
    ;;; syntax-rules literals, one clause per name; `ctor-name` recurses
    ;;; over its actual (variadic, duplicates-allowed) argument list, which
    ;;; needs its own independent ellipsis — hence the `(... ...)` escape so
    ;;; the outer define-enum expansion doesn't try to consume it itself.
    ;;;
    ;;; `ctor-name` always resolves each name via `(type-name nm)` rather
    ;;; than quoting `nm` itself: quoting a pattern variable directly inside
    ;;; a macro that is both self-recursive and generated by an enclosing
    ;;; macro does not substitute correctly in this expander (a recursive
    ;;; `(quote nm) ...` clause re-quotes the literal pattern-variable name
    ;;; "nm" instead of the captured identifier on the recursive call).
    ;;; Going through `type-name`'s flat, non-recursive dispatch — which
    ;;; does quote correctly — sidesteps it.

    (define-syntax define-enum
      (syntax-rules ()
        ((_ type-name (name ...) ctor-name)
         (begin
           (define %enum-define-holder (make-enum-type '(name ...)))
           (define-syntax type-name
             (syntax-rules (name ...)
               ((_ name) (enum-name->enum %enum-define-holder 'name))
               ...))
           (define-syntax ctor-name
             (syntax-rules ()
               ((_) (enum-empty-set %enum-define-holder))
               ((_ nm rest (... ...))
                (enum-set-adjoin (ctor-name rest (... ...)) (type-name nm)))))))))

    (define-syntax define-enumeration
      (syntax-rules ()
        ((_ type-name (name ...) ctor-name)
         (begin
           (define %enum-define-holder (make-enum-type (list (list 'name 'name) ...)))
           (define-syntax type-name
             (syntax-rules (name ...)
               ((_ name) 'name)
               ...))
           (define-syntax ctor-name
             (syntax-rules ()
               ((_) (enum-empty-set %enum-define-holder))
               ((_ nm rest (... ...))
                (enum-set-adjoin (ctor-name rest (... ...))
                                 (enum-name->enum %enum-define-holder (type-name nm))))))))))

    ))
