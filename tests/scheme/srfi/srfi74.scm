;; SRFI 74 (octet-addressed binary blocks) tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi74.scm
;;
;; The byte-order surface this SRFI exposes is audited in depth in
;; tests/scheme/audit/endianness-audit.scm (audit v2, Phase 7C), which also
;; explains why the native accessors cannot be pinned non-circularly from
;; Scheme alone. This file keeps the SRFI's own functional coverage.
;;
;; Every assertion carries a name: a failure here can surface on the big-endian
;; s390x leg, where SRFI-64 prints the failed assertion's *value* and not its
;; source, so an unnamed failure is literally a bare `#f` among 30 candidates.

(import (scheme base) (scheme process-context) (srfi 64) (srfi 74)
        (kaappi primitives))

(test-begin "srfi-74")

(test-equal "(endianness big) is eq? to itself"
            #t (eq? (endianness big) (endianness big)))
(test-equal "(endianness big) is not (endianness little)"
            #f (eq? (endianness big) (endianness little)))
(test-assert "(endianness native) is one of the two named orders"
             (or (eq? (endianness native) (endianness big))
                 (eq? (endianness native) (endianness little))))

(test-equal "blob? accepts a fresh blob" #t (blob? (make-blob 4)))
(test-equal "a blob is a bytevector" #t (bytevector? (make-blob 4)))
(test-equal "blob-length of a fresh blob" 4 (blob-length (make-blob 4)))
(test-equal "make-blob zero-fills" '(0 0 0 0) (blob->u8-list (make-blob 4)))
(test-equal "u8-list->blob preserves order" '(9 8 7) (blob->u8-list (u8-list->blob '(9 8 7))))
(test-equal "blob=? on equal blobs" #t (blob=? (make-blob 2) (u8-list->blob '(0 0))))
(test-equal "blob=? on differing blobs" #f (blob=? (u8-list->blob '(1 2)) (u8-list->blob '(1 3))))
(test-equal "blob-copy duplicates contents"
            '(1 2 3) (blob->u8-list (blob-copy (u8-list->blob '(1 2 3)))))

(let ((a (u8-list->blob '(1 2 3))) (b (make-blob 3)))
  (blob-copy! a 1 b 0 2)
  (test-equal "blob-copy! copies n octets from source-start" '(2 3 0) (blob->u8-list b)))

;; single-byte accessors
(let ((b (make-blob 2)))
  (blob-u8-set! b 0 200)
  (test-equal "blob-u8-ref reads what blob-u8-set! wrote" 200 (blob-u8-ref b 0))
  (blob-s8-set! b 1 -1)
  (test-equal "blob-s8-ref sign-extends" -1 (blob-s8-ref b 1))
  (test-equal "blob-u8-ref sees the same octet unsigned" 255 (blob-u8-ref b 1)))

;; fixed-width big/little round trips
(let ((b (make-blob 8)))
  (blob-u16-set! (endianness big) b 0 #x0102)
  (test-equal "blob-u16-set! big byte layout"
              '(1 2) (list (blob-u8-ref b 0) (blob-u8-ref b 1)))
  (test-equal "blob-u16-ref big round-trips" 258 (blob-u16-ref (endianness big) b 0))
  (blob-u16-set! (endianness little) b 2 #x0102)
  (test-equal "blob-u16-set! little byte layout"
              '(2 1) (list (blob-u8-ref b 2) (blob-u8-ref b 3)))
  (test-equal "blob-u16-ref little round-trips" 258 (blob-u16-ref (endianness little) b 2))
  (blob-s16-set! (endianness big) b 4 -1)
  (test-equal "blob-s16-ref big round-trips -1" -1 (blob-s16-ref (endianness big) b 4))
  (test-equal "the same octets read unsigned are 65535"
              65535 (blob-u16-ref (endianness big) b 4)))

(let ((b (make-blob 4)))
  (blob-u32-set! (endianness big) b 0 #xDEADBEEF)
  (test-equal "blob-u32-ref big round-trips" #xDEADBEEF (blob-u32-ref (endianness big) b 0))
  (test-equal "blob-u32-set! big byte layout"
              (list #xDE #xAD #xBE #xEF)
              (list (blob-u8-ref b 0) (blob-u8-ref b 1) (blob-u8-ref b 2) (blob-u8-ref b 3))))

(let ((b (make-blob 8)))
  (blob-s64-set! (endianness little) b 0 -123456789012345)
  (test-equal "blob-s64-ref little round-trips a large negative"
              -123456789012345 (blob-s64-ref (endianness little) b 0))
  ;; -123456789012345 is 0xFFFF_8FB7_79F2_2087, so the low byte is 0x87 and
  ;; the high byte 0xFF: a byte-level check, where the round trip above would
  ;; pass under either order.
  (test-equal "blob-s64-set! little byte layout"
              '(#x87 #x20 #xF2 #x79 #xB7 #x8F #xFF #xFF) (blob->u8-list b)))

;; Native accessors. NOT "native agrees with (endianness native)" -- that was
;; the assertion here until Phase 7C, and it could not fail on any host:
;; lib/srfi/74.sld *defines* blob-u32-native-set! as
;; (blob-u32-set! (endianness native) ...), so both sides were the same call.
;; What is pinned instead is that native selects the layout the host's own
;; byte order calls for, against the two explicit layouts checked above.
;; The remaining link -- %host-big-endian? telling the truth about the
;; machine -- is unreachable from Scheme and lives in src/tests_endian.zig.
(let ((b (make-blob 4)))
  (blob-u32-native-set! b 0 #x01020304)
  (test-equal "blob-u32-native-set! lays out bytes in the host's order"
              (if (%host-big-endian?) '(1 2 3 4) '(4 3 2 1))
              (blob->u8-list b))
  (test-equal "blob-u32-native-ref round-trips" #x01020304 (blob-u32-native-ref b 0)))

;; generic uint/sint at arbitrary sizes
(let ((b (make-blob 5)))
  (blob-uint-set! 5 (endianness big) b 0 1099511627775) ; 2^40 - 1
  (test-equal "blob-uint-ref size 5 big round-trips 2^40-1"
              1099511627775 (blob-uint-ref 5 (endianness big) b 0)))
(let ((b (make-blob 3)))
  (blob-sint-set! 3 (endianness little) b 0 -8388608) ; -(2^23)
  (test-equal "blob-sint-ref size 3 little round-trips -(2^23)"
              -8388608 (blob-sint-ref 3 (endianness little) b 0)))

;; list conversions
(test-equal "blob->uint-list inverts uint-list->blob (big)"
            '(1 2 3) (blob->uint-list 2 (endianness big) (uint-list->blob 2 (endianness big) '(1 2 3))))
(test-equal "blob->sint-list inverts sint-list->blob (little)"
            '(-1 -2 3) (blob->sint-list 2 (endianness little) (sint-list->blob 2 (endianness little) '(-1 -2 3))))

(let ((runner (test-runner-current)))
  (test-end "srfi-74")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
