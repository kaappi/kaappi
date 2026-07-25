;;; SRFI 25 -- Multi-dimensional Array Primitives.
;;;
;;; Arrays are heterogeneous (arbitrary Scheme objects) with no spec-defined
;;; internal representation and no relationship to SRFI 4/160's numeric
;;; vectors -- a record wrapping a plain vector is spec-sufficient, so this
;;; library is pure portable Scheme.
;;;
;;; A shape is represented as a vector of (lower . upper) pairs, one per
;;; dimension. The spec's own "a shape is itself a d-by-2 array" framing is
;;; never operationally tested by any of the 10 mandated procedures (there is
;;; no shape? and no way to recover a shape back from an array), so shapes
;;; deliberately do not satisfy array? here.
;;;
;;; An array is either "simple" (store is a row-major vector, base/mapper
;;; are #f) or "shared" (store is #f; base is the underlying array and mapper
;;; is an affine index-translation procedure). array-ref/array-set! on a
;;; shared array translate the index through mapper and recurse into base's
;;; own ref/set! -- not into base's raw store -- so arbitrarily nested shared
;;; views work correctly at the cost of O(depth) indirection per access. The
;;; spec's own rationale for the affine restriction is that composed affine
;;; maps *could* be collapsed to O(1), but this is a stated optimization
;;; opportunity, not a requirement; recursive delegation is fully conformant.
(define-library (srfi 25)
  (import (scheme base))
  (export array? make-array shape array
          array-rank array-start array-end
          array-ref array-set!
          share-array)
  (begin

    (define-record-type <array>
      (%make-array-record shape store base mapper)
      array?
      (shape array-shape-vec)
      (store array-store)
      (base array-base)
      (mapper array-mapper))

    (define (%lower shape-vec k) (car (vector-ref shape-vec k)))
    (define (%upper shape-vec k) (cdr (vector-ref shape-vec k)))

    ;; Per spec, "An array does not retain a dependence to the shape array"
    ;; given to make-array/array/share-array -- deep-copy (fresh vector,
    ;; fresh pairs) so a caller mutating their own shape object afterwards
    ;; (shape returns an ordinary, caller-visible mutable vector of pairs)
    ;; can never retroactively corrupt an already-constructed array's bounds
    ;; or its store's already-fixed size.
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

    ;; Row-major mixed-radix offset, with a per-dimension bounds check.
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
            (%array-ref-indices
             (array-base a)
             (call-with-values (lambda () (apply (array-mapper a) indices)) list)))))

    (define (%array-set-indices! a indices obj)
      (let ((store (array-store a)))
        (if store
            (vector-set! store (%row-major-offset (array-shape-vec a) indices) obj)
            (%array-set-indices!
             (array-base a)
             (call-with-values (lambda () (apply (array-mapper a) indices)) list)
             obj))))

    ;; --- the 10 mandated procedures ---

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

    (define (make-array shape . fill)
      (unless (<= (length fill) 1)
        (error "make-array: expects at most one fill value" fill))
      (%make-array-record
       (%copy-shape shape) (make-vector (%shape-volume shape) (if (pair? fill) (car fill) #f)) #f #f))

    (define (array shape . objs)
      (let ((size (%shape-volume shape)))
        (unless (= size (length objs))
          (error "array: wrong number of initial values for shape" size (length objs)))
        (%make-array-record (%copy-shape shape) (list->vector objs) #f #f)))

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
      (%make-array-record (%copy-shape shape) #f a proc))))
