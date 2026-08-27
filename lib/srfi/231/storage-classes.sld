;;; SRFI 231 -- Storage classes (phase 1b of #1694's SRFI 231 slice).
;;;
;;; A storage-class is a 9-field record of procedures/values managing a
;;; specialized array's backing store (getter, setter, checker, maker,
;;; copier, length, default, data?, data->body) -- confirmed via primary
;;; source + the official reference implementation before writing any code.
;;; This mirrors, and can directly extend, the (kind maker ref setter!
;;; length default) table already built for SRFI 63's array kinds
;;; (lib/srfi/63.sld's %kind-table), just with two more fields (checker,
;;; a value-validity predicate; data?/data->body, a zero-copy-sharing test
;;; and converter used by make-specialized-array-from-data in a later
;;; phase) and itself a first-class Scheme object rather than a bare list.
;;;
;;; 17 storage-class global variables must all be BOUND, but per spec --
;;; "Implementations with an appropriate homogeneous vector type should
;;; define the associated global variable using make-storage-class.
;;; Otherwise, they shall define the associated global variable to #f" --
;;; an implementation lacking the underlying element type may bind one to
;;; #f. 12 of the 17 map cleanly onto this codebase's already-shipped
;;; (srfi 160 <tag>) NumericVector substrate; 2 more (generic, char) need
;;; no numeric substrate at all -- Kaappi's native vector/string already
;;; satisfy the "linearly indexed, 0-based, vector-like" contract, and the
;;; spec gives their exact reference definitions verbatim, reused here
;;; unchanged. u1 is a direct port of the reference's own bit-packing over
;;; u16vector (the representation the spec itself documents for bit
;;; arrays), and f16 a faithful port of its software half-floats over
;;; u16vector (#2379) -- the spec's #f escape clause is for implementations
;;; lacking the substrate, which neither port is. f8 alone is left #f,
;;; even in the SRFI's OWN reference implementation (no standard 8-bit
;;; float Scheme type exists anywhere).
(define-library (srfi 231 storage-classes)
  (import (scheme base)
          (srfi 160 s8) (srfi 160 s16) (srfi 160 s32) (srfi 160 s64)
          (srfi 160 u16) (srfi 160 u32) (srfi 160 u64)
          (srfi 160 f32) (srfi 160 f64)
          ;; bitwise-and/ior/not for u1's bit-packing (R7RS-small has no
          ;; bitwise primitives of its own)
          (srfi 60)
          ;; finite?/nan? for the f16 codec's special-value classification
          (scheme inexact))
  (export make-storage-class storage-class?
          storage-class-getter storage-class-setter storage-class-checker
          storage-class-maker storage-class-copier storage-class-length
          storage-class-default storage-class-data? storage-class-data->body
          generic-storage-class char-storage-class
          s8-storage-class s16-storage-class s32-storage-class s64-storage-class
          u1-storage-class u8-storage-class u16-storage-class u32-storage-class u64-storage-class
          f8-storage-class f16-storage-class f32-storage-class f64-storage-class
          c64-storage-class c128-storage-class)
  (begin

    (define-record-type <storage-class>
      (make-storage-class getter setter checker maker copier length default data? data->body)
      storage-class?
      (getter storage-class-getter)
      (setter storage-class-setter)
      (checker storage-class-checker)
      (maker storage-class-maker)
      (copier storage-class-copier)
      (length storage-class-length)
      (default storage-class-default)
      (data? storage-class-data?)
      (data->body storage-class-data->body))

    ;; data->body: the body IS the data for every built-in class (no
    ;; offset/scale to install), but the contract still requires rejecting
    ;; wrong-typed data instead of handing it back as a would-be body
    ;; (reference implementation: "converts data to a body, raising an
    ;; exception if needed").
    (define (%checked-data->body pred class-name type-name)
      (lambda (data)
        (if (pred data)
            data
            (error (string-append "Expecting a " type-name
                                  " passed to (storage-class-data->body "
                                  class-name "): ")
                   data))))

    ;; Reference definitions from the spec text itself, reused verbatim --
    ;; Kaappi's native vector/string already satisfy every one of
    ;; make-storage-class's operational contracts (O(1) getter/setter,
    ;; maker taking n+fill, copier in R7RS vector-copy!/string-copy!'s
    ;; (to at from start end) order, checker, data? sharing test).
    (define generic-storage-class
      (make-storage-class vector-ref vector-set! (lambda (arg) #t)
                           make-vector vector-copy! vector-length
                           #f vector? (%checked-data->body vector? "generic-storage-class" "vector")))

    ;; Reference default is #\null (NUL, U+0000) -- generic-arrays.scm's
    ;; defaults list and the official test suite both assert it; the spec
    ;; prose's #\0 (digit zero) is stale relative to its own reference.
    (define char-storage-class
      (make-storage-class string-ref string-set! char?
                           make-string string-copy! string-length
                           #\null string? (%checked-data->body string? "char-storage-class" "string")))

    (define (%exact-int-range-checker lo hi)
      (lambda (x) (and (exact-integer? x) (<= lo x hi))))

    (define s8-storage-class
      (make-storage-class s8vector-ref s8vector-set! (%exact-int-range-checker -128 127)
                           make-s8vector s8vector-copy! s8vector-length 0 s8vector? (%checked-data->body s8vector? "s8-storage-class" "s8vector")))
    (define s16-storage-class
      (make-storage-class s16vector-ref s16vector-set! (%exact-int-range-checker -32768 32767)
                           make-s16vector s16vector-copy! s16vector-length 0 s16vector? (%checked-data->body s16vector? "s16-storage-class" "s16vector")))
    (define s32-storage-class
      (make-storage-class s32vector-ref s32vector-set! (%exact-int-range-checker -2147483648 2147483647)
                           make-s32vector s32vector-copy! s32vector-length 0 s32vector? (%checked-data->body s32vector? "s32-storage-class" "s32vector")))
    (define s64-storage-class
      (make-storage-class s64vector-ref s64vector-set!
                           (%exact-int-range-checker -9223372036854775808 9223372036854775807)
                           make-s64vector s64vector-copy! s64vector-length 0 s64vector? (%checked-data->body s64vector? "s64-storage-class" "s64vector")))

    ;; u8 is a plain R7RS bytevector alias throughout this codebase (per
    ;; SRFI 160's own design), so its storage class is built directly on
    ;; (scheme base)'s bytevector procedures, not a (srfi 160 u8) import.
    (define u8-storage-class
      (make-storage-class bytevector-u8-ref bytevector-u8-set! (%exact-int-range-checker 0 255)
                           make-bytevector bytevector-copy! bytevector-length 0 bytevector? (%checked-data->body bytevector? "u8-storage-class" "bytevector")))
    (define u16-storage-class
      (make-storage-class u16vector-ref u16vector-set! (%exact-int-range-checker 0 65535)
                           make-u16vector u16vector-copy! u16vector-length 0 u16vector? (%checked-data->body u16vector? "u16-storage-class" "u16vector")))
    (define u32-storage-class
      (make-storage-class u32vector-ref u32vector-set! (%exact-int-range-checker 0 4294967295)
                           make-u32vector u32vector-copy! u32vector-length 0 u32vector? (%checked-data->body u32vector? "u32-storage-class" "u32vector")))
    (define u64-storage-class
      (make-storage-class u64vector-ref u64vector-set! (%exact-int-range-checker 0 18446744073709551615)
                           make-u64vector u64vector-copy! u64vector-length 0 u64vector? (%checked-data->body u64vector? "u64-storage-class" "u64vector")))

    ;; fX/cX checkers match the reference exactly: f32/f64 accept only
    ;; inexact reals (flonum?, generic-arrays.scm's f32/f64 checker) and
    ;; c64/c128 only complexes whose real and imaginary parts are both
    ;; inexact. Accepting exact values silently coerces them (1/3 stored
    ;; into c64 narrows to f32 precision), diverging from the reference's
    ;; "value cannot be stored in body" error (#2355).
    (define (%flonum-checker x) (and (real? x) (inexact? x)))
    (define (%inexact-complex-checker x)
      (and (complex? x) (inexact? (real-part x)) (inexact? (imag-part x))))

    (define f32-storage-class
      (make-storage-class f32vector-ref f32vector-set! %flonum-checker
                           make-f32vector f32vector-copy! f32vector-length 0.0 f32vector? (%checked-data->body f32vector? "f32-storage-class" "f32vector")))
    (define f64-storage-class
      (make-storage-class f64vector-ref f64vector-set! %flonum-checker
                           make-f64vector f64vector-copy! f64vector-length 0.0 f64vector? (%checked-data->body f64vector? "f64-storage-class" "f64vector")))

    ;; c64/c128 -- a faithful port of the reference's representation
    ;; (generic-arrays.scm's make-complex-storage-classes): the body is a
    ;; homogeneous FLOAT vector (f32vector for c64, f64vector for c128) of
    ;; twice the logical length, real and imaginary parts interleaved.
    ;; data? accepts exactly the even-length float vectors that can serve
    ;; as the body zero-copy -- the spec's data? contract ("returns #t if
    ;; and only if data->body returns a body sharing data with data,
    ;; without copying") permits accepting the reference's data shape only
    ;; by actually using it as the body, so reference-coupled portable code
    ;; and the official suite's fixtures flow into
    ;; make-specialized-array-from-data unchanged (#2382; the class
    ;; previously rejected them -- kaappi's bodies were native
    ;; c64vector/c128vector). Kaappi's SRFI 160 c64vector/c128vector use
    ;; the identical byte layout -- 2 consecutive f32s/f64s per element,
    ;; never boxed -- so this is a change of type tag, not of memory
    ;; shape; the spec explicitly allows either representation ("another
    ;; implementation ... might make another choice"), and reference
    ;; fidelity is what interoperates. Consequence: the copier's element
    ;; granularity is FLOATS (2 per complex element), and
    ;; c64vector/c128vector data is no longer accepted -- convert with
    ;; make-specialized-array's maker or a copy loop if needed.
    (define (%complex-storage-class float-ref float-set! make-float-vector
                                    float-copy! float-length vec?
                                    class-name type-name)
      (make-storage-class
       ;; getter -- reassemble the interleaved pair (an inexact zero
       ;; imag stays complex, kaappi#2269, exactly like the native
       ;; c64vector decode)
       (lambda (body i)
         (make-rectangular (float-ref body (* 2 i))
                           (float-ref body (+ (* 2 i) 1))))
       ;; setter -- explode into the interleaved pair (f32 storage rounds)
       (lambda (body i obj)
         (float-set! body (* 2 i) (real-part obj))
         (float-set! body (+ (* 2 i) 1) (imag-part obj)))
       ;; checker
       %inexact-complex-checker
       ;; maker -- the fill exploded into alternating re/im
       (lambda (n val)
         (let* ((l (* 2 n))
                (re (real-part val))
                (im (imag-part val))
                (result (make-float-vector l)))
           (do ((i 0 (+ i 2)))
               ((= i l) result)
             (float-set! result i re)
             (float-set! result (+ i 1) im))))
       ;; copier
       float-copy!
       ;; length -- half the physical float count
       (lambda (body) (quotient (float-length body) 2))
       ;; default
       (make-rectangular 0.0 0.0)
       ;; data?
       (lambda (data)
         (and (vec? data) (even? (float-length data))))
       ;; data->body -- identity on even-length float vectors
       (lambda (data)
         (if (and (vec? data) (even? (float-length data)))
             data
             (error (string-append "Expecting a " type-name
                                   " with an even number of elements passed to (storage-class-data->body "
                                   class-name "): ")
                    data)))))

    (define c64-storage-class
      (%complex-storage-class f32vector-ref f32vector-set! make-f32vector
                              f32vector-copy! f32vector-length f32vector?
                              "c64-storage-class" "f32vector"))
    (define c128-storage-class
      (%complex-storage-class f64vector-ref f64vector-set! make-f64vector
                              f64vector-copy! f64vector-length f64vector?
                              "c128-storage-class" "f64vector"))

    ;; u1 -- bit arrays, ported from the reference implementation's own
    ;; bit-packing (generic-arrays.scm's u1-storage-class): the body is a
    ;; (vector n u16vector) pair where n is the number of VALID bits and
    ;; the u16vector holds the bit string little-endian within each u16
    ;; (bit i lives at u16[i div 16], bit position i mod 16). The spec
    ;; mandates uX for X=1 and documents exactly this representation, and
    ;; (srfi 160 u16) supplies the substrate, so #f was not the spec's
    ;; sanctioned fallback here (#2353). The reference passes #f for the
    ;; copier ("no copier (for now") and so do we; nothing in this
    ;; package ever calls storage-class-copier.
    (define u1-storage-class
      (make-storage-class
       ;; getter
       (lambda (v i)
         (let ((index (quotient i 16))
               (shift (modulo i 16))
               (bodyv (vector-ref v 1)))
           (bitwise-and (arithmetic-shift (u16vector-ref bodyv index) (- shift)) 1)))
       ;; setter
       (lambda (v i val)
         (let ((index (quotient i 16))
               (shift (modulo i 16))
               (bodyv (vector-ref v 1)))
           (u16vector-set! bodyv index
                           (bitwise-ior (arithmetic-shift val shift)
                                        (bitwise-and (u16vector-ref bodyv index)
                                                     (bitwise-not (arithmetic-shift 1 shift)))))))
       ;; checker -- 0 and 1 only
       (lambda (val) (and (exact-integer? val) (= 0 (bitwise-and -2 val))))
       ;; maker -- n is the exact requested bit count; an all-ones
       ;; initializer fills every bit of every u16 (extra tail bits past
       ;; n are dead storage the length getter never exposes)
       (lambda (size initializer)
         (let ((u16-size (quotient (+ size 15) 16)))
           (vector size (make-u16vector u16-size (if (= 0 initializer) 0 65535)))))
       ;; no copier, as in the reference
       #f
       ;; length -- the valid-bit count, not 16 * u16 length
       (lambda (v) (vector-ref v 0))
       ;; default
       0
       ;; data? -- raw u16vector of bits
       u16vector?
       ;; data->body -- every bit of the data is valid
       (lambda (data)
         (if (not (u16vector? data))
             (error "Expecting a u16vector passed to (storage-class-data->body u1-storage-class): " data)
             (vector (* 16 (u16vector-length data)) data)))))

    ;; f8 -- #f even in the SRFI's OWN reference implementation: no
    ;; standard 8-bit float format exists to conform to.
    (define f8-storage-class #f)

    ;; f16 -- software half-floats over a u16vector: a faithful
    ;; transliteration of the reference implementation's own codec
    ;; (generic-arrays.scm's f16->double / double->f16), hand-expanded
    ;; from its defining macro for the single instantiation (mantissa-width
    ;; 10, exponent-width 5, bias 15) the class needs (#2379). The codec
    ;; is pure arithmetic -- no host bit-reinterpretation anywhere -- which
    ;; is exactly why it ports to R7RS-small. Gambit-ism substitutions,
    ;; each semantics-preserving:
    ;;   ##flonum->fixnum (flround x) -> (exact (round x))
    ;;     (R7RS round IS ties-to-even, the required rounding mode)
    ;;   flscalbn x n -> (* x (expt 2.0 n))
    ;;     (every scale factor here is a power of two within f64's exact
    ;;     range, so the scale-exactly-then-round-ONCE shape -- no double
    ;;     rounding -- is preserved)
    ;;   ##flcopysign sign test -> (or (< x 0.0) (eqv? x -0.0))
    ;;     (comparisons don't distinguish -0.0; eqv? does, per R7RS)
    ;;   flfinite?/flnan? -> finite?/nan? from (scheme inexact)
    ;; The two structural properties that make this codec correct, both
    ;; from the reference and both preserved:
    ;;   - the subnormal branch scales by 2^24 directly: ONE rounding at
    ;;     the subnormal ulp (a normalize-then-shift formula would round
    ;;     twice, at the wrong ulp);
    ;;   - mantissa carry after rounding: a significand that rounds up to
    ;;     exactly 2048 bumps the exponent -- exact, no re-round; at the
    ;;     top binade it overflows to infinity. This is what rounds the
    ;;     tie 65520.0 UP to +inf.0 while 65519.9 stays 65504.0.
    ;; -0.0 round-trips both ways (#x8000 <-> -0.0); |x| below 2^-25
    ;; rounds to signed zero, with the tie 2^-25 exactly going to 0 (even)
    ;; and the subnormal tie 1.5*2^-24 to mantissa 2. NaN payloads are
    ;; not preserved -- decode yields +nan.0 and encode canonicalizes
    ;; every NaN to #x7FFF -- since a NaN's sign and payload are not
    ;; portable across implementations (decode yields +nan.0 either way).
    (define (%f16-decode x)   ;; exact integer in [0,65536) -> real
      (let ((e (bitwise-and 31 (arithmetic-shift x -10)))
            (m (bitwise-and 1023 x))
            (s (arithmetic-shift x -15)))
        (cond ((= e 31)
               (if (= m 0)
                   (if (= s 0) +inf.0 -inf.0)
                   +nan.0))
              ((> e 0)
               (let ((n (if (= s 0) (+ 1024 m) (- (+ 1024 m)))))
                 (* n (expt 2.0 (- e 25)))))
              ((= m 0)
               (if (= s 0) +0.0 -0.0))
              (else
               (let ((n (if (= s 0) m (- m))))
                 (* n (expt 2.0 -24)))))))

    ;; floor(log2|x|), clamped to [-15, 16], for a finite, nonzero real
    ;; x -- the reference's flilogb, written fresh as a halving/doubling
    ;; loop (exact at every step: multiplying by 2.0 or 0.5 never
    ;; rounds). The clamp loses nothing: %f16-encode only ever consumes
    ;; the classification ("<= -15", "in [-14,15]", ">= 16") plus the
    ;; exact exponent inside the normal range, and it bounds the loop to
    ;; ~31 iterations even for astronomically large or tiny doubles.
    (define (%ilogb x)
      (let ((ax (abs x)))
        (if (>= ax 1.0)
            (let loop ((e 0) (v ax))
              (cond ((< v 2.0) e)
                    ((>= e 16) 16)
                    (else (loop (+ e 1) (* v 0.5)))))
            (let loop ((e -1) (v (* ax 2.0)))
              (cond ((>= v 1.0) e)
                    ((<= e -15) -15)
                    (else (loop (- e 1) (* v 2.0))))))))

    (define (%f16-encode x)   ;; real -> exact integer in [0,65536)
      (define (%construct sign-bit biased-exponent mantissa)
        (bitwise-ior (arithmetic-shift sign-bit 15)
                     (bitwise-ior (arithmetic-shift biased-exponent 10)
                                  mantissa)))
      (let ((sign-bit (if (or (< x 0.0) (eqv? x -0.0)) 1 0)))
        (cond ((not (finite? x))
               (if (nan? x)
                   ;; canonical NaN: the sign bit of a NaN is unobservable
                   (%construct 0 31 1023)
                   ;; an infinity
                   (%construct sign-bit 31 0)))
              ((zero? x)
               ;; a zero (sign preserved)
               (%construct sign-bit 0 0))
              (else
               (let ((exponent (%ilogb x)))
                 (cond ((<= 16 exponent)
                        ;; infinity: the exponent is too large
                        (%construct sign-bit 31 0))
                       ((< -15 exponent)
                        ;; probably normal, finite in representation,
                        ;; unless the rounded mantissa carries
                        (let ((possible-mantissa
                               (exact (round (* (abs x)
                                                (expt 2.0 (- 10 exponent)))))))
                          (if (< possible-mantissa 2048)
                              ;; no overflow
                              (%construct sign-bit
                                          (+ exponent 15)
                                          (bitwise-and possible-mantissa 1023))
                              (if (= exponent 15)
                                  ;; maximum finite exponent: overflow to
                                  ;; infinity
                                  (%construct sign-bit 31 0)
                                  ;; increase exponent by 1, mantissa is
                                  ;; zero, no double rounding
                                  (%construct sign-bit (+ exponent 16) 0)))))

                       (else
                        ;; usually subnormal
                        (let ((possible-mantissa
                               (exact (round (* (abs x) (expt 2.0 24))))))
                          (if (< possible-mantissa 1024)
                              ;; doesn't overflow to normal
                              (%construct sign-bit 0 possible-mantissa)
                              ;; overflow to smallest normal
                              (%construct sign-bit 1 0))))))))))

    ;; Class wiring mirrors the reference's f16 entry exactly: the same
    ;; checker acceptance as f32/f64 (flonum? -- the setter ROUNDS, never
    ;; rejects), the fill encoded once by the maker, and the identity
    ;; data->body contract of every u16vector-backed class.
    (define f16-storage-class
      (make-storage-class
       ;; getter
       (lambda (body i) (%f16-decode (u16vector-ref body i)))
       ;; setter
       (lambda (body i obj) (u16vector-set! body i (%f16-encode obj)))
       ;; checker
       %flonum-checker
       ;; maker
       (lambda (n val) (make-u16vector n (%f16-encode val)))
       ;; copier
       u16vector-copy!
       ;; length
       u16vector-length
       ;; default
       0.0
       ;; data?
       u16vector?
       ;; data->body
       (%checked-data->body u16vector? "f16-storage-class" "u16vector")))))
