;;; SRFI 164 -- Enhanced multi-dimensional Arrays.
;;;
;;; An explicit, compatible extension of SRFI 25 (identical shape
;;; representation, share-array copied from its spec text byte for byte) --
;;; not a separate lineage. Implemented as its own independent library
;;; (rather than importing (srfi 25)) because define-record-type field
;;; accessors don't cross library boundaries and this SRFI's array needs a
;;; third, storage-free mode that SRFI 25's record has no room for.
;;;
;;; A shape is a vector of (lower . upper) pairs, one per dimension, exactly
;;; as in SRFI 25 -- deliberately not made to satisfy array? itself (the
;;; spec's "no separate data type for a shape" is compatible with this;
;;; array-shape, new in this SRFI, is the intended way to get a shape back
;;; from an array).
;;;
;;; Scope note: the spec says "every gvector is an array" and recommends a
;;; library-based implementation "should use the existing vector type" for
;;; simple rank-1 zero-lower-bound arrays -- i.e. array? is described as
;;; also being true of a plain R7RS vector. This is a "should" (a
;;; recommendation), not a "must", and honoring it would mean every
;;; array-* procedure needs a parallel plain-vector code path; deliberately
;;; not implemented here. array? in this library is true only for values
;;; constructed by this library's own procedures.
;;;
;;; An array is one of three modes, discriminated by which fields are set:
;;;   - "simple": store is a row-major vector; base/mapper/getter/setter #f.
;;;   - "shared/view": base is set; array-ref/set! translate the index
;;;     through mapper (called with the new array's indices as separate
;;;     arguments, returning the base array's coordinates via multiple
;;;     values -- SRFI 25's share-array convention) and recurse into base's
;;;     own ref/set!, not its raw store. Backs share-array, array-transform,
;;;     array-reshape (non-simple source), and array-index-share.
;;;   - "virtual": getter is set, store/base are #f; array-ref calls getter
;;;     directly, array-set! calls setter (or raises if setter is #f).
;;;     Backs build-array, index-array, and array-index-ref's non-scalar
;;;     case.
;;;
;;; array-transform's transform argument uses a DIFFERENT calling
;;; convention than share-array's proc -- one vector argument in, one
;;; vector result out, per the spec's own explicit contrast between the
;;; two. It is adapted into the shared/view mode's variadic/multiple-values
;;; mapper convention with a one-line wrapper. transform need not be
;;; affine: this implementation never checks or exploits affineness
;;; anywhere (share-array's own affine requirement is stated as an
;;; optimization opportunity, not a correctness requirement), so reusing
;;; the same shared/view mode for a non-affine transform is already
;;; correct with no special-casing.
;;;
;;; array->vector returns the live backing vector for a simple array
;;; (true zero-copy identity, per spec) but a disconnected snapshot copy
;;; for a non-simple array -- the spec calls for a live view there too,
;;; which a literal R7RS vector cannot provide in portable Scheme (vectors
;;; have no hooks, unlike this codebase's custom ports). A deliberate,
;;; documented scope reduction.
(define-library (srfi 164)
  (import (scheme base))
  (export array? make-array shape array
          array-rank array-start array-end
          array-ref array-set!
          share-array
          ->shape array-shape array-size
          build-array index-array
          array-index-ref array-index-share
          array-copy! array-fill!
          array-transform
          array-reshape
          array-flatten
          array->vector)
  (begin

    (define-record-type <array>
      (%make-array-record shape store base mapper getter setter)
      array?
      (shape array-shape-vec)
      (store array-store)
      (base array-base)
      (mapper array-mapper)
      (getter array-getter)
      (setter array-setter))

    (define (%lower shape-vec k) (car (vector-ref shape-vec k)))
    (define (%upper shape-vec k) (cdr (vector-ref shape-vec k)))

    ;; Per spec (inherited from SRFI 25): an array does not retain a
    ;; dependence on the shape argument given to its constructor.
    (define (%copy-shape shape-vec)
      (let* ((n (vector-length shape-vec)) (copy (make-vector n)))
        (let loop ((i 0))
          (when (< i n)
            (let ((pair (vector-ref shape-vec i)))
              (vector-set! copy i (cons (car pair) (cdr pair))))
            (loop (+ i 1))))
        copy))

    (define (%shape-volume shape-vec)
      (let loop ((i 0) (acc 1))
        (if (= i (vector-length shape-vec))
            acc
            (loop (+ i 1) (* acc (- (%upper shape-vec i) (%lower shape-vec i)))))))

    ;; Row-major mixed-radix offset (a shape's flat rank for a multi-index),
    ;; with a per-dimension bounds check.
    (define (%row-major-offset shape-vec indices)
      (let loop ((i 0) (idxs indices) (acc 0))
        (if (null? idxs)
            acc
            (let ((lo (%lower shape-vec i))
                  (hi (%upper shape-vec i))
                  (ix (car idxs)))
              (unless (and (integer? ix) (<= lo ix) (< ix hi))
                (error "array-ref/array-set!: index out of range for dimension" i ix))
              (loop (+ i 1) (cdr idxs) (+ (* acc (- hi lo)) (- ix lo)))))))

    ;; Inverse of %row-major-offset: decompose a flat rank back into a
    ;; multi-index for a given shape.
    (define (%unrank shape-vec rank)
      (let* ((d (vector-length shape-vec)) (widths (make-vector d)))
        (let loop ((i 0))
          (when (< i d)
            (vector-set! widths i (- (%upper shape-vec i) (%lower shape-vec i)))
            (loop (+ i 1))))
        (let loop ((i (- d 1)) (r rank) (acc '()))
          (if (< i 0)
              acc
              (let ((w (vector-ref widths i)))
                (loop (- i 1) (quotient r w) (cons (+ (%lower shape-vec i) (remainder r w)) acc)))))))

    (define (%same-shape? s1 s2)
      (and (= (vector-length s1) (vector-length s2))
           (let loop ((i 0))
             (or (= i (vector-length s1))
                 (and (= (%lower s1 i) (%lower s2 i))
                      (= (%upper s1 i) (%upper s2 i))
                      (loop (+ i 1)))))))

    ;; Visit every multi-index of shape-vec in row-major order.
    (define (%for-each-index shape-vec proc)
      (let ((rank (vector-length shape-vec)))
        (define (go dim acc)
          (if (= dim rank)
              (proc (reverse acc))
              (let ((lo (%lower shape-vec dim)) (hi (%upper shape-vec dim)))
                (let iter ((i lo))
                  (when (< i hi)
                    (go (+ dim 1) (cons i acc))
                    (iter (+ i 1)))))))
        (go 0 '())))

    (define (%split-last lst)
      (let loop ((lst lst) (acc '()))
        (if (null? (cdr lst))
            (values (reverse acc) (car lst))
            (loop (cdr lst) (cons (car lst) acc)))))

    (define (%index-value->list x)
      (cond
       ((vector? x) (vector->list x))
       ((array? x)
        (unless (= (array-rank x) 1)
          (error "array-ref/array-set!: packed index array must be 1-dimensional" x))
        (unless (= 0 (array-start x 0))
          (error "array-ref/array-set!: packed index array must be 0-based" x))
        (let ((end (array-end x 0)))
          (let loop ((i 0) (acc '()))
            (if (= i end) (reverse acc) (loop (+ i 1) (cons (array-ref x i) acc))))))
       (else (error "array-ref/array-set!: invalid packed index" x))))

    (define (%normalize-indices idx-args)
      (if (and (pair? idx-args) (null? (cdr idx-args))
               (let ((x (car idx-args))) (or (vector? x) (array? x))))
          (%index-value->list (car idx-args))
          idx-args))

    (define (%check-rank! a indices who)
      (unless (= (length indices) (array-rank a))
        (error (string-append who ": wrong number of indices") a indices)))

    (define (%array-ref-indices a indices)
      (let ((store (array-store a)))
        (if store
            (vector-ref store (%row-major-offset (array-shape-vec a) indices))
            (let ((base (array-base a)))
              (if base
                  (%array-ref-indices
                   base
                   (call-with-values (lambda () (apply (array-mapper a) indices)) list))
                  (apply (array-getter a) indices))))))

    (define (%array-set-indices! a indices obj)
      (let ((store (array-store a)))
        (if store
            (vector-set! store (%row-major-offset (array-shape-vec a) indices) obj)
            (let ((base (array-base a)))
              (if base
                  (%array-set-indices!
                   base
                   (call-with-values (lambda () (apply (array-mapper a) indices)) list)
                   obj)
                  (let ((setter (array-setter a)))
                    (if setter
                        (apply setter obj indices)
                        (error "array-set!: array is immutable (no setter)" a))))))))

    ;; --- the 10 procedures inherited from SRFI 25 ---

    (define (shape . bounds)
      (let ((n (length bounds)))
        (unless (even? n) (error "shape: odd number of bounds" bounds))
        (let ((vec (make-vector (quotient n 2))))
          (let loop ((i 0) (bs bounds))
            (if (null? bs)
                vec
                (let ((lo (car bs)) (hi (cadr bs)))
                  (unless (<= lo hi) (error "shape: lower bound exceeds upper bound" lo hi))
                  (vector-set! vec i (cons lo hi))
                  (loop (+ i 1) (cddr bs))))))))

    ;; Unlike SRFI 25, this SRFI's make-array accepts multiple fill values,
    ;; cycling through them until the array is full.
    ;;
    ;; Per spec, "the procedures in this specification that require a
    ;; shape can accept a shape-specifier, as if converted by the
    ;; procedure ->shape" -- every shape-taking procedure below coerces
    ;; through ->shape rather than assuming an already-canonical shape.
    ;; ->shape always returns a fresh vector (even its passthrough branch
    ;; conses new pairs), so this also satisfies the "does not retain a
    ;; dependence on the shape argument" requirement without a separate copy.
    (define (make-array shape . values)
      (let* ((canonical (->shape shape))
             (size (%shape-volume canonical))
             (store (make-vector size #f)))
        (when (pair? values)
          (let loop ((i 0) (vs values))
            (when (< i size)
              (vector-set! store i (car vs))
              (loop (+ i 1) (if (null? (cdr vs)) values (cdr vs))))))
        (%make-array-record canonical store #f #f #f #f)))

    (define (array shape . objs)
      (let* ((canonical (->shape shape)) (size (%shape-volume canonical)))
        (unless (= size (length objs))
          (error "array: wrong number of initial values for shape" size (length objs)))
        (%make-array-record canonical (list->vector objs) #f #f #f #f)))

    (define (array-rank a) (vector-length (array-shape-vec a)))
    (define (array-start a k) (%lower (array-shape-vec a) k))
    (define (array-end a k) (%upper (array-shape-vec a) k))

    (define (array-ref a . idx-args)
      (let ((indices (%normalize-indices idx-args)))
        (%check-rank! a indices "array-ref")
        (%array-ref-indices a indices)))

    (define (array-set! a . args)
      (call-with-values
       (lambda () (%split-last args))
       (lambda (idx-args obj)
         (let ((indices (%normalize-indices idx-args)))
           (%check-rank! a indices "array-set!")
           (%array-set-indices! a indices obj)
           (if #f #f)))))

    (define (share-array a shape proc)
      (%make-array-record (->shape shape) #f a proc #f #f))

    ;; --- the 13 procedures new in SRFI 164 ---

    ;; Checks the same lo <= hi (and exactness) constraint as `shape`, so
    ;; a bad specifier element fails right here with a reference to the
    ;; element, rather than surfacing later as an obscure make-vector/
    ;; vector-ref error somewhere downstream.
    (define (%check-bounds! who lo hi elt)
      (unless (and (exact? lo) (exact? hi) (<= lo hi))
        (error (string-append who ": invalid bounds in shape specifier element") elt)))

    (define (->shape specifier)
      (let* ((n (vector-length specifier)) (vec (make-vector n)))
        (let loop ((i 0))
          (if (= i n)
              vec
              (begin
                (vector-set!
                 vec i
                 (let ((elt (vector-ref specifier i)))
                   (cond
                    ((and (pair? elt) (integer? (car elt)) (integer? (cdr elt)))
                     (%check-bounds! "->shape" (car elt) (cdr elt) elt)
                     (cons (car elt) (cdr elt)))
                    ((and (pair? elt) (integer? (car elt)) (pair? (cdr elt))
                          (integer? (cadr elt)) (null? (cddr elt)))
                     (%check-bounds! "->shape" (car elt) (cadr elt) elt)
                     (cons (car elt) (cadr elt)))
                    ((and (integer? elt) (exact? elt) (>= elt 0))
                     (cons 0 elt))
                    (else (error "->shape: invalid shape specifier element" elt)))))
                (loop (+ i 1)))))))

    (define (array-shape a) (%copy-shape (array-shape-vec a)))
    (define (array-size a) (%shape-volume (array-shape-vec a)))

    ;; Per spec, build-array's getter is called with a single argument (an
    ;; index vector) and its setter (if any) with two arguments (an index
    ;; vector, then the new value) -- a different convention than this
    ;; library's internal variadic-indices/value-first dispatch, so both
    ;; are adapted at this boundary.
    (define (build-array shape getter . setter)
      (%make-array-record
       (->shape shape) #f #f #f
       (lambda indices (getter (list->vector indices)))
       (if (pair? setter)
           (let ((user-setter (car setter)))
             (lambda (value . indices) (user-setter (list->vector indices) value)))
           #f)))

    (define (index-array shape)
      (let ((shape-copy (->shape shape)))
        (%make-array-record shape-copy #f #f #f
                             (lambda indices (%row-major-offset shape-copy indices))
                             #f)))

    ;; Shared resolver for array-index-ref / array-index-share: each of
    ;; `indices` is an integer or an array; the result's shape is the
    ;; concatenation of every array-valued index's own shape, and reading
    ;; result-index j means splitting j into per-original-dimension
    ;; segments and, per dimension, using the integer directly or looking
    ;; it up via (array-ref that-index-array segment...). Written as flat,
    ;; separately-named top-level helpers rather than deeply nested
    ;; internal defines/lets, so each piece's parenthesization stays easy
    ;; to check by eye.
    (define (%index-shape-parts specs)
      (if (null? specs)
          '()
          (if (integer? (car specs))
              (%index-shape-parts (cdr specs))
              (append (vector->list (%copy-shape (array-shape-vec (car specs))))
                      (%index-shape-parts (cdr specs))))))

    (define (%index-take specs remaining acc)
      (if (null? specs)
          (reverse acc)
          (if (integer? (car specs))
              (%index-take (cdr specs) remaining (cons (car specs) acc))
              (%index-take-array (car specs) (cdr specs) remaining acc))))

    (define (%index-take-array spec specs remaining acc)
      (%index-take-seg spec specs (array-rank spec) remaining '() acc))

    (define (%index-take-seg spec specs k rem seg acc)
      (if (= k 0)
          (%index-take specs rem (cons (apply array-ref spec (reverse seg)) acc))
          (%index-take-seg spec specs (- k 1) (cdr rem) (cons (car rem) seg) acc)))

    ;; resolver takes ONE argument that is already a list of new-indices
    ;; (its callers always pass an already-collected list, e.g. from a
    ;; rest-parameter lambda or '()) -- a fixed single parameter, not a
    ;; rest parameter, or calling it with a pre-built list would wrap it
    ;; in an extra layer.
    (define (%index-resolve indices)
      (values
       (list->vector (%index-shape-parts indices))
       (lambda (new-indices) (%index-take indices new-indices '()))))

    (define (array-index-ref a . indices)
      (call-with-values
       (lambda () (%index-resolve indices))
       (lambda (result-shape resolver)
         (if (= 0 (vector-length result-shape))
             (apply array-ref a (resolver '()))
             (build-array result-shape
                          (lambda (index-vec) (apply array-ref a (resolver (vector->list index-vec)))))))))

    (define (array-index-share a . indices)
      (call-with-values
       (lambda () (%index-resolve indices))
       (lambda (result-shape resolver)
         (if (= 0 (vector-length result-shape))
             (share-array a (shape) (lambda () (apply values (resolver '()))))
             (share-array a result-shape (lambda new-indices (apply values (resolver new-indices))))))))

    (define (array-copy! dst src)
      (unless (%same-shape? (array-shape-vec dst) (array-shape-vec src))
        (error "array-copy!: destination and source must have the same shape" dst src))
      (%for-each-index (array-shape-vec src)
                        (lambda (idx) (%array-set-indices! dst idx (%array-ref-indices src idx)))))

    (define (array-fill! a value)
      (%for-each-index (array-shape-vec a) (lambda (idx) (%array-set-indices! a idx value))))

    (define (array-transform a shape transform)
      (%make-array-record (->shape shape) #f a
                           (lambda indices (apply values (vector->list (transform (list->vector indices)))))
                           #f #f))

    (define (array-reshape a shape)
      (let ((new-shape (->shape shape)))
        (unless (= (%shape-volume new-shape) (array-size a))
          (error "array-reshape: new shape must have the same volume as the original array" shape a))
        (let ((store (array-store a)))
          (if store
              (%make-array-record new-shape store #f #f #f #f)
              (let ((old-shape (array-shape-vec a)))
                (%make-array-record
                 new-shape #f a
                 (lambda new-indices
                   (apply values (%unrank old-shape (%row-major-offset new-shape new-indices))))
                 #f #f))))))

    (define (array-flatten a)
      (let* ((size (array-size a)) (result (make-array (shape 0 size) #f)) (i 0))
        (%for-each-index (array-shape-vec a)
                          (lambda (idx)
                            (%array-set-indices! result (list i) (%array-ref-indices a idx))
                            (set! i (+ i 1))))
        result))

    (define (array->vector a)
      (or (array-store a)
          (let* ((size (array-size a)) (vec (make-vector size)) (i 0))
            (%for-each-index (array-shape-vec a)
                              (lambda (idx)
                                (vector-set! vec i (%array-ref-indices a idx))
                                (set! i (+ i 1))))
            vec)))))
