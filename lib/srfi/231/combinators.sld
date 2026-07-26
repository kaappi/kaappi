;;; SRFI 231 -- Bulk combinators and conversions (phase 4 of #1694's
;;; SRFI 231 slice). Builds on phases 1a/1b/2/3 (intervals, storage
;;; classes, core array object, views/sharing). See intervals.sld's
;;; header for the overall roadmap; (srfi 231) itself is still not
;;; importable as a bare library.
;;;
;;; array-map/for-each/fold-left/fold-right/any/every are all variadic
;;; over arrays (one mandatory array plus a rest-list of additional
;;; arrays, ALL of which must have the exact SAME domain -- interval
;;; equality, not just matching shape). array-reduce is the one
;;; exception: fixed 2-arg, single array only, hard-errors on an empty
;;; array (confirmed unconditional in the reference implementation --
;;; there is no seed/identity to fall back on, unlike fold-left/right).
;;; array-map returns a lazy (recomputed on every access), immutable,
;;; non-specialized array -- never eagerly evaluated.
;;;
;;; array-fold-left calls operator as (operator acc e0 e1 ...); array-
;;; fold-right calls it as (operator e0 e1 ... acc) -- accumulator LAST,
;;; not first -- confirmed via the spec's own formal reference
;;; definition, which passes elements as SEPARATE positional arguments
;;; via apply, never as one packed list argument. Confirmed via the
;;; spec's own example that this distinction is observable, not just
;;; notational: (array-fold-left - 0 a) and (array-fold-right - 0 a)
;;; give different, non-interchangeable results for a non-associative
;;; operator.
;;;
;;; array-inner-product's compositional definition (curry + permute +
;;; copy + outer-product + map + reduce) needed care in two places the
;;; spec's own prose pseudocode gets subtly wrong: it omits the required
;;; second argument to array-curry on its second call (both calls need
;;; it -- confirmed against the reference implementation, not just the
;;; inconsistent prose), and its "Assumes" paragraph doesn't mention
;;; that the shared axis's width must be nonzero (also confirmed only
;;; via the reference implementation -- needed because the inner
;;; reduction would otherwise call array-reduce on an empty array).
;;;
;;; list*->array/array->list*/vector*->array/array->vector* infer or
;;; produce a per-dimension shape from nested-list/vector STRUCTURE
;;; (recursion depth = target dimension, sublist/subvector lengths at
;;; each level must be mutually equal -- a ragged structure is
;;; rejected). The empty-collection edge cases are genuinely
;;; undomesticable by intuition alone and were verified by hand-tracing
;;; all four of the spec's own worked examples against the actual
;;; algorithm: (list*->array 0 '()) yields a RANK-0 array whose single
;;; element IS the empty list (a real, non-empty, volume-1 array!),
;;; while (list*->array 1 '()) yields a genuinely EMPTY rank-1 array --
;;; these look superficially similar but are entirely different shapes.
;;; (Also worth knowing, though not exercised by anything in this file:
;;; the spec's own examples show that round-tripping an empty array
;;; through array->list* then back through list*->array is only
;;; guaranteed to preserve dimensions from the outermost NONZERO-width
;;; axis onward -- any axis strictly before the first zero-width axis
;;; encountered during the nested-list walk loses its width information,
;;; since the recursion never reaches deep enough to record it.)
(define-library (srfi 231 combinators)
  (import (scheme base) (srfi 1)
          (srfi 231 misc) (srfi 231 intervals) (srfi 231 storage-classes)
          (srfi 231 arrays) (srfi 231 views))
  (export array-map array-for-each array-fold-left array-fold-right array-reduce
          array-any array-every array-outer-product array-inner-product
          array->list list->array array->list* list*->array
          array->vector vector->array array->vector* vector*->array)
  (begin

    (define (%opt lst i default) (if (> (length lst) i) (list-ref lst i) default))

    (define (%check-same-domain! all who)
      (let ((domain (array-domain (car all))))
        (for-each (lambda (a)
                    (unless (interval= (array-domain a) domain)
                      (error (string-append who ": all arrays must have the same domain") all)))
                  all)))

    ;; --- mapping / folding / iteration ---

    ;; Lazy: the result's getter recomputes f on every access, never
    ;; eagerly evaluated -- confirmed by the spec's own reference
    ;; definition, which builds an ordinary (immutable, non-specialized)
    ;; make-array rather than a specialized/precomputed one.
    (define (array-map f array . arrays)
      (let ((all (cons array arrays)))
        (%check-same-domain! all "array-map")
        (make-array (array-domain array)
                    (lambda multi-index
                      (apply f (map (lambda (a) (apply (array-getter a) multi-index)) all))))))

    (define (array-for-each f array . arrays)
      (let ((all (cons array arrays)))
        (%check-same-domain! all "array-for-each")
        (interval-for-each (lambda multi-index (apply f (map (lambda (a) (apply (array-getter a) multi-index)) all)))
                            (array-domain array))))

    (define (array-fold-left operator identity array . arrays)
      (let ((all (cons array arrays)) (acc identity))
        (%check-same-domain! all "array-fold-left")
        (interval-for-each (lambda multi-index
                              (set! acc (apply operator acc (map (lambda (a) (apply (array-getter a) multi-index)) all))))
                            (array-domain array))
        acc))

    ;; Per spec, ALL f-evaluations complete before ANY operator
    ;; application -- collect per-index element-lists via cons during one
    ;; lex-order traversal (giving reverse-lex order for free), then a
    ;; plain left-walk applying (operator e0 e1 ... acc), matching
    ;; interval-fold-right's own already-verified technique.
    (define (array-fold-right operator identity array . arrays)
      (let ((all (cons array arrays)) (results '()))
        (%check-same-domain! all "array-fold-right")
        (interval-for-each (lambda multi-index
                              (set! results (cons (map (lambda (a) (apply (array-getter a) multi-index)) all) results)))
                            (array-domain array))
        (let loop ((xs results) (acc identity))
          (if (null? xs) acc (loop (cdr xs) (apply operator (append (car xs) (list acc))))))))

    ;; No identity/seed -- a private sentinel distinguishes "no elements
    ;; combined yet" from a legitimate accumulated value, matching the
    ;; reference implementation's own technique (needed because there is
    ;; no safe placeholder value that couldn't collide with a real
    ;; element). Hard error on an empty array -- confirmed unconditional,
    ;; not gated by any safety flag.
    (define %array-reduce-sentinel (list 'array-reduce-sentinel))

    (define (array-reduce operator array)
      (unless (array? array) (error "array-reduce: not an array" array))
      (unless (procedure? operator) (error "array-reduce: not a procedure" operator))
      (when (array-empty? array) (error "array-reduce: cannot reduce an empty array" array))
      (let ((acc %array-reduce-sentinel) (getter (array-getter array)))
        (interval-for-each (lambda multi-index
                              (let ((val (apply getter multi-index)))
                                (set! acc (if (eq? acc %array-reduce-sentinel) val (operator acc val)))))
                            (array-domain array))
        acc))

    ;; Short-circuits via call/cc on the first non-#f result, returning
    ;; that ACTUAL result (not just #t) -- matching the spec's own
    ;; "returns that result" wording, not a forced boolean.
    (define (array-any predicate array . arrays)
      (let ((all (cons array arrays)))
        (%check-same-domain! all "array-any")
        (call/cc
         (lambda (return)
           (interval-for-each (lambda multi-index
                                 (let ((r (apply predicate (map (lambda (a) (apply (array-getter a) multi-index)) all))))
                                   (when r (return r))))
                               (array-domain array))
           #f))))

    ;; Short-circuits (returning #f) on the first #f result; otherwise
    ;; returns the LAST nonfalse result, not just #t.
    (define (array-every predicate array . arrays)
      (let ((all (cons array arrays)) (last-result #t))
        (%check-same-domain! all "array-every")
        (call/cc
         (lambda (return)
           (interval-for-each (lambda multi-index
                                 (let ((r (apply predicate (map (lambda (a) (apply (array-getter a) multi-index)) all))))
                                   (if r (set! last-result r) (return #f))))
                               (array-domain array))
           last-result))))

    ;; --- products ---

    (define (array-outer-product operator array1 array2)
      (let ((domain (interval-cartesian-product (array-domain array1) (array-domain array2)))
            (d1 (array-dimension array1)))
        (make-array domain
                    (lambda multi-index
                      (operator (apply (array-getter array1) (take multi-index d1))
                                (apply (array-getter array2) (drop multi-index d1)))))))

    (define (array-inner-product A f g B)
      (unless (and (>= (array-dimension A) 1) (>= (array-dimension B) 1))
        (error "array-inner-product: both arrays must have dimension at least 1" A B))
      (let ((a-last (- (array-dimension A) 1)))
        (unless (and (= (interval-lower-bound (array-domain A) a-last) (interval-lower-bound (array-domain B) 0))
                     (= (interval-upper-bound (array-domain A) a-last) (interval-upper-bound (array-domain B) 0)))
          (error "array-inner-product: A's last axis bounds must match B's first axis bounds" A B))
        (when (zero? (interval-width (array-domain B) 0))
          (error "array-inner-product: the shared axis has zero width" A B))
        (array-outer-product
         (lambda (a b) (array-reduce f (array-map g a b)))
         (array-copy (array-curry A 1))
         (array-copy (array-curry (array-permute B (index-rotate (array-dimension B) 1)) 1)))))

    ;; --- flat list/vector conversions ---

    (define (array->list array)
      (let ((acc '()))
        (interval-for-each (lambda multi-index (set! acc (cons (apply (array-getter array) multi-index) acc)))
                            (array-domain array))
        (reverse acc)))

    (define (array->vector array) (list->vector (array->list array)))

    (define (list->array interval lst . opts)
      (unless (interval? interval) (error "list->array: not an interval" interval))
      (unless (= (length lst) (interval-volume interval))
        (error "list->array: list length does not match interval volume" interval lst))
      (let* ((storage-class (%opt opts 0 generic-storage-class))
             (mutable? (%opt opts 1 (specialized-array-default-mutable?)))
             (safe? (%opt opts 2 (specialized-array-default-safe?)))
             (dest (make-specialized-array interval storage-class (storage-class-default storage-class) safe?))
             (setter (array-setter dest))
             (remaining lst))
        (interval-for-each (lambda multi-index
                              (apply setter (car remaining) multi-index)
                              (set! remaining (cdr remaining)))
                            interval)
        (if mutable? dest (array-freeze! dest))))

    (define (vector->array interval vect . opts)
      (unless (interval? interval) (error "vector->array: not an interval" interval))
      (unless (= (vector-length vect) (interval-volume interval))
        (error "vector->array: vector length does not match interval volume" interval vect))
      (let* ((storage-class (%opt opts 0 generic-storage-class))
             (mutable? (%opt opts 1 (specialized-array-default-mutable?)))
             (safe? (%opt opts 2 (specialized-array-default-safe?)))
             (dest (make-specialized-array interval storage-class (storage-class-default storage-class) safe?))
             (setter (array-setter dest))
             (i 0))
        (interval-for-each (lambda multi-index
                              (apply setter (vector-ref vect i) multi-index)
                              (set! i (+ i 1)))
                            interval)
        (if mutable? dest (array-freeze! dest))))

    ;; --- nested list/vector conversions ---

    (define (array->list* array)
      (define (a->l a)
        (let ((dim (array-dimension a)))
          (cond
           ((= dim 0) ((array-getter a)))
           ((= dim 1) (array->list a))
           (else (array->list (array-map a->l (array-curry a (- dim 1))))))))
      (a->l array))

    (define (array->vector* array)
      (define (nested-list->nested-vector dim data)
        (if (= dim 0) data (list->vector (map (lambda (l) (nested-list->nested-vector (- dim 1) l)) data))))
      (nested-list->nested-vector (array-dimension array) (array->list* array)))

    ;; dimension=0 short-circuits to '() unconditionally (per the
    ;; reference implementation -- the spec's own prose pseudocode has a
    ;; documentation bug here, returning #t via `or`, which cannot
    ;; possibly be right since the caller immediately does
    ;; (list->vector (check-nested-list ...))). A length-0 list at ANY
    ;; recursion depth also short-circuits to '() immediately, even when
    ;; dimension=1 -- this ordering (checked before the dimension=1
    ;; special case) is exactly why (list*->array 1 '()) and
    ;; (list*->array 2 '()) both come out as all-dimensions-zero shapes.
    (define (%check-nested-list dimension nested-data)
      (if (= dimension 0)
          '()
          (and (list? nested-data)
               (let ((len (length nested-data)))
                 (cond
                  ((= len 0) '())
                  ((= dimension 1) (list len))
                  (else
                   (let* ((sublists (map (lambda (l) (%check-nested-list (- dimension 1) l)) nested-data))
                          (first (car sublists)))
                     (and first (every (lambda (l) (equal? first l)) (cdr sublists))
                          (cons len first)))))))))

    (define (%flatten-nested-list dimension nested-list)
      (case dimension
        ((0) (list nested-list))
        ((1) (list-copy nested-list))
        (else (apply append (map (lambda (l) (%flatten-nested-list (- dimension 1) l)) nested-list)))))

    (define (list*->array dimension nested-list . opts)
      (let ((shape (%check-nested-list dimension nested-list)))
        (unless shape
          (error "list*->array: nested-list is not the right shape for the given dimension" dimension nested-list))
        (let* ((padded-shape (append shape (make-list (- dimension (length shape)) 0)))
               (interval (make-interval (list->vector padded-shape)))
               (flat (%flatten-nested-list dimension nested-list)))
          (apply list->array interval flat opts))))

    ;; vector*->array delegates entirely to list*->array: converting the
    ;; nested-vector structure into an equivalent nested-list structure
    ;; first preserves rectangularity/shape identically at every level,
    ;; so re-deriving check-nested-vector/flatten-nested-vector as
    ;; separate vector-flavored algorithms would be pure duplication --
    ;; %check-nested-list (inside list*->array) already validates
    ;; rectangularity on the converted result. This conversion step
    ;; itself still needs its own vector? check at every recursion level,
    ;; though: without it, a malformed nested-vector (wrong depth, or a
    ;; non-vector where one is expected) would crash with a raw
    ;; vector->list type error instead of the same friendly, domain-
    ;; specific "not the right shape" error the list path already gives.
    (define (%nested-vector->nested-list dimension nested-data)
      (if (= dimension 0)
          nested-data
          (begin
            (unless (vector? nested-data)
              (error "vector*->array: nested-vector is not the right shape for the given dimension"
                     dimension nested-data))
            (map (lambda (v) (%nested-vector->nested-list (- dimension 1) v)) (vector->list nested-data)))))

    (define (vector*->array dimension nested-vector . opts)
      (apply list*->array dimension (%nested-vector->nested-list dimension nested-vector) opts))))
