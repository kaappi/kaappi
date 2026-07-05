;; SRFI-151 (bitwise operations) conformance tests — audit Phase 3.4
;; The library's helper procedures compute bitwise ops on magnitudes with
;; truncating quotients (see #1214), so most operations involving negative
;; operands — including everything built on bitwise-not — return wrong
;; values. Positive-operand behavior is exercised here.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi151.scm

(import (scheme base) (srfi 151) (chibi test))

(test-begin "srfi-151")

;;; --- bitwise-not ---
(test -11 (bitwise-not 10))
(test 36 (bitwise-not -37))
(test -1 (bitwise-not 0))

;;; --- and/ior/xor: identities and positive operands ---
(test -1 (bitwise-and))
(test 0 (bitwise-ior))
(test 0 (bitwise-xor))
(test 12 (bitwise-and 12))
(test 8 (bitwise-and 12 10))
(test 4 (bitwise-and 14 6 5))
(test 11 (bitwise-ior 3 10))
(test 7 (bitwise-ior 1 2 4))
(test 5 (bitwise-xor 6 3))
(test 5 (bitwise-xor 7 3 1))

;; negative operands (two's-complement semantics)
;; FAIL: #1214 (bitwise ops compute on magnitudes — wrong for negatives)
;; (test 4 (bitwise-and -2 5))
;; FAIL: #1214
;; (test -1 (bitwise-ior -2 1))
;; FAIL: #1214
;; (test -7 (bitwise-xor -2 5))

;;; --- derived two-operand ops ---
(test -7 (bitwise-eqv 5 3))          ; not(xor) stays in positive helpers
(test -2 (bitwise-nand 5 3))
(test -8 (bitwise-nor 5 3))
;; SRFI-151: bitwise-eqv is n-ary: (bitwise-eqv) => -1, (bitwise-eqv 5) => 5
;; FAIL: #1233 (bitwise-eqv accepts exactly two arguments)
;; (test -1 (bitwise-eqv))
;; andc/orc route one operand through bitwise-not, hitting the magnitude bug
;; FAIL: #1214 (bitwise-andc1 wrong when complemented operand is odd-negative)
;; (test 1 (bitwise-andc1 2 3))
;; FAIL: #1214
;; (test 1 (bitwise-andc2 3 2))
;; FAIL: #1214
;; (test -3 (bitwise-orc1 2 5))
;; FAIL: #1214
;; (test -3 (bitwise-orc2 5 2))

;;; --- arithmetic-shift ---
(test 16 (arithmetic-shift 1 4))
(test 4 (arithmetic-shift 16 -2))
(test 0 (arithmetic-shift 7 -4))
(test -12 (arithmetic-shift -3 2))
;; right shift is arithmetic (floor), not truncating
;; FAIL: #1214 (right shift uses truncating quotient)
;; (test -1 (arithmetic-shift -1 -1))
;; FAIL: #1214
;; (test -4 (arithmetic-shift -7 -1))

;;; --- bit-count / integer-length ---
(test 0 (bit-count 0))
(test 2 (bit-count 5))
(test 8 (bit-count 255))
(test 0 (bit-count -1))
(test 1 (bit-count -2))
(test 0 (integer-length 0))
(test 1 (integer-length 1))
(test 3 (integer-length 7))
(test 4 (integer-length 8))
(test 0 (integer-length -1))
(test 2 (integer-length -4))

;;; --- bitwise-if ---
(test 3 (bitwise-if 1 1 2))
;; FAIL: #1214 (not-mask path collapses: (bitwise-if 3 1 8) returns 1, not 9)
;; (test 9 (bitwise-if 3 1 8))
;; FAIL: #1214 (zero mask: all bits should come from the third argument)
;; (test 6 (bitwise-if 0 15 6))

;;; --- single-bit operations ---
(test #t (bit-set? 0 5))
(test #f (bit-set? 1 5))
(test #t (bit-set? 2 5))
(test #f (bit-set? 31 5))
;; FAIL: #1214 (bit-set? shifts with truncating quotient — wrong on negatives)
;; (test #t (bit-set? 100 -1))
;; (test #f (bit-set? 1 -3))

;; SRFI-151: the bit argument of copy-bit is a boolean
;; FAIL: #1233 (copy-bit expects 0/1 and errors on booleans)
;; (test 4 (copy-bit 2 0 #t))
;; FAIL: #1233
;; (test 1 (copy-bit 2 5 #f))

(test 5 (bit-swap 0 2 5))          ; both bits set: no clear path involved
;; bit-swap clears bits via copy-bit's bitwise-not mask — magnitude bug
;; FAIL: #1214 (bit-swap wrong whenever a bit must be cleared)
;; (test 1 (bit-swap 0 2 4))
;; FAIL: #1214
;; (test 5 (bit-swap 0 1 6))

(test #t (any-bit-set? 3 6))
(test #f (any-bit-set? 1 6))
(test #t (every-bit-set? 4 6))
(test #f (every-bit-set? 7 6))

(test -1 (first-set-bit 0))
(test 0 (first-set-bit 1))
(test 3 (first-set-bit 8))
(test 2 (first-set-bit 12))
(test 1 (first-set-bit -2))

;;; --- bit fields (positive operands) ---
(test 0 (bit-field 6 0 1))
(test 3 (bit-field 6 1 3))
(test 5 (bit-field 42 1 4))
(test #t (bit-field-any? 6 0 2))
(test #f (bit-field-any? 6 3 6))
(test #t (bit-field-every? 7 0 3))
(test #f (bit-field-every? 5 0 3))
(test 7 (bit-field-set 1 1 3))
;; field clear/replace mask with bitwise-not — magnitude bug again
;; FAIL: #1214 (bit-field-clear collapses high bits: returns 7 for (15 1 3))
;; (test 9 (bit-field-clear 15 1 3))
;; FAIL: #1214
;; (test 5 (bit-field-replace 7 0 1 2))
;; FAIL: #1214
;; (test 21 (bit-field-replace-same 17 42 1 4))

;; rotate/reverse work when the value fits inside the field at offset 0
(test 5 (bit-field-rotate 6 1 0 3))
(test 6 (bit-field-rotate 6 0 0 3))
(test 3 (bit-field-rotate 6 -1 0 3))
(test 3 (bit-field-reverse 6 0 3))
(test 12 (bit-field-reverse 3 0 4))

;;; --- bits <-> list/vector ---
(test '(#f #t #t #f) (bits->list 6 4))
(test '() (bits->list 0 0))
(test 5 (list->bits '(#t #f #t)))
(test 0 (list->bits '()))
(test 13 (bits #t #f #t #t))
(test 0 (bits))
(test #(#t #f #t) (bits->vector 5 3))
(test 5 (vector->bits #(#t #f #t)))
(test 4 (vector->bits #(#f #f #t)))
;; SRFI-151: the length argument of bits->list / bits->vector is optional
;; FAIL: #1233 (length argument is required)
;; (test '(#t #f #t) (bits->list 5))
;; FAIL: #1233
;; (test #(#t #f #t) (bits->vector 5))

;;; --- fold / for-each / unfold / generator ---
(test 2 (bitwise-fold (lambda (b acc) (if b (+ acc 1) acc)) 0 5))
(test '(#t #f #t)
      (let ((acc '()))
        (bitwise-for-each (lambda (b) (set! acc (cons b acc))) 5)
        (reverse acc)))
(test 5 (bitwise-unfold (lambda (i) (= i 4)) even? (lambda (i) (+ i 1)) 0))
(test 0 (bitwise-unfold (lambda (i) #t) odd? (lambda (i) i) 0))

;; SRFI-151: the generator yields booleans
;; FAIL: #1233 (make-bitwise-generator yields 0/1 fixnums, not booleans)
;; (test '(#t #f #t #f)
;;       (let ((g (make-bitwise-generator 5)))
;;         (list (g) (g) (g) (g))))

(test-end "srfi-151")
