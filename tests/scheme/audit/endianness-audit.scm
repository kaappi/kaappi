;;; Byte-order audit -- every Scheme-visible surface whose answer could differ
;;; on a big-endian host (audit v2, Phase 7C).
;;;
;;; WHY THIS FILE EXISTS
;;;
;;; s390x is the project's only big-endian target and exists precisely to catch
;;; byte-order bugs (kaappi#1654). What `ci.yml`'s `s390x-test` job actually
;;; runs is three steps -- the cross-compile, `zig build test
;;; -Dtarget=s390x-linux`, and `tests/scheme/r7rs/r7rs-tests.scm`. It does NOT
;;; run `run-all.sh`, so no `tests/scheme/**` file except `r7rs-tests.scm` has
;;; ever executed on a big-endian machine, and `r7rs-tests.scm` imports no SRFI
;;; with a byte-order-sensitive surface. This file gathers those surfaces into
;;; one command:
;;;
;;;     zig-out/bin/kaappi tests/scheme/audit/endianness-audit.scm
;;;
;;; and `tools/run-endian-suite.sh` runs it alongside the other files that
;;; carry endian assertions.
;;;
;;; THE TAUTOLOGY THIS FILE REPLACES
;;;
;;; `tests/scheme/srfi/srfi74.scm` asserted, under the heading "native
;;; accessors agree with explicit-endianness accessors", that
;;;
;;;     (blob-u32-native-set! b1 0 42)
;;;     (blob-u32-set! (endianness native) b2 0 42)
;;;
;;; produce the same bytes. But `lib/srfi/74.sld` defines
;;;
;;;     (define (blob-u32-native-set! b k n) (blob-u32-set! (endianness native) b k n))
;;;
;;; so the two sides are the same call. The assertion cannot fail on any host.
;;;
;;; What CAN fail, and is pinned here, is a three-link chain:
;;;
;;;   1. `(endianness big)` and `(endianness little)` produce the documented
;;;      byte layouts. Host-independent -- the expected bytes below are
;;;      constants, not functions of the platform -- so these run and mean the
;;;      same thing everywhere, and they are the assertions a swapped Horner
;;;      loop in `lib/srfi/74.sld` would break.
;;;   2. `(endianness native)` selects between those two by `%host-big-endian?`.
;;;      Pinned here relative to that primitive, never to a hardcoded order:
;;;      the byte layout of a native access is a value the platform decides.
;;;   3. `%host-big-endian?` tells the truth about the machine. NOT pinnable
;;;      from Scheme -- every Scheme route to the host's byte order goes
;;;      through this same primitive. It is pinned against an actual memory
;;;      probe in `src/tests_endian.zig`, which the s390x leg already runs.
;;;
;;; Nothing below asserts a value the platform decides. Where a native-order
;;; layout is checked, the expectation is computed from `%host-big-endian?`.

(import (scheme base) (scheme write) (scheme char) (scheme process-context)
        (srfi 64) (srfi 74) (srfi 135)
        (srfi 160 u8) (srfi 160 u16) (srfi 160 s16) (srfi 160 u32) (srfi 160 s32)
        (srfi 160 u64) (srfi 160 s64) (srfi 160 f32) (srfi 160 f64)
        (srfi 160 c64) (srfi 160 c128)
        (prefix (srfi 271 determinized) d:)
        (kaappi primitives))

(test-begin "endianness audit")

(define (bl b) (blob->u8-list b))

(define (bytevector->list bv)
  (let loop ((i (- (bytevector-length bv) 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons (bytevector-u8-ref bv i) acc)))))

(define (write-to-string x)
  (let ((p (open-output-string))) (write x p) (get-output-string p)))

;;; ------------------------------------------------------------------
;;; 1. The two Scheme-visible facts about host byte order, pinned to
;;;    each other.
;;;
;;;    `%host-big-endian?` itself is ground truth as far as Scheme is
;;;    concerned; `src/tests_endian.zig` is where it meets the machine.
;;; ------------------------------------------------------------------

(test-assert "%host-big-endian? answers with a boolean"
             (boolean? (%host-big-endian?)))

(test-assert "(endianness native) is one of the two named orders"
             (memq (endianness native) '(big little)))

(test-equal "(endianness native) is 'big exactly when %host-big-endian? is true"
            (if (%host-big-endian?) 'big 'little)
            (endianness native))

(test-equal "(endianness big) is the symbol big" 'big (endianness big))
(test-equal "(endianness little) is the symbol little" 'little (endianness little))

;;; ------------------------------------------------------------------
;;; 2. SRFI 74 explicit endianness, checked at the byte level.
;;;
;;;    "The procedure blob-uint-ref ... interpreting the octets as the
;;;     representation of a number in the endianness specified by endianness"
;;;     -- SRFI 74, Operations on blobs.
;;;
;;;    Every expected byte list below is a constant. Each test value is chosen
;;;    so its byte-reverse is a *different* number, which is what makes the
;;;    assertion discriminating rather than symmetric: 0x0102030405060708
;;;    reversed is 0x0807060504030201, and a palindromic value like
;;;    0x01010101 would pass under either order.
;;; ------------------------------------------------------------------

(let ((b (make-blob 2)))
  (blob-u16-set! (endianness big) b 0 #x0102)
  (test-equal "blob-u16-set! big puts the most significant byte first"
              '(1 2) (bl b)))

(let ((b (make-blob 2)))
  (blob-u16-set! (endianness little) b 0 #x0102)
  (test-equal "blob-u16-set! little puts the least significant byte first"
              '(2 1) (bl b)))

(let ((b (make-blob 4)))
  (blob-u32-set! (endianness big) b 0 #x01020304)
  (test-equal "blob-u32-set! big byte layout" '(1 2 3 4) (bl b))
  (test-equal "blob-u32-ref big reads back what big wrote"
              #x01020304 (blob-u32-ref (endianness big) b 0))
  (test-equal "blob-u32-ref little over big-written bytes reads the reverse"
              #x04030201 (blob-u32-ref (endianness little) b 0)))

(let ((b (make-blob 4)))
  (blob-u32-set! (endianness little) b 0 #x01020304)
  (test-equal "blob-u32-set! little byte layout" '(4 3 2 1) (bl b)))

(let ((b (make-blob 8)))
  (blob-u64-set! (endianness big) b 0 #x0102030405060708)
  (test-equal "blob-u64-set! big byte layout" '(1 2 3 4 5 6 7 8) (bl b))
  (test-equal "blob-u64-ref big round-trips"
              #x0102030405060708 (blob-u64-ref (endianness big) b 0)))

(let ((b (make-blob 8)))
  (blob-u64-set! (endianness little) b 0 #x0102030405060708)
  (test-equal "blob-u64-set! little byte layout" '(8 7 6 5 4 3 2 1) (bl b))
  (test-equal "blob-u64-ref little round-trips"
              #x0102030405060708 (blob-u64-ref (endianness little) b 0)))

;; Signed accessors: sign extension must not depend on which end the sign byte
;; landed on. -2 is 0xFFFE / 0xFFFFFFFE, whose discriminating byte is the 0xFE.
(let ((b (make-blob 2)))
  (blob-s16-set! (endianness big) b 0 -2)
  (test-equal "blob-s16-set! big puts the sign byte first" '(255 254) (bl b))
  (test-equal "blob-s16-ref big round-trips a negative"
              -2 (blob-s16-ref (endianness big) b 0)))

(let ((b (make-blob 2)))
  (blob-s16-set! (endianness little) b 0 -2)
  (test-equal "blob-s16-set! little puts the sign byte last" '(254 255) (bl b))
  (test-equal "blob-s16-ref little round-trips a negative"
              -2 (blob-s16-ref (endianness little) b 0)))

(let ((b (make-blob 4)))
  (blob-s32-set! (endianness big) b 0 -2)
  (test-equal "blob-s32-set! big byte layout" '(255 255 255 254) (bl b)))

(let ((b (make-blob 4)))
  (blob-s32-set! (endianness little) b 0 -2)
  (test-equal "blob-s32-set! little byte layout" '(254 255 255 255) (bl b)))

(let ((b (make-blob 8)))
  (blob-s64-set! (endianness big) b 0 -2)
  (test-equal "blob-s64-set! big byte layout"
              '(255 255 255 255 255 255 255 254) (bl b))
  (test-equal "blob-s64-ref big round-trips a negative"
              -2 (blob-s64-ref (endianness big) b 0)))

(let ((b (make-blob 8)))
  (blob-s64-set! (endianness little) b 0 -2)
  (test-equal "blob-s64-set! little byte layout"
              '(254 255 255 255 255 255 255 255) (bl b))
  (test-equal "blob-s64-ref little round-trips a negative"
              -2 (blob-s64-ref (endianness little) b 0)))

;; A 64-bit magnitude past the fixnum range (2^47) exercises the bignum path
;; through the same Horner loops. 2^63 - 1 is 0x7FFFFFFFFFFFFFFF.
(let ((b (make-blob 8)))
  (blob-u64-set! (endianness big) b 0 #x7F0102030405060E)
  (test-equal "blob-u64-set! big byte layout beyond the fixnum range"
              '(127 1 2 3 4 5 6 14) (bl b))
  (test-equal "blob-u64-ref big round-trips beyond the fixnum range"
              #x7F0102030405060E (blob-u64-ref (endianness big) b 0)))

;;; Generic width accessors at sizes with no fixed-width alias.

(let ((b (make-blob 3)))
  (blob-uint-set! 3 (endianness big) b 0 #x010203)
  (test-equal "blob-uint-set! size 3 big byte layout" '(1 2 3) (bl b)))

(let ((b (make-blob 3)))
  (blob-uint-set! 3 (endianness little) b 0 #x010203)
  (test-equal "blob-uint-set! size 3 little byte layout" '(3 2 1) (bl b)))

(let ((b (make-blob 5)))
  (blob-uint-set! 5 (endianness big) b 0 #x0102030405)
  (test-equal "blob-uint-set! size 5 big byte layout" '(1 2 3 4 5) (bl b))
  (test-equal "blob-uint-ref size 5 big round-trips"
              #x0102030405 (blob-uint-ref 5 (endianness big) b 0)))

(let ((b (make-blob 3)))
  (blob-sint-set! 3 (endianness little) b 0 -2)
  (test-equal "blob-sint-set! size 3 little byte layout" '(254 255 255) (bl b))
  (test-equal "blob-sint-ref size 3 little round-trips a negative"
              -2 (blob-sint-ref 3 (endianness little) b 0)))

(let ((b (make-blob 3)))
  (blob-sint-set! 3 (endianness big) b 0 -2)
  (test-equal "blob-sint-set! size 3 big byte layout" '(255 255 254) (bl b)))

;;; List conversions carry the same order through, element by element.

(test-equal "uint-list->blob size 2 big byte layout"
            '(1 2 2 1) (bl (uint-list->blob 2 (endianness big) '(#x0102 #x0201))))
(test-equal "uint-list->blob size 2 little byte layout"
            '(2 1 1 2) (bl (uint-list->blob 2 (endianness little) '(#x0102 #x0201))))
(test-equal "blob->uint-list size 2 big reads elements in order"
            '(#x0102 #x0304) (blob->uint-list 2 (endianness big) (u8-list->blob '(1 2 3 4))))
(test-equal "blob->uint-list size 2 little reads elements in order"
            '(#x0201 #x0403) (blob->uint-list 2 (endianness little) (u8-list->blob '(1 2 3 4))))
(test-equal "blob->sint-list size 2 big sign-extends per element"
            '(-2 1) (blob->sint-list 2 (endianness big) (u8-list->blob '(255 254 0 1))))
(test-equal "sint-list->blob size 4 little byte layout"
            '(254 255 255 255) (bl (sint-list->blob 4 (endianness little) '(-2))))

;;; ------------------------------------------------------------------
;;; 3. SRFI 74 native accessors -- the replacement for the tautology.
;;;
;;;    The expectation is derived from `%host-big-endian?`, never hardcoded:
;;;    a native access's byte layout is a value the platform decides. What is
;;;    asserted is that native SELECTS the right one of the two layouts
;;;    section 2 has already pinned independently.
;;; ------------------------------------------------------------------

(define (native-layout big-bytes little-bytes)
  (if (%host-big-endian?) big-bytes little-bytes))

(let ((b (make-blob 2)))
  (blob-u16-native-set! b 0 #x0102)
  (test-equal "blob-u16-native-set! lays out bytes in the host's order"
              (native-layout '(1 2) '(2 1)) (bl b)))

(let ((b (make-blob 4)))
  (blob-u32-native-set! b 0 #x01020304)
  (test-equal "blob-u32-native-set! lays out bytes in the host's order"
              (native-layout '(1 2 3 4) '(4 3 2 1)) (bl b))
  (test-equal "blob-u32-native-ref round-trips"
              #x01020304 (blob-u32-native-ref b 0)))

(let ((b (make-blob 8)))
  (blob-u64-native-set! b 0 #x0102030405060708)
  (test-equal "blob-u64-native-set! lays out bytes in the host's order"
              (native-layout '(1 2 3 4 5 6 7 8) '(8 7 6 5 4 3 2 1)) (bl b))
  (test-equal "blob-u64-native-ref round-trips"
              #x0102030405060708 (blob-u64-native-ref b 0)))

(let ((b (make-blob 4)))
  (blob-s32-native-set! b 0 -2)
  (test-equal "blob-s32-native-set! lays out bytes in the host's order"
              (native-layout '(255 255 255 254) '(254 255 255 255)) (bl b))
  (test-equal "blob-s32-native-ref round-trips a negative"
              -2 (blob-s32-native-ref b 0)))

(let ((b (make-blob 2)))
  (blob-s16-native-set! b 0 -2)
  (test-equal "blob-s16-native-set! lays out bytes in the host's order"
              (native-layout '(255 254) '(254 255)) (bl b))
  (test-equal "blob-s16-native-ref round-trips a negative"
              -2 (blob-s16-native-ref b 0)))

(let ((b (make-blob 8)))
  (blob-s64-native-set! b 0 -2)
  (test-equal "blob-s64-native-ref round-trips a negative"
              -2 (blob-s64-native-ref b 0)))

;; The other half of "native selects the right one": on a little-endian host a
;; native write must NOT match the big-endian layout, and vice versa. Without
;; this, a `native` arm that always answered 'big would still pass everything
;; above on a big-endian machine.
(let ((native (make-blob 4)) (other (make-blob 4)))
  (blob-u32-native-set! native 0 #x01020304)
  (blob-u32-set! (if (%host-big-endian?) (endianness little) (endianness big))
                 other 0 #x01020304)
  (test-assert "a native write differs from the opposite explicit order"
               (not (equal? (bl native) (bl other)))))

;;; ------------------------------------------------------------------
;;; 4. SRFI 160 numeric vectors.
;;;
;;;    Multi-byte elements are stored in HOST-NATIVE byte order in a raw byte
;;;    buffer (`primitives_srfi160.zig`, `native_endian`). That order is not
;;;    observable from Scheme -- there is no byte view of a NumericVector, and
;;;    the six `%numeric-vector-*` primitives are the entire native surface --
;;;    so nothing here asserts a layout. What IS observable is that the two
;;;    independent hand-written decoders agree with the encoder: element
;;;    access (`primitives_srfi160.zig`) and the printer's own numeric-vector
;;;    arm (`printer.zig`). On a little-endian host they cannot disagree even
;;;    if both were wrong; on s390x a one-sided byte-order mistake shows up
;;;    here. Values are chosen so each byte-reverse is a different number.
;;; ------------------------------------------------------------------

(test-equal "u16vector: ref agrees with the encoder" 258 (u16vector-ref (u16vector 258) 0))
(test-equal "u16vector: printer agrees with the encoder"
            "#<u16vector 258>" (write-to-string (u16vector 258)))
(test-equal "s16vector: ref agrees with the encoder on a negative"
            -2 (s16vector-ref (s16vector -2) 0))
(test-equal "s16vector: printer agrees with the encoder on a negative"
            "#<s16vector -2>" (write-to-string (s16vector -2)))
(test-equal "u32vector: ref agrees with the encoder"
            16909060 (u32vector-ref (u32vector 16909060) 0))
(test-equal "u32vector: printer agrees with the encoder"
            "#<u32vector 16909060>" (write-to-string (u32vector 16909060)))
(test-equal "s32vector: ref agrees with the encoder on a negative"
            -2 (s32vector-ref (s32vector -2) 0))
(test-equal "u64vector: ref agrees with the encoder"
            72623859790382856 (u64vector-ref (u64vector 72623859790382856) 0))
(test-equal "u64vector: printer agrees with the encoder"
            "#<u64vector 72623859790382856>"
            (write-to-string (u64vector 72623859790382856)))
(test-equal "s64vector: ref agrees with the encoder on a negative"
            -2 (s64vector-ref (s64vector -2) 0))
(test-equal "f32vector: ref agrees with the encoder" 1.5 (f32vector-ref (f32vector 1.5) 0))
(test-equal "f64vector: ref agrees with the encoder" 1.5 (f64vector-ref (f64vector 1.5) 0))
(test-equal "f64vector: printer agrees with the encoder"
            "#<f64vector 1.5>" (write-to-string (f64vector 1.5)))
(test-equal "f64vector: an asymmetric double survives encode/decode"
            1.0000000000000002 (f64vector-ref (f64vector 1.0000000000000002) 0))

;; Complex elements are two consecutive reals in the same buffer, so a
;; byte-order mistake can also swap real and imaginary halves. -2.5 vs 1.5
;; makes that swap observable.
(test-equal "c64vector: ref keeps real and imaginary in order"
            (make-rectangular 1.5 -2.5)
            (c64vector-ref (c64vector (make-rectangular 1.5 -2.5)) 0))
(test-equal "c128vector: ref keeps real and imaginary in order"
            (make-rectangular 1.5 -2.5)
            (c128vector-ref (c128vector (make-rectangular 1.5 -2.5)) 0))
(test-equal "c64vector: printer agrees with the encoder"
            "#<c64vector 1.5-2.5i>"
            (write-to-string (c64vector (make-rectangular 1.5 -2.5))))

;; Adjacent elements must not bleed into one another -- the failure mode a
;; width/offset mistake produces, which byte-order bugs often accompany.
(test-equal "u16vector: adjacent elements stay separate"
            '(258 513 1027) (u16vector->list (u16vector 258 513 1027)))
(test-equal "u32vector: adjacent elements stay separate"
            '(16909060 33752069) (u32vector->list (u32vector 16909060 33752069)))
(test-equal "s64vector: adjacent elements stay separate"
            '(-2 1 -9007199254740993)
            (s64vector->list (s64vector -2 1 -9007199254740993)))
(test-equal "f64vector: adjacent elements stay separate"
            '(1.5 -2.5) (f64vector->list (f64vector 1.5 -2.5)))

;; u8 is a plain bytevector, so its "byte order" is the identity on every host
;; -- the discriminating control for the block above.
(test-equal "u8vector is a bytevector and has no byte order to get wrong"
            '(1 2 3) (bytevector->list (u8vector 1 2 3)))

;;; ------------------------------------------------------------------
;;; 5. SRFI 135 UTF-16 conversions.
;;;
;;;    "textual->utf16be ... returns a bytevector containing the UTF-16BE
;;;     encoding" -- SRFI 135. These orders are named by the procedure, not by
;;;    the host, so every expectation here is a constant on every platform.
;;;    `tests/scheme/srfi/srfi135.scm` has no utf16 coverage at all.
;;; ------------------------------------------------------------------

(test-equal "textual->utf16be puts the high byte first"
            '(0 65 0 66) (bytevector->list (textual->utf16be (text #\A #\B))))
(test-equal "textual->utf16le puts the low byte first"
            '(65 0 66 0) (bytevector->list (textual->utf16le (text #\A #\B))))
(test-equal "textual->utf16 emits a big-endian BOM followed by big-endian data"
            '(#xFE #xFF 0 65) (bytevector->list (textual->utf16 (text #\A))))

;; A codepoint whose two bytes differ makes the order discriminating; U+00E9
;; is 0x00E9 and U+03BB (lambda) is 0x03BB.
(test-equal "textual->utf16be of a non-ASCII BMP codepoint"
            '(#x03 #xBB) (bytevector->list (textual->utf16be (text #\x3BB))))
(test-equal "textual->utf16le of a non-ASCII BMP codepoint"
            '(#xBB #x03) (bytevector->list (textual->utf16le (text #\x3BB))))

;; A surrogate pair is where a UTF-16 byte-order mistake hides best: each of
;; the two units must be byte-swapped independently, and a whole-pair swap
;; still decodes to *a* character. U+1F600 is D83D DE00.
(test-equal "textual->utf16be of an astral codepoint (surrogate pair)"
            '(#xD8 #x3D #xDE #x00) (bytevector->list (textual->utf16be (text #\x1F600))))
(test-equal "textual->utf16le of an astral codepoint (surrogate pair)"
            '(#x3D #xD8 #x00 #xDE) (bytevector->list (textual->utf16le (text #\x1F600))))
(test-equal "utf16be->text round-trips an astral codepoint"
            "\x1F600;" (textual->string (utf16be->text (textual->utf16be (text #\x1F600)))))
(test-equal "utf16le->text round-trips an astral codepoint"
            "\x1F600;" (textual->string (utf16le->text (textual->utf16le (text #\x1F600)))))

;; BOM dispatch: the reader must follow the BOM it is given, not the host.
(test-equal "utf16->text follows a little-endian BOM"
            "A" (textual->string (utf16->text (bytevector #xFF #xFE #x41 #x00))))
(test-equal "utf16->text follows a big-endian BOM"
            "A" (textual->string (utf16->text (bytevector #xFE #xFF #x00 #x41))))
(test-equal "utf16->text with no BOM defaults to big-endian"
            "A" (textual->string (utf16->text (bytevector #x00 #x41))))

(test-equal "utf16be->text decodes big-endian bytes"
            "AB" (textual->string (utf16be->text (textual->utf16be (text #\A #\B)))))
(test-equal "utf16le->text decodes little-endian bytes"
            "AB" (textual->string (utf16le->text (textual->utf16le (text #\A #\B)))))
(test-equal "utf16->text honours a big-endian BOM"
            "\x3BB;" (textual->string (utf16->text (textual->utf16 (text #\x3BB)))))

;;; ------------------------------------------------------------------
;;; 6. Byte-oriented surfaces that must NOT vary with host order.
;;;
;;;    These are the discriminating controls for the whole file: UTF-8 and
;;;    bytevectors are defined over octets, so a big-endian host must produce
;;;    byte-for-byte identical answers. If one of these ever differs on s390x,
;;;    something is byte-punning a multi-byte scalar that should not be.
;;; ------------------------------------------------------------------

(test-equal "string->utf8 of a 2-byte codepoint is order-independent"
            '(#xCE #xBB) (bytevector->list (string->utf8 "\x3BB;")))
(test-equal "string->utf8 of a 3-byte codepoint is order-independent"
            '(#xE2 #x82 #xAC) (bytevector->list (string->utf8 "\x20AC;")))
(test-equal "string->utf8 of a 4-byte codepoint is order-independent"
            '(#xF0 #x9F #x98 #x80) (bytevector->list (string->utf8 "\x1F600;")))
(test-equal "utf8->string round-trips a 4-byte codepoint"
            "\x1F600;" (utf8->string (string->utf8 "\x1F600;")))
(test-equal "bytevector literals keep their index order"
            '(1 2 3 4) (bytevector->list #u8(1 2 3 4)))
(test-equal "char->integer is a codepoint, not a byte layout"
            955 (char->integer #\x3BB))

;;; ------------------------------------------------------------------
;;; 7. Exact integers wider than a machine word.
;;;
;;;    Bignum limbs are u64 in little-endian LIMB order (not byte order),
;;;    each limb serialized whole. Arithmetic across the limb boundary is
;;;    where a limb-order confusion would surface as a wrong value.
;;; ------------------------------------------------------------------

(test-equal "a bignum straddling the 64-bit limb boundary is exact"
            18446744073709551617 (+ (expt 2 64) 1))
(test-equal "a bignum's low bits survive the limb boundary"
            1 (modulo (+ (expt 2 64) 1) (expt 2 32)))
(test-equal "a bignum's high limb survives division"
            (expt 2 32) (quotient (expt 2 64) (expt 2 32)))
(test-equal "number->string of a two-limb bignum"
            "18446744073709551617" (number->string (+ (expt 2 64) 1)))
(test-equal "a negative two-limb bignum round-trips through string->number"
            (- (+ (expt 2 64) 1)) (string->number "-18446744073709551617"))

;;; ------------------------------------------------------------------
;;; 8. SRFI 271 determinized random ports: golden byte sequences.
;;;
;;;    `primitives_random_port.zig` and `types_port.zig` move u64s across the
;;;    bytevector boundary with an explicit `.little` in four places: the seed
;;;    words in, the state words in, the state words out, and each 8-byte
;;;    output block. `tests/scheme/srfi/srfi271.scm` compares one port against
;;;    another *on the same host*, so a swap present on both sides of any of
;;;    those pairings cancels out and stays green everywhere -- the same
;;;    cancelling pairing the `.sbc` round-trip tests have (audit v2, 7D).
;;;
;;;    Every expected value below is a literal, derived from the published
;;;    xoshiro256** algorithm rather than captured from this implementation,
;;;    so it means the same thing on a big-endian host as on a little-endian
;;;    one. The two directions never touch: the "from a seed" assertions
;;;    consult no literal state, and the "from a literal state" assertions
;;;    consult no seed.
;;; ------------------------------------------------------------------

(define endian-seed
  #u8(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
      17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32))

(define (endian-seeded-port) (d:make-random-port (open-input-bytevector endian-seed)))

;; Direction 1: seed bytes -> state words -> output blocks.
;; xoshiro256** mixes the words, so a byte-swapped seed read produces a
;; different stream rather than a mirrored one -- there is nothing here for a
;; swap on the output side to cancel against.
(test-equal "SRFI 271: a fixed 32-byte seed yields a fixed first 16 output bytes"
            #u8(#xE8 #xCB #x61 #xF8 #x8E #x25 #xBC #x52
                #x80 #x32 #xCB #x61 #xF8 #x8E #x25 #xBC)
            (read-bytevector 16 (endian-seeded-port)))

;; The state of an *unread* port is the cancelling case, stated explicitly so
;; the assertion after it is not mistaken for a duplicate: the words go in
;; through readInt(.little) and straight back out through writeInt(.little),
;; so the state bytes equal the seed bytes under any consistent byte order.
(test-equal "SRFI 271: an unread port's state echoes the seed bytes (the cancelling case)"
            endian-seed
            (bytevector-copy (d:random-port-state (endian-seeded-port)) 14 46))

;; After one byte the words have advanced, so the state bytes are a real
;; function of the seed rather than a copy of it.
(test-equal "SRFI 271: the state after one byte is a fixed 46-byte sequence"
            #u8(#x53 #x32 #x37 #x31 #x01 #x01 #xE8 #xCB
                #x61 #xF8 #x8E #x25 #xBC #x52 #x11 #x12
                #x13 #x14 #x15 #x16 #x17 #x38 #x19 #x1A
                #x1B #x1C #x1D #x1E #x1F #x00 #x10 #x10
                #x02 #x04 #x06 #x08 #x0A #x0C #x02 #x02
                #x02 #x02 #x02 #x06 #x02 #x02)
            (let ((p (endian-seeded-port)))
              (read-u8 p)
              (d:random-port-state p)))

;; Direction 2: a literal state in. Consults nothing above.
(define endian-literal-state
  #u8(#x53 #x32 #x37 #x31 #x01 #x08 #x00 #x00
      #x00 #x00 #x00 #x00 #x00 #x00 #x08 #x07
      #x06 #x05 #x04 #x03 #x02 #x01 #x18 #x17
      #x16 #x15 #x14 #x13 #x12 #x11 #x28 #x27
      #x26 #x25 #x24 #x23 #x22 #x21 #x38 #x37
      #x36 #x35 #x34 #x33 #x32 #x31))

(test-assert "SRFI 271: the hand-written literal state is accepted as a state"
             (d:random-port-state? endian-literal-state))

(test-equal "SRFI 271: a literal state yields a fixed first 8 output bytes"
            #u8(#x7A #x9D #x07 #x71 #xDA #x43 #xAD #x16)
            (read-bytevector 8 (d:make-random-port endian-literal-state)))

(test-equal "SRFI 271: a literal state's own state after three bytes is fixed"
            #u8(#x53 #x32 #x37 #x31 #x01 #x03 #x7A #x9D
                #x07 #x71 #xDA #x43 #xAD #x16 #x28 #x27
                #x26 #x25 #x24 #x23 #x22 #x21 #x38 #x37
                #x36 #x35 #x34 #x33 #x32 #x31 #x20 #x20
                #x10 #x0E #x0C #x0A #x08 #x06 #x04 #x04
                #x04 #x04 #x04 #x04 #x04 #x04)
            (let ((p (d:make-random-port endian-literal-state)))
              (read-bytevector 3 p)
              (d:random-port-state p)))

;; The fixed part of the layout, spelled out so a header change is a named
;; failure rather than a diff inside a 46-byte blob.
(test-equal "SRFI 271: a state begins with the ASCII magic S271 and version 1"
            '(83 50 55 49 1)
            (let ((st (d:random-port-state (endian-seeded-port))))
              (list (bytevector-u8-ref st 0) (bytevector-u8-ref st 1)
                    (bytevector-u8-ref st 2) (bytevector-u8-ref st 3)
                    (bytevector-u8-ref st 4))))

(test-equal "SRFI 271: a state is 46 bytes"
            46 (bytevector-length (d:random-port-state (endian-seeded-port))))

(let ((runner (test-runner-current)))
  (test-end "endianness audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
