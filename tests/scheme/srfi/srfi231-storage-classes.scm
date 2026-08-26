;; SRFI 231 (Intervals and Generalized Arrays) tests -- phase 1b: storage
;; classes. Arrays themselves are a later phase of this multi-slice SRFI,
;; tracked under issue #1694; (srfi 231) itself is not yet an importable
;; bare library.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231-storage-classes.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 160 u16) (srfi 231 storage-classes))

(test-begin "srfi-231-storage-classes")

;;; --- storage-class? disjointness ---
(test-equal #t (storage-class? s8-storage-class))
(test-equal #f (storage-class? 42))
(test-equal #f (storage-class? (vector)))

;;; --- a generic helper exercising the full 9-field contract on a
;;; storage class, used across every one of the 14 real classes below.
;;; Complex values read back from a c64/c128 body are always genuinely
;;; complex-tagged, including a zero imaginary part (an inexact zero imag
;;; stays complex, kaappi#2269), so numeric equality (=) is used for the
;;; value-carrying checks when both sides are numbers, since equal? would
;;; otherwise spuriously fail despite both sides being the same number.
;;; bad-value has no meaningful "checker rejects this" case for
;;; generic-storage-class (its checker always returns #t), so that
;;; assertion is a separate, optional check. ---
(define (%same? a b) (if (and (number? a) (number? b)) (= a b) (equal? a b)))

(define (check-storage-class sc value bad-value expected-default . rejects-bad?)
  (let* ((maker (storage-class-maker sc))
         (getter (storage-class-getter sc))
         (setter (storage-class-setter sc))
         (length-proc (storage-class-length sc))
         (checker (storage-class-checker sc))
         (body (maker 3 (storage-class-default sc))))
    (test-assert (%same? expected-default (storage-class-default sc)))
    (test-equal 3 (length-proc body))
    (test-assert (%same? expected-default (getter body 0)))
    (setter body 1 value)
    (test-assert (%same? value (getter body 1)))
    ;; exercise the copier field too -- otherwise a wrong copy procedure
    ;; would pass every other assertion here undetected
    (let ((copied (maker 3 (storage-class-default sc))))
      ((storage-class-copier sc) copied 0 body 0 3)
      (test-assert (%same? value (getter copied 1))))
    (test-equal #t (checker value))
    (when (or (null? rejects-bad?) (car rejects-bad?))
      (test-equal #f (checker bad-value)))
    (test-equal #t ((storage-class-data? sc) body))
    (test-equal #t (eq? body ((storage-class-data->body sc) body)))))

;; generic's checker accepts everything, including bad-value, by design;
;; its default fill value is #f (per the spec's own reference definition)
(check-storage-class generic-storage-class 42 99 #f #f)
;; char's default is #\null (NUL), per the reference's defaults list and
;; the official test suite -- the spec prose's #\0 is stale (#2354)
(check-storage-class char-storage-class #\z 42 #\null)
(check-storage-class s8-storage-class -100 200 0)
(check-storage-class s16-storage-class -30000 40000 0)
(check-storage-class s32-storage-class -2000000000 3000000000 0)
(check-storage-class s64-storage-class -9000000000000000000 9300000000000000000 0)
(check-storage-class u8-storage-class 200 -1 0)
(check-storage-class u16-storage-class 60000 -1 0)
(check-storage-class u32-storage-class 4000000000 -1 0)
(check-storage-class u64-storage-class 18000000000000000000 -1 0)
(check-storage-class f32-storage-class 3.5 "not a number" 0.0)
(check-storage-class f64-storage-class 3.5 "not a number" 0.0)
(check-storage-class c64-storage-class (make-rectangular 1.0 2.0) "not a number" 0.0)
(check-storage-class c128-storage-class (make-rectangular 1.0 2.0) "not a number" 0.0)

;;; --- generic checker specifically accepts anything, unlike every typed one ---
(test-equal #t ((storage-class-checker generic-storage-class) (vector 1 2 3)))
(test-equal #t ((storage-class-checker generic-storage-class) "a string"))

;;; --- u1 is a real storage class: bit-packed over u16vector exactly as
;;; the reference implements it and the spec documents (body = (vector
;;; valid-bit-count u16vector), little-endian within each u16) -- #2353.
;;; It cannot go through check-storage-class because its copier is #f
;;; (as in the reference; the spec allows a #f copier). f8/f16 remain
;;; bound-but-#f (f8 even in the reference; f16 is a documented scope
;;; reduction). ---
(test-equal #t (storage-class? u1-storage-class))
(test-equal 0 (storage-class-default u1-storage-class))
(test-equal #t ((storage-class-data? u1-storage-class) (u16vector 0 1)))
(let* ((body ((storage-class-maker u1-storage-class) 40 0))
       (getter (storage-class-getter u1-storage-class))
       (setter (storage-class-setter u1-storage-class))
       (checker (storage-class-checker u1-storage-class)))
  ;; all 40 bits round-trip, crossing three u16 boundaries
  (do ((i 0 (+ i 1))) ((= i 40)) (setter body i (modulo i 2)))
  (test-equal #t (let ((ok #t))
                   (do ((i 0 (+ i 1))) ((= i 40))
                     (unless (= (getter body i) (modulo i 2)) (set! ok #f)))
                   ok))
  (test-equal 40 ((storage-class-length u1-storage-class) body))
  (test-equal #t (checker 0))
  (test-equal #t (checker 1))
  (test-equal #f (checker 2))
  (test-equal #f (checker -1)))
;; an all-ones initializer fills every bit
(let ((ones ((storage-class-maker u1-storage-class) 20 1)))
  (test-equal #t (let ((ok #t))
                   (do ((i 0 (+ i 1))) ((= i 20))
                     (unless (= 1 ((storage-class-getter u1-storage-class) ones i)) (set! ok #f)))
                   ok)))
;; data->body wraps a raw u16vector (16 valid bits per element), it is
;; not the identity like every other built-in class
(let* ((raw (u16vector #b111100110111))
       (body ((storage-class-data->body u1-storage-class) raw)))
  (test-equal #t (vector? body))
  (test-equal 16 ((storage-class-length u1-storage-class) body))
  (test-equal 1 ((storage-class-getter u1-storage-class) body 0))
  (test-equal 0 ((storage-class-getter u1-storage-class) body 3)))
(test-equal #t (guard (e (#t #t))
                  ((storage-class-data->body u1-storage-class) 'a)
                  #f))
(test-equal #f f8-storage-class)
(test-equal #f f16-storage-class)

;;; --- fX/cX checkers match the reference exactly: inexact reals only
;;; for f32/f64 (flonum?), inexact-real-part + inexact-imag-part for
;;; c64/c128 -- exact values were silently coerced (1/3 into c64 lost
;;; f32 precision) before kaappi#2355 ---
(test-equal #t ((storage-class-checker f64-storage-class) 3.5))
(test-equal #t ((storage-class-checker f64-storage-class) -0.0))
(test-equal #f ((storage-class-checker f64-storage-class) 3))
(test-equal #f ((storage-class-checker f64-storage-class) 1/3))
(test-equal #f ((storage-class-checker f32-storage-class) 42))
(test-equal #t ((storage-class-checker c64-storage-class) (make-rectangular 3.5 -1.0)))
(test-equal #t ((storage-class-checker c64-storage-class) 3.5))     ; inexact real: imag-part is 0.0
(test-equal #f ((storage-class-checker c64-storage-class) (make-rectangular 3 4)))
(test-equal #f ((storage-class-checker c64-storage-class) 1/3))
(test-equal #f ((storage-class-checker c128-storage-class) (make-rectangular 1/2 2)))

;;; --- make-storage-class is a fully general public constructor, not just
;;; internal machinery for the 14 named singletons ---
(let* ((sc (make-storage-class vector-ref vector-set! symbol? make-vector vector-copy! vector-length
                                'default-sym vector? values))
       (body ((storage-class-maker sc) 2 (storage-class-default sc))))
  ((storage-class-setter sc) body 0 'hello)
  (test-equal 'hello ((storage-class-getter sc) body 0))
  (test-equal 'default-sym ((storage-class-getter sc) body 1))
  (test-equal #t ((storage-class-checker sc) 'a-symbol))
  (test-equal #f ((storage-class-checker sc) 42)))

;;; --- storage-class-data->body: rejects wrong-typed data (raising, like
;;; the reference implementation) and hands correct data back unchanged
;;; (the body IS the data -- zero-copy) ---
(test-equal #t (guard (e (#t #t))
                  ((storage-class-data->body u8-storage-class) 'a)
                  #f))
(test-equal #t (guard (e (#t #t))
                  ((storage-class-data->body generic-storage-class) 'a)
                  #f))
(test-equal #t (guard (e (#t #t))
                  ((storage-class-data->body f64-storage-class) "not an f64vector")
                  #f))
(let ((v (vector 1 2 3)) (u #u8(9 8)))
  (test-equal #t (eq? v ((storage-class-data->body generic-storage-class) v)))
  (test-equal #t (eq? u ((storage-class-data->body u8-storage-class) u))))

(let ((runner (test-runner-current)))
  (test-end "srfi-231-storage-classes")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
