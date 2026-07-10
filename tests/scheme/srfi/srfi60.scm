;; SRFI-60 (integers as bits) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi60.scm

(import (scheme base) (srfi 60) (scheme process-context) (srfi 64))

(test-begin "srfi-60")

;;; --- log* bitwise ops ---
(test-equal 10 (logand 11 26))
(test-equal 11 (logior 3 10))
(test-equal 6 (logxor 3 5))
(test-equal -11 (lognot 10))
(test-equal 9 (lognot -10))

;;; --- bitwise-* aliases (SRFI-33 names, #1164) ---
(test-equal 10 (bitwise-and 11 26))
(test-equal 11 (bitwise-ior 3 10))
(test-equal 6 (bitwise-xor 3 5))
(test-equal -11 (bitwise-not 10))
(test-equal 9 (bitwise-not -10))

;;; --- bitwise-if / bitwise-merge ---
(test-equal 9 (bitwise-if 3 1 8))
(test-equal 9 (bitwise-merge 3 1 8))

;;; --- logtest / any-bits-set? ---
(test-equal #t (logtest 3 6))
(test-equal #f (logtest 1 4))
(test-equal #t (any-bits-set? 3 6))
(test-equal #f (any-bits-set? 1 4))

;;; --- logbit? / bit-set? ---
(test-equal #f (logbit? 0 2))
(test-equal #t (logbit? 1 2))
(test-equal #t (logbit? 2 4))
(test-equal #f (bit-set? 0 2))
(test-equal #t (bit-set? 1 2))
(test-equal #t (bit-set? 2 4))

;;; --- ash / arithmetic-shift ---
(test-equal 16 (ash 1 4))
(test-equal 2 (ash 8 -2))
(test-equal -16 (ash -1 4))
(test-equal 16 (arithmetic-shift 1 4))
(test-equal 2 (arithmetic-shift 8 -2))
(test-equal -16 (arithmetic-shift -1 4))

;;; --- logcount / bit-count ---
(test-equal 3 (logcount 13))
(test-equal 0 (logcount 0))
(test-equal 3 (bit-count 13))
(test-equal 0 (bit-count 0))

;;; --- integer-length ---
(test-equal 4 (integer-length 8))
(test-equal 0 (integer-length 0))
(test-equal 3 (integer-length -8))

;;; --- first-set-bit / log2-binary-factors ---
(test-equal 0 (first-set-bit 1))
(test-equal 1 (first-set-bit 6))
(test-equal 3 (first-set-bit 8))
(test-equal -1 (first-set-bit 0))
(test-equal 0 (log2-binary-factors 1))
(test-equal 1 (log2-binary-factors 6))
(test-equal 3 (log2-binary-factors 8))
(test-equal -1 (log2-binary-factors 0))

;;; --- bit-field ---
(test-equal 2 (bit-field 13 1 3))
(test-equal 0 (bit-field 6 0 1))

;;; --- copy-bit ---
(test-equal 5 (copy-bit 0 4 #t))
(test-equal 4 (copy-bit 0 5 #f))

;;; --- copy-bit-field ---
(test-equal 10 (copy-bit-field 0 #b1010 0 4))
(test-equal #b11111111 (copy-bit-field #b11110000 #b00001111 0 4))
(test-equal 98 (copy-bit-field #b1101010 #b0010011 1 4))

;;; --- rotate-bit-field ---
(test-equal 12 (rotate-bit-field #b0110 1 1 4))
(test-equal #b110100 (rotate-bit-field #b110100 0 0 8))
(test-equal 1 (rotate-bit-field #b0100 2 0 4))

;;; --- reverse-bit-field ---
(test-equal 3 (reverse-bit-field #b1100 0 4))
(test-equal 10 (reverse-bit-field 10 1 4))

;;; --- negative-operand semantics (two's complement) ---
(test-equal 8 (logand -4 8))
(test-equal 5 (logand -1 5))
(test-equal -8 (logand -4 -6))
(test-equal -2 (logior -4 2))
(test-equal -6 (logxor -1 5))
(test-equal -4 (ash -15 -2))

;;; --- integer->list / list->integer / booleans->integer (#1164) ---
(test-equal '(#t #t #t #f) (integer->list 14))
(test-equal '(#t #f #t) (integer->list 5))
(test-equal '(#f #f #f #t #t #t #f) (integer->list 14 7))
(test-equal '() (integer->list 0))
(test-equal 14 (list->integer '(#t #t #t #f)))
(test-equal 5 (list->integer '(#t #f #t)))
(test-equal 0 (list->integer '()))
(test-equal 14 (booleans->integer #t #t #t #f))
(test-equal 5 (booleans->integer #t #f #t))
(test-equal 0 (booleans->integer))

;;; --- round-trip: integer->list->integer ---
(test-equal 42 (list->integer (integer->list 42)))
(test-equal 0 (list->integer (integer->list 0)))
(test-equal 255 (list->integer (integer->list 255)))

(let ((runner (test-runner-current)))
  (test-end "srfi-60")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
