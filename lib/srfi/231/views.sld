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
;;; library NumPy" and not specified in prose beyond that -- the
;;; reference implementation's actual algorithm (empirically probing
;;; strides, filtering size-1 axes, greedily matching adjacent-axis
;;; volume groups between old and new shapes, verifying C-contiguity
;;; within each group) is substantially more general than what's
;;; implemented here. This port deliberately implements a conservative
;;; special case instead: reshape succeeds zero-copy whenever the SOURCE
;;; array is already array-packed? (the overwhelmingly common real case,
;;; e.g. reshaping a fresh array-copy result), using a plain row-major
;;; reindex; otherwise it behaves exactly as the spec allows for a
;;; failed detection (error, or a forced copy-then-retry when
;;; copy-on-failure? is #t). This never wrongly claims an affine map
;;; exists (so it's never incorrect), but is more conservative than the
;;; full algorithm for some non-packed-but-still-affinely-reshapable
;;; arrays (e.g. some genuinely strided views) -- confirmed against both
;;; of the spec's own worked examples (a packed array reshaping
;;; successfully; a array-sample'd non-packed array failing without
;;; copy-on-failure? and succeeding with it), which this simplification
;;; handles identically to the full algorithm.
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
             (getter (if safe? (%safe-getter new-domain raw-getter) raw-getter))
             (setter (and mutable?
                          (if safe? (%safe-setter new-domain (storage-class-checker storage-class) raw-setter) raw-setter))))
        (%make-array new-domain getter setter body new-indexer storage-class safe?)))

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
    (define (%tile-cut-offsets width lower Sk)
      (cond
       ((and (integer? Sk) (exact? Sk) (positive? Sk))
        (let* ((n (quotient (+ width (- Sk 1)) Sk))
               (offsets (make-vector (+ n 1) lower)))
          (let loop ((i 1))
            (when (<= i n)
              (vector-set! offsets i (min (+ lower (* i Sk)) (+ lower width)))
              (loop (+ i 1))))
          offsets))
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
              (vector-set! cuts k (%tile-cut-offsets (vector-ref widths k) (vector-ref lowers k) (vector-ref S k)))
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
    ;; array-copy! is documented to differ from array-copy only in
    ;; call/cc re-entrancy safety during the fill (the spec permits it to
    ;; be faster/leaner by skipping a safety guarantee, never in the
    ;; final result for an ordinary, non-continuation-abusing caller);
    ;; this port implements both identically (a direct fill loop, no
    ;; accumulate-to-a-list-first indirection) as a deliberate, documented
    ;; scope reduction -- getters that escape and re-invoke a captured
    ;; continuation mid-copy are exotic enough that the extra allocation
    ;; and complexity isn't justified for this phase.
    (define (%array-copy-impl array opts)
      (unless (array? array) (error "array-copy: not an array" array))
      (let* ((specialized? (specialized-array? array))
             (storage-class (%opt opts 0 (if specialized? (array-storage-class array) generic-storage-class)))
             (mutable? (%opt opts 1 (if specialized? (mutable-array? array) (specialized-array-default-mutable?))))
             (safe? (%opt opts 2 (if specialized? (array-safe? array) (specialized-array-default-safe?))))
             (domain (array-domain array))
             (getter (array-getter array))
             (dest (make-specialized-array domain storage-class (storage-class-default storage-class) safe?))
             (dest-setter (array-setter dest)))
        (interval-for-each (lambda multi-index (apply dest-setter (apply getter multi-index) multi-index)) domain)
        (if mutable? dest (array-freeze! dest))))

    (define (array-copy array . opts) (%array-copy-impl array opts))
    (define (array-copy! array . opts) (%array-copy-impl array opts))

    ;; --- specialized-array-reshape: see the file header for the
    ;; documented conservative simplification (packed-check based rather
    ;; than the reference implementation's full NumPy-derived multi-group
    ;; stride-matching algorithm). ---

    (define (specialized-array-reshape array new-domain . maybe-copy-on-failure)
      (unless (specialized-array? array) (error "specialized-array-reshape: not a specialized array" array))
      (unless (interval? new-domain) (error "specialized-array-reshape: not an interval" new-domain))
      (unless (= (interval-volume new-domain) (interval-volume (array-domain array)))
        (error "specialized-array-reshape: new-domain volume does not match array's volume" new-domain array))
      (let ((copy-on-failure? (if (null? maybe-copy-on-failure) #f (car maybe-copy-on-failure))))
        (cond
         ((array-empty? array)
          ;; any empty array reshapes trivially to any other same-volume
          ;; (also empty) domain -- its getter/setter can never actually
          ;; be invoked, so a placeholder is safe.
          (%make-array new-domain
                       (%safe-getter new-domain (lambda multi-index (error "unreachable: empty array access")))
                       (and (mutable-array? array)
                            (%safe-setter new-domain (lambda (v) #t)
                                          (lambda (val . multi-index) (error "unreachable: empty array access"))))
                       (array-body array) (lambda multi-index 0)
                       (array-storage-class array) (array-safe? array)))
         ((array-packed? array)
          (let* ((storage-class (array-storage-class array))
                 (body (array-body array))
                 (base (apply (array-indexer array) (interval-lower-bounds->list (array-domain array))))
                 (lex (%make-lex-indexer new-domain))
                 (new-indexer (lambda multi-index (+ base (apply lex multi-index))))
                 (safe? (array-safe? array))
                 (mutable? (mutable-array? array))
                 (raw-getter (lambda multi-index
                               ((storage-class-getter storage-class) body (apply new-indexer multi-index))))
                 (raw-setter (lambda (val . multi-index)
                               ((storage-class-setter storage-class) body (apply new-indexer multi-index) val)))
                 (getter (if safe? (%safe-getter new-domain raw-getter) raw-getter))
                 (setter (and mutable?
                              (if safe? (%safe-setter new-domain (storage-class-checker storage-class) raw-setter) raw-setter))))
            (%make-array new-domain getter setter body new-indexer storage-class safe?)))
         (copy-on-failure? (specialized-array-reshape (array-copy array) new-domain #f))
         (else (error "specialized-array-reshape: requested reshape is not affinely representable without copying"
                      array new-domain)))))))
