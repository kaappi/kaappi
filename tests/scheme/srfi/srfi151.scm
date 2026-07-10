;; SRFI-151 (bitwise operations) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi151.scm

(import (scheme base) (srfi 151) (scheme process-context) (srfi 64))

(test-begin "srfi-151")

;;; --- bitwise-not ---
(test-equal -11 (bitwise-not 10))
(test-equal 36 (bitwise-not -37))
(test-equal -1 (bitwise-not 0))

;;; --- and/ior/xor: identities and positive operands ---
(test-equal -1 (bitwise-and))
(test-equal 0 (bitwise-ior))
(test-equal 0 (bitwise-xor))
(test-equal 12 (bitwise-and 12))
(test-equal 8 (bitwise-and 12 10))
(test-equal 4 (bitwise-and 14 6 5))
(test-equal 11 (bitwise-ior 3 10))
(test-equal 7 (bitwise-ior 1 2 4))
(test-equal 5 (bitwise-xor 6 3))
(test-equal 5 (bitwise-xor 7 3 1))

;; negative operands (two's-complement semantics)
(test-equal 8 (bitwise-and -4 8))
(test-equal 5 (bitwise-and -1 5))
(test-equal -8 (bitwise-and -4 -6))
(test-equal 4 (bitwise-and -2 5))
(test-equal -2 (bitwise-ior -4 2))
(test-equal -1 (bitwise-ior -2 1))
(test-equal -6 (bitwise-xor -1 5))
(test-equal -12 (bitwise-xor -4 8))
(test-equal -5 (bitwise-xor -2 5))

;;; --- derived two-operand ops ---
(test-equal -7 (bitwise-eqv 5 3))          ; not(xor) stays in positive helpers
(test-equal -2 (bitwise-nand 5 3))
(test-equal -8 (bitwise-nor 5 3))
(test-equal -1 (bitwise-eqv))
(test-equal 5 (bitwise-eqv 5))
(test-equal 1 (bitwise-eqv 1 1 1))
(test-equal 1 (bitwise-andc1 2 3))
(test-equal 1 (bitwise-andc2 3 2))
(test-equal -3 (bitwise-orc1 2 5))
(test-equal -3 (bitwise-orc2 5 2))

;;; --- arithmetic-shift ---
(test-equal 16 (arithmetic-shift 1 4))
(test-equal 4 (arithmetic-shift 16 -2))
(test-equal 0 (arithmetic-shift 7 -4))
(test-equal -12 (arithmetic-shift -3 2))
(test-equal -1 (arithmetic-shift -1 -1))
(test-equal -4 (arithmetic-shift -7 -1))
(test-equal -4 (arithmetic-shift -15 -2))

;;; --- bit-count / integer-length ---
(test-equal 0 (bit-count 0))
(test-equal 2 (bit-count 5))
(test-equal 8 (bit-count 255))
(test-equal 0 (bit-count -1))
(test-equal 1 (bit-count -2))
(test-equal 0 (integer-length 0))
(test-equal 1 (integer-length 1))
(test-equal 3 (integer-length 7))
(test-equal 4 (integer-length 8))
(test-equal 0 (integer-length -1))
(test-equal 2 (integer-length -4))

;;; --- bitwise-if ---
(test-equal 3 (bitwise-if 1 1 2))
(test-equal 9 (bitwise-if 3 1 8))
(test-equal 6 (bitwise-if 0 15 6))

;;; --- single-bit operations ---
(test-equal #t (bit-set? 0 5))
(test-equal #f (bit-set? 1 5))
(test-equal #t (bit-set? 2 5))
(test-equal #f (bit-set? 31 5))
(test-equal #t (bit-set? 100 -1))
(test-equal #f (bit-set? 1 -3))

(test-equal 4 (copy-bit 2 0 #t))
(test-equal 1 (copy-bit 2 5 #f))

(test-equal 5 (bit-swap 0 2 5))          ; both bits set: no clear path involved
(test-equal 1 (bit-swap 0 2 4))
(test-equal 5 (bit-swap 0 1 6))

(test-equal #t (any-bit-set? 3 6))
(test-equal #f (any-bit-set? 1 6))
(test-equal #t (every-bit-set? 4 6))
(test-equal #f (every-bit-set? 7 6))

(test-equal -1 (first-set-bit 0))
(test-equal 0 (first-set-bit 1))
(test-equal 3 (first-set-bit 8))
(test-equal 2 (first-set-bit 12))
(test-equal 1 (first-set-bit -2))

;;; --- bit fields (positive operands) ---
(test-equal 0 (bit-field 6 0 1))
(test-equal 3 (bit-field 6 1 3))
(test-equal 5 (bit-field 42 1 4))
(test-equal #t (bit-field-any? 6 0 2))
(test-equal #f (bit-field-any? 6 3 6))
(test-equal #t (bit-field-every? 7 0 3))
(test-equal #f (bit-field-every? 5 0 3))
(test-equal 7 (bit-field-set 1 1 3))
(test-equal 9 (bit-field-clear 15 1 3))
(test-equal 5 (bit-field-replace 7 0 1 2))
(test-equal 27 (bit-field-replace-same 17 42 1 4))

;; rotate/reverse work when the value fits inside the field at offset 0
(test-equal 5 (bit-field-rotate 6 1 0 3))
(test-equal 6 (bit-field-rotate 6 0 0 3))
(test-equal 3 (bit-field-rotate 6 -1 0 3))
(test-equal 3 (bit-field-reverse 6 0 3))
(test-equal 12 (bit-field-reverse 3 0 4))

;;; --- bits <-> list/vector ---
(test-equal '(#f #t #t #f) (bits->list 6 4))
(test-equal '() (bits->list 0 0))
(test-equal 5 (list->bits '(#t #f #t)))
(test-equal 0 (list->bits '()))
(test-equal 13 (bits #t #f #t #t))
(test-equal 0 (bits))
(test-equal #(#t #f #t) (bits->vector 5 3))
(test-equal 5 (vector->bits #(#t #f #t)))
(test-equal 4 (vector->bits #(#f #f #t)))
(test-equal '(#t #f #t) (bits->list 5))
(test-equal '() (bits->list 0))
(test-equal #(#t #f #t) (bits->vector 5))
(test-equal #() (bits->vector 0))

;;; --- fold / for-each / unfold / generator ---
(test-equal 2 (bitwise-fold (lambda (b acc) (if b (+ acc 1) acc)) 0 5))
(test-equal '(#t #f #t)
            (let ((acc '()))
              (bitwise-for-each (lambda (b) (set! acc (cons b acc))) 5)
              (reverse acc)))
(test-equal 5 (bitwise-unfold (lambda (i) (= i 4)) even? (lambda (i) (+ i 1)) 0))
(test-equal 0 (bitwise-unfold (lambda (i) #t) odd? (lambda (i) i) 0))

(test-equal '(#t #f #t #f)
            (let ((g (make-bitwise-generator 5)))
              (list (g) (g) (g) (g))))
(test-equal '(#f #f)
            (let ((g (make-bitwise-generator 0)))
              (list (g) (g))))

(let ((runner (test-runner-current)))
  (test-end "srfi-151")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
