;;; SRFI 160 base -- (srfi 160 base)
;;;
;;; Supplies, for all 12 element kinds (u8 plus the 11 kinds backed by the
;;; native NumericVector heap type), the 9 SRFI-4-shaped core procedures
;;; (make-Uvector, Uvector, Uvector?, Uvector-length, Uvector-ref,
;;; Uvector-set!, Uvector->list, list->Uvector, U?).
;;;
;;; It also supplies, under internal `%uvec-*` names, a single generic
;;; implementation of SRFI 160's much larger SRFI-133-shaped extended
;;; surface (map/fold/filter/unfold/copy!/append/generator/comparator/etc.).
;;; This generic layer is written ONCE and works for every kind uniformly,
;;; including u8 (a bytevector, not a NumericVector) -- `%uvec-ref`/
;;; `%uvec-set!`/`%uvec-length`/`%uvec-make` dispatch on `bytevector?` vs
;;; `%numeric-vector?` so the same algorithm bodies serve both. Each
;;; per-type library (lib/srfi/160/<tag>.sld) imports this library, renames
;;; the generics that don't need a fresh vector's kind (fold, for-each,
;;; index, swap!, ...) directly to their type-specific name, and wraps the
;;; generics that construct a new vector (map, copy, unfold, filter, ...)
;;; in a one-line closure fixing that type's kind symbol.
;;;
;;; Kind-needing vs. no-kind split: an operation needs an explicit kind
;;; argument only if it allocates a *new* Uvector without an input Uvector
;;; to infer the kind from (unfold) or where the result's kind should be
;;; pinned to the calling wrapper's type rather than inferred (map, copy,
;;; filter, ...). Operations that only read, mutate in place, or produce a
;;; non-Uvector result (fold, for-each, swap!, ->list, ->vector, ...) need
;;; no kind parameter at all.
(define-library (srfi 160 base)
  (import (scheme base) (scheme cxr) (srfi 128) (srfi 160 primitives))
  (export
   ;; --- u8 (bytevector alias) ---
   u8vector? make-u8vector u8vector u8vector-length u8vector-ref u8vector-set!
   u8vector->list list->u8vector u8?
   ;; --- s8/u16/s16/u32/s32/u64/s64/f32/f64/c64/c128 core ---
   make-s8vector s8vector s8vector? s8vector-length s8vector-ref s8vector-set!
   s8vector->list list->s8vector s8?
   make-u16vector u16vector u16vector? u16vector-length u16vector-ref u16vector-set!
   u16vector->list list->u16vector u16?
   make-s16vector s16vector s16vector? s16vector-length s16vector-ref s16vector-set!
   s16vector->list list->s16vector s16?
   make-u32vector u32vector u32vector? u32vector-length u32vector-ref u32vector-set!
   u32vector->list list->u32vector u32?
   make-s32vector s32vector s32vector? s32vector-length s32vector-ref s32vector-set!
   s32vector->list list->s32vector s32?
   make-u64vector u64vector u64vector? u64vector-length u64vector-ref u64vector-set!
   u64vector->list list->u64vector u64?
   make-s64vector s64vector s64vector? s64vector-length s64vector-ref s64vector-set!
   s64vector->list list->s64vector s64?
   make-f32vector f32vector f32vector? f32vector-length f32vector-ref f32vector-set!
   f32vector->list list->f32vector f32?
   make-f64vector f64vector f64vector? f64vector-length f64vector-ref f64vector-set!
   f64vector->list list->f64vector f64?
   make-c64vector c64vector c64vector? c64vector-length c64vector-ref c64vector-set!
   c64vector->list list->c64vector c64?
   make-c128vector c128vector c128vector? c128vector-length c128vector-ref c128vector-set!
   c128vector->list list->c128vector c128?
   ;; --- generic extended-surface helpers (internal; consumed by per-type libs) ---
   %uvec-for-each %uvec-fold %uvec-fold-right %uvec-count %uvec-any %uvec-every
   %uvec-index %uvec-index-right %uvec-skip %uvec-skip-right
   %uvec-empty? %uvec= %uvec-swap! %uvec-fill! %uvec-reverse! %uvec-copy! %uvec-reverse-copy!
   %uvec-map! %uvec-unfold! %uvec-unfold-right! %uvec-reverse->list %uvec-generator %uvec-write
   %uvec-unfold %uvec-unfold-right %uvec-copy %uvec-reverse-copy
   %uvec-append %uvec-concatenate %uvec-append-subvectors
   %uvec-take %uvec-take-right %uvec-drop %uvec-drop-right %uvec-segment
   %uvec-map %uvec-cumulate
   %uvec-take-while %uvec-take-while-right %uvec-drop-while %uvec-drop-while-right
   %uvec-filter %uvec-remove %uvec-partition
   %uvec-reverse-list-> %uvec->vector %uvec-vector-> %uvec-make-comparator)
  (begin

    ;; --- shared low-level dispatch (bytevector [u8] vs. NumericVector) ---

    (define (%uvec? v) (or (bytevector? v) (%numeric-vector? v)))
    (define (%uvec-kind v) (if (bytevector? v) 'u8 (%numeric-vector-kind v)))
    (define (%uvec-length v) (if (bytevector? v) (bytevector-length v) (%numeric-vector-length v)))
    (define (%uvec-ref v i) (if (bytevector? v) (bytevector-u8-ref v i) (%numeric-vector-ref v i)))
    (define (%uvec-set! v i x)
      (if (bytevector? v) (bytevector-u8-set! v i x) (%numeric-vector-set! v i x)))
    (define (%uvec-default-fill kind)
      (case kind ((f32 f64 c64 c128) 0.0) (else 0)))
    (define (%uvec-make kind n fill)
      (if (eq? kind 'u8) (make-bytevector n fill) (%make-numeric-vector kind n fill)))
    (define (%uvec-min-length vs) (apply min (map %uvec-length vs)))
    (define (%uvec-map-refs i v vs) (map (lambda (u) (%uvec-ref u i)) vs))

    (define (%opt-start-end args len)
      (let ((start (if (pair? args) (car args) 0)))
        (values start (if (and (pair? args) (pair? (cdr args))) (cadr args) len))))

    (define (%uvec-elt-valid? kind obj)
      (case kind
        ((s8) (and (integer? obj) (exact? obj) (<= -128 obj 127)))
        ((u16) (and (integer? obj) (exact? obj) (<= 0 obj 65535)))
        ((s16) (and (integer? obj) (exact? obj) (<= -32768 obj 32767)))
        ((u32) (and (integer? obj) (exact? obj) (<= 0 obj 4294967295)))
        ((s32) (and (integer? obj) (exact? obj) (<= -2147483648 obj 2147483647)))
        ((u64) (and (integer? obj) (exact? obj) (<= 0 obj 18446744073709551615)))
        ((s64) (and (integer? obj) (exact? obj) (<= -9223372036854775808 obj 9223372036854775807)))
        ((f32 f64) (real? obj))
        ((c64 c128) (number? obj))
        ((u8) (and (integer? obj) (exact? obj) (<= 0 obj 255)))
        (else #f)))

    ;; --- per-type core (9 SRFI-4-shaped procedures), generated once per kind ---

    (define-syntax define-uvector-core
      (syntax-rules ()
        ((_ kind mk ctor pred lenf reff setf ->lst lst-> validp)
         (begin
           (define (mk n . fill)
             (%make-numeric-vector 'kind n (if (pair? fill) (car fill) (%uvec-default-fill 'kind))))
           (define (ctor . vals) (%uvec-list-> 'kind vals))
           (define (pred obj) (and (%numeric-vector? obj) (eq? (%numeric-vector-kind obj) 'kind)))
           (define (lenf v) (%numeric-vector-length v))
           (define (reff v i) (%numeric-vector-ref v i))
           (define (setf v i x) (%numeric-vector-set! v i x))
           (define (->lst v . args) (apply %uvec->list v args))
           (define (lst-> lst) (%uvec-list-> 'kind lst))
           (define (validp obj) (%uvec-elt-valid? 'kind obj))))))

    ;; %uvec-list-> is defined below (with the rest of the conversion
    ;; helpers) but used above -- library bodies are letrec*-like, so this
    ;; forward reference resolves fine since none of these are invoked
    ;; until called, by which point every sibling define has run.

    (define-uvector-core s8 make-s8vector s8vector s8vector? s8vector-length
      s8vector-ref s8vector-set! s8vector->list list->s8vector s8?)
    (define-uvector-core u16 make-u16vector u16vector u16vector? u16vector-length
      u16vector-ref u16vector-set! u16vector->list list->u16vector u16?)
    (define-uvector-core s16 make-s16vector s16vector s16vector? s16vector-length
      s16vector-ref s16vector-set! s16vector->list list->s16vector s16?)
    (define-uvector-core u32 make-u32vector u32vector u32vector? u32vector-length
      u32vector-ref u32vector-set! u32vector->list list->u32vector u32?)
    (define-uvector-core s32 make-s32vector s32vector s32vector? s32vector-length
      s32vector-ref s32vector-set! s32vector->list list->s32vector s32?)
    (define-uvector-core u64 make-u64vector u64vector u64vector? u64vector-length
      u64vector-ref u64vector-set! u64vector->list list->u64vector u64?)
    (define-uvector-core s64 make-s64vector s64vector s64vector? s64vector-length
      s64vector-ref s64vector-set! s64vector->list list->s64vector s64?)
    (define-uvector-core f32 make-f32vector f32vector f32vector? f32vector-length
      f32vector-ref f32vector-set! f32vector->list list->f32vector f32?)
    (define-uvector-core f64 make-f64vector f64vector f64vector? f64vector-length
      f64vector-ref f64vector-set! f64vector->list list->f64vector f64?)
    (define-uvector-core c64 make-c64vector c64vector c64vector? c64vector-length
      c64vector-ref c64vector-set! c64vector->list list->c64vector c64?)
    (define-uvector-core c128 make-c128vector c128vector c128vector? c128vector-length
      c128vector-ref c128vector-set! c128vector->list list->c128vector c128?)

    ;; u8vector is a bytevector alias, per SRFI 160's own recommendation.
    (define u8vector? bytevector?)
    (define (make-u8vector n . fill) (make-bytevector n (if (pair? fill) (car fill) 0)))
    (define (u8vector . vals) (apply bytevector vals))
    (define u8vector-length bytevector-length)
    (define u8vector-ref bytevector-u8-ref)
    (define u8vector-set! bytevector-u8-set!)
    (define (u8vector->list bv . args) (apply %uvec->list bv args))
    (define (list->u8vector lst) (%uvec-list-> 'u8 lst))
    (define (u8? obj) (%uvec-elt-valid? 'u8 obj))

    ;; --- generic extended surface: no-kind (read/mutate-in-place/non-Uvector result) ---

    (define (%uvec-for-each f v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i 0))
          (when (< i n)
            (apply f (%uvec-ref v i) (%uvec-map-refs i v vs))
            (loop (+ i 1))))))

    (define (%uvec-map! f v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i 0))
          (when (< i n)
            (%uvec-set! v i (apply f (%uvec-ref v i) (%uvec-map-refs i v vs)))
            (loop (+ i 1))))))

    (define (%uvec-fold kons knil v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i 0) (acc knil))
          (if (= i n) acc
              (loop (+ i 1) (apply kons acc (%uvec-ref v i) (%uvec-map-refs i v vs)))))))

    (define (%uvec-fold-right kons knil v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i (- n 1)) (acc knil))
          (if (< i 0) acc
              (loop (- i 1) (apply kons acc (%uvec-ref v i) (%uvec-map-refs i v vs)))))))

    (define (%uvec-count pred v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i 0) (c 0))
          (if (= i n) c
              (loop (+ i 1)
                    (if (apply pred (%uvec-ref v i) (%uvec-map-refs i v vs)) (+ c 1) c))))))

    (define (%uvec-any pred v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i 0))
          (and (< i n)
               (let ((r (apply pred (%uvec-ref v i) (%uvec-map-refs i v vs))))
                 (if r r (loop (+ i 1))))))))

    (define (%uvec-every pred v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i 0) (last #t))
          (if (= i n) last
              (let ((r (apply pred (%uvec-ref v i) (%uvec-map-refs i v vs))))
                (and r (loop (+ i 1) r)))))))

    (define (%uvec-index pred v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i 0))
          (cond ((= i n) #f)
                ((apply pred (%uvec-ref v i) (%uvec-map-refs i v vs)) i)
                (else (loop (+ i 1)))))))

    (define (%uvec-index-right pred v . vs)
      (let ((n (%uvec-min-length (cons v vs))))
        (let loop ((i (- n 1)))
          (cond ((< i 0) #f)
                ((apply pred (%uvec-ref v i) (%uvec-map-refs i v vs)) i)
                (else (loop (- i 1)))))))

    (define (%uvec-skip pred v . vs)
      (apply %uvec-index (lambda args (not (apply pred args))) v vs))

    (define (%uvec-skip-right pred v . vs)
      (apply %uvec-index-right (lambda args (not (apply pred args))) v vs))

    (define (%uvec-empty? v) (= 0 (%uvec-length v)))

    (define (%uvec-eq2? v1 v2)
      (and (= (%uvec-length v1) (%uvec-length v2))
           (let ((n (%uvec-length v1)))
             (let loop ((i 0))
               (or (= i n)
                   (and (= (%uvec-ref v1 i) (%uvec-ref v2 i)) (loop (+ i 1))))))))

    (define (%uvec= v . vs)
      (or (null? vs) (and (%uvec-eq2? v (car vs)) (apply %uvec= vs))))

    (define (%uvec-swap! v i j)
      (let ((tmp (%uvec-ref v i)))
        (%uvec-set! v i (%uvec-ref v j))
        (%uvec-set! v j tmp)))

    (define (%uvec-fill! v fill . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length v))))
        (let loop ((i start)) (when (< i end) (%uvec-set! v i fill) (loop (+ i 1))))))

    (define (%uvec-reverse! v . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length v))))
        (let loop ((i start) (j (- end 1)))
          (when (< i j) (%uvec-swap! v i j) (loop (+ i 1) (- j 1))))))

    (define (%uvec-copy! to at from . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length from))))
        (if (<= at start)
            (let loop ((i start) (j at))
              (when (< i end) (%uvec-set! to j (%uvec-ref from i)) (loop (+ i 1) (+ j 1))))
            (let loop ((i (- end 1)) (j (+ at (- end start 1))))
              (when (>= i start) (%uvec-set! to j (%uvec-ref from i)) (loop (- i 1) (- j 1)))))))

    (define (%uvec-reverse-copy! to at from . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length from))))
        (let ((n (- end start)))
          (let loop ((i 0))
            (when (< i n)
              (%uvec-set! to (+ at i) (%uvec-ref from (- end i 1)))
              (loop (+ i 1)))))))

    (define (%uvec-unfold! f v start end . seeds)
      (let loop ((i start) (seeds seeds))
        (if (>= i end)
            v
            (call-with-values
             (lambda () (apply f i seeds))
             (lambda (elem . new-seeds)
               (%uvec-set! v i elem)
               (loop (+ i 1) (if (null? new-seeds) seeds new-seeds)))))))

    (define (%uvec-unfold-right! f v start end . seeds)
      (let loop ((i (- end 1)) (seeds seeds))
        (if (< i start)
            v
            (call-with-values
             (lambda () (apply f i seeds))
             (lambda (elem . new-seeds)
               (%uvec-set! v i elem)
               (loop (- i 1) (if (null? new-seeds) seeds new-seeds)))))))

    (define (%uvec->list v . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length v))))
        (let loop ((i (- end 1)) (acc '()))
          (if (< i start) acc (loop (- i 1) (cons (%uvec-ref v i) acc))))))

    (define (%uvec-reverse->list v . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length v))))
        (let loop ((i start) (acc '()))
          (if (>= i end) acc (loop (+ i 1) (cons (%uvec-ref v i) acc))))))

    (define (%uvec-list-> kind lst)
      (let* ((n (length lst)) (out (%uvec-make kind n (%uvec-default-fill kind))))
        (let loop ((i 0) (lst lst))
          (if (null? lst) out (begin (%uvec-set! out i (car lst)) (loop (+ i 1) (cdr lst)))))))

    (define (%uvec-generator v)
      (let ((i 0) (n (%uvec-length v)))
        (lambda ()
          (if (>= i n) (eof-object)
              (let ((x (%uvec-ref v i))) (set! i (+ i 1)) x)))))

    (define (%uvec-write v . port) (if (pair? port) (write v (car port)) (write v)))

    ;; --- generic extended surface: needs an explicit output kind ---

    (define (%uvec-unfold kind f len . seeds)
      (let ((out (%uvec-make kind len (%uvec-default-fill kind))))
        (let loop ((i 0) (seeds seeds))
          (if (= i len)
              out
              (call-with-values
               (lambda () (apply f i seeds))
               (lambda (elem . new-seeds)
                 (%uvec-set! out i elem)
                 (loop (+ i 1) (if (null? new-seeds) seeds new-seeds))))))))

    (define (%uvec-unfold-right kind f len . seeds)
      (let ((out (%uvec-make kind len (%uvec-default-fill kind))))
        (let loop ((i (- len 1)) (seeds seeds))
          (if (< i 0)
              out
              (call-with-values
               (lambda () (apply f i seeds))
               (lambda (elem . new-seeds)
                 (%uvec-set! out i elem)
                 (loop (- i 1) (if (null? new-seeds) seeds new-seeds))))))))

    (define (%uvec-copy kind v . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length v))))
        (let* ((n (- end start)) (out (%uvec-make kind n (%uvec-default-fill kind))))
          (let loop ((i 0))
            (when (< i n) (%uvec-set! out i (%uvec-ref v (+ start i))) (loop (+ i 1))))
          out)))

    (define (%uvec-reverse-copy kind v . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length v))))
        (let* ((n (- end start)) (out (%uvec-make kind n (%uvec-default-fill kind))))
          (let loop ((i 0))
            (when (< i n) (%uvec-set! out i (%uvec-ref v (- end i 1))) (loop (+ i 1))))
          out)))

    (define (%uvec-take kind v n) (%uvec-copy kind v 0 n))
    (define (%uvec-take-right kind v n) (%uvec-copy kind v (- (%uvec-length v) n) (%uvec-length v)))
    (define (%uvec-drop kind v n) (%uvec-copy kind v n (%uvec-length v)))
    (define (%uvec-drop-right kind v n) (%uvec-copy kind v 0 (- (%uvec-length v) n)))

    (define (%uvec-segment kind v n)
      (let ((len (%uvec-length v)))
        (let loop ((start 0) (acc '()))
          (if (>= start len) (reverse acc)
              (loop (min len (+ start n)) (cons (%uvec-copy kind v start (min len (+ start n))) acc))))))

    (define (%uvec-concatenate kind vs)
      (let* ((total (apply + (map %uvec-length vs)))
             (out (%uvec-make kind total (%uvec-default-fill kind))))
        (let loop ((vs vs) (offset 0))
          (if (null? vs)
              out
              (let ((v (car vs)) (n (%uvec-length (car vs))))
                (let copy ((i 0))
                  (when (< i n) (%uvec-set! out (+ offset i) (%uvec-ref v i)) (copy (+ i 1))))
                (loop (cdr vs) (+ offset n)))))))

    (define (%uvec-append kind . vs) (%uvec-concatenate kind vs))

    (define (%uvec-append-subvectors kind . args)
      (let loop ((args args) (parts '()))
        (if (null? args)
            (%uvec-concatenate kind (reverse parts))
            (loop (cdddr args) (cons (%uvec-copy kind (car args) (cadr args) (caddr args)) parts)))))

    (define (%uvec-map kind f v . vs)
      (let* ((n (%uvec-min-length (cons v vs))) (out (%uvec-make kind n (%uvec-default-fill kind))))
        (let loop ((i 0))
          (when (< i n)
            (%uvec-set! out i (apply f (%uvec-ref v i) (%uvec-map-refs i v vs)))
            (loop (+ i 1))))
        out))

    (define (%uvec-cumulate kind f knil v)
      (let* ((n (%uvec-length v)) (out (%uvec-make kind n (%uvec-default-fill kind))))
        (let loop ((i 0) (acc knil))
          (when (< i n)
            (let ((acc2 (f acc (%uvec-ref v i)))) (%uvec-set! out i acc2) (loop (+ i 1) acc2))))
        out))

    (define (%uvec-take-while kind pred v)
      (let ((n (%uvec-length v)))
        (let loop ((i 0))
          (if (or (= i n) (not (pred (%uvec-ref v i)))) (%uvec-copy kind v 0 i) (loop (+ i 1))))))

    (define (%uvec-drop-while kind pred v)
      (let ((n (%uvec-length v)))
        (let loop ((i 0))
          (if (or (= i n) (not (pred (%uvec-ref v i)))) (%uvec-copy kind v i n) (loop (+ i 1))))))

    (define (%uvec-take-while-right kind pred v)
      (let ((n (%uvec-length v)))
        (let loop ((i (- n 1)))
          (if (or (< i 0) (not (pred (%uvec-ref v i)))) (%uvec-copy kind v (+ i 1) n) (loop (- i 1))))))

    (define (%uvec-drop-while-right kind pred v)
      (let ((n (%uvec-length v)))
        (let loop ((i (- n 1)))
          (if (or (< i 0) (not (pred (%uvec-ref v i)))) (%uvec-copy kind v 0 (+ i 1)) (loop (- i 1))))))

    (define (%uvec-filter kind pred v)
      (let* ((n (%uvec-length v)) (tmp (%uvec-make kind n (%uvec-default-fill kind))))
        (let loop ((i 0) (j 0))
          (if (= i n)
              (%uvec-copy kind tmp 0 j)
              (if (pred (%uvec-ref v i))
                  (begin (%uvec-set! tmp j (%uvec-ref v i)) (loop (+ i 1) (+ j 1)))
                  (loop (+ i 1) j))))))

    (define (%uvec-remove kind pred v) (%uvec-filter kind (lambda (x) (not (pred x))) v))

    (define (%uvec-partition kind pred v)
      (let* ((n (%uvec-length v)) (out (%uvec-make kind n (%uvec-default-fill kind))))
        (let loop ((i 0) (front 0))
          (if (= i n)
              (begin
                (let loop2 ((i 0) (j front))
                  (when (< i n)
                    (if (not (pred (%uvec-ref v i)))
                        (begin (%uvec-set! out j (%uvec-ref v i)) (loop2 (+ i 1) (+ j 1)))
                        (loop2 (+ i 1) j))))
                (values out front))
              (if (pred (%uvec-ref v i))
                  (begin (%uvec-set! out front (%uvec-ref v i)) (loop (+ i 1) (+ front 1)))
                  (loop (+ i 1) front))))))

    (define (%uvec-reverse-list-> kind lst)
      (let* ((n (length lst)) (out (%uvec-make kind n (%uvec-default-fill kind))))
        (let loop ((i (- n 1)) (lst lst))
          (if (null? lst) out (begin (%uvec-set! out i (car lst)) (loop (- i 1) (cdr lst)))))))

    (define (%uvec->vector v . args)
      (let-values (((start end) (%opt-start-end args (%uvec-length v))))
        (let* ((n (- end start)) (out (make-vector n)))
          (let loop ((i 0)) (when (< i n) (vector-set! out i (%uvec-ref v (+ start i))) (loop (+ i 1))))
          out)))

    (define (%uvec-vector-> kind vec . args)
      (let-values (((start end) (%opt-start-end args (vector-length vec))))
        (let* ((n (- end start)) (out (%uvec-make kind n (%uvec-default-fill kind))))
          (let loop ((i 0)) (when (< i n) (%uvec-set! out i (vector-ref vec (+ start i))) (loop (+ i 1))))
          out)))

    (define (%uvec-orderable? kind) (not (memq kind '(c64 c128))))

    (define (%uvec-less? a b)
      (let ((na (%uvec-length a)) (nb (%uvec-length b)))
        (let loop ((i 0))
          (cond ((and (= i na) (= i nb)) #f)
                ((= i na) #t)
                ((= i nb) #f)
                ((< (%uvec-ref a i) (%uvec-ref b i)) #t)
                ((> (%uvec-ref a i) (%uvec-ref b i)) #f)
                (else (loop (+ i 1)))))))

    (define (%uvec-hash v)
      (let ((n (%uvec-length v)))
        (let loop ((i 0) (h 0))
          (if (= i n) (abs h) (loop (+ i 1) (+ (* h 31) (number-hash (%uvec-ref v i))))))))

    (define (%uvec-make-comparator kind)
      (make-comparator
       (lambda (obj) (and (%uvec? obj) (eq? (%uvec-kind obj) kind)))
       %uvec=
       (and (%uvec-orderable? kind) %uvec-less?)
       %uvec-hash))))
