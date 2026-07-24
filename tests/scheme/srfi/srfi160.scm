;; SRFI 160 (homogeneous numeric vector libraries) tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi160.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 128)
        (srfi 160 u8) (srfi 160 s8) (srfi 160 u16) (srfi 160 s16)
        (srfi 160 u32) (srfi 160 s32) (srfi 160 u64) (srfi 160 s64)
        (srfi 160 f32) (srfi 160 f64) (srfi 160 c64) (srfi 160 c128))

(test-begin "srfi-160")

;;; --- core (constructor/predicate/accessor/mutator/list conversion) per type ---

(test-equal #t (s8vector? (s8vector 1 2 3)))
(test-equal #t (s8? 127))
(test-equal #f (s8? 128))
(test-equal '(1 2 3) (s8vector->list (s8vector 1 2 3)))
(test-equal '(9 9) (s8vector->list (make-s8vector 2 9)))
(test-equal '(-5 5) (s8vector->list (list->s8vector '(-5 5))))
(let ((v (s8vector 1 2 3))) (s8vector-set! v 0 -1) (test-equal -1 (s8vector-ref v 0)))

(test-equal #t (u16? 65535))
(test-equal #f (u16? 65536))
(test-equal #f (u16? -1))
(test-equal '(0 65535) (u16vector->list (u16vector 0 65535)))

(test-equal #t (s16? 32767))
(test-equal #t (s16? -32768))
(test-equal #f (s16? 32768))
(test-equal '(-32768 32767) (s16vector->list (s16vector -32768 32767)))

(test-equal #t (u32? 4294967295))
(test-equal #f (u32? 4294967296))
(test-equal '(4294967295) (u32vector->list (u32vector 4294967295)))

(test-equal #t (s32? 2147483647))
(test-equal #t (s32? -2147483648))
(test-equal #f (s32? 2147483648))
(test-equal '(-2147483648 2147483647) (s32vector->list (s32vector -2147483648 2147483647)))

(test-equal #t (u64? 18446744073709551615))
(test-equal #f (u64? 18446744073709551616))
(test-equal #f (u64? -1))
(test-equal '(0 18446744073709551615) (u64vector->list (u64vector 0 18446744073709551615)))
(test-equal 18446744073709551615 (u64vector-fold + 0 (u64vector 18446744073709551615)))

(test-equal #t (s64? 9223372036854775807))
(test-equal #t (s64? -9223372036854775808))
(test-equal #f (s64? 9223372036854775808))
(test-equal 9223372036854775808 (s64vector-fold + 0 (s64vector 9223372036854775807 1)))

;; f32 truncates to real 32-bit precision (the deficiency SRFI 4's old
;; wrapped-vector implementation had -- 1.1 is not exactly representable
;; in either width, but the f32-rounded value differs from the f64 one).
(test-assert (not (= 1.1 (f32vector-ref (f32vector 1.1) 0))))
(test-equal 1.1 (f64vector-ref (f64vector 1.1) 0))

(test-equal '(1.0+2.0i 3.0-1.0i) (c64vector->list (c64vector 1.0+2.0i 3.0-1.0i)))
(test-equal '(1.0+2.0i) (c128vector->list (c128vector 1.0+2.0i)))
(test-equal #t (c64? 1.0))
(test-equal #t (c64? 1.0+2.0i))

;; u8 stays a bytevector alias.
(test-equal #t (bytevector? (make-u8vector 3 0)))
(test-equal #t (u8vector? (bytevector 1 2 3)))

;; disjointness across kinds.
(test-equal #f (s8vector? (u8vector 1)))
(test-equal #f (u16vector? (s16vector 1)))
(test-equal #f (f32vector? (f64vector 1.0)))
(test-equal #f (c64vector? (c128vector 1.0)))

;;; --- range-check rejection (set! and constructor) ---
(test-equal #t (guard (e (#t #t)) (s8vector-set! (s8vector 1) 0 128) #f))
(test-equal #t (guard (e (#t #t)) (s8vector 200) #f))
(test-equal #t (guard (e (#t #t)) (u16vector-set! (u16vector 1) 0 -1) #f))
(test-equal #t (guard (e (#t #t)) (u64vector-set! (u64vector 1) 0 -1) #f))
(test-equal #t (guard (e (#t #t)) (s64vector-set! (s64vector 1) 0 9223372036854775808) #f))
(test-equal #t (guard (e (#t #t)) (s8vector-ref (s8vector 1) 5) #f))

;;; --- SRFI-133-shaped extended surface (representative coverage) ---

(test-equal '(2 3 4) (s8vector->list (s8vector-map (lambda (x) (+ x 1)) (s8vector 1 2 3))))
(test-equal 10 (s8vector-fold + 0 (s8vector 1 2 3 4)))
;; cons-based (non-commutative) so this would fail under left-to-right traversal
(test-equal '(1 2 3) (s8vector-fold-right (lambda (acc x) (cons x acc)) '() (s8vector 1 2 3)))
(let ((sum 0))
  (s8vector-for-each (lambda (x) (set! sum (+ sum x))) (s8vector 1 2 3))
  (test-equal 6 sum))
(test-equal '(1 2) (s8vector->list (s8vector-take (s8vector 1 2 3 4 5) 2)))
(test-equal '(3 4 5) (s8vector->list (s8vector-drop (s8vector 1 2 3 4 5) 2)))
(test-equal '(4 5) (s8vector->list (s8vector-take-right (s8vector 1 2 3 4 5) 2)))
(test-equal '(1 2 3) (s8vector->list (s8vector-drop-right (s8vector 1 2 3 4 5) 2)))
(test-equal '(1 2 3 4) (s8vector->list (s8vector-append (s8vector 1 2) (s8vector 3 4))))
(test-equal '(1 2 3 4) (s8vector->list (s8vector-concatenate (list (s8vector 1 2) (s8vector 3 4)))))
(test-equal '(3 2 1) (s8vector->list (s8vector-reverse-copy (s8vector 1 2 3))))
(test-equal '((1 2) (3 4) (5)) (map s8vector->list (s8vector-segment (s8vector 1 2 3 4 5) 2)))
(test-equal '(1 2 20 30)
  (s8vector->list (s8vector-append-subvectors (s8vector 1 2 3 4) 0 2 (s8vector 10 20 30) 1 3)))
(test-equal '(0 1 3 6) (s8vector->list (s8vector-cumulate + 0 (s8vector 0 1 2 3))))

(test-equal '(1 3 5) (s8vector->list (s8vector-filter odd? (s8vector 1 2 3 4 5))))
(test-equal '(2 4) (s8vector->list (s8vector-remove odd? (s8vector 1 2 3 4 5))))
(call-with-values
 (lambda () (s8vector-partition odd? (s8vector 1 2 3 4 5)))
 (lambda (v k) (test-equal '(1 3 5 2 4) (s8vector->list v)) (test-equal 3 k)))

(test-equal '(1 3 5) (s8vector->list (s8vector-take-while odd? (s8vector 1 3 5 4 7))))
(test-equal '(4 7) (s8vector->list (s8vector-drop-while odd? (s8vector 1 3 5 4 7))))
(test-equal '(4 6 8) (s8vector->list (s8vector-take-while-right even? (s8vector 1 3 4 6 8))))
(test-equal '(1 3) (s8vector->list (s8vector-drop-while-right even? (s8vector 1 3 4 6 8))))

(test-equal 2 (s8vector-index even? (s8vector 1 3 4 5)))
(test-equal 3 (s8vector-index-right odd? (s8vector 1 3 4 5)))
(test-equal 0 (s8vector-skip even? (s8vector 1 3 4 5)))
(test-equal #f (s8vector-any even? (s8vector 1 3 5)))
(test-equal #t (s8vector-every positive? (s8vector 1 2 3)))
(test-equal 2 (s8vector-count even? (s8vector 1 2 3 4)))
(test-equal #t (s8vector-empty? (s8vector)))
(test-equal #f (s8vector-empty? (s8vector 1)))
(test-equal #t (s8vector= (s8vector 1 2) (s8vector 1 2)))
(test-equal #f (s8vector= (s8vector 1 2) (s8vector 1 3)))

(let ((v (s8vector 1 2 3)))
  (s8vector-swap! v 0 2)
  (test-equal '(3 2 1) (s8vector->list v))
  (s8vector-fill! v 9 1 3)
  (test-equal '(3 9 9) (s8vector->list v))
  (s8vector-reverse! v)
  (test-equal '(9 9 3) (s8vector->list v)))

(let ((to (make-s8vector 4 0)) (from (s8vector 1 2 3 4)))
  (s8vector-copy! to 1 from 0 2)
  (test-equal '(0 1 2 0) (s8vector->list to)))

(test-equal '(0 2 4 6) (s8vector->list (s8vector-unfold (lambda (i seed) (values (* i 2) #f)) 4 #f)))
;; seed-threaded (not just a function of the index) so left-to-right vs.
;; right-to-left traversal produce different, distinguishable results.
(test-equal '(3 2 1 0)
  (s8vector->list (s8vector-unfold-right (lambda (i seed) (values seed (+ seed 1))) 4 0)))
(let ((v (make-s8vector 4 0)))
  (s8vector-unfold! (lambda (i seed) (values seed (+ seed 1))) v 0 4 10)
  (test-equal '(10 11 12 13) (s8vector->list v)))

(let ((g (make-s8vector-generator (s8vector 10 20))))
  (test-equal 10 (g)) (test-equal 20 (g)) (test-assert (eof-object? (g))))

(test-equal #t (=? s8vector-comparator (s8vector 1 2) (s8vector 1 2)))
(test-equal #t (<? s8vector-comparator (s8vector 1 2) (s8vector 1 3)))
(test-equal #f (comparator-ordered? c64vector-comparator))

(test-equal '(1 2 3) (vector->list (s8vector->vector (s8vector 1 2 3))))
(test-equal '(1 2 3) (s8vector->list (vector->s8vector #(1 2 3))))
(test-equal '(1 2 3) (s8vector->list (reverse-list->s8vector '(3 2 1))))
(test-equal '(3 2 1) (reverse-s8vector->list (s8vector 1 2 3)))

;; u8 shares the same generic engine as the NumericVector-backed kinds.
(test-equal '(2 3 4) (u8vector->list (u8vector-map (lambda (x) (+ x 1)) (u8vector 1 2 3))))
(test-equal 6 (u8vector-fold + 0 (u8vector 1 2 3)))
(test-equal '(1 2) (u8vector->list (u8vector-take (u8vector 1 2 3) 2)))

(let ((runner (test-runner-current)))
  (test-end "srfi-160")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
