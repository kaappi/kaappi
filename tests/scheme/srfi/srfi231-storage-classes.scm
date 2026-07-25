;; SRFI 231 (Intervals and Generalized Arrays) tests -- phase 1b: storage
;; classes. Arrays themselves are a later phase of this multi-slice SRFI,
;; tracked under issue #1694; (srfi 231) itself is not yet an importable
;; bare library.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231-storage-classes.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 231 storage-classes))

(test-begin "srfi-231-storage-classes")

;;; --- storage-class? disjointness ---
(test-equal #t (storage-class? s8-storage-class))
(test-equal #f (storage-class? 42))
(test-equal #f (storage-class? (vector)))

;;; --- a generic helper exercising the full 9-field contract on a
;;; storage class, used across every one of the 14 real classes below.
;;; Complex values read back from a c64/c128 body are always genuinely
;;; complex-tagged even with a zero imaginary part (unlike a bare
;;; make-rectangular call at the Scheme level, which collapses eagerly),
;;; so numeric equality (=) is used for the value-carrying checks when
;;; both sides are numbers, since equal? would otherwise spuriously fail
;;; despite both sides being the same number. bad-value has no meaningful
;;; "checker rejects this" case for generic-storage-class (its checker
;;; always returns #t), so that assertion is a separate, optional check. ---
(define (%same? a b) (if (and (number? a) (number? b)) (= a b) (equal? a b)))

(define (check-storage-class sc value bad-value expected-default . rejects-bad?)
  (let* ((maker (storage-class-maker sc))
         (getter (storage-class-getter sc))
         (setter (storage-class-setter sc))
         (length-proc (storage-class-length sc))
         (checker (storage-class-checker sc))
         (body (maker 3 (storage-class-default sc))))
    (test-assert (%same? expected-default (storage-class-default sc)))
    (test-equal 3 (length-proc body))
    (test-assert (%same? expected-default (getter body 0)))
    (setter body 1 value)
    (test-assert (%same? value (getter body 1)))
    (test-equal #t (checker value))
    (when (or (null? rejects-bad?) (car rejects-bad?))
      (test-equal #f (checker bad-value)))
    (test-equal #t ((storage-class-data? sc) body))
    (test-equal #t (eq? body ((storage-class-data->body sc) body)))))

;; generic's checker accepts everything, including bad-value, by design;
;; its default fill value is #f (per the spec's own reference definition)
(check-storage-class generic-storage-class 42 99 #f #f)
(check-storage-class char-storage-class #\z 42 #\0)
(check-storage-class s8-storage-class -100 200 0)
(check-storage-class s16-storage-class -30000 40000 0)
(check-storage-class s32-storage-class -2000000000 3000000000 0)
(check-storage-class s64-storage-class -9000000000000000000 9300000000000000000 0)
(check-storage-class u8-storage-class 200 -1 0)
(check-storage-class u16-storage-class 60000 -1 0)
(check-storage-class u32-storage-class 4000000000 -1 0)
(check-storage-class u64-storage-class 18000000000000000000 -1 0)
(check-storage-class f32-storage-class 3.5 "not a number" 0.0)
(check-storage-class f64-storage-class 3.5 "not a number" 0.0)
(check-storage-class c64-storage-class (make-rectangular 1.0 2.0) "not a number" 0.0)
(check-storage-class c128-storage-class (make-rectangular 1.0 2.0) "not a number" 0.0)

;;; --- generic checker specifically accepts anything, unlike every typed one ---
(test-equal #t ((storage-class-checker generic-storage-class) (vector 1 2 3)))
(test-equal #t ((storage-class-checker generic-storage-class) "a string"))

;;; --- the 3 kinds with no Kaappi-native representation are bound (as the
;;; spec requires every storage-class global to be) but #f, matching the
;;; spec's own reference implementation for f8 specifically ---
(test-equal #f u1-storage-class)
(test-equal #f f8-storage-class)
(test-equal #f f16-storage-class)

;;; --- make-storage-class is a fully general public constructor, not just
;;; internal machinery for the 14 named singletons ---
(let* ((sc (make-storage-class vector-ref vector-set! symbol? make-vector vector-copy! vector-length
                                'default-sym vector? values))
       (body ((storage-class-maker sc) 2 (storage-class-default sc))))
  ((storage-class-setter sc) body 0 'hello)
  (test-equal 'hello ((storage-class-getter sc) body 0))
  (test-equal 'default-sym ((storage-class-getter sc) body 1))
  (test-equal #t ((storage-class-checker sc) 'a-symbol))
  (test-equal #f ((storage-class-checker sc) 42)))

(let ((runner (test-runner-current)))
  (test-end "srfi-231-storage-classes")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
