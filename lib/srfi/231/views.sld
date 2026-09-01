;;; SRFI 231 -- Views, sharing, and reshaping (phase 3 of #1694's SRFI 231
;;; slice). Builds on phases 1a/1b/2 (intervals, storage classes, core
;;; array object). See intervals.sld's header for the overall roadmap;
;;; (srfi 231) itself is still not importable as a bare library.
;;;
;;; specialized-array-share is the foundational primitive here -- every
;;; view/transform procedure that shares a specialized array's body (all
;;; except array-curry/array-tile's own OUTER array, array-copy, and
;;; specialized-array-reshape) is defined in terms of it. It composes a
;;; caller-supplied affine "new-domain->old-domain" mapping (called with
;;; the NEW array's indices as separate arguments, returning OLD
;;; coordinates via multiple values -- confirmed from the spec's own
;;; "shearing" example, which is strictly more general than any of the
;;; other sharing procedures combined) with the source array's own
;;; indexer, and inherits mutability/safety from the source.
;;;
;;; A recurring pattern confirmed across array-extract/translate/permute/
;;; reverse/sample: each dispatches 3 ways on the SOURCE array's own mode
;;; (specialized -> specialized-array-share; mutable-non-specialized ->
;;; make-array with getter+setter; immutable -> make-array with getter
;;; only), and the OUTPUT exactly mirrors the input's mode. array-curry
;;; and array-tile break this pattern deliberately: their OUTER array is
;;; unconditionally plain immutable/non-specialized regardless of input
;;; mode (confirmed by an explicit spec quote for curry: "B is always an
;;; immutable array... computed anew for each call" -- i.e. never
;;; cached/memoized), while their INNER elements (the subarrays) follow
;;; the same 3-way mirroring as everything else.
;;;
;;; specialized-array-reshape's affine-detectability test is, in the
;;; spec's own words, "modeled on the corresponding code in the Python
;;; library NumPy" and not specified in prose beyond that. This port
;;; follows the reference implementation's actual algorithm, derived from
;;; NumPy's _attempt_nocopy_reshape: empirically probe the source array's
;;; own (affine) indexer to recover its base and per-axis strides, drop
;;; the size-1 axes, then greedily match minimal adjacent-axis volume
;;; groups between the old and new shapes, verifying within each group
;;; that the old strides are C-contiguous (stride[k] = dim[k+1] *
;;; stride[k+1]) so a single affine map covers the group. A reversed or
;;; otherwise negatively-strided view is handled correctly -- its strides
;;; still satisfy the C-contiguity relation, just with a negative unit --
;;; which is why a plain packed-only shortcut (the previous port here)
;;; wrongly rejected e.g. (specialized-array-reshape (array-reverse ...)
;;; ...). When no affine map exists the procedure behaves exactly as the
;;; spec allows: error, or a forced copy-then-retry when copy-on-failure?
;;; is #t (the copy is packed, so the retry always succeeds).
;;;
;;; The reshape matching loops (loop-1..loop-4 in %specialized-array-reshape)
;;; are a line-by-line translation of NumPy's _attempt_nocopy_reshape
;;; (numpy/core/src/multiarray/shape.c), by way of the SRFI 231 reference
;;; implementation, which carries the same derivation note. NumPy is
;;; distributed under the BSD 3-Clause License, Copyright (c) 2005-2024,
;;; NumPy Developers.
(define-library (srfi 231 views)
  (import (scheme base)
          (srfi 231 misc) (srfi 231 intervals) (srfi 231 storage-classes) (srfi 231 arrays))
  (export specialized-array-share
          array-extract array-translate array-permute array-reverse
          array-curry array-tile array-sample
          array-copy array-copy!
          specialized-array-reshape)
  (begin

    (define (%vector-every pred v)
      (let loop ((i 0))
        (or (= i (vector-length v))
            (and (pred (vector-ref v i)) (loop (+ i 1))))))

    (define (%opt lst i default) (if (> (length lst) i) (list-ref lst i) default))

    ;; --- the foundational sharing primitive ---

    (define (specialized-array-share array new-domain new-domain->old-domain)
      (unless (specialized-array? array) (error "specialized-array-share: not a specialized array" array))
      (unless (interval? new-domain) (error "specialized-array-share: not an interval" new-domain))
      (unless (procedure? new-domain->old-domain)
        (error "specialized-array-share: new-domain->old-domain must be a procedure" new-domain->old-domain))
      (when (> (interval-volume new-domain) (interval-volume (array-domain array)))
        (error "specialized-array-share: new-domain has more elements than array" new-domain array))
      (let* ((storage-class (array-storage-class array))
             (body (array-body array))
             (old-indexer (array-indexer array))
             (new-indexer (lambda multi-index
                            (call-with-values (lambda () (apply new-domain->old-domain multi-index)) old-indexer)))
             (safe? (array-safe? array))
             (mutable? (mutable-array? array))
             (raw-getter (lambda multi-index
                           ((storage-class-getter storage-class) body (apply new-indexer multi-index))))
             (raw-setter (lambda (val . multi-index)
                           ((storage-class-setter storage-class) body (apply new-indexer multi-index) val)))
             ;; always checked; the raw pair is kept for bulk ops (#2448)
             (getter (%safe-getter new-domain raw-getter))
             (setter (and mutable?
                          (%safe-setter new-domain (storage-class-checker storage-class) raw-setter))))
        (%make-array/unsafe new-domain getter setter body new-indexer storage-class safe?
                            raw-getter (and mutable? raw-setter))))

    ;; --- the 3-way dispatch shape shared by extract/translate/permute/reverse/sample ---

    (define (array-extract array new-domain)
      (unless (array? array) (error "array-extract: not an array" array))
      (unless (interval? new-domain) (error "array-extract: not an interval" new-domain))
      (unless (= (interval-dimension new-domain) (array-dimension array))
        (error "array-extract: dimension mismatch" new-domain array))
      (unless (interval-subset? new-domain (array-domain array))
        (error "array-extract: new-domain is not a subset of array's domain" new-domain array))
      (cond
       ((specialized-array? array) (specialized-array-share array new-domain values))
       ((mutable-array? array) (make-array new-domain (array-getter array) (array-setter array)))
       (else (make-array new-domain (array-getter array)))))

    (define (array-translate array translation)
      (unless (array? array) (error "array-translate: not an array" array))
      (unless (translation? translation) (error "array-translate: not a valid translation" translation))
      (unless (= (vector-length translation) (array-dimension array))
        (error "array-translate: dimension mismatch" translation array))
      (let ((new-domain (interval-translate (array-domain array) translation))
            (tlist (vector->list translation)))
        (cond
         ((specialized-array? array)
          (specialized-array-share array new-domain (lambda multi-index (apply values (map - multi-index tlist)))))
         ((mutable-array? array)
          (make-array new-domain
                      (lambda multi-index (apply (array-getter array) (map - multi-index tlist)))
                      (lambda (val . multi-index) (apply (array-setter array) val (map - multi-index tlist)))))
         (else
          (make-array new-domain (lambda multi-index (apply (array-getter array) (map - multi-index tlist))))))))

    (define (%permutation-invert perm)
      (let* ((n (vector-length perm)) (inv (make-vector n 0)))
        (let loop ((i 0))
          (when (< i n)
            (vector-set! inv (vector-ref perm i) i)
            (loop (+ i 1))))
        inv))

    ;; result[i] = lst[perm-vec[i]]
    (define (%list-permute lst perm-vec)
      (let ((v (list->vector lst)))
        (map (lambda (p) (vector-ref v p)) (vector->list perm-vec))))

    (define (array-permute array permutation)
      (unless (array? array) (error "array-permute: not an array" array))
      (unless (permutation? permutation) (error "array-permute: not a valid permutation" permutation))
      (unless (= (vector-length permutation) (array-dimension array))
        (error "array-permute: dimension mismatch" permutation array))
      (let* ((new-domain (interval-permute (array-domain array) permutation))
             (inv (%permutation-invert permutation)))
        (cond
         ((specialized-array? array)
          (specialized-array-share array new-domain
                                    (lambda multi-index (apply values (%list-permute multi-index inv)))))
         ((mutable-array? array)
          (make-array new-domain
                      (lambda multi-index (apply (array-getter array) (%list-permute multi-index inv)))
                      (lambda (val . multi-index) (apply (array-setter array) val (%list-permute multi-index inv)))))
         (else
          (make-array new-domain
                      (lambda multi-index (apply (array-getter array) (%list-permute multi-index inv))))))))

    (define (%flip-multi-index-maker domain flip-vec)
      (let ((lowers (interval-lower-bounds->list domain))
            (uppers (interval-upper-bounds->list domain))
            (flips (vector->list flip-vec)))
        (lambda (multi-index)
          (map (lambda (i f l u) (if f (- (+ l u -1) i) i)) multi-index flips lowers uppers))))

    ;; flip? default: reverse every axis (a same-length all-#t vector) --
    ;; the array's own DOMAIN is unchanged (unlike translate/permute/sample);
    ;; only the index<->value correspondence changes.
    (define (array-reverse array . maybe-flip)
      (unless (array? array) (error "array-reverse: not an array" array))
      (let* ((d (array-dimension array))
             (flip? (if (null? maybe-flip) (make-vector d #t) (car maybe-flip))))
        (unless (and (vector? flip?) (= (vector-length flip?) d) (%vector-every boolean? flip?))
          (error "array-reverse: flip? must be a boolean vector matching the array's dimension" flip? array))
        (let* ((domain (array-domain array))
               (flip-fn (%flip-multi-index-maker domain flip?)))
          (cond
           ((specialized-array? array)
            (specialized-array-share array domain (lambda multi-index (apply values (flip-fn multi-index)))))
           ((mutable-array? array)
            (make-array domain
                        (lambda multi-index (apply (array-getter array) (flip-fn multi-index)))
                        (lambda (val . multi-index) (apply (array-setter array) val (flip-fn multi-index)))))
           (else
            (make-array domain (lambda multi-index (apply (array-getter array) (flip-fn multi-index)))))))))

    (define (array-sample array scales)
      (unless (array? array) (error "array-sample: not an array" array))
      (unless (and (vector? scales) (%vector-every (lambda (x) (and (integer? x) (exact? x) (positive? x))) scales))
        (error "array-sample: scales must be a vector of positive exact integers" scales))
      (unless (= (vector-length scales) (array-dimension array))
        (error "array-sample: dimension mismatch" scales array))
      (unless (%vector-every zero? (interval-lower-bounds->vector (array-domain array)))
        (error "array-sample: array's domain must have all-zero lower bounds" array))
      (let ((new-domain (interval-scale (array-domain array) scales))
            (slist (vector->list scales)))
        (cond
         ((specialized-array? array)
          (specialized-array-share array new-domain (lambda multi-index (apply values (map * multi-index slist)))))
         ((mutable-array? array)
          (make-array new-domain
                      (lambda multi-index (apply (array-getter array) (map * multi-index slist)))
                      (lambda (val . multi-index) (apply (array-setter array) val (map * multi-index slist)))))
         (else
          (make-array new-domain (lambda multi-index (apply (array-getter array) (map * multi-index slist))))))))

    ;; --- array-curry: outer array is ALWAYS plain immutable/non-specialized,
    ;; computed fresh on every outer-getter call (never cached), regardless
    ;; of the input array's own mode -- confirmed by an explicit spec quote.
    ;; Inner arrays mirror the input's mode 3-way, same as extract/etc. ---

    (define (array-curry array inner-dimension)
      (unless (array? array) (error "array-curry: not an array" array))
      (unless (and (integer? inner-dimension) (exact? inner-dimension)
                   (<= 0 inner-dimension (array-dimension array)))
        (error "array-curry: inner-dimension out of range" inner-dimension array))
      (call-with-values (lambda () (interval-projections (array-domain array) inner-dimension))
        (lambda (outer-interval inner-interval)
          (cond
           ((specialized-array? array)
            (make-array outer-interval
                        (lambda outer-multi-index
                          (specialized-array-share
                           array inner-interval
                           (lambda inner-multi-index (apply values (append outer-multi-index inner-multi-index)))))))
           ((mutable-array? array)
            (make-array outer-interval
                        (lambda outer-multi-index
                          (make-array inner-interval
                                      (lambda inner-multi-index
                                        (apply (array-getter array) (append outer-multi-index inner-multi-index)))
                                      (lambda (val . inner-multi-index)
                                        (apply (array-setter array) val (append outer-multi-index inner-multi-index)))))))
           (else
            (make-array outer-interval
                        (lambda outer-multi-index
                          (make-array inner-interval
                                      (lambda inner-multi-index
                                        (apply (array-getter array) (append outer-multi-index inner-multi-index)))))))))))

    ;; --- array-tile: outer array is ALWAYS plain immutable/non-specialized
    ;; (same shape as curry's outer array); each tile is produced via
    ;; array-extract itself, reusing its own 3-way dispatch rather than
    ;; re-implementing sharing here. ---

    ;; Per-axis cut offsets: a (n+1)-length vector of absolute coordinates
    ;; bounding n slices. Sk is either a positive exact integer (uniform
    ;; width, LAST slice truncated via min if it doesn't divide evenly --
    ;; confirmed spec-sanctioned, not an error) or a nonempty vector of
    ;; nonnegative exact integers summing to the axis's width (custom
    ;; per-slice widths, exact prefix sums).
    (define (%tile-cut-offsets width lower k Sk)
      (cond
       ((and (integer? Sk) (exact? Sk) (positive? Sk))
        ;; A scalar slice-width is legal only on a positive-width axis; a
        ;; zero-width axis must use the explicit-vector form (e.g. #(0)),
        ;; whose entries sum to the width -- the reference implementation's
        ;; own rule.
        (if (eqv? width 0)
            (error "array-tile: a scalar slice-width is allowed only on an axis of positive width" k Sk width)
            (let* ((n (quotient (+ width (- Sk 1)) Sk))
                   (offsets (make-vector (+ n 1) lower)))
              (let loop ((i 1))
                (when (<= i n)
                  (vector-set! offsets i (min (+ lower (* i Sk)) (+ lower width)))
                  (loop (+ i 1))))
              offsets)))
       ((and (vector? Sk) (> (vector-length Sk) 0)
             (%vector-every (lambda (x) (and (integer? x) (exact? x) (>= x 0))) Sk)
             (= (let loop ((i 0) (acc 0)) (if (= i (vector-length Sk)) acc (loop (+ i 1) (+ acc (vector-ref Sk i))))) width))
        (let* ((n (vector-length Sk)) (offsets (make-vector (+ n 1) lower)))
          (let loop ((i 1) (acc lower))
            (when (<= i n)
              (let ((new-acc (+ acc (vector-ref Sk (- i 1)))))
                (vector-set! offsets i new-acc)
                (loop (+ i 1) new-acc))))
          offsets))
       (else (error "array-tile: invalid slice-width component" Sk width))))

    (define (array-tile array S)
      (unless (array? array) (error "array-tile: not an array" array))
      (let* ((domain (array-domain array)) (d (array-dimension array))
             (lowers (interval-lower-bounds->vector domain))
             (widths (interval-widths domain)))
        (unless (and (vector? S) (= (vector-length S) d))
          (error "array-tile: S must be a vector matching the array's dimension" S array))
        (let ((cuts (make-vector d #f)))
          (let loop ((k 0))
            (when (< k d)
              (vector-set! cuts k (%tile-cut-offsets (vector-ref widths k) (vector-ref lowers k) k (vector-ref S k)))
              (loop (+ k 1))))
          (let ((out-dims (list->vector (map (lambda (c) (- (vector-length c) 1)) (vector->list cuts)))))
            (make-array
             (make-interval out-dims)
             (lambda outer-multi-index
               (let ((sub-lo (make-vector d 0)) (sub-hi (make-vector d 0)))
                 (let loop ((k 0) (js outer-multi-index))
                   (when (< k d)
                     (let ((c (vector-ref cuts k)) (j (car js)))
                       (vector-set! sub-lo k (vector-ref c j))
                       (vector-set! sub-hi k (vector-ref c (+ j 1))))
                     (loop (+ k 1) (cdr js))))
                 (array-extract array (make-interval sub-lo sub-hi)))))))))

    ;; --- array-copy / array-copy!: always produces a specialized array.
    ;; If the source is ALREADY specialized, omitted options are taken
    ;; from the SOURCE (storage-class/mutable?/safe?), making the default
    ;; call a true copy; otherwise omitted options fall back to
    ;; generic-storage-class/specialized-array-default-mutable?/-safe? --
    ;; confirmed via an explicit spec quote naming this exact asymmetry.
    ;; array-copy must be safe under a getter that captures a
    ;; continuation and re-invokes it after the copy returned (the whole
    ;; documented difference from array-copy!): the re-entry gets a FRESH
    ;; array, and the array the first call already returned never mutates
    ;; under its holder. That requires collecting every source value
    ;; BEFORE the destination exists, into a pre-sized scratch vector
    ;; indexed by a position threaded FUNCTIONALLY through the walk --
    ;; the threading is the safety mechanism (a set! position counter, or
    ;; interval-fold-left/right, which use one, lets the re-entry keep
    ;; counting on the first run's progress). The scratch itself is
    ;; shared mutable state, deliberately: a re-entry resumes from the
    ;; position captured at its capture point, so positions below it
    ;; retain the first run's values and positions above are re-fetched
    ;; -- observably identical to a functional cons accumulator, without
    ;; that shape's cost (at 1M elements: 18.0M total pair allocations
    ;; for a cons-list collector against 16.0M here, and its N live
    ;; pairs gone; the churn that remains is the library apply shape
    ;; every fill loop already shares -- kaappi#2464). A direct fill into
    ;; a pre-allocated destination (the pre-#2454 shape, and what
    ;; array-copy! still is -- the spec explicitly permits the `!`
    ;; variant to skip exactly this guarantee) lets the resumed fill
    ;; overwrite the already-returned array.
    (define (%domain-walk lowers uppers leaf k)
      ;; Walk the domain in lexicographic order (first axis outermost,
      ;; matching %interval-for-each-indices in intervals.sld), calling
      ;; (leaf index k) per multi-index with the index as a list, and
      ;; threading the leaf's returned position functionally through the
      ;; axis loops and the recursion. That threading is what makes a
      ;; continuation captured inside a leaf re-run the walk from ITS
      ;; captured position over ITS captured prefix, never the first
      ;; run's. One helper serves both array-copy passes so they cannot
      ;; drift out of order-agreement.
      (letrec ((walk
                (lambda (ls us rev-index k)
                  (if (null? ls)
                      (leaf (reverse rev-index) k)
                      (let loop ((i (car ls)) (k k))
                        (if (>= i (car us))
                            k
                            (loop (+ i 1)
                                  (walk (cdr ls) (cdr us)
                                        (cons i rev-index) k))))))))
        (walk lowers uppers '() k)))

    (define (%array-copy-impl array opts call/cc-safe?)
      (unless (array? array) (error "array-copy: not an array" array))
      (%check-boolean! (%opt opts 1 (specialized-array-default-mutable?)) "array-copy: mutable?")
      (%check-boolean! (%opt opts 2 (specialized-array-default-safe?)) "array-copy: safe?")
      (let* ((specialized? (specialized-array? array))
             (storage-class (%opt opts 0 (if specialized? (array-storage-class array) generic-storage-class)))
             (mutable? (%opt opts 1 (if specialized? (mutable-array? array) (specialized-array-default-mutable?))))
             (safe? (%opt opts 2 (if specialized? (array-safe? array) (specialized-array-default-safe?))))
             (domain (array-domain array))
             ;; indices come from a walk over the source's own domain, so
             ;; neither side needs the index check; values are still
             ;; checked unless provably valid (#2448)
             (getter (array-unsafe-getter array))
             (checker (%copy-value-checker array storage-class))
             (lowers (interval-lower-bounds->list domain))
             (uppers (interval-upper-bounds->list domain))
             ;; The whole collection runs here, inside the binding --
             ;; strictly before the destination below is allocated --
             ;; calling every getter (and the value checker) into the
             ;; scratch, so a continuation captured in a getter re-runs
             ;; collection and materializes its own destination.
             (scratch (and call/cc-safe?
                           (let ((buf (make-vector (interval-volume domain))))
                             (%domain-walk lowers uppers
                                           (lambda (index k)
                                             (let ((val (apply getter index)))
                                               (when (and checker (not (checker val)))
                                                 (error "array-copy: not all elements of the source can be stored in the destination"
                                                        val storage-class))
                                               (vector-set! buf k val)
                                               (+ k 1)))
                                           0)
                             buf)))
             (dest (make-specialized-array domain storage-class (storage-class-default storage-class) safe?))
             (dest-setter (array-unsafe-setter dest)))
        (if call/cc-safe?
            ;; Copy-out from the scratch: the values are already
            ;; collected, so a getter re-entry cannot change what lands
            ;; in dest. The dest-setter is library code for the built-in
            ;; storage classes but USER code when the destination's
            ;; storage class came from make-storage-class -- a
            ;; continuation captured there re-enters this copy-out with
            ;; dest already allocated, so it does not get a fresh array
            ;; (the same residual exposure the reference implementation's
            ;; own accumulate-then-materialize shape has; both runs write
            ;; identical collected values, so only the identity of the
            ;; re-entry's result object is affected).
            (%domain-walk lowers uppers
                          (lambda (index k)
                            (apply dest-setter (vector-ref scratch k) index)
                            (+ k 1))
                          0)
            (interval-for-each (lambda multi-index
                                 (let ((val (apply getter multi-index)))
                                   (when (and checker (not (checker val)))
                                     (error "array-copy: not all elements of the source can be stored in the destination"
                                            val storage-class))
                                   (apply dest-setter val multi-index)))
                               domain))
        (if mutable? dest (array-freeze! dest))))

    (define (array-copy array . opts) (%array-copy-impl array opts #t))
    (define (array-copy! array . opts) (%array-copy-impl array opts #f))

    ;; --- specialized-array-reshape: see the file header for the
    ;; algorithm description. ---

    ;; Returns all-lowers first, then one multi-index per axis with that
    ;; single axis incremented by 1 (staying in-domain if the axis width
    ;; permits, else left at its lower bound). Probing the array's affine
    ;; indexer at the base and at each of these recovers base + per-axis
    ;; strides. Mirrors the reference impl's %%compute-multi-index-increments.
    (define (%reshape-index-increments lowers uppers)
      (if (null? lowers)
          (list lowers)
          (let* ((rest (%reshape-index-increments (cdr lowers) (cdr uppers)))
                 (lower (car lowers))
                 (upper (car uppers))
                 (next (+ lower 1)))
            (cons (cons lower (car rest))
                  (cons (cons (if (< next upper) next lower) (car rest))
                        (map (lambda (mi) (cons lower mi)) (cdr rest)))))))

    ;; Keep vector element k iff (pred k) -- filters BY INDEX, not by value.
    (define (%vector-filter-by-index pred v)
      (let loop ((k 0) (acc '()))
        (if (= k (vector-length v))
            (list->vector (reverse acc))
            (loop (+ k 1) (if (pred k) (cons (vector-ref v k) acc) acc)))))

    ;; base + sum_i strides_i * (index_i - lower_i) -- the generic affine
    ;; body-offset indexer the NumPy grouping produces.
    (define (%reshape-affine-indexer base lowers strides)
      (lambda multi-index
        (let loop ((acc base) (mi multi-index) (lo lowers) (st strides))
          (if (null? mi)
              acc
              (loop (+ acc (* (car st) (- (car mi) (car lo))))
                    (cdr mi) (cdr lo) (cdr st))))))

    (define (specialized-array-reshape array new-domain . maybe-copy-on-failure)
      (unless (specialized-array? array) (error "specialized-array-reshape: not a specialized array" array))
      (unless (interval? new-domain) (error "specialized-array-reshape: not an interval" new-domain))
      (unless (= (interval-volume new-domain) (interval-volume (array-domain array)))
        (error "specialized-array-reshape: new-domain volume does not match array's volume" new-domain array))
      (let ((copy-on-failure? (if (null? maybe-copy-on-failure) #f (car maybe-copy-on-failure))))
        (%check-boolean! copy-on-failure? "specialized-array-reshape: copy-on-failure?")
        (%specialized-array-reshape array new-domain copy-on-failure?)))

    (define (%specialized-array-reshape array new-domain copy-on-failure?)
      (if (array-empty? array)
          ;; any empty array reshapes trivially to any other same-volume
          ;; (also empty) domain -- its getter/setter can never actually
          ;; be invoked, so a placeholder is safe.
          (%make-array new-domain
                       (%safe-getter new-domain (lambda multi-index (error "unreachable: empty array access")))
                       (and (mutable-array? array)
                            (%safe-setter new-domain (lambda (v) #t)
                                          (lambda (val . multi-index) (error "unreachable: empty array access"))))
                       (array-body array) (lambda multi-index 0)
                       (array-storage-class array) (array-safe? array))
          (let* ((indexer (array-indexer array))
                 (domain (array-domain array))
                 (lowers (interval-lower-bounds->list domain))
                 (uppers (interval-upper-bounds->list domain))
                 (sides (interval-widths domain))
                 (increments (%reshape-index-increments lowers uppers))
                 (base (apply indexer (car increments)))
                 (strides (list->vector (map (lambda (mi) (- (apply indexer mi) base))
                                             (cdr increments))))
                 ;; drop the size-1 axes: they contribute no stride and
                 ;; would derail the adjacent-group matching below.
                 (keep? (lambda (i) (not (eqv? 1 (vector-ref sides i)))))
                 (olddims (%vector-filter-by-index keep? sides))
                 (oldstrides (%vector-filter-by-index keep? strides))
                 (newdims (interval-widths new-domain))
                 (newnd (vector-length newdims))
                 (oldnd (vector-length olddims))
                 ;; Any new axis not assigned a stride by the matching below
                 ;; is a width-1 axis, whose (index - lower) term is always 0,
                 ;; so its stride value is never observed -- leaving it 0 is
                 ;; safe (the reference notes NumPy instead sets these to a
                 ;; value; "we leave it zero").
                 (newstrides (make-vector newnd 0))
                 (fail (lambda ()
                         (if copy-on-failure?
                             (%specialized-array-reshape (array-copy array) new-domain #f)
                             (error "specialized-array-reshape: requested reshape is not affinely representable without copying"
                                    array new-domain))))
                 (build
                  (lambda ()
                    (let* ((storage-class (array-storage-class array))
                           (body (array-body array))
                           (new-indexer (%reshape-affine-indexer
                                         base
                                         (interval-lower-bounds->list new-domain)
                                         (vector->list newstrides)))
                           (safe? (array-safe? array))
                           (mutable? (mutable-array? array))
                           (raw-getter (lambda multi-index
                                         ((storage-class-getter storage-class) body (apply new-indexer multi-index))))
                           (raw-setter (lambda (val . multi-index)
                                         ((storage-class-setter storage-class) body (apply new-indexer multi-index) val)))
                           (getter (%safe-getter new-domain raw-getter))
                           (setter (and mutable?
                                        (%safe-setter new-domain (storage-class-checker storage-class) raw-setter))))
                      (%make-array/unsafe new-domain getter setter body new-indexer storage-class safe?
                                          raw-getter (and mutable? raw-setter))))))
            ;; NumPy's _attempt_nocopy_reshape, transcribed. Walk minimal
            ;; adjacent-axis groups of equal volume in the old and new
            ;; shapes; within each old group require C-contiguity so one
            ;; affine stride covers it, then derive the new group's strides.
            (let loop-1 ((oi 0) (oj 1) (ni 0) (nj 1))
              (if (and (< ni newnd) (< oi oldnd))
                  (let loop-2 ((nj nj) (oj oj)
                               (np (vector-ref newdims ni))
                               (op (vector-ref olddims oi)))
                    (if (not (= np op))
                        (if (< np op)
                            (loop-2 (+ nj 1) oj (* np (vector-ref newdims nj)) op)
                            (loop-2 nj (+ oj 1) np (* op (vector-ref olddims oj))))
                        (let loop-3 ((ok oi))
                          (if (< ok (- oj 1))
                              (if (not (= (vector-ref oldstrides ok)
                                          (* (vector-ref olddims (+ ok 1))
                                             (vector-ref oldstrides (+ ok 1)))))
                                  (fail)
                                  (loop-3 (+ ok 1)))
                              (begin
                                (vector-set! newstrides (- nj 1) (vector-ref oldstrides (- oj 1)))
                                (let loop-4 ((nk (- nj 1)))
                                  (if (< ni nk)
                                      (begin
                                        (vector-set! newstrides (- nk 1)
                                                     (* (vector-ref newstrides nk) (vector-ref newdims nk)))
                                        (loop-4 (- nk 1)))
                                      (loop-1 oj (+ oj 1) nj (+ nj 1)))))))))
                  (build))))))))
