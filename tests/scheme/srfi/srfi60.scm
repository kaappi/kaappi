;; SRFI-60 (integers as bits) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi60.scm

(import (scheme base) (srfi 60) (chibi test))

(test-begin "srfi-60")

;;; --- log* bitwise ops ---
(test 10 (logand 11 26))
(test 11 (logior 3 10))
(test 6 (logxor 3 5))
(test -11 (lognot 10))
(test 9 (lognot -10))

;;; --- bitwise-* aliases (SRFI-33 names, #1164) ---
(test 10 (bitwise-and 11 26))
(test 11 (bitwise-ior 3 10))
(test 6 (bitwise-xor 3 5))
(test -11 (bitwise-not 10))
(test 9 (bitwise-not -10))

;;; --- bitwise-if / bitwise-merge ---
(test 9 (bitwise-if 3 1 8))
(test 9 (bitwise-merge 3 1 8))

;;; --- logtest / any-bits-set? ---
(test #t (logtest 3 6))
(test #f (logtest 1 4))
(test #t (any-bits-set? 3 6))
(test #f (any-bits-set? 1 4))

;;; --- logbit? / bit-set? ---
(test #f (logbit? 0 2))
(test #t (logbit? 1 2))
(test #t (logbit? 2 4))
(test #f (bit-set? 0 2))
(test #t (bit-set? 1 2))
(test #t (bit-set? 2 4))

;;; --- ash / arithmetic-shift ---
(test 16 (ash 1 4))
(test 2 (ash 8 -2))
(test -16 (ash -1 4))
(test 16 (arithmetic-shift 1 4))
(test 2 (arithmetic-shift 8 -2))
(test -16 (arithmetic-shift -1 4))

;;; --- logcount / bit-count ---
(test 3 (logcount 13))
(test 0 (logcount 0))
(test 3 (bit-count 13))
(test 0 (bit-count 0))

;;; --- integer-length ---
(test 4 (integer-length 8))
(test 0 (integer-length 0))
(test 3 (integer-length -8))

;;; --- first-set-bit / log2-binary-factors ---
(test 0 (first-set-bit 1))
(test 1 (first-set-bit 6))
(test 3 (first-set-bit 8))
(test -1 (first-set-bit 0))
(test 0 (log2-binary-factors 1))
(test 1 (log2-binary-factors 6))
(test 3 (log2-binary-factors 8))
(test -1 (log2-binary-factors 0))

;;; --- bit-field ---
(test 2 (bit-field 13 1 3))
(test 0 (bit-field 6 0 1))

;;; --- copy-bit ---
(test 5 (copy-bit 0 4 #t))
(test 4 (copy-bit 0 5 #f))

;;; --- copy-bit-field ---
(test 10 (copy-bit-field 0 #b1010 0 4))
(test #b11111111 (copy-bit-field #b11110000 #b00001111 0 4))
(test 98 (copy-bit-field #b1101010 #b0010011 1 4))

;;; --- rotate-bit-field ---
(test 12 (rotate-bit-field #b0110 1 1 4))
(test #b110100 (rotate-bit-field #b110100 0 0 8))
(test 1 (rotate-bit-field #b0100 2 0 4))

;;; --- reverse-bit-field ---
(test 3 (reverse-bit-field #b1100 0 4))
(test 10 (reverse-bit-field 10 1 4))

;;; --- negative-operand semantics (two's complement) ---
(test 8 (logand -4 8))
(test 5 (logand -1 5))
(test -8 (logand -4 -6))
(test -2 (logior -4 2))
(test -6 (logxor -1 5))
(test -4 (ash -15 -2))

;;; --- integer->list / list->integer / booleans->integer (#1164) ---
(test '(#t #t #t #f) (integer->list 14))
(test '(#t #f #t) (integer->list 5))
(test '(#f #f #f #t #t #t #f) (integer->list 14 7))
(test '() (integer->list 0))
(test 14 (list->integer '(#t #t #t #f)))
(test 5 (list->integer '(#t #f #t)))
(test 0 (list->integer '()))
(test 14 (booleans->integer #t #t #t #f))
(test 5 (booleans->integer #t #f #t))
(test 0 (booleans->integer))

;;; --- round-trip: integer->list->integer ---
(test 42 (list->integer (integer->list 42)))
(test 0 (list->integer (integer->list 0)))
(test 255 (list->integer (integer->list 255)))

(test-end "srfi-60")
