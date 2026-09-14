;;; SRFI 63 -- Homogeneous and Heterogeneous Arrays.
;;;
;;; Supersedes SRFI 47 (its own status header says so); every one of 47's 9
;;; core procedures has an identical signature here, so 47 is not
;;; separately implemented. Confirmed incompatible with SRFI 25/164 (both
;;; SRFIs' own Issues sections say so): array-set!'s new-value argument is
;;; SECOND here (right after array), vs. LAST in 25/164; make-array's first
;;; argument is a "prototype" (a type/fill-value carrier), not a
;;; bounds-shape object; every dimension is a plain zero-based size (no
;;; arbitrary lower bounds, no shape object at all).
;;;
;;; An array is one of two modes:
;;;   - "simple": store is a backing vector/bytevector/(srfi 160)
;;;     NumericVector; kind selects, via %kind-table, which accessor
;;;     closures to use for it.
;;;   - "shared": base/mapper are set. make-shared-array's mapper is
;;;     called with the NEW array's indices as separate arguments (as in
;;;     this codebase's other array SRFIs) but -- confirmed from this
;;;     SRFI's own worked examples, a rank-2-to-1 diagonal view and a
;;;     rank-2-to-2 offset view -- RETURNS A LIST of old coordinates, not
;;;     multiple values. This is the one genuinely easy-to-get-backwards
;;;     detail versus SRFI 25/164's share-array/array-transform, so it is
;;;     never assumed to match; array-ref/set! recurse into the base
;;;     array's own ref/set! (not its raw store), so new/old ranks can
;;;     differ freely (as the diagonal example demonstrates) and nested
;;;     shared arrays compose correctly for both reads and writes.
;;;
;;; Prototype-driven typing: make-array's prototype is an array, vector, or
;;; string (its "kind" is reused directly), or the result of one of the 20
;;; standard 0-or-1-argument type-tag generator procedures (A:fixZ8b,
;;; A:floR64b, etc.) below. 12 of the 20 kinds reuse this codebase's own
;;; already-shipped, already-validated (srfi 160 <tag>) procedures (or
;;; plain bytevectors for the 8-bit unsigned case, matching u8's
;;; bytevector-alias treatment throughout this codebase) rather than
;;; re-deriving range/exactness checking from scratch -- the same
;;; "one substrate, thin per-kind wrappers" shape as SRFI 160 itself, with
;;; zero new engine work. The remaining 8 kinds (16/128-bit floats, 16/32-
;;; bit complex, all 3 decimal-float widths) have no Kaappi-native
;;; representation to back them with, so they fall back to a plain,
;;; unchecked vector -- a spec-sanctioned fallback ("resorting finally to
;;; vector" for unsupported homogeneous types), not a shortcut; the
;;; decimal-float conversion rules are, per this SRFI's own Issues section,
;;; explicitly "yet to be determined" even in the reference implementation.
;;;
;;; equal? is genuinely overridden: SRFI 63 exports an array-augmented
;;; R5RS equal?, so this library renames the standard scheme-base equal?
;;; on import and defines its own that delegates to the original for the
;;; non-array case. This only affects code that imports equal? from this
;;; library -- ordinary R7RS import-collision rules apply to anyone who
;;; also imports (scheme base) without excluding one or the other.
(define-library (srfi 63)
  (import (rename (scheme base) (equal? %r7rs-equal?))
          (srfi 160 s8) (srfi 160 s16) (srfi 160 s32) (srfi 160 s64)
          (srfi 160 u16) (srfi 160 u32) (srfi 160 u64)
          (srfi 160 f32) (srfi 160 f64) (srfi 160 c64) (srfi 160 c128))
  (export array? array-rank array-dimensions
          make-array make-shared-array array-in-bounds?
          array-ref array-set! equal?
          list->array array->list vector->array array->vector
          A:floC128b A:floC64b A:floC32b A:floC16b
          A:floR128b A:floR64b A:floR32b A:floR16b
          A:floQ128d A:floQ64d A:floQ32d
          A:fixZ64b A:fixZ32b A:fixZ16b A:fixZ8b
          A:fixN64b A:fixN32b A:fixN16b A:fixN8b
          A:bool)
  (begin

    (define-record-type <uarray>
      (%make-uarray dims kind store base mapper)
      %uarray?
      (dims array-dims-vec)
      (kind array-kind)
      (store array-store)
      (base array-base)
      (mapper array-mapper))

    ;; Per spec ("Arrays are not disjoint from other Scheme types"), a plain
    ;; vector or string IS an array in its own right (rank 1, kind 'generic
    ;; or 'char respectively) -- not just a valid make-array/make-shared-array
    ;; prototype. array? and the core accessors all dispatch across three
    ;; representations: <uarray> records, plain vectors, plain strings.
    (define (array? a) (or (%uarray? a) (vector? a) (string? a)))

    (define (%array-like-dims-vec a)
      (cond
       ((%uarray? a) (array-dims-vec a))
       ((vector? a) (vector (vector-length a)))
       (else (vector (string-length a)))))

    (define (%array-like-ref a indices)
      (cond
       ((%uarray? a) (%array-ref-indices a indices))
       ((vector? a) (vector-ref a (car indices)))
       (else (string-ref a (car indices)))))

    (define (%array-like-set! a indices value)
      (cond
       ((%uarray? a) (%array-set-indices! a indices value))
       ((vector? a) (vector-set! a (car indices) value))
       (else (string-set! a (car indices) value))))

    ;; --- kind dispatch table: (kind maker ref setter! length default) ---

    (define (%bool-set! v i x)
      (unless (boolean? x) (error "array-set!: value must be a boolean for this array's kind" x))
      (vector-set! v i x))

    (define %kind-table
      (list
       (list 'fixZ8b  make-s8vector  s8vector-ref  s8vector-set!  s8vector-length  0)
       (list 'fixZ16b make-s16vector s16vector-ref s16vector-set! s16vector-length 0)
       (list 'fixZ32b make-s32vector s32vector-ref s32vector-set! s32vector-length 0)
       (list 'fixZ64b make-s64vector s64vector-ref s64vector-set! s64vector-length 0)
       (list 'fixN8b  make-bytevector bytevector-u8-ref bytevector-u8-set! bytevector-length 0)
       (list 'fixN16b make-u16vector u16vector-ref u16vector-set! u16vector-length 0)
       (list 'fixN32b make-u32vector u32vector-ref u32vector-set! u32vector-length 0)
       (list 'fixN64b make-u64vector u64vector-ref u64vector-set! u64vector-length 0)
       (list 'floR32b make-f32vector f32vector-ref f32vector-set! f32vector-length 0.0)
       (list 'floR64b make-f64vector f64vector-ref f64vector-set! f64vector-length 0.0)
       (list 'floC64b make-c64vector c64vector-ref c64vector-set! c64vector-length 0.0)
       (list 'floC128b make-c128vector c128vector-ref c128vector-set! c128vector-length 0.0)
       (list 'bool make-vector vector-ref %bool-set! vector-length #f)
       (list 'char make-string string-ref string-set! string-length #\a)
       (list 'generic make-vector vector-ref vector-set! vector-length #f)))

    (define (%kind-entry kind)
      (or (assq kind %kind-table) (error "invalid array kind" kind)))
    (define (%kind-maker kind) (list-ref (%kind-entry kind) 1))
    (define (%kind-ref kind) (list-ref (%kind-entry kind) 2))
    (define (%kind-setter kind) (list-ref (%kind-entry kind) 3))
    (define (%kind-default kind) (list-ref (%kind-entry kind) 5))

    ;; --- shape helpers (0-based only -- simpler than SRFI 25/164) ---

    (define (%dims-volume dims-vec)
      (let loop ((i 0) (acc 1))
        (if (= i (vector-length dims-vec)) acc (loop (+ i 1) (* acc (vector-ref dims-vec i))))))

    (define (%row-major-offset dims-vec indices)
      (let loop ((i 0) (idxs indices) (acc 0))
        (if (null? idxs)
            acc
            (let ((dim (vector-ref dims-vec i)) (ix (car idxs)))
              (unless (and (integer? ix) (<= 0 ix) (< ix dim))
                (error "array-ref/array-set!: index out of range for dimension" i ix))
              (loop (+ i 1) (cdr idxs) (+ (* acc dim) ix))))))

    (define (%check-rank! a indices who)
      (unless (= (length indices) (array-rank a))
        (error (string-append who ": wrong number of indices") a indices)))

    (define (%for-each-index dims-vec proc)
      (let ((rank (vector-length dims-vec)))
        (define (go dim acc)
          (if (= dim rank)
              (proc (reverse acc))
              (let ((n (vector-ref dims-vec dim)))
                (let iter ((i 0))
                  (when (< i n)
                    (go (+ dim 1) (cons i acc))
                    (iter (+ i 1)))))))
        (go 0 '())))

    ;; A shared view's own declared dims-vec (from make-shared-array's dims
    ;; arguments) is its real bounds -- %row-major-offset is called here
    ;; purely to enforce them (and discarded) before delegating through the
    ;; mapper, since the mapper itself has no obligation to reject an index
    ;; the view's own shape disallows; array-in-bounds? must agree with this.
    (define (%array-ref-indices a indices)
      (let ((store (array-store a)))
        (if store
            ((%kind-ref (array-kind a)) store (%row-major-offset (array-dims-vec a) indices))
            (begin
              (%row-major-offset (array-dims-vec a) indices)
              (%array-like-ref (array-base a) (apply (array-mapper a) indices))))))

    (define (%array-set-indices! a indices value)
      (let ((store (array-store a)))
        (if store
            ((%kind-setter (array-kind a)) store (%row-major-offset (array-dims-vec a) indices) value)
            (begin
              (%row-major-offset (array-dims-vec a) indices)
              (%array-like-set! (array-base a) (apply (array-mapper a) indices) value)))))

    ;; --- the 20 prototype-generator procedures ---

    ;; A rank-0 array has dims #() -- %dims-volume's empty-product convention
    ;; makes that exactly 1 cell, matching the mathematical "0-dimensional
    ;; array is a single scalar" reading. With a fill value given, that cell
    ;; is actually populated (via the kind's own setter, which also enforces
    ;; the kind's usual range/type validation on the fill value for free) so
    ;; make-array can later read it back as "the element at the origin of
    ;; prototype" -- a zero-length store could never carry that value at all.
    (define (%build-prototype kind fill)
      (cond
       ((null? fill) (%make-uarray (vector) kind ((%kind-maker kind) 1 (%kind-default kind)) #f #f))
       ((null? (cdr fill))
        (let ((store ((%kind-maker kind) 1 (%kind-default kind))))
          ((%kind-setter kind) store 0 (car fill))
          (%make-uarray (vector) kind store #f #f)))
       (else (error "array prototype constructor: too many arguments" fill))))

    (define (A:fixZ8b . fill) (%build-prototype 'fixZ8b fill))
    (define (A:fixZ16b . fill) (%build-prototype 'fixZ16b fill))
    (define (A:fixZ32b . fill) (%build-prototype 'fixZ32b fill))
    (define (A:fixZ64b . fill) (%build-prototype 'fixZ64b fill))
    (define (A:fixN8b . fill) (%build-prototype 'fixN8b fill))
    (define (A:fixN16b . fill) (%build-prototype 'fixN16b fill))
    (define (A:fixN32b . fill) (%build-prototype 'fixN32b fill))
    (define (A:fixN64b . fill) (%build-prototype 'fixN64b fill))
    (define (A:floR32b . fill) (%build-prototype 'floR32b fill))
    (define (A:floR64b . fill) (%build-prototype 'floR64b fill))
    (define (A:floC64b . fill) (%build-prototype 'floC64b fill))
    (define (A:floC128b . fill) (%build-prototype 'floC128b fill))
    (define (A:bool . fill) (%build-prototype 'bool fill))
    ;; No Kaappi-native representation exists for these -- fall back to a
    ;; plain, unchecked vector (spec-sanctioned: "resorting finally to
    ;; vector" is the explicit fallback for an unsupported homogeneous type).
    (define (A:floR16b . fill) (%build-prototype 'generic fill))
    (define (A:floR128b . fill) (%build-prototype 'generic fill))
    (define (A:floC16b . fill) (%build-prototype 'generic fill))
    (define (A:floC32b . fill) (%build-prototype 'generic fill))
    (define (A:floQ32d . fill) (%build-prototype 'generic fill))
    (define (A:floQ64d . fill) (%build-prototype 'generic fill))
    (define (A:floQ128d . fill) (%build-prototype 'generic fill))

    ;; --- the 13 core procedures ---

    ;; %uarray?, not the public array? (which is also true of plain vectors/
    ;; strings) -- a vector/string prototype's kind is derived structurally
    ;; instead, never via the <uarray>-only array-kind accessor.
    (define (%prototype-kind proto)
      (cond
       ((%uarray? proto) (array-kind proto))
       ((vector? proto) 'generic)
       ((string? proto) 'char)
       (else (error "make-array: prototype must be an array, vector, or string" proto))))

    ;; Per spec: "the returned array will be filled with the element at the
    ;; origin of prototype" when the prototype has any elements at all;
    ;; unspecified (here, the kind's own zero-ish default) when it has none.
    (define (%prototype-origin-fill proto kind)
      (cond
       ((%uarray? proto)
        (if (> (%dims-volume (array-dims-vec proto)) 0)
            (%array-ref-indices proto (make-list (array-rank proto) 0))
            (%kind-default kind)))
       ((vector? proto) (if (> (vector-length proto) 0) (vector-ref proto 0) (%kind-default kind)))
       ((string? proto) (if (> (string-length proto) 0) (string-ref proto 0) (%kind-default kind)))
       (else (%kind-default kind))))

    (define (array-rank a) (vector-length (%array-like-dims-vec a)))
    (define (array-dimensions a) (vector->list (%array-like-dims-vec a)))

    (define (make-array prototype . dims)
      (let* ((kind (%prototype-kind prototype))
             (dims-vec (list->vector dims))
             (fill (%prototype-origin-fill prototype kind))
             (store ((%kind-maker kind) (%dims-volume dims-vec) fill)))
        (%make-uarray dims-vec kind store #f #f)))

    (define (make-shared-array a mapper . dims)
      (%make-uarray (list->vector dims) (%prototype-kind a) #f a mapper))

    (define (array-in-bounds? a . indices)
      (and (= (length indices) (array-rank a))
           (let ((dims (%array-like-dims-vec a)))
             (let loop ((i 0) (idxs indices))
               (or (null? idxs)
                   (and (integer? (car idxs)) (<= 0 (car idxs)) (< (car idxs) (vector-ref dims i))
                        (loop (+ i 1) (cdr idxs))))))))

    (define (array-ref a . indices)
      (%check-rank! a indices "array-ref")
      (%array-like-ref a indices))

    ;; Value is the SECOND argument (right after array), the opposite
    ;; convention from SRFI 25/164's array-set!.
    (define (array-set! a value . indices)
      (%check-rank! a indices "array-set!")
      (%array-like-set! a indices value))

    ;; Scope reduction: this array-augmented equal? only special-cases two
    ;; genuine <uarray> records. Vector-vs-vector and string-vs-string (both
    ;; now also arrays per array?) already compare correctly via plain R7RS
    ;; equal? below; cross-representation array equality (a <uarray> vs. a
    ;; plain vector with the same apparent shape/contents) is not attempted.
    (define (equal? a b)
      (if (and (%uarray? a) (%uarray? b))
          (and (equal? (array-dimensions a) (array-dimensions b))
               (let ((ok #t))
                 (%for-each-index (array-dims-vec a)
                                   (lambda (idx)
                                     (unless (equal? (%array-ref-indices a idx) (%array-ref-indices b idx))
                                       (set! ok #f))))
                 ok))
          (%r7rs-equal? a b)))

    ;; --- the 4 procedures new in SRFI 63 ---

    (define (%infer-dims rank nested)
      (let loop ((r rank) (x nested) (dims '()))
        (if (= r 0)
            (list->vector (reverse dims))
            (loop (- r 1) (if (null? x) '() (car x)) (cons (length x) dims)))))

    (define (%flatten-nested rank nested)
      (if (= rank 0)
          (list nested)
          (apply append (map (lambda (sub) (%flatten-nested (- rank 1) sub)) nested))))

    (define (list->array rank prototype nested)
      (unless (and (integer? rank) (exact? rank) (>= rank 0))
        (error "list->array: rank must be a nonnegative exact integer" rank))
      (let* ((kind (%prototype-kind prototype))
             (dims-vec (if (= rank 0) (vector) (%infer-dims rank nested)))
             (flat (if (= rank 0) (list nested) (%flatten-nested rank nested)))
             (size (%dims-volume dims-vec))
             (store ((%kind-maker kind) size (%kind-default kind))))
        (let loop ((i 0) (xs flat))
          (when (< i size)
            ((%kind-setter kind) store i (car xs))
            (loop (+ i 1) (cdr xs))))
        (%make-uarray dims-vec kind store #f #f)))

    (define (array->list a)
      (let* ((dims (%array-like-dims-vec a)) (rank (vector-length dims)))
        (define (build level prefix)
          (if (= level rank)
              (%array-like-ref a (reverse prefix))
              (let ((n (vector-ref dims level)))
                (let loop ((i 0) (acc '()))
                  (if (= i n)
                      (reverse acc)
                      (loop (+ i 1) (cons (build (+ level 1) (cons i prefix)) acc)))))))
        (build 0 '())))

    (define (vector->array vect prototype . dims)
      (let* ((kind (%prototype-kind prototype))
             (dims-vec (list->vector dims))
             (size (%dims-volume dims-vec)))
        (unless (= size (vector-length vect))
          (error "vector->array: vector length doesn't match dimensions" vect dims))
        (let ((store ((%kind-maker kind) size (%kind-default kind))))
          (let loop ((i 0))
            (when (< i size)
              ((%kind-setter kind) store i (vector-ref vect i))
              (loop (+ i 1))))
          (%make-uarray dims-vec kind store #f #f))))

    (define (array->vector a)
      (let* ((dims (%array-like-dims-vec a)) (size (%dims-volume dims)) (v (make-vector size)) (i 0))
        (%for-each-index dims
                          (lambda (idx) (vector-set! v i (%array-like-ref a idx)) (set! i (+ i 1))))
        v))))
