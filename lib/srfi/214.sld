;;; SRFI 214 — Flexvectors
;;;
;;; A flexvector is a mutable, growable sequence: fast random access like a
;;; vector, plus fast insertion/removal at the end. This implementation is a
;;; <flexvector> record wrapping a native mutable vector "backing store"
;;; (whose capacity may exceed the logical length) plus a length field.
;;; Growth doubles the backing store's capacity, so flexvector-add-back!/
;;; flexvector-remove-back! of one element are amortized O(1) and
;;; flexvector-ref/flexvector-set! are O(1) — matching the spec's requirement
;;; that flexvectors have the same performance as native vectors for random
;;; access, since Kaappi's vector-ref/vector-set! are O(1).
;;;
;;; flexvector-add!/flexvector-remove! at an arbitrary interior index are
;;; O(n) (they shift the tail of the backing store), which is what the spec
;;; implies by only promising O(1) at the back.
;;;
;;; Most read-only, whole-flexvector operations delegate to the built-in
;;; (srfi 133) vector library over a fresh [0,length) slice of the backing
;;; store (native vector-map/vector-fold/etc. don't know to stop short of an
;;; oversized backing vector's true capacity), so this file reuses vector
;;; internals rather than reimplementing them.

(define-library (srfi 214)
  (import (scheme base) (scheme case-lambda) (srfi 1) (srfi 133))

  (export
    ;; constructors
    make-flexvector flexvector flexvector-unfold flexvector-unfold-right
    flexvector-copy flexvector-reverse-copy flexvector-append
    flexvector-concatenate flexvector-append-subvectors
    ;; predicates
    flexvector? flexvector-empty? flexvector=?
    ;; selectors
    flexvector-ref flexvector-front flexvector-back flexvector-length
    ;; mutators
    flexvector-add! flexvector-add-front! flexvector-add-back!
    flexvector-add-all! flexvector-append!
    flexvector-remove! flexvector-remove-front! flexvector-remove-back!
    flexvector-remove-range! flexvector-clear!
    flexvector-set! flexvector-swap! flexvector-fill!
    flexvector-reverse! flexvector-copy! flexvector-reverse-copy!
    ;; iteration
    flexvector-fold flexvector-fold-right
    flexvector-map flexvector-map/index flexvector-map! flexvector-map/index!
    flexvector-append-map flexvector-append-map/index
    flexvector-filter flexvector-filter/index
    flexvector-filter! flexvector-filter/index!
    flexvector-for-each flexvector-for-each/index
    flexvector-count flexvector-cumulate
    ;; searching
    flexvector-index flexvector-index-right
    flexvector-skip flexvector-skip-right
    flexvector-binary-search flexvector-any flexvector-every
    flexvector-partition
    ;; conversion
    flexvector->vector vector->flexvector
    flexvector->list reverse-flexvector->list
    list->flexvector reverse-list->flexvector
    flexvector->string string->flexvector
    flexvector->generator generator->flexvector)

  (begin

    (define-record-type <flexvector>
      (%make-fv vec len)
      flexvector?
      (vec %fv-vec %fv-vec-set!)
      (len %fv-len %fv-len-set!))

    (define (flexvector-length fv) (%fv-len fv))
    (define (flexvector-empty? fv) (= (%fv-len fv) 0))

    (define (%fv-capacity fv) (vector-length (%fv-vec fv)))

    ;; Grow the backing store (by doubling) until it can hold `needed`
    ;; elements. Leaves the logical length untouched.
    (define (%fv-ensure-capacity! fv needed)
      (let ((cap (%fv-capacity fv)))
        (when (< cap needed)
          (let loop ((new-cap (if (= cap 0) 4 cap)))
            (if (>= new-cap needed)
                (let ((new-vec (make-vector new-cap #f)))
                  (vector-copy! new-vec 0 (%fv-vec fv) 0 (%fv-len fv))
                  (%fv-vec-set! fv new-vec))
                (loop (* new-cap 2)))))))

    (define (%fv-check-ref fv i who)
      (unless (and (integer? i) (exact? i) (>= i 0) (< i (%fv-len fv)))
        (error (string-append who ": index out of range") i fv)))

    ;; Allows i == length (an insertion point right after the last element).
    (define (%fv-check-ins fv i who)
      (unless (and (integer? i) (exact? i) (>= i 0) (<= i (%fv-len fv)))
        (error (string-append who ": index out of range") i fv)))

    ;; An exact-length copy of fv's logical contents. Needed before handing
    ;; data to a (srfi 133) procedure that has no start/end parameters and
    ;; would otherwise see the whole (possibly oversized) backing store.
    (define (%fv-slice fv) (vector-copy (%fv-vec fv) 0 (%fv-len fv)))
    (define (%fv-slices fvs) (map %fv-slice fvs))

    ;;; --- constructors ---

    (define make-flexvector
      (case-lambda
        ((size) (%make-fv (make-vector size #f) size))
        ((size fill) (%make-fv (make-vector size fill) size))))

    (define (flexvector . xs)
      (let ((v (list->vector xs)))
        (%make-fv v (vector-length v))))

    (define (flexvector-unfold p f g . seeds)
      (let ((fv (make-flexvector 0)))
        (let loop ((seeds seeds))
          (if (apply p seeds)
              fv
              (begin
                (flexvector-add-back! fv (apply f seeds))
                (loop (call-with-values (lambda () (apply g seeds)) list)))))))

    ;; Builds right-to-left via add-front!, so the *last* generated element
    ;; ends up at index 0 — matching SRFI 1's unfold-right, which conses
    ;; each new (f seed) in front of the accumulation started at the tail.
    (define (flexvector-unfold-right p f g . seeds)
      (let ((fv (make-flexvector 0)))
        (let loop ((seeds seeds))
          (if (apply p seeds)
              fv
              (begin
                (flexvector-add-front! fv (apply f seeds))
                (loop (call-with-values (lambda () (apply g seeds)) list)))))))

    (define flexvector-copy
      (case-lambda
        ((fv) (flexvector-copy fv 0 (%fv-len fv)))
        ((fv start) (flexvector-copy fv start (%fv-len fv)))
        ((fv start end)
         (%make-fv (vector-copy (%fv-vec fv) start end) (- end start)))))

    (define flexvector-reverse-copy
      (case-lambda
        ((fv) (flexvector-reverse-copy fv 0 (%fv-len fv)))
        ((fv start) (flexvector-reverse-copy fv start (%fv-len fv)))
        ((fv start end)
         (%make-fv (vector-reverse-copy (%fv-vec fv) start end) (- end start)))))

    (define (flexvector-append . fvs)
      (let ((v (apply vector-append (%fv-slices fvs))))
        (%make-fv v (vector-length v))))

    (define (flexvector-concatenate fvs) (apply flexvector-append fvs))

    ;; Note: destructures the triples by hand with car/cdr rather than
    ;; caddr/cdddr — those depth-3 compositions live in (scheme cxr), not
    ;; (scheme base), and this file only imports the latter.
    (define (flexvector-append-subvectors . args)
      (let loop ((args args) (vecs '()) (total 0))
        (if (null? args)
            (let ((v (apply vector-append (reverse vecs))))
              (%make-fv v total))
            (let* ((fv (car args))
                   (rest1 (cdr args))
                   (start (car rest1))
                   (rest2 (cdr rest1))
                   (end (car rest2))
                   (rest3 (cdr rest2)))
              (loop rest3
                    (cons (vector-copy (%fv-vec fv) start end) vecs)
                    (+ total (- end start)))))))

    ;;; --- predicates ---

    (define (flexvector=? elt=? . fvs)
      (or (null? fvs)
          (null? (cdr fvs))
          (let loop ((fvs fvs))
            (or (null? (cdr fvs))
                (let ((a (car fvs)) (b (cadr fvs)))
                  (and (= (flexvector-length a) (flexvector-length b))
                       (let check ((i 0))
                         (or (>= i (flexvector-length a))
                             (and (elt=? (flexvector-ref a i) (flexvector-ref b i))
                                  (check (+ i 1)))))
                       (loop (cdr fvs))))))))

    ;;; --- selectors ---

    (define (flexvector-ref fv i)
      (%fv-check-ref fv i "flexvector-ref")
      (vector-ref (%fv-vec fv) i))

    (define (flexvector-front fv)
      (when (flexvector-empty? fv) (error "flexvector-front: empty flexvector" fv))
      (vector-ref (%fv-vec fv) 0))

    (define (flexvector-back fv)
      (when (flexvector-empty? fv) (error "flexvector-back: empty flexvector" fv))
      (vector-ref (%fv-vec fv) (- (%fv-len fv) 1)))

    ;;; --- mutators ---

    ;; Inserts x ... at index i, shifting [i,len) right. Handles
    ;; add-front!/add-back! too (i = 0 or i = len), so back-insertion of a
    ;; single element only pays for capacity growth, not any shifting.
    (define (flexvector-add! fv i . xs)
      (%fv-check-ins fv i "flexvector-add!")
      (let ((n (length xs))
            (old-len (%fv-len fv)))
        (when (> n 0)
          (%fv-ensure-capacity! fv (+ old-len n))
          (let ((vec (%fv-vec fv)))
            (let shift ((k (- old-len 1)))
              (when (>= k i)
                (vector-set! vec (+ k n) (vector-ref vec k))
                (shift (- k 1))))
            (let write-loop ((xs xs) (k i))
              (unless (null? xs)
                (vector-set! vec k (car xs))
                (write-loop (cdr xs) (+ k 1))))
            (%fv-len-set! fv (+ old-len n)))))
      fv)

    (define (flexvector-add-front! fv . xs) (apply flexvector-add! fv 0 xs))
    (define (flexvector-add-back! fv . xs) (apply flexvector-add! fv (%fv-len fv) xs))
    (define (flexvector-add-all! fv i xs) (apply flexvector-add! fv i xs))

    (define (flexvector-append! fv1 . fvs)
      (for-each
        (lambda (fv2)
          (let ((old-len (%fv-len fv1)) (n (%fv-len fv2)))
            (%fv-ensure-capacity! fv1 (+ old-len n))
            (vector-copy! (%fv-vec fv1) old-len (%fv-vec fv2) 0 n)
            (%fv-len-set! fv1 (+ old-len n))))
        fvs)
      fv1)

    (define (flexvector-remove! fv i)
      (%fv-check-ref fv i "flexvector-remove!")
      (let ((vec (%fv-vec fv)) (old-len (%fv-len fv)))
        (let ((val (vector-ref vec i)))
          (let shift ((k i))
            (when (< k (- old-len 1))
              (vector-set! vec k (vector-ref vec (+ k 1)))
              (shift (+ k 1))))
          (%fv-len-set! fv (- old-len 1))
          val)))

    (define (flexvector-remove-front! fv) (flexvector-remove! fv 0))

    (define (flexvector-remove-back! fv)
      (when (flexvector-empty? fv) (error "flexvector-remove-back!: empty flexvector" fv))
      (let* ((old-len (%fv-len fv)) (val (vector-ref (%fv-vec fv) (- old-len 1))))
        (%fv-len-set! fv (- old-len 1))
        val))

    (define flexvector-remove-range!
      (case-lambda
        ((fv start) (flexvector-remove-range! fv start (%fv-len fv)))
        ((fv start end)
         (let ((vec (%fv-vec fv)) (old-len (%fv-len fv)) (n (- end start)))
           (let shift ((k start))
             (when (< k (- old-len n))
               (vector-set! vec k (vector-ref vec (+ k n)))
               (shift (+ k 1))))
           (%fv-len-set! fv (- old-len n))
           fv))))

    (define (flexvector-clear! fv) (%fv-len-set! fv 0) fv)

    ;; Returns the previous value, unless i = length, in which case this
    ;; acts like flexvector-add-back! and returns an unspecified value.
    (define (flexvector-set! fv i x)
      (if (= i (%fv-len fv))
          (begin (flexvector-add-back! fv x) (if #f #f))
          (begin
            (%fv-check-ref fv i "flexvector-set!")
            (let ((old (vector-ref (%fv-vec fv) i)))
              (vector-set! (%fv-vec fv) i x)
              old))))

    (define (flexvector-swap! fv i j)
      (%fv-check-ref fv i "flexvector-swap!")
      (%fv-check-ref fv j "flexvector-swap!")
      (vector-swap! (%fv-vec fv) i j))

    (define flexvector-fill!
      (case-lambda
        ((fv fill) (flexvector-fill! fv fill 0 (%fv-len fv)))
        ((fv fill start) (flexvector-fill! fv fill start (%fv-len fv)))
        ((fv fill start end)
         (vector-fill! (%fv-vec fv) fill start end)
         fv)))

    (define (flexvector-reverse! fv)
      (vector-reverse! (%fv-vec fv) 0 (%fv-len fv))
      fv)

    (define flexvector-copy!
      (case-lambda
        ((to at from) (flexvector-copy! to at from 0 (%fv-len from)))
        ((to at from start) (flexvector-copy! to at from start (%fv-len from)))
        ((to at from start end)
         (let ((n (- end start)))
           (%fv-ensure-capacity! to (+ at n))
           (vector-copy! (%fv-vec to) at (%fv-vec from) start end)
           (when (> (+ at n) (%fv-len to)) (%fv-len-set! to (+ at n)))
           to))))

    (define flexvector-reverse-copy!
      (case-lambda
        ((to at from) (flexvector-reverse-copy! to at from 0 (%fv-len from)))
        ((to at from start) (flexvector-reverse-copy! to at from start (%fv-len from)))
        ((to at from start end)
         ;; Snapshot the source range first: reversal reads and writes in
         ;; opposite directions, so in-place overlap safety can't be
         ;; assumed the way plain vector-copy! guarantees it.
         (let* ((n (- end start))
                (src (vector-copy (%fv-vec from) start end)))
           (%fv-ensure-capacity! to (+ at n))
           (vector-reverse-copy! (%fv-vec to) at src 0 n)
           (when (> (+ at n) (%fv-len to)) (%fv-len-set! to (+ at n)))
           to))))

    ;;; --- conversion (defined early: iteration below builds on these) ---

    (define flexvector->vector
      (case-lambda
        ((fv) (%fv-slice fv))
        ((fv start) (vector-copy (%fv-vec fv) start (%fv-len fv)))
        ((fv start end) (vector-copy (%fv-vec fv) start end))))

    (define vector->flexvector
      (case-lambda
        ((vec) (vector->flexvector vec 0 (vector-length vec)))
        ((vec start) (vector->flexvector vec start (vector-length vec)))
        ((vec start end)
         (%make-fv (vector-copy vec start end) (- end start)))))

    (define flexvector->list
      (case-lambda
        ((fv) (vector->list (%fv-vec fv) 0 (%fv-len fv)))
        ((fv start) (vector->list (%fv-vec fv) start (%fv-len fv)))
        ((fv start end) (vector->list (%fv-vec fv) start end))))

    (define reverse-flexvector->list
      (case-lambda
        ((fv) (reverse (flexvector->list fv)))
        ((fv start) (reverse (flexvector->list fv start)))
        ((fv start end) (reverse (flexvector->list fv start end)))))

    (define (list->flexvector lst)
      (let ((v (list->vector lst))) (%make-fv v (vector-length v))))

    (define (reverse-list->flexvector lst) (list->flexvector (reverse lst)))

    (define flexvector->string
      (case-lambda
        ((fv) (vector->string (%fv-vec fv) 0 (%fv-len fv)))
        ((fv start) (vector->string (%fv-vec fv) start (%fv-len fv)))
        ((fv start end) (vector->string (%fv-vec fv) start end))))

    (define string->flexvector
      (case-lambda
        ((s) (string->flexvector s 0 (string-length s)))
        ((s start) (string->flexvector s start (string-length s)))
        ((s start end)
         (%make-fv (string->vector s start end) (- end start)))))

    (define (flexvector->generator fv)
      (let ((i 0) (n (%fv-len fv)) (vec (%fv-vec fv)))
        (lambda ()
          (if (>= i n)
              (eof-object)
              (let ((v (vector-ref vec i)))
                (set! i (+ i 1))
                v)))))

    (define (generator->flexvector gen)
      (let ((fv (make-flexvector 0)))
        (let loop ((v (gen)))
          (if (eof-object? v)
              fv
              (begin (flexvector-add-back! fv v) (loop (gen)))))))

    ;;; --- iteration ---

    (define (flexvector-fold kons knil fv1 . fvs)
      (apply vector-fold kons knil (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-fold-right kons knil fv1 . fvs)
      (apply vector-fold-right kons knil (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-map f fv1 . fvs)
      (vector->flexvector (apply vector-map f (%fv-slice fv1) (%fv-slices fvs))))

    (define (flexvector-map/index f fv1 . fvs)
      (let* ((all (cons fv1 fvs))
             (n (apply min (map flexvector-length all)))
             (result (make-vector n #f)))
        (let loop ((i 0))
          (when (< i n)
            (vector-set! result i (apply f i (map (lambda (fv) (flexvector-ref fv i)) all)))
            (loop (+ i 1))))
        (vector->flexvector result)))

    (define (flexvector-map! f fv1 . fvs)
      (let* ((all (cons fv1 fvs))
             (n (apply min (map flexvector-length all))))
        (let loop ((i 0))
          (when (< i n)
            (vector-set! (%fv-vec fv1) i (apply f (map (lambda (fv) (flexvector-ref fv i)) all)))
            (loop (+ i 1))))
        fv1))

    (define (flexvector-map/index! f fv1 . fvs)
      (let* ((all (cons fv1 fvs))
             (n (apply min (map flexvector-length all))))
        (let loop ((i 0))
          (when (< i n)
            (vector-set! (%fv-vec fv1) i (apply f i (map (lambda (fv) (flexvector-ref fv i)) all)))
            (loop (+ i 1))))
        fv1))

    (define (flexvector-append-map f fv1 . fvs)
      (let* ((all (cons fv1 fvs))
             (n (apply min (map flexvector-length all)))
             (parts (let loop ((i 0) (acc '()))
                      (if (>= i n)
                          (reverse acc)
                          (loop (+ i 1)
                                (cons (apply f (map (lambda (fv) (flexvector-ref fv i)) all)) acc))))))
        (apply flexvector-append parts)))

    (define (flexvector-append-map/index f fv1 . fvs)
      (let* ((all (cons fv1 fvs))
             (n (apply min (map flexvector-length all)))
             (parts (let loop ((i 0) (acc '()))
                      (if (>= i n)
                          (reverse acc)
                          (loop (+ i 1)
                                (cons (apply f i (map (lambda (fv) (flexvector-ref fv i)) all)) acc))))))
        (apply flexvector-append parts)))

    (define (flexvector-filter pred? fv)
      (list->flexvector (filter pred? (flexvector->list fv))))

    (define (flexvector-filter/index pred? fv)
      (let ((n (flexvector-length fv)))
        (let loop ((i 0) (acc '()))
          (if (>= i n)
              (list->flexvector (reverse acc))
              (let ((v (flexvector-ref fv i)))
                (loop (+ i 1) (if (pred? i v) (cons v acc) acc)))))))

    (define (flexvector-filter! pred? fv)
      (let* ((lst (filter pred? (flexvector->list fv)))
             (v (list->vector lst)))
        (%fv-vec-set! fv v)
        (%fv-len-set! fv (vector-length v))
        fv))

    (define (flexvector-filter/index! pred? fv)
      (let* ((n (flexvector-length fv))
             (kept (let loop ((i 0) (acc '()))
                     (if (>= i n)
                         (reverse acc)
                         (let ((v (flexvector-ref fv i)))
                           (loop (+ i 1) (if (pred? i v) (cons v acc) acc))))))
             (v (list->vector kept)))
        (%fv-vec-set! fv v)
        (%fv-len-set! fv (vector-length v))
        fv))

    (define (flexvector-for-each f fv1 . fvs)
      (apply vector-for-each f (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-for-each/index f fv1 . fvs)
      (let* ((all (cons fv1 fvs))
             (n (apply min (map flexvector-length all))))
        (let loop ((i 0))
          (when (< i n)
            (apply f i (map (lambda (fv) (flexvector-ref fv i)) all))
            (loop (+ i 1))))))

    (define (flexvector-count pred? fv1 . fvs)
      (apply vector-count pred? (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-cumulate f knil fv)
      (vector->flexvector (vector-cumulate f knil (%fv-slice fv))))

    ;;; --- searching ---

    (define (flexvector-index pred? fv1 . fvs)
      (apply vector-index pred? (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-index-right pred? fv1 . fvs)
      (apply vector-index-right pred? (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-skip pred? fv1 . fvs)
      (apply vector-skip pred? (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-skip-right pred? fv1 . fvs)
      (apply vector-skip-right pred? (%fv-slice fv1) (%fv-slices fvs)))

    (define flexvector-binary-search
      (case-lambda
        ((fv value cmp) (flexvector-binary-search fv value cmp 0 (%fv-len fv)))
        ((fv value cmp start) (flexvector-binary-search fv value cmp start (%fv-len fv)))
        ((fv value cmp start end)
         (let ((result (vector-binary-search (vector-copy (%fv-vec fv) start end) value cmp)))
           (if (integer? result) (+ result start) result)))))

    (define (flexvector-any pred? fv1 . fvs)
      (apply vector-any pred? (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-every pred? fv1 . fvs)
      (apply vector-every pred? (%fv-slice fv1) (%fv-slices fvs)))

    (define (flexvector-partition pred? fv)
      (let loop ((i 0) (n (flexvector-length fv)) (yes '()) (no '()))
        (if (>= i n)
            (values (list->flexvector (reverse yes)) (list->flexvector (reverse no)))
            (let ((v (flexvector-ref fv i)))
              (if (pred? v)
                  (loop (+ i 1) n (cons v yes) no)
                  (loop (+ i 1) n yes (cons v no)))))))))
