;;; SRFI 231 -- Multi-array assembly (phase 5, the final content phase,
;;; of #1694's SRFI 231 slice). Builds on all prior phases (intervals,
;;; storage classes, core array object, views/sharing, bulk
;;; combinators). See intervals.sld's header for the overall roadmap;
;;; only assembling this file's exports into a public lib/srfi/231.sld
;;; re-export hub remains after this.
;;;
;;; array-assign! is the odd one out in this cluster: unlike
;;; stack/decurry/append/block, it has no bang-less/bang-ful pair (just
;;; itself) and is intrinsically NOT call/cc safe (it explicitly mutates
;;; destination in place, interleaved get-then-set per index in
;;; lexicographic order -- confirmed via the reference implementation,
;;; since the spec's own prose is ambiguous between "read all, then
;;; write all" and "interleaved"; the spec's own aliasing warning --
;;; "if assigning any element of destination affects the value of any
;;; element of source, the result is undefined" -- only makes sense
;;; under an interleaved implementation with no isolation copy).
;;; Requires EXACT domain equality (interval=, confirmed via the spec's
;;; own regression test showing same-volume-but-different-domain is
;;; explicitly rejected, not merely discouraged) and returns an
;;; unspecified value (confirmed via the reference implementation
;;; returning (void), not destination).
;;;
;;; array-stack/array-decurry/array-append/array-block all follow the
;;; same shape already established for every specialized-array
;;; constructor in this codebase: build a plain (lazy, immutable)
;;; virtual array over the computed result domain, then delegate
;;; entirely to array-copy (already handling storage-class/mutable?/
;;; safe? option parsing and the materializing fill loop) rather than
;;; hand-rolling a separate fill mechanism per procedure. Their `!`
;;; twins are implemented as pure aliases of the non-! version -- a
;;; scope reduction already established for array-copy/array-copy! in
;;; phase 3, now confirmed for these four too by reading the reference
;;; implementation directly: every one of these four's `!` and non-`!`
;;; entry points are two one-line wrappers around one shared internal
;;; helper differing only in whether input arrays are eagerly
;;; materialized before the fill runs, a distinction that is only
;;; observable under the exotic multi-shot-continuation-re-entry
;;; scenario the spec itself declares "an error" to trigger.
(define-library (srfi 231 assembly)
  (import (scheme base) (srfi 1)
          (srfi 231 misc) (srfi 231 intervals) (srfi 231 storage-classes)
          (srfi 231 arrays) (srfi 231 views) (srfi 231 combinators))
  (export array-assign!
          array-stack array-stack!
          array-decurry array-decurry!
          array-append array-append!
          array-block array-block!)
  (begin

    ;; offsets is a vector of n+1 cumulative boundaries; find i such that
    ;; offsets[i] <= j < offsets[i+1]. Linear scan -- the segment counts
    ;; involved here (list length for stack/append, one axis's width for
    ;; block) are never large enough to justify a binary search.
    (define (%find-segment offsets j)
      (let loop ((i 0))
        (if (< j (vector-ref offsets (+ i 1))) i (loop (+ i 1)))))

    ;; Intrinsically not call/cc safe -- explicitly mutates destination,
    ;; interleaved get-then-set per index in lexicographic order.
    ;; Returns an unspecified value.
    (define (array-assign! destination source)
      (unless (mutable-array? destination) (error "array-assign!: destination must be mutable" destination))
      (unless (array? source) (error "array-assign!: source is not an array" source))
      (unless (interval= (array-domain destination) (array-domain source))
        (error "array-assign!: destination and source must have the same domain" destination source))
      (let ((dest-setter (array-setter destination)) (src-getter (array-getter source)))
        (interval-for-each (lambda multi-index (apply dest-setter (apply src-getter multi-index) multi-index))
                            (array-domain destination))))

    ;; Stacks arrays (a nonempty list, all with IDENTICAL domains) along
    ;; a NEW k'th axis (0 <= k <= dimension, inclusive of the dimension
    ;; itself -- appending after the last existing axis is legal). The
    ;; new axis has lower bound 0 and upper bound (length arrays); every
    ;; other axis keeps its original relative order, shifted right past
    ;; position k. A partial inverse of array-curry.
    (define (array-stack k arrays . opts)
      (unless (and (list? arrays) (pair? arrays)) (error "array-stack: arrays must be a nonempty list" arrays))
      (let* ((first (car arrays)) (base-domain (array-domain first)) (d (array-dimension first)) (n (length arrays)))
        (for-each (lambda (a) (unless (interval= (array-domain a) base-domain)
                                (error "array-stack: all arrays must have the same domain" arrays)))
                  arrays)
        (unless (and (integer? k) (exact? k) (<= 0 k d)) (error "array-stack: k out of range" k d))
        (let* ((lowers (interval-lower-bounds->list base-domain))
               (uppers (interval-upper-bounds->list base-domain))
               (new-domain (make-interval (list->vector (append (take lowers k) (cons 0 (drop lowers k))))
                                           (list->vector (append (take uppers k) (cons n (drop uppers k))))))
               (getters (list->vector (map array-getter arrays)))
               (virtual (make-array
                         new-domain
                         (lambda multi-index
                           (let ((i (list-ref multi-index k)))
                             (apply (vector-ref getters i)
                                    (append (take multi-index k) (drop multi-index (+ k 1)))))))))
          (apply array-copy virtual opts))))

    (define (array-stack! k arrays . opts) (apply array-stack k arrays opts))

    ;; Takes a "curried" array of arrays (all inner arrays sharing one
    ;; common domain -- actively validated here, matching the reference
    ;; implementation's stricter-than-the-bare-spec behavior) and returns
    ;; a single specialized array with domain (interval-cartesian-product
    ;; outer-domain inner-domain) -- outer axes first, inner axes second.
    ;; An inverse to array-curry; a multi-dimensional version of
    ;; array-stack.
    (define (array-decurry AofA . opts)
      (unless (array? AofA) (error "array-decurry: not an array" AofA))
      (when (array-empty? AofA) (error "array-decurry: outer array must be nonempty" AofA))
      (let* ((outer-domain (array-domain AofA))
             (outer-d (array-dimension AofA))
             (outer-getter (array-getter AofA))
             (sample-inner (apply outer-getter (interval-lower-bounds->list outer-domain)))
             (inner-domain (array-domain sample-inner)))
        (interval-for-each
         (lambda multi-index
           (unless (interval= (array-domain (apply outer-getter multi-index)) inner-domain)
             (error "array-decurry: not all elements of the outer array have the same domain" AofA)))
         outer-domain)
        (let* ((new-domain (interval-cartesian-product outer-domain inner-domain))
               (virtual (make-array
                         new-domain
                         (lambda multi-index
                           (let ((outer-idx (take multi-index outer-d)) (inner-idx (drop multi-index outer-d)))
                             (apply (array-getter (apply outer-getter outer-idx)) inner-idx))))))
          (apply array-copy virtual opts))))

    (define (array-decurry! AofA . opts) (apply array-decurry AofA opts))

    ;; Concatenates a nonempty list of arrays along an EXISTING axis k
    ;; (0 <= k < dimension, exclusive of the dimension -- unlike stack's
    ;; inclusive range, since k must name an axis that already exists).
    ;; All arrays must agree exactly (same lower AND upper bound) on
    ;; every axis except k; the result's k'th axis has its lower bound
    ;; reset to 0 and width equal to the sum of each input's own k'th
    ;; width. A partial inverse of array-tile.
    (define (array-append k arrays . opts)
      (unless (and (list? arrays) (pair? arrays)) (error "array-append: arrays must be a nonempty list" arrays))
      (let* ((first (car arrays)) (d (array-dimension first)) (first-domain (array-domain first)))
        (unless (and (integer? k) (exact? k) (<= 0 k) (< k d)) (error "array-append: k out of range" k d))
        (for-each
         (lambda (a)
           (unless (= (array-dimension a) d) (error "array-append: dimension mismatch" arrays))
           (let loop ((i 0))
             (when (< i d)
               (unless (or (= i k)
                           (and (= (interval-lower-bound (array-domain a) i) (interval-lower-bound first-domain i))
                                (= (interval-upper-bound (array-domain a) i) (interval-upper-bound first-domain i))))
                 (error "array-append: domains must agree on every axis except k" arrays))
               (loop (+ i 1)))))
         arrays)
        (let* ((n (length arrays))
               (widths (list->vector (map (lambda (a) (interval-width (array-domain a) k)) arrays)))
               (offsets (make-vector (+ n 1) 0)))
          (let loop ((i 0))
            (when (< i n)
              (vector-set! offsets (+ i 1) (+ (vector-ref offsets i) (vector-ref widths i)))
              (loop (+ i 1))))
          (let* ((total-width (vector-ref offsets n))
                 (new-lowers (interval-lower-bounds->vector first-domain))
                 (new-uppers (interval-upper-bounds->vector first-domain))
                 (base-lowers-k (list->vector (map (lambda (a) (interval-lower-bound (array-domain a) k)) arrays)))
                 (arr-vec (list->vector arrays)))
            (vector-set! new-lowers k 0)
            (vector-set! new-uppers k total-width)
            (let* ((new-domain (make-interval new-lowers new-uppers))
                   (virtual
                    (make-array
                     new-domain
                     (lambda multi-index
                       (let* ((j (list-ref multi-index k))
                              (seg (%find-segment offsets j))
                              (local-j (+ (- j (vector-ref offsets seg)) (vector-ref base-lowers-k seg))))
                         (apply (array-getter (vector-ref arr-vec seg))
                                (map (lambda (idx val) (if (= idx k) local-j val)) (iota d) multi-index)))))))
              (apply array-copy virtual opts))))))

    (define (array-append! k arrays . opts) (apply array-append k arrays opts))

    ;; Per-axis width-consistency validation for array-block: for every
    ;; axis k, partition AofA into 1-D "slices" perpendicular to k (move
    ;; k to the front, curry away the rest) and confirm every slice's own
    ;; blocks (which vary over every axis EXCEPT k) share one common k'th
    ;; width -- directly reusing array-curry/array-permute/index-first
    ;; rather than hand-rolling a separate traversal.
    (define (%array-block-validate-widths AofA d)
      (let loop ((k 0))
        (when (< k d)
          (let ((slices (array-curry (array-permute AofA (index-first d k)) (- d 1))))
            (unless (array-every
                     (lambda (slice)
                       (let ((widths (map (lambda (a) (interval-width (array-domain a) k)) (array->list slice))))
                         (or (null? widths) (every (lambda (w) (= (car widths) w)) (cdr widths)))))
                     slices)
              (error "array-block: elements cannot be assembled into a consistent block structure" AofA k)))
          (loop (+ k 1)))))

    ;; Per-axis cumulative offsets, found by probing exactly one
    ;; representative "pencil" (a 1-D line of blocks along axis k, all
    ;; other outer-indices held at 0) rather than re-scanning the whole
    ;; array again -- valid only because %array-block-validate-widths
    ;; already proved every other line parallel to it has the identical
    ;; width profile. Assumes A's own domain already has all-zero lower
    ;; bounds (the caller normalizes this first), so "all other
    ;; outer-indices at 0" is always a valid probe point.
    (define (%array-block-axis-offsets A d k)
      (let* ((pencil (apply (array-getter (array-curry (array-permute A (index-last d k)) 1))
                             (make-list (- d 1) 0)))
             (pencil-getter (array-getter pencil))
             (pencil-size (interval-width (array-domain pencil) 0))
             (offsets (make-vector (+ pencil-size 1) 0)))
        (let loop ((i 0))
          (when (< i pencil-size)
            (vector-set! offsets (+ i 1) (+ (vector-ref offsets i) (interval-width (array-domain (pencil-getter i)) k)))
            (loop (+ i 1))))
        offsets))

    ;; Assembles a d-dimensional array of d-dimensional blocks (every
    ;; block must have the same rank as AofA itself, actively validated)
    ;; into one flat specialized array by tiling them together. Full
    ;; inverse of array-tile; multi-dimensional generalization of
    ;; array-append. AofA's own domain is normalized to zero lower bounds
    ;; first so every "corner"/pencil-start probe used by validation and
    ;; offset computation is always literally an all-zeros multi-index,
    ;; matching the reference implementation's own approach and avoiding
    ;; having to track bounds by hand through the axis permutations both
    ;; helpers perform internally.
    (define (array-block AofA . opts)
      (unless (array? AofA) (error "array-block: not an array" AofA))
      (when (array-empty? AofA) (error "array-block: outer array must be nonempty" AofA))
      (let* ((d (array-dimension AofA))
             (orig-lowers (interval-lower-bounds->vector (array-domain AofA)))
             (orig-getter (array-getter AofA)))
        (interval-for-each
         (lambda multi-index
           (unless (= (array-dimension (apply orig-getter multi-index)) d)
             (error "array-block: not all elements have the same dimension as the outer array" AofA)))
         (array-domain AofA))
        (let* ((A (array-translate (array-copy AofA) (vector-map - orig-lowers)))
               (A-getter (array-getter A)))
          (%array-block-validate-widths A d)
          (let* ((offsets (list->vector (map (lambda (k) (%array-block-axis-offsets A d k)) (iota d))))
                 (new-uppers (vector-map (lambda (offs) (vector-ref offs (- (vector-length offs) 1))) offsets))
                 (new-domain (make-interval new-uppers))
                 (virtual
                  (make-array
                   new-domain
                   (lambda multi-index
                     (let* ((mi-vec (list->vector multi-index))
                            (outer-idx (make-vector d 0))
                            (local-idx (make-vector d 0)))
                       (let loop ((k 0))
                         (when (< k d)
                           (let* ((offs (vector-ref offsets k)) (j (vector-ref mi-vec k)) (seg (%find-segment offs j)))
                             (vector-set! outer-idx k seg)
                             (vector-set! local-idx k (- j (vector-ref offs seg))))
                           (loop (+ k 1))))
                       (let* ((block (apply A-getter (vector->list outer-idx)))
                              (block-lowers (interval-lower-bounds->vector (array-domain block))))
                         (apply (array-getter block) (vector->list (vector-map + local-idx block-lowers)))))))))
            (apply array-copy virtual opts)))))

    (define (array-block! AofA . opts) (apply array-block AofA opts))))
