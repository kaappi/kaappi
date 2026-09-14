;; SRFI 126 — R6RS-based hashtables.
;;
;; A portable wrapper over the built-in (srfi 69) hash-table primitives,
;; translating the R6RS "hashtable" vocabulary (no hyphen between "hash"
;; and "table") onto SRFI 69's "hash-table" (hyphenated) engine. The two
;; naming conventions never collide textually except for `string-hash` and
;; `string-ci-hash`, which SRFI 126 requires with SRFI-69-compatible
;; semantics anyway, so those two are re-exported unchanged (see
;; lib/srfi/125.sld for the precedent of renaming only a *true* collision
;; on import — `hash-table-ref` there — rather than renaming everything).
;;
;; --- Scope: the non-weak baseline only ------------------------------------
;;
;; SRFI 126's own spec text says weak and ephemeral hashtables "cannot be
;; implemented by portable library code" (they need platform/GC-level
;; support this codebase's (srfi 69) hash tables don't have for that
;; purpose) and that support for them is optional to begin with ("Support
;; for all types of weak and ephemeral hashtables is optional"). So:
;;
;;   * every constructor's `weakness` argument accepts only `#f`; passing
;;     any of the other spec-legal symbols (weak-key, weak-value,
;;     weak-key-and-value, ephemeral-key, ephemeral-value,
;;     ephemeral-key-and-value) raises an error rather than silently
;;     downgrading to an ordinary (strong-reference) table. The spec
;;     explicitly sanctions this: "the implementation should signal the
;;     user in an implementation-defined manner when an unsupported value
;;     is used." An error was chosen over silently ignoring the value
;;     because weakness changes memory-retention behavior a caller may be
;;     relying on — unlike `capacity` (a pure performance hint with no
;;     observable semantics), silently downgrading weakness could hide a
;;     real correctness assumption in the caller's program.
;;   * `hashtable-weakness` always returns `#f`.
;;   * the `#hasheq(...)`-style external representation (reader/printer
;;     syntax) is not implemented at all — the spec says this too "cannot
;;     be implemented by portable library code," needing reader-level
;;     support this library cannot add.
;;   * the `(weakness <symbol>)` expand-time-checked syntax and the
;;     `(hash-salt)` syntax are both omitted: the former only matters for
;;     the weak/ephemeral machinery this port doesn't have, and the latter
;;     isn't required by any procedure in this port's surface.
;;
;; `capacity` arguments are accepted everywhere the spec allows them, for
;; signature compatibility, but are otherwise ignored: they are a sizing
;; hint only ("approximately capacity elements") and the underlying
;; `make-hash-table` / `alist->hash-table` primitives don't support
;; presizing.
;;
;; `hashtable-mutable?` always returns `#t`, and `hashtable-copy`'s
;; `mutable` argument has no effect: this codebase has no notion of an
;; immutable hash table, so every hashtable — and every copy — is mutable.

(define-library (srfi 126)
  (import (scheme base) (scheme case-lambda) (srfi 69) (srfi 227))
  (export
   ;; Constructors
   make-eq-hashtable
   make-eqv-hashtable
   make-hashtable
   alist->eq-hashtable
   alist->eqv-hashtable
   alist->hashtable
   ;; Access / mutation
   hashtable?
   hashtable-size
   hashtable-ref
   hashtable-set!
   hashtable-delete!
   hashtable-contains?
   hashtable-lookup
   hashtable-update!
   hashtable-intern!
   ;; Copying
   hashtable-copy
   hashtable-clear!
   hashtable-empty-copy
   ;; Key/value collections
   hashtable-keys
   hashtable-values
   hashtable-entries
   hashtable-key-list
   hashtable-value-list
   hashtable-entry-lists
   ;; Iteration
   hashtable-walk
   hashtable-update-all!
   hashtable-prune!
   hashtable-merge!
   hashtable-sum
   hashtable-map->lset
   hashtable-find
   ;; Misc
   hashtable-empty?
   hashtable-pop!
   hashtable-inc!
   hashtable-dec!
   ;; Inspection
   hashtable-equivalence-function
   hashtable-hash-function
   hashtable-weakness
   hashtable-mutable?
   ;; Hash functions
   equal-hash
   string-hash
   string-ci-hash
   symbol-hash)
  (begin
    ;; -----------------------------------------------------------------
    ;; Internal helpers (all private — none of these are exported)
    ;; -----------------------------------------------------------------

    ;; Local aliases for the two SRFI-69 inspectors we need to special-case
    ;; below. Distinct names sidestep any visual ambiguity against the
    ;; R6RS-named wrappers with near-identical spelling (hashtable-hash-
    ;; -function vs. hash-table-hash-function) defined later in this file.
    (define %builtin-equiv-fn hash-table-equivalence-function)
    (define %builtin-hash-fn hash-table-hash-function)

    ;; A private, never-exposed object used as an "absent" sentinel so
    ;; hashtable-ref & friends can tell "key missing" apart from "key
    ;; present with a stored value that happens to look like a default"
    ;; using a single table probe (hash-table-ref/default) instead of an
    ;; existence check followed by a second lookup.
    (define %absent (list 'srfi-126-absent))

    ;; Every constructor's `weakness` slot only supports #f — see the file
    ;; header. Raise a clear, specific error otherwise.
    (define (%check-weakness weakness who)
      (when weakness
        (error (string-append who
                              ": weak/ephemeral hashtables are not supported (SRFI 126 "
                              "non-weak baseline of this port); pass #f")
               weakness)))

    ;; `make-hashtable`'s `hash` argument may be a single procedure or a
    ;; pair of them (R6RS allows implementations to pick a representation
    ;; and derive/ignore the other). This engine keeps one hash function
    ;; per table, so a pair collapses to its car.
    (define (%hash-single hash) (if (pair? hash) (car hash) hash))

    ;; Shared by make-hashtable / alist->hashtable: dispatch to the eq?/
    ;; eqv? fast constructors when the spec says to, else build a custom
    ;; table from the given hash/equiv pair.
    (define (%general-ctor hash equiv)
      (cond ((and (not hash) (eq? equiv eq?)) (make-hash-table eq?))
            ((and (not hash) (eq? equiv eqv?)) (make-hash-table eqv?))
            (else (make-hash-table equiv (%hash-single hash)))))

    (define (%general-alist-ctor hash equiv alist)
      (cond ((and (not hash) (eq? equiv eq?)) (alist->hash-table alist eq?))
            ((and (not hash) (eq? equiv eqv?)) (alist->hash-table alist eqv?))
            (else (alist->hash-table alist equiv (%hash-single hash)))))

    ;; Split a (key . value) alist (as returned by hash-table->alist, one
    ;; consistent snapshot) into two parallel lists. Used where the spec
    ;; requires the key/value results to correspond index-for-index —
    ;; unlike the independent hashtable-keys / hashtable-values, which
    ;; don't promise that.
    (define (%entry-lists-from-alist alist)
      (values (map car alist) (map cdr alist)))

    ;; -----------------------------------------------------------------
    ;; Constructors
    ;; -----------------------------------------------------------------

    (define make-eq-hashtable
      (opt-lambda ((capacity #f) (weakness #f))
                  (%check-weakness weakness "make-eq-hashtable")
                  (make-hash-table eq?)))

    (define make-eqv-hashtable
      (opt-lambda ((capacity #f) (weakness #f))
                  (%check-weakness weakness "make-eqv-hashtable")
                  (make-hash-table eqv?)))

    (define make-hashtable
      (opt-lambda (hash equiv (capacity #f) (weakness #f))
                  (%check-weakness weakness "make-hashtable")
                  (%general-ctor hash equiv)))

    (define alist->eq-hashtable
      (case-lambda
        ((alist) (alist->hash-table alist eq?))
        ((capacity alist) (alist->hash-table alist eq?))
        ((capacity weakness alist) (%check-weakness weakness
                                                    "alist->eq-hashtable")
                                   (alist->hash-table alist eq?))))

    (define alist->eqv-hashtable
      (case-lambda
        ((alist) (alist->hash-table alist eqv?))
        ((capacity alist) (alist->hash-table alist eqv?))
        ((capacity weakness alist) (%check-weakness weakness
                                                    "alist->eqv-hashtable")
                                   (alist->hash-table alist eqv?))))

    (define alist->hashtable
      (case-lambda
        ((hash equiv alist) (%general-alist-ctor hash equiv alist))
        ((hash equiv capacity alist) (%general-alist-ctor hash equiv alist))
        ((hash equiv capacity weakness alist) (%check-weakness weakness
                                                               "alist->hashtable")
                                              (%general-alist-ctor hash
                                                                   equiv
                                                                   alist))))

    ;; -----------------------------------------------------------------
    ;; Access / mutation
    ;; -----------------------------------------------------------------

    (define hashtable? hash-table?)
    (define hashtable-size hash-table-size)
    (define hashtable-set! hash-table-set!)
    (define hashtable-delete! hash-table-delete!)
    (define hashtable-contains? hash-table-exists?)

    ;; hashtable-ref's `default`, unlike SRFI 69's hash-table-ref third
    ;; argument, is a plain value returned as-is — never invoked, even if
    ;; it happens to be a procedure. hash-table-ref/default already has
    ;; exactly this "return the literal default" semantics, so it's used
    ;; directly rather than SRFI 69's hash-table-ref.
    (define hashtable-ref
      (case-lambda
        ((ht key) (let ((v (hash-table-ref/default ht key %absent)))
                    (if (eq? v %absent)
                        (error "hashtable-ref: key not found and no default given"
                               key)
                        v)))
        ((ht key default) (hash-table-ref/default ht key default))))

    (define (hashtable-lookup ht key)
      (let ((v (hash-table-ref/default ht key %absent)))
        (if (eq? v %absent) (values #f #f) (values v #t))))

    ;; hashtable-update!'s `default` (like hashtable-ref's) is a plain
    ;; value that `proc` is applied to, not a thunk — a second point of
    ;; divergence from SRFI 69's hash-table-update!, whose fourth argument
    ;; is a zero-argument thunk. Reimplemented here rather than delegated.
    (define hashtable-update!
      (case-lambda
        ((ht key proc) (let ((old (hash-table-ref/default ht key %absent)))
                         (if (eq? old %absent)
                             (error "hashtable-update!: key not found and no default given"
                                    key)
                             (let ((new (proc old)))
                               (hash-table-set! ht key new)
                               new))))
        ((ht key proc default) (let ((new (proc (hash-table-ref/default ht
                                                                        key
                                                                        default))))
                                 (hash-table-set! ht key new)
                                 new))))

    (define (hashtable-intern! ht key default-proc)
      (let ((v (hash-table-ref/default ht key %absent)))
        (if (eq? v %absent)
            (let ((val (default-proc))) (hash-table-set! ht key val) val)
            v)))

    ;; -----------------------------------------------------------------
    ;; Copying
    ;; -----------------------------------------------------------------

    (define hashtable-copy
      (opt-lambda (ht (mutable #f) (weakness #f))
                  (%check-weakness weakness "hashtable-copy")
                  (hash-table-copy ht)))

    (define hashtable-clear!
      (opt-lambda (ht (capacity #f))
                  (for-each (lambda (k) (hash-table-delete! ht k))
                            (hash-table-keys ht))))

    (define hashtable-empty-copy
      (opt-lambda (ht (capacity #f))
                  (make-hash-table (%builtin-equiv-fn ht) (%builtin-hash-fn ht))))

    ;; -----------------------------------------------------------------
    ;; Key/value collections
    ;; -----------------------------------------------------------------

    (define (hashtable-keys ht) (list->vector (hash-table-keys ht)))
    (define (hashtable-values ht) (list->vector (hash-table-values ht)))

    (define (hashtable-entries ht)
      (let-values (((ks vs) (%entry-lists-from-alist (hash-table->alist ht))))
        (values (list->vector ks) (list->vector vs))))

    (define (hashtable-key-list ht) (hash-table-keys ht))
    (define (hashtable-value-list ht) (hash-table-values ht))

    (define (hashtable-entry-lists ht)
      (%entry-lists-from-alist (hash-table->alist ht)))

    ;; -----------------------------------------------------------------
    ;; Iteration
    ;; -----------------------------------------------------------------

    (define hashtable-walk hash-table-walk)

    (define (hashtable-update-all! ht proc)
      (for-each (lambda (k)
                  (hash-table-set! ht
                                   k
                                   (proc k (hash-table-ref/default ht k #f))))
                (hash-table-keys ht)))

    (define (hashtable-prune! ht proc)
      (for-each (lambda (k)
                  (if (proc k (hash-table-ref/default ht k #f))
                      (hash-table-delete! ht k)))
                (hash-table-keys ht)))

    ;; SRFI 126's hashtable-merge! copies source into dest, source winning
    ;; on collision, and returns dest — exactly the built-in SRFI 69
    ;; hash-table-merge!'s behavior (contrast with SRFI 125's own
    ;; hash-table-merge!, which instead aliases union! so dest wins; see
    ;; lib/srfi/125.sld).
    (define hashtable-merge! hash-table-merge!)

    (define (hashtable-sum ht init proc) (hash-table-fold ht proc init))

    (define (hashtable-map->lset ht proc)
      (hash-table-fold ht (lambda (k v acc) (cons (proc k v) acc)) '()))

    (define (hashtable-find ht proc)
      (let loop ((keys (hash-table-keys ht)))
        (if (null? keys)
            (values #f #f #f)
            (let* ((k (car keys)) (v (hash-table-ref/default ht k #f)))
              (if (proc k v) (values k v #t) (loop (cdr keys)))))))

    ;; -----------------------------------------------------------------
    ;; Misc
    ;; -----------------------------------------------------------------

    (define (hashtable-empty? ht) (zero? (hash-table-size ht)))

    (define (hashtable-pop! ht)
      (let-values (((key value found?) (hashtable-find ht (lambda (k v) #t))))
        (if (not found?)
            (error "hashtable-pop!: hashtable is empty")
            (begin (hash-table-delete! ht key) (values key value)))))

    (define hashtable-inc!
      (opt-lambda (ht key (number 1))
                  (hashtable-update! ht key (lambda (v) (+ v number)) 0)))

    (define hashtable-dec!
      (opt-lambda (ht key (number 1))
                  (hashtable-update! ht key (lambda (v) (- v number)) 0)))

    ;; -----------------------------------------------------------------
    ;; Inspection
    ;; -----------------------------------------------------------------

    (define hashtable-equivalence-function %builtin-equiv-fn)

    ;; Per spec, eq?/eqv?-hashtables report #f here (no separate hash
    ;; function to expose, since the fast eq?/eqv? paths don't consult
    ;; one); everything else reports its actual hash function, same as
    ;; the underlying SRFI 69 table stores.
    (define (hashtable-hash-function ht)
      (let ((equiv (%builtin-equiv-fn ht)))
        (if (or (eq? equiv eq?) (eq? equiv eqv?)) #f (%builtin-hash-fn ht))))

    (define (hashtable-weakness ht)
      (if (hash-table? ht) #f (error "hashtable-weakness: not a hashtable" ht)))

    (define (hashtable-mutable? ht)
      (if (hash-table? ht) #t (error "hashtable-mutable?: not a hashtable" ht)))

    ;; -----------------------------------------------------------------
    ;; Hash functions
    ;; -----------------------------------------------------------------
    ;;
    ;; string-hash and string-ci-hash are re-exported straight from
    ;; (srfi 69) (imported above, unrenamed): both accept an optional
    ;; second `bound` argument beyond what SRFI 126 requires, which is a
    ;; harmless superset, and both already match the required semantics
    ;; ("compatible with string=?" / "string-ci=?" respectively).

    ;; equal-hash: the built-in generic `hash` is already structural
    ;; (equal?-compatible) and depth-bounded, so it terminates even on
    ;; cyclic input, matching the spec's explicit requirement.
    (define (equal-hash obj) (hash obj))

    ;; symbol-hash: `hash` already special-cases symbols with a
    ;; content-based (name) hash; reuse it directly.
    (define (symbol-hash sym) (hash sym))))
