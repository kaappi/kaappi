;; SRFI-60 (integers as bits) conformance tests — audit Phase 3d
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi60.scm

(import (scheme base) (srfi 60) (chibi test))

(test-begin "srfi-60")

;;; --- positive-operand bitwise ops ---
(test 10 (logand 11 26))
(test 11 (logior 3 10))
(test 6 (logxor 3 5))
(test -11 (lognot 10))
(test 9 (lognot -10))

;;; --- logtest / logbit? ---
(test #t (logtest 3 6))
(test #f (logtest 1 4))
(test #f (logbit? 0 2))
(test #t (logbit? 1 2))
(test #t (logbit? 2 4))

;;; --- shifts ---
(test 16 (ash 1 4))
(test 2 (ash 8 -2))
(test -16 (ash -1 4))

;;; --- counting ---
(test 3 (logcount 13))
(test 0 (logcount 0))
(test 4 (integer-length 8))
(test 0 (integer-length 0))
(test 3 (integer-length -8))

;;; --- bit-field ---
(test 2 (bit-field 13 1 3))
(test 0 (bit-field 6 0 1))

;;; --- negative-operand semantics (two's complement, SRFI-60 example set) ---
(test 8 (logand -4 8))
(test 5 (logand -1 5))
(test -8 (logand -4 -6))
(test -2 (logior -4 2))
(test -6 (logxor -1 5))
(test 9 (bitwise-merge 3 1 8))
(test -4 (ash -15 -2))

;;; --- bitwise-* canonical names (SRFI-60 dual naming) ---
;; FAIL: #1164 (bitwise-and/-ior/-xor/-not aliases not exported from (srfi 60))
;; (test 10 (bitwise-and 11 26))
;; (test 11 (bitwise-ior 3 10))

(test-end "srfi-60")
