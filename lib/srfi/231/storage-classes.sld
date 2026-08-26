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
;;; arrays). f8 is left #f even in the SRFI's OWN reference implementation
;;; (no standard 8-bit-float Scheme type exists anywhere), and f16 -- which
;;; the reference implements as software half-floats -- remains #f as a
;;; documented scope reduction (#2353).
(define-library (srfi 231 storage-classes)
  (import (scheme base)
          (srfi 160 s8) (srfi 160 s16) (srfi 160 s32) (srfi 160 s64)
          (srfi 160 u16) (srfi 160 u32) (srfi 160 u64)
          (srfi 160 f32) (srfi 160 f64) (srfi 160 c64) (srfi 160 c128)
          ;; bitwise-and/ior/not for u1's bit-packing (R7RS-small has no
          ;; bitwise primitives of its own)
          (srfi 60))
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

    (define c64-storage-class
      (make-storage-class c64vector-ref c64vector-set! %inexact-complex-checker
                           make-c64vector c64vector-copy! c64vector-length
                           (make-rectangular 0.0 0.0) c64vector? (%checked-data->body c64vector? "c64-storage-class" "c64vector")))
    (define c128-storage-class
      (make-storage-class c128vector-ref c128vector-set! %inexact-complex-checker
                           make-c128vector c128vector-copy! c128vector-length
                           (make-rectangular 0.0 0.0) c128vector? (%checked-data->body c128vector? "c128-storage-class" "c128vector")))

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

    (define f8-storage-class #f)
    ;; f16 stays #f for now: the reference implements software half-floats
    ;; over u16vectors, which is a deliberate port of its own to make, not
    ;; a mechanical substrate mapping like u1's (#2353 tracks the call).
    (define f16-storage-class #f)))
