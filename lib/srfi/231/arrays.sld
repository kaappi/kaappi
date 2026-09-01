;;; SRFI 231 -- Core array object (phase 2 of #1694's SRFI 231 slice).
;;;
;;; Builds on phase 1a (lib/srfi/231/intervals.sld) and phase 1b
;;; (lib/srfi/231/storage-classes.sld). See intervals.sld's header for the
;;; overall multi-slice roadmap; (srfi 231) itself is still not importable
;;; as a bare library until every phase lands.
;;;
;;; An array is a domain (an interval) plus a getter (a procedure called
;;; with SEPARATE positional index arguments, confirmed throughout the
;;; primary spec text and its reference implementation -- never a packed
;;; vector/list). A setter, if present, makes it mutable; array-set!'s
;;; value argument is SECOND (right after the array), matching SRFI 63's
;;; convention, not SRFI 25/164's value-last -- confirmed directly from
;;; the spec's own formal signature, "array-set! array object . multi-index".
;;; array? is disjoint from vector/string here (matching 25/164, NOT
;;; 63's "vectors/strings are rank-1 arrays" rule) -- confirmed via direct
;;; fetch specifically because getting this backwards was the single
;;; biggest miss when implementing SRFI 63.
;;;
;;; specialized-array? => array? (spec: "A specialized-array is an
;;; array."); mutable-array? => array? (entailed by make-array's own
;;; contract). specialized-array? and mutable-array? are orthogonal --
;;; array-freeze! can make a specialized array immutable in place, and a
;;; plain closure-backed array can be mutable without being specialized
;;; (e.g. a hash-table-backed sparse array, per the spec's own example).
;;; One <array> record covers all four combinations: the specialized-only
;;; fields (body/indexer/storage-class/safe?) are simply #f on a plain
;;; array, and (not (array-setter-raw a)) means immutable.
(define-library (srfi 231 arrays)
  (import (scheme base)
          (srfi 231 intervals) (srfi 231 storage-classes))
  (export array? mutable-array? specialized-array?
          make-array make-specialized-array make-specialized-array-from-data
          array-domain array-getter array-setter array-dimension
          array-ref array-set! array-freeze! array-empty?
          array-body array-indexer array-storage-class array-safe? array-packed?
          specialized-array-default-safe? specialized-array-default-mutable?
          ;; Not part of SRFI 231's own public API -- exported only for
          ;; sibling library files in this package (lib/srfi/231/views.sld
          ;; and later phases) to build genuinely specialized arrays with
          ;; custom indexers, the same way (srfi 160 base)'s %uvec-* helpers
          ;; exist only for that package's own per-tag files to consume.
          %make-array %make-array/unsafe %safe-getter %safe-setter
          array-unsafe-getter array-unsafe-setter %copy-value-checker
          %make-lex-indexer %check-boolean!)
  (begin

    ;; getter/setter are ALWAYS the checked, user-visible pair; unsafe-getter
    ;; and unsafe-setter are the internal, unchecked pair that bulk
    ;; operations use because they only ever present in-domain multi-indices
    ;; they generated themselves (#2448).
    ;;
    ;; safe? no longer gates whether array-ref/array-set! check -- they
    ;; always do. It is retained because the spec exposes array-safe?, and
    ;; it still records what the caller asked for.
    (define-record-type <array>
      (%make-array/unsafe domain getter setter body indexer storage-class safe?
                          unsafe-getter unsafe-setter)
      array?
      (domain array-domain)
      (getter array-getter)
      (setter %array-setter-raw %array-set-setter!)
      (body %array-body-raw)
      (indexer %array-indexer-raw)
      (storage-class %array-storage-class-raw)
      (safe? %array-safe?-raw)
      (unsafe-getter %array-unsafe-getter-raw)
      (unsafe-setter %array-unsafe-setter-raw %array-set-unsafe-setter!))

    ;; An array with no separately-supplied raw pair -- a closure-backed
    ;; generalized array, where no unchecked accessor exists to fall back
    ;; to. Its "unsafe" accessors are the checked ones, so bulk operations
    ;; stay correct; they simply do not get the speedup.
    (define (%make-array domain getter setter body indexer storage-class safe?)
      (%make-array/unsafe domain getter setter body indexer storage-class safe?
                          getter setter))

    ;; Bulk operations call these instead of array-getter/array-setter.
    ;; ONLY valid when the caller generates the multi-index from the array's
    ;; own domain (interval-for-each and friends). Never hand one to user code.
    (define (array-unsafe-getter a) (%array-unsafe-getter-raw a))
    (define (array-unsafe-setter a) (%array-unsafe-setter-raw a))

    (define (mutable-array? a) (and (array? a) (if (%array-setter-raw a) #t #f)))
    (define (specialized-array? a) (and (array? a) (if (%array-body-raw a) #t #f)))

    (define (array-setter a)
      (unless (mutable-array? a) (error "array-setter: not a mutable array" a))
      (%array-setter-raw a))

    (define (array-body a)
      (unless (specialized-array? a) (error "array-body: not a specialized array" a))
      (%array-body-raw a))

    (define (array-indexer a)
      (unless (specialized-array? a) (error "array-indexer: not a specialized array" a))
      (%array-indexer-raw a))

    (define (array-storage-class a)
      (unless (specialized-array? a) (error "array-storage-class: not a specialized array" a))
      (%array-storage-class-raw a))

    (define (array-safe? a)
      (unless (specialized-array? a) (error "array-safe?: not a specialized array" a))
      (%array-safe?-raw a))

    ;; Values are still checked on the way INTO a destination body, even
    ;; though the index check is skipped -- storing an out-of-range value
    ;; is what actually corrupts (u1 silently drops bits) or raises from
    ;; deep inside the storage layer, and neither is acceptable just
    ;; because the caller asked for an unsafe array (#2448).
    ;;
    ;; Returns the checker to apply per element, or #f when the check is
    ;; provably vacuous:
    ;;   - a generic destination manipulates every value; or
    ;;   - source and destination share a storage class, so every value
    ;;     read out of the source body already satisfies the destination's
    ;;     checker by construction.
    ;; (The reference goes further with a widening table -- u8 into u32 and
    ;; friends. Not needed for the paths here; the two cases above already
    ;; cover same-class copies and generic destinations.)
    (define (%copy-value-checker source dest-storage-class)
      (if (or (eq? dest-storage-class generic-storage-class)
              (and (specialized-array? source)
                   (eq? (array-storage-class source) dest-storage-class)))
          #f
          (storage-class-checker dest-storage-class)))

    (define (array-dimension a) (interval-dimension (array-domain a)))
    (define (array-empty? a) (interval-empty? (array-domain a)))

    (define (array-ref a . multi-index) (apply (array-getter a) multi-index))
    ;; Value is the SECOND argument (right after array), matching SRFI
    ;; 63's convention (opposite of SRFI 25/164's value-last).
    (define (array-set! a object . multi-index) (apply (array-setter a) object multi-index))

    (define (array-freeze! a)
      (unless (array? a) (error "array-freeze!: not an array" a))
      (%array-set-setter! a #f)
      ;; must clear BOTH -- leaving the unsafe setter live would keep a
      ;; frozen array writable through the bulk-operation path (#2448)
      (%array-set-unsafe-setter! a #f)
      a)

    (define (make-array interval getter . maybe-setter)
      (unless (interval? interval) (error "make-array: not an interval" interval))
      (unless (procedure? getter) (error "make-array: getter must be a procedure" getter))
      (let ((setter (if (null? maybe-setter) #f (car maybe-setter))))
        (unless (or (not setter) (procedure? setter))
          (error "make-array: setter must be a procedure or #f" setter))
        ;; The reference wraps EVERY generalized array's getter/setter in
        ;; index checks (%%make-safer-array, generic-arrays.scm): out-of-
        ;; domain, wrong-arity, and empty-domain calls all error there, and
        ;; the official suite tests it -- plain arrays are not exempt
        ;; (#2362). Valid accesses are unaffected. Plain arrays have no
        ;; storage-class checker, so the setter's value check is vacuous.
        (%make-array interval (%safe-getter interval getter)
                     (and setter (%safe-setter interval (lambda (v) #t) setter))
                     #f #f #f #f)))

    ;; safe?/mutable? are booleans everywhere they appear (the two default
    ;; parameters and both specialized constructors' options) -- the
    ;; reference implementation rejects non-booleans at each site rather
    ;; than letting a truthy wrong-typed value silently flip a mode.
    (define (%check-boolean! x who)
      (unless (boolean? x) (error (string-append who ": argument must be a boolean") x)))

    (define (%boolean-parameter default name)
      (make-parameter default (lambda (x) (%check-boolean! x name) x)))

    (define specialized-array-default-safe?
      (%boolean-parameter #f "specialized-array-default-safe?"))
    (define specialized-array-default-mutable?
      (%boolean-parameter #t "specialized-array-default-mutable?"))

    ;; The lexicographical mapping of interval onto [0, interval-volume) --
    ;; per spec, a specialized array's own indexer. Subtracts each axis's
    ;; lower bound first to get a local 0-based index, then applies the
    ;; standard row-major stride computation using the interval's own
    ;; widths -- a direct generalization of SRFI 63's %row-major-offset to
    ;; arbitrary (not just zero-based) lower bounds. The walk consumes
    ;; exactly d arguments; anything left over is a too-long multi-index,
    ;; which must error even on the unsafe path -- the reference's
    ;; fixed-arity getters reject wrong arity regardless of safe? (#2358).
    (define (%make-lex-indexer interval)
      (let ((lo (interval-lower-bounds->vector interval))
            (widths (interval-widths interval))
            (d (interval-dimension interval)))
        (lambda multi-index
          (let loop ((i 0) (xs multi-index) (acc 0))
            (if (= i d)
                (if (null? xs)
                    acc
                    (error "array indexer: too many multi-index arguments for the array's dimension" xs))
                (loop (+ i 1) (cdr xs)
                      (+ (* acc (vector-ref widths i)) (- (car xs) (vector-ref lo i)))))))))

    (define (%safe-getter interval raw-getter)
      (lambda multi-index
        (unless (apply interval-contains-multi-index? interval multi-index)
          (error "array getter: multi-index not in domain" multi-index))
        (apply raw-getter multi-index)))

    (define (%safe-setter interval checker raw-setter)
      (lambda (val . multi-index)
        (unless (apply interval-contains-multi-index? interval multi-index)
          (error "array setter: multi-index not in domain" multi-index))
        (unless (checker val)
          (error "array setter: value rejected by storage-class checker" val))
        (apply raw-setter val multi-index)))

    (define (%opt lst i default) (if (> (length lst) i) (list-ref lst i) default))

    (define (make-specialized-array interval . opts)
      (unless (interval? interval) (error "make-specialized-array: not an interval" interval))
      (%check-boolean! (%opt opts 2 (specialized-array-default-safe?))
                       "make-specialized-array: safe?")
      (let* ((storage-class (%opt opts 0 generic-storage-class))
             (initial-value (%opt opts 1 (storage-class-default storage-class)))
             (safe? (%opt opts 2 (specialized-array-default-safe?))))
        ;; Upfront validation matching the reference (:2587-:2601): a
        ;; non-storage-class second argument and an initial value the
        ;; class cannot manipulate both error at construction, named by
        ;; this procedure, instead of surfacing from the maker later (or,
        ;; for float classes, silently coercing) (#2359).
        (unless (storage-class? storage-class)
          (error "make-specialized-array: not a storage class" storage-class))
        (unless ((storage-class-checker storage-class) initial-value)
          (error "make-specialized-array: initial-value cannot be manipulated by storage-class"
                 initial-value storage-class))
        (let* ((body ((storage-class-maker storage-class) (interval-volume interval) initial-value))
               (indexer (%make-lex-indexer interval))
               (raw-getter (lambda multi-index
                             ((storage-class-getter storage-class) body (apply indexer multi-index))))
               (raw-setter (lambda (val . multi-index)
                             ((storage-class-setter storage-class) body (apply indexer multi-index) val)))
               ;; ALWAYS checked, whatever safe? says -- the spec makes
               ;; safe? add checks, it never licenses an unchecked
               ;; user-visible accessor (#2448).
               (getter (%safe-getter interval raw-getter))
               (setter (%safe-setter interval (storage-class-checker storage-class) raw-setter)))
          (%make-array/unsafe interval getter setter body indexer storage-class safe?
                              raw-getter raw-setter))))

    ;; Wraps EXTERNALLY supplied data (e.g. a plain vector or one of this
    ;; codebase's own (srfi 160 <tag>) numeric vectors) as the body of a
    ;; new 1-D array WITHOUT copying -- data must already be exactly
    ;; body-shaped for storage-class (per storage-class-data?).
    (define (make-specialized-array-from-data data . opts)
      (%check-boolean! (%opt opts 1 (specialized-array-default-mutable?))
                       "make-specialized-array-from-data: mutable?")
      (%check-boolean! (%opt opts 2 (specialized-array-default-safe?))
                       "make-specialized-array-from-data: safe?")
      (let* ((storage-class (%opt opts 0 generic-storage-class))
             (mutable? (%opt opts 1 (specialized-array-default-mutable?)))
             (safe? (%opt opts 2 (specialized-array-default-safe?))))
        (unless (storage-class? storage-class)
          (error "make-specialized-array-from-data: not a storage class" storage-class))
        (unless ((storage-class-data? storage-class) data)
          (error "make-specialized-array-from-data: data is not compatible with storage-class" data storage-class))
        (let* ((body ((storage-class-data->body storage-class) data))
               (n ((storage-class-length storage-class) body))
               (interval (make-interval (vector n)))
               (indexer (lambda (i) i))
               (raw-getter (lambda (i) ((storage-class-getter storage-class) body (indexer i))))
               (raw-setter (lambda (val i) ((storage-class-setter storage-class) body (indexer i) val)))
               (getter (%safe-getter interval raw-getter))
               (setter (and mutable?
                            (%safe-setter interval (storage-class-checker storage-class) raw-setter))))
          (%make-array/unsafe interval getter setter body indexer storage-class safe?
                              raw-getter (and mutable? raw-setter)))))

    ;; #t iff lexicographic traversal order visits CONSECUTIVE, INCREASING
    ;; body positions -- per spec, "the elements of array, taken in
    ;; lexicographical order, are stored in (array-body array) with
    ;; increasing and consecutive indices". The first visited position may
    ;; be ANY base (a non-zero offset view such as array-extract's is still
    ;; packed), matching the reference implementation, which checks only
    ;; stride-1 differences between lexicographic neighbors and treats a
    ;; length-1 axis as trivially packed. Always true immediately after
    ;; make-specialized-array/make-specialized-array-from-data; becomes
    ;; meaningful once a later phase's view/share/reverse procedures
    ;; install a different indexer over the same body. Escapes via call/cc
    ;; on the first mismatch rather than scanning the full domain, since a
    ;; later phase's non-packed arrays could otherwise pay a full
    ;; interval-volume traversal just to report "not packed" at index 0.
    (define (array-packed? a)
      (unless (specialized-array? a) (error "array-packed?: not a specialized array" a))
      (call/cc
       (lambda (return)
         (let ((expected #f) (indexer (array-indexer a)))
           (interval-for-each (lambda multi-index
                                (let ((idx (apply indexer multi-index)))
                                  (cond ((not expected) (set! expected (+ idx 1)))
                                        ((= idx expected) (set! expected (+ expected 1)))
                                        (else (return #f)))))
                               (array-domain a))
           #t))))))
