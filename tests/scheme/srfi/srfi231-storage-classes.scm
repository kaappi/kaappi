;; SRFI 231 (Intervals and Generalized Arrays) tests -- phase 1b: storage
;; classes. Arrays themselves are a later phase of this multi-slice SRFI,
;; tracked under issue #1694; (srfi 231) itself is not yet an importable
;; bare library.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231-storage-classes.scm

(import (scheme base) (scheme inexact) (scheme process-context) (srfi 64)
        (srfi 160 u16) (srfi 160 f32) (srfi 160 f64) (srfi 160 c64)
        (srfi 231 storage-classes))

(test-begin "srfi-231-storage-classes")

;;; --- storage-class? disjointness ---
(test-equal #t (storage-class? s8-storage-class))
(test-equal #f (storage-class? 42))
(test-equal #f (storage-class? (vector)))

;;; --- a generic helper exercising the full 9-field contract on a
;;; storage class, used across every one of the 15 real classes below
;;; that have a copier (u1's is #f, as in the reference).
;;; Complex values read back from a c64/c128 body are always genuinely
;;; complex-tagged, including a zero imaginary part (an inexact zero imag
;;; stays complex, kaappi#2269), so numeric equality (=) is used for the
;;; value-carrying checks when both sides are numbers, since equal? would
;;; otherwise spuriously fail despite both sides being the same number.
;;; bad-value has no meaningful "checker rejects this" case for
;;; generic-storage-class (its checker always returns #t), so that
;;; assertion is a separate, optional check. A second optional is the
;;; copier's body-units per logical element -- 1 everywhere except the
;;; complex classes, whose interleaved-float bodies hold 2 (see the c64
;;; section below). ---
(define (%same? a b) (if (and (number? a) (number? b)) (= a b) (equal? a b)))

(define (check-storage-class sc value bad-value expected-default . opts)
  (let ((rejects-bad? (or (null? opts) (car opts)))
        (units-per-element (if (or (null? opts) (null? (cdr opts))) 1 (cadr opts))))
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
    ;; would pass every other assertion here undetected; the copier counts
    ;; BODY units, so complex classes copy 2 floats per logical element
    (let ((copied (maker 3 (storage-class-default sc))))
      ((storage-class-copier sc) copied 0 body 0 (* 3 units-per-element))
      (test-assert (%same? value (getter copied 1))))
    (test-equal #t (checker value))
    (when rejects-bad?
      (test-equal #f (checker bad-value)))
    (test-equal #t ((storage-class-data? sc) body))
    (test-equal #t (eq? body ((storage-class-data->body sc) body))))))

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
;; f16 stores 3.5 exactly (binary16 has plenty of precision there), so
;; the setter/getter round-trip inside check-storage-class holds as-is
(check-storage-class f16-storage-class 3.5 "not a number" 0.0)
;; complex classes: the copier counts FLOATS (2 per complex element)
(check-storage-class c64-storage-class (make-rectangular 1.0 2.0) "not a number" 0.0 #t 2)
(check-storage-class c128-storage-class (make-rectangular 1.0 2.0) "not a number" 0.0 #t 2)

;;; --- generic checker specifically accepts anything, unlike every typed one ---
(test-equal #t ((storage-class-checker generic-storage-class) (vector 1 2 3)))
(test-equal #t ((storage-class-checker generic-storage-class) "a string"))

;;; --- u1 is a real storage class: bit-packed over u16vector exactly as
;;; the reference implements it and the spec documents (body = (vector
;;; valid-bit-count u16vector), little-endian within each u16) -- #2353.
;;; It cannot go through check-storage-class because its copier is #f
;;; (as in the reference; the spec allows a #f copier). f16 is likewise
;;; real (software half-floats over u16vector, #2379 -- see the f16
;;; section below); f8 alone remains bound-but-#f, as in the SRFI's own
;;; reference implementation. ---
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

;;; --- f16 is a real storage class: software half-floats over u16vector,
;;; a faithful port of the reference implementation's arithmetic codec
;;; (#2379; the u16vector substrate makes the spec's #f escape clause --
;;; written for implementations lacking a homogeneous vector type -- inap-
;;; plicable). The codec itself is library-internal, so every probe below
;;; goes through the public getter/setter on a one-element body. ---
(define %f16-get (storage-class-getter f16-storage-class))
(define %f16-set! (storage-class-setter f16-storage-class))
(define %f16-body (make-u16vector 1 0))
(define (%f16-decode p)            ; bit pattern -> double
  (u16vector-set! %f16-body 0 p)
  (%f16-get %f16-body 0))
(define (%f16-encode x)            ; double -> bit pattern
  (%f16-set! %f16-body 0 x)
  (u16vector-ref %f16-body 0))

;; directed edges of the IEEE 754 binary16 conversion
(test-equal 1.0 (%f16-decode #x3C00))
(test-equal #x3C00 (%f16-encode 1.0))
(test-equal -0.0 (%f16-decode #x8000))
(test-equal #x8000 (%f16-encode -0.0))
(test-equal +inf.0 (%f16-decode #x7C00))
(test-equal #x7C00 (%f16-encode +inf.0))
(test-equal -inf.0 (%f16-decode #xFC00))
(test-equal #xFC00 (%f16-encode -inf.0))
;; every NaN pattern decodes to +nan.0 and re-encodes canonically to
;; #x7FFF: NaN sign/payload is not portable (a sanctioned deviation, the
;; reference itself documents decode yielding +nan.0)
(test-equal +nan.0 (%f16-decode #x7C01))
(test-equal #x7FFF (%f16-encode +nan.0))
;; max finite 65504, and the overflow tie: 65520.0 (exactly halfway to
;; the next binade) rounds UP to +inf.0 while 65519.9 stays 65504 -- the
;; mantissa-carry-at-top-binade branch
(test-equal 65504.0 (%f16-decode #x7BFF))
(test-equal #x7BFF (%f16-encode 65504.0))
(test-equal #x7C00 (%f16-encode 65520.0))
(test-equal #x7BFF (%f16-encode 65519.9))
;; below the smallest subnormal rounds to SIGNED zero; the tie 2^-25
;; goes to 0 (ties-to-even), and the subnormal tie 1.5*2^-24 to
;; mantissa 2 (even), not 1
(test-equal #x8000 (%f16-encode (- (expt 2.0 -30))))
(test-equal #x0000 (%f16-encode (expt 2.0 -25)))
(test-equal #x0002 (%f16-encode (* 1.5 (expt 2.0 -24))))
;; smallest subnormal / largest subnormal / smallest normal
(test-equal #x0001 (%f16-encode (expt 2.0 -24)))
(test-equal (- (expt 2.0 -14) (expt 2.0 -24)) (%f16-decode #x03FF))
(test-equal (expt 2.0 -14) (%f16-decode #x0400))
;; mantissa carry inside the format: 2047.5/1024 rounds up to 2.0
;; (pattern #x4000); the near tie 2046.5/1024 stays even-down at
;; 2046/1024 (pattern #x3FFE)
(test-equal #x4000 (%f16-encode (/ 2047.5 1024.0)))
(test-equal 2.0 (%f16-decode #x4000))
(test-equal #x3FFE (%f16-encode (/ 2046.5 1024.0)))
;; negative values mirror every branch (sign tested via eqv? on -0.0 and
;; via the sign bit of the pattern)
(test-equal #xBC00 (%f16-encode -1.0))
(test-equal -65504.0 (%f16-decode #xFBFF))
(test-equal #xFC00 (%f16-encode -65520.0))

;; exhaustive: every one of the 65536 bit patterns round-trips
;; decode+encode unchanged, except the 2046 NaN payloads (e=31, m<>0),
;; which canonically collapse to #x7FFF. This is the reference
;; implementation's own validation strategy (its test comment block),
;; tightened to a full sweep: encode(decode(p)) = p pins the codec's
;; rounding exactly -- any double rounding or wrong-ulp scaling breaks
;; some pattern.
(let ((ok #t)
      (nan-patterns 0))
  (do ((p 0 (+ p 1)))
      ((= p 65536))
    (let ((x (%f16-decode p)))
      (if (nan? x)
          (set! nan-patterns (+ nan-patterns 1))
          (unless (= p (%f16-encode x)) (set! ok #f)))))
  (test-equal #t ok)
  (test-equal 2046 nan-patterns))

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

;;; --- c64/c128 use the reference's interleaved-float representation
;;; (#2382): the body is an f32/f64vector of twice the logical length
;;; with real and imaginary parts alternating, and even-length float
;;; vectors are accepted as data ZERO-COPY (the spec's data? contract --
;;; "#t if and only if data->body returns a body sharing data with data,
;;; without copying" -- is what lets the reference's data shape
;;; interoperate, which a converting data->body would violate). Bodies
;;; are no longer native c64vectors/c128vectors, though the byte layout
;;; is identical (2 consecutive f32s/f64s per element either way). ---
(test-equal #t ((storage-class-data? c64-storage-class) (make-f32vector 10)))
(test-equal #t ((storage-class-data? c128-storage-class) (make-f64vector 10)))
;; odd-length float vectors cannot be complex bodies
(test-equal #f ((storage-class-data? c64-storage-class) (make-f32vector 5)))
(test-equal #f ((storage-class-data? c128-storage-class) (make-f64vector 7)))
;; and the native complex vectors are no longer the body type
(test-equal #f ((storage-class-data? c64-storage-class) (make-c64vector 4)))
;; data->body shares (does not copy) the reference's data shape
(let ((v (make-f32vector 6 0.0)))
  (test-equal #t (eq? v ((storage-class-data->body c64-storage-class) v))))
(test-equal #t (guard (e (#t #t))
                  ((storage-class-data->body c64-storage-class) (make-f32vector 5))
                  #f))
;; interleave: getter/setter/length across the re/im pairs
(let* ((v (f32vector 1.0 2.0 3.0 4.0 5.0 6.0))
       (body ((storage-class-data->body c64-storage-class) v))
       (get (storage-class-getter c64-storage-class))
       (put! (storage-class-setter c64-storage-class)))
  (test-equal 3 ((storage-class-length c64-storage-class) body))
  (test-equal 1.0+2.0i (get body 0))
  (test-equal 3.0+4.0i (get body 1))
  (test-equal 5.0+6.0i (get body 2))
  ;; the setter explodes the complex into the two float slots
  (put! body 1 (make-rectangular 7.0 8.0))
  (test-equal 7.0 (f32vector-ref v 2))
  (test-equal 8.0 (f32vector-ref v 3))
  (test-equal 7.0+8.0i (get body 1)))
;; the maker fills alternating re/im across the whole body
(let* ((body ((storage-class-maker c64-storage-class) 2 (make-rectangular -1.5 2.5)))
       (get (storage-class-getter c64-storage-class)))
  (test-equal -1.5+2.5i (get body 0))
  (test-equal -1.5+2.5i (get body 1))
  (test-equal 4 (f32vector-length body)))

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
