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
;;; unchanged. The remaining 3 (u1, f8, f16) have no Kaappi-native
;;; representation; f8 is left #f even in the SRFI's OWN reference
;;; implementation (no standard 8-bit-float Scheme type exists anywhere),
;;; and u1/f16 -- though fully portable-implementable via bit-packing over
;;; a u16vector, per the reference implementation's own code -- are also
;;; deferred to #f for this phase as a documented, spec-sanctioned scope
;;; reduction rather than a blocker; revisit if a caller ever needs them.
(define-library (srfi 231 storage-classes)
  (import (scheme base)
          (srfi 160 s8) (srfi 160 s16) (srfi 160 s32) (srfi 160 s64)
          (srfi 160 u16) (srfi 160 u32) (srfi 160 u64)
          (srfi 160 f32) (srfi 160 f64) (srfi 160 c64) (srfi 160 c128))
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

    ;; Reference definitions from the spec text itself, reused verbatim --
    ;; Kaappi's native vector/string already satisfy every one of
    ;; make-storage-class's operational contracts (O(1) getter/setter,
    ;; maker taking n+fill, copier in R7RS vector-copy!/string-copy!'s
    ;; (to at from start end) order, checker, data? sharing test).
    (define generic-storage-class
      (make-storage-class vector-ref vector-set! (lambda (arg) #t)
                           make-vector vector-copy! vector-length
                           #f vector? values))

    (define char-storage-class
      (make-storage-class string-ref string-set! char?
                           make-string string-copy! string-length
                           #\0 string? values))

    (define (%exact-int-range-checker lo hi)
      (lambda (x) (and (exact-integer? x) (<= lo x hi))))

    (define s8-storage-class
      (make-storage-class s8vector-ref s8vector-set! (%exact-int-range-checker -128 127)
                           make-s8vector s8vector-copy! s8vector-length 0 s8vector? values))
    (define s16-storage-class
      (make-storage-class s16vector-ref s16vector-set! (%exact-int-range-checker -32768 32767)
                           make-s16vector s16vector-copy! s16vector-length 0 s16vector? values))
    (define s32-storage-class
      (make-storage-class s32vector-ref s32vector-set! (%exact-int-range-checker -2147483648 2147483647)
                           make-s32vector s32vector-copy! s32vector-length 0 s32vector? values))
    (define s64-storage-class
      (make-storage-class s64vector-ref s64vector-set!
                           (%exact-int-range-checker -9223372036854775808 9223372036854775807)
                           make-s64vector s64vector-copy! s64vector-length 0 s64vector? values))

    ;; u8 is a plain R7RS bytevector alias throughout this codebase (per
    ;; SRFI 160's own design), so its storage class is built directly on
    ;; (scheme base)'s bytevector procedures, not a (srfi 160 u8) import.
    (define u8-storage-class
      (make-storage-class bytevector-u8-ref bytevector-u8-set! (%exact-int-range-checker 0 255)
                           make-bytevector bytevector-copy! bytevector-length 0 bytevector? values))
    (define u16-storage-class
      (make-storage-class u16vector-ref u16vector-set! (%exact-int-range-checker 0 65535)
                           make-u16vector u16vector-copy! u16vector-length 0 u16vector? values))
    (define u32-storage-class
      (make-storage-class u32vector-ref u32vector-set! (%exact-int-range-checker 0 4294967295)
                           make-u32vector u32vector-copy! u32vector-length 0 u32vector? values))
    (define u64-storage-class
      (make-storage-class u64vector-ref u64vector-set! (%exact-int-range-checker 0 18446744073709551615)
                           make-u64vector u64vector-copy! u64vector-length 0 u64vector? values))

    (define f32-storage-class
      (make-storage-class f32vector-ref f32vector-set! real?
                           make-f32vector f32vector-copy! f32vector-length 0.0 f32vector? values))
    (define f64-storage-class
      (make-storage-class f64vector-ref f64vector-set! real?
                           make-f64vector f64vector-copy! f64vector-length 0.0 f64vector? values))

    ;; complex? is true of every number in Scheme's numeric tower
    ;; (real/rational/integer are all complex), matching the spec's own
    ;; intent that any number -- real or genuinely complex -- is valid.
    (define c64-storage-class
      (make-storage-class c64vector-ref c64vector-set! complex?
                           make-c64vector c64vector-copy! c64vector-length
                           (make-rectangular 0.0 0.0) c64vector? values))
    (define c128-storage-class
      (make-storage-class c128vector-ref c128vector-set! complex?
                           make-c128vector c128vector-copy! c128vector-length
                           (make-rectangular 0.0 0.0) c128vector? values))

    (define u1-storage-class #f)
    (define f8-storage-class #f)
    (define f16-storage-class #f)))
