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
          %make-array %safe-getter %safe-setter %make-lex-indexer)
  (begin

    (define-record-type <array>
      (%make-array domain getter setter body indexer storage-class safe?)
      array?
      (domain array-domain)
      (getter array-getter)
      (setter %array-setter-raw %array-set-setter!)
      (body %array-body-raw)
      (indexer %array-indexer-raw)
      (storage-class %array-storage-class-raw)
      (safe? %array-safe?-raw))

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

    (define (array-dimension a) (interval-dimension (array-domain a)))
    (define (array-empty? a) (interval-empty? (array-domain a)))

    (define (array-ref a . multi-index) (apply (array-getter a) multi-index))
    ;; Value is the SECOND argument (right after array), matching SRFI
    ;; 63's convention (opposite of SRFI 25/164's value-last).
    (define (array-set! a object . multi-index) (apply (array-setter a) object multi-index))

    (define (array-freeze! a)
      (unless (array? a) (error "array-freeze!: not an array" a))
      (%array-set-setter! a #f)
      a)

    (define (make-array interval getter . maybe-setter)
      (unless (interval? interval) (error "make-array: not an interval" interval))
      (unless (procedure? getter) (error "make-array: getter must be a procedure" getter))
      (let ((setter (if (null? maybe-setter) #f (car maybe-setter))))
        (%make-array interval getter setter #f #f #f #f)))

    (define specialized-array-default-safe? (make-parameter #f))
    (define specialized-array-default-mutable? (make-parameter #t))

    ;; The lexicographical mapping of interval onto [0, interval-volume) --
    ;; per spec, a specialized array's own indexer. Subtracts each axis's
    ;; lower bound first to get a local 0-based index, then applies the
    ;; standard row-major stride computation using the interval's own
    ;; widths -- a direct generalization of SRFI 63's %row-major-offset to
    ;; arbitrary (not just zero-based) lower bounds.
    (define (%make-lex-indexer interval)
      (let ((lo (interval-lower-bounds->vector interval))
            (widths (interval-widths interval))
            (d (interval-dimension interval)))
        (lambda multi-index
          (let loop ((i 0) (xs multi-index) (acc 0))
            (if (= i d)
                acc
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
      (let* ((storage-class (%opt opts 0 generic-storage-class))
             (initial-value (%opt opts 1 (storage-class-default storage-class)))
             (safe? (%opt opts 2 (specialized-array-default-safe?)))
             (body ((storage-class-maker storage-class) (interval-volume interval) initial-value))
             (indexer (%make-lex-indexer interval))
             (raw-getter (lambda multi-index
                           ((storage-class-getter storage-class) body (apply indexer multi-index))))
             (raw-setter (lambda (val . multi-index)
                           ((storage-class-setter storage-class) body (apply indexer multi-index) val)))
             (getter (if safe? (%safe-getter interval raw-getter) raw-getter))
             (setter (if safe? (%safe-setter interval (storage-class-checker storage-class) raw-setter) raw-setter)))
        (%make-array interval getter setter body indexer storage-class safe?)))

    ;; Wraps EXTERNALLY supplied data (e.g. a plain vector or one of this
    ;; codebase's own (srfi 160 <tag>) numeric vectors) as the body of a
    ;; new 1-D array WITHOUT copying -- data must already be exactly
    ;; body-shaped for storage-class (per storage-class-data?).
    (define (make-specialized-array-from-data data . opts)
      (let* ((storage-class (%opt opts 0 generic-storage-class))
             (mutable? (%opt opts 1 (specialized-array-default-mutable?)))
             (safe? (%opt opts 2 (specialized-array-default-safe?))))
        (unless ((storage-class-data? storage-class) data)
          (error "make-specialized-array-from-data: data is not compatible with storage-class" data storage-class))
        (let* ((body ((storage-class-data->body storage-class) data))
               (n ((storage-class-length storage-class) body))
               (interval (make-interval (vector n)))
               (indexer (lambda (i) i))
               (raw-getter (lambda (i) ((storage-class-getter storage-class) body (indexer i))))
               (raw-setter (lambda (val i) ((storage-class-setter storage-class) body (indexer i) val)))
               (getter (if safe? (%safe-getter interval raw-getter) raw-getter))
               (setter (and mutable?
                            (if safe? (%safe-setter interval (storage-class-checker storage-class) raw-setter) raw-setter))))
          (%make-array interval getter setter body indexer storage-class safe?))))

    ;; #t iff lexicographic traversal order visits body positions
    ;; 0,1,2,...,volume-1 consecutively -- always true immediately after
    ;; make-specialized-array/make-specialized-array-from-data (their own
    ;; indexer IS that exact lexicographic mapping); becomes meaningful
    ;; once a later phase's view/share/reverse procedures install a
    ;; different (non-consecutive) indexer over the same body. Escapes via
    ;; call/cc on the first mismatch rather than scanning the full domain,
    ;; since a later phase's non-packed arrays could otherwise pay a full
    ;; interval-volume traversal just to report "not packed" at index 0.
    (define (array-packed? a)
      (unless (specialized-array? a) (error "array-packed?: not a specialized array" a))
      (call/cc
       (lambda (return)
         (let ((expected 0) (indexer (array-indexer a)))
           (interval-for-each (lambda multi-index
                                 (unless (= (apply indexer multi-index) expected) (return #f))
                                 (set! expected (+ expected 1)))
                               (array-domain a))
           #t))))))
