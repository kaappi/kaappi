;; SRFI-178 (Bitvector library) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi178.scm

(import (scheme base) (scheme process-context) (srfi 178) (srfi 64))

(test-begin "srfi-178")

;;; --- bit conversion ---
(test-equal "bit->integer: 0" 0 (bit->integer 0))
(test-equal "bit->integer: #f" 0 (bit->integer #f))
(test-equal "bit->integer: 1" 1 (bit->integer 1))
(test-equal "bit->integer: #t" 1 (bit->integer #t))
(test-equal "bit->boolean: 0" #f (bit->boolean 0))
(test-equal "bit->boolean: 1" #t (bit->boolean 1))

;;; --- constructors ---
(test-assert "bitvector?: true" (bitvector? (bitvector 0 1 0)))
(test-assert "bitvector?: false for bytevector" (not (bitvector? (bytevector 0 1 0))))
(test-equal "make-bitvector: default fill" '(0 0 0) (bitvector->list/int (make-bitvector 3)))
(test-equal "make-bitvector: with fill" '(1 1 1) (bitvector->list/int (make-bitvector 3 1)))
(test-equal "bitvector: from args" '(1 0 1) (bitvector->list/int (bitvector 1 0 1)))
(test-equal "bitvector: booleans accepted" '(1 0) (bitvector->list/int (bitvector #t #f)))

(test-equal "bitvector-unfold"
  '(0 1 0 1)
  (bitvector->list/int (bitvector-unfold (lambda (i seed) (values (modulo i 2) seed)) 4 0)))

(test-equal "bitvector-copy" '(1 0) (bitvector->list/int (bitvector-copy (bitvector 1 1 0 0) 1 3)))
(test-equal "bitvector-reverse-copy" '(0 1 1) (bitvector->list/int (bitvector-reverse-copy (bitvector 1 1 0))))
(test-equal "bitvector-append" '(1 0 0 1) (bitvector->list/int (bitvector-append (bitvector 1 0) (bitvector 0 1))))
(test-equal "bitvector-concatenate" '(1 0 0 1) (bitvector->list/int (bitvector-concatenate (list (bitvector 1 0) (bitvector 0 1)))))

;;; --- predicates ---
(test-assert "bitvector-empty?: true" (bitvector-empty? (bitvector)))
(test-assert "bitvector-empty?: false" (not (bitvector-empty? (bitvector 1))))
(test-assert "bitvector=?: equal" (bitvector=? (bitvector 1 0) (bitvector 1 0)))
(test-assert "bitvector=?: unequal" (not (bitvector=? (bitvector 1 0) (bitvector 0 1))))

;;; --- selectors ---
(test-equal "bitvector-ref/int" 1 (bitvector-ref/int (bitvector 0 1 0) 1))
(test-equal "bitvector-ref/bool" #t (bitvector-ref/bool (bitvector 0 1 0) 1))
(test-equal "bitvector-length" 3 (bitvector-length (bitvector 0 1 0)))

;;; --- iteration ---
(test-equal "bitvector-take" '(1 1) (bitvector->list/int (bitvector-take (bitvector 1 1 0 0) 2)))
(test-equal "bitvector-take-right" '(0 0) (bitvector->list/int (bitvector-take-right (bitvector 1 1 0 0) 2)))
(test-equal "bitvector-drop" '(0 0) (bitvector->list/int (bitvector-drop (bitvector 1 1 0 0) 2)))
(test-equal "bitvector-drop-right" '(1 1) (bitvector->list/int (bitvector-drop-right (bitvector 1 1 0 0) 2)))
(test-equal "bitvector-segment"
  '((1 1) (0 0) (1))
  (map bitvector->list/int (bitvector-segment (bitvector 1 1 0 0 1) 2)))

(test-equal "bitvector-fold/int" 2 (bitvector-fold/int + 0 (bitvector 1 0 1)))
(test-equal "bitvector-fold-right/int"
  '(1 0 1)
  (bitvector-fold-right/int (lambda (acc bit) (cons bit acc)) '() (bitvector 1 0 1)))
(test-equal "bitvector-map/int" '(0 1 0) (bitvector->list/int (bitvector-map/int (lambda (b) (- 1 b)) (bitvector 1 0 1))))
(test-equal "bitvector-map->list/bool" '(#f #t #f) (bitvector-map->list/bool (lambda (b) (not b)) (bitvector 1 0 1)))
;; Regression: bitvector-map/bool and bitvector-map!/bool once passed f a
;; single list argument instead of applying it to the bit booleans.
(test-equal "bitvector-map/bool" '(0 1 0) (bitvector->list/int (bitvector-map/bool (lambda (b) (not b)) (bitvector 1 0 1))))
(let ((bv (bitvector 1 0 1)))
  (bitvector-map!/bool (lambda (b) (not b)) bv)
  (test-equal "bitvector-map!/bool" '(0 1 0) (bitvector->list/int bv)))

(let ((sum 0))
  (bitvector-for-each/int (lambda (b) (set! sum (+ sum b))) (bitvector 1 1 0 1))
  (test-equal "bitvector-for-each/int" 3 sum))

;;; --- prefix/suffix/pad/trim ---
(test-equal "bitvector-prefix-length" 2 (bitvector-prefix-length (bitvector 1 1 0) (bitvector 1 1 1)))
(test-equal "bitvector-suffix-length" 2 (bitvector-suffix-length (bitvector 0 1 1) (bitvector 1 1 1)))
(test-assert "bitvector-prefix?" (bitvector-prefix? (bitvector 1 1) (bitvector 1 1 0)))
(test-assert "bitvector-suffix?" (bitvector-suffix? (bitvector 1 0) (bitvector 1 1 0)))
(test-equal "bitvector-pad" '(0 0 1) (bitvector->list/int (bitvector-pad 0 (bitvector 1) 3)))
(test-equal "bitvector-pad-right" '(1 0 0) (bitvector->list/int (bitvector-pad-right 0 (bitvector 1) 3)))
(test-equal "bitvector-trim" '(1 0) (bitvector->list/int (bitvector-trim 0 (bitvector 0 0 1 0))))
(test-equal "bitvector-trim-right" '(1 0 1) (bitvector->list/int (bitvector-trim-right 0 (bitvector 1 0 1 0 0))))
(test-equal "bitvector-trim-both" '(1) (bitvector->list/int (bitvector-trim-both 0 (bitvector 0 1 0))))

;;; --- mutators ---
(let ((bv (bitvector 0 0 0)))
  (bitvector-set! bv 1 1)
  (test-equal "bitvector-set!" '(0 1 0) (bitvector->list/int bv)))

(let ((bv (bitvector 1 0)))
  (bitvector-swap! bv 0 1)
  (test-equal "bitvector-swap!" '(0 1) (bitvector->list/int bv)))

(let ((bv (bitvector 1 1 0 0)))
  (bitvector-reverse! bv)
  (test-equal "bitvector-reverse!" '(0 0 1 1) (bitvector->list/int bv)))

(let ((to (make-bitvector 4 0)) (from (bitvector 1 1)))
  (bitvector-copy! to 1 from)
  (test-equal "bitvector-copy!" '(0 1 1 0) (bitvector->list/int to)))

;;; --- conversion ---
(test-equal "list->bitvector / bitvector->list/int roundtrip" '(1 0 1) (bitvector->list/int (list->bitvector '(1 0 1))))
(test-equal "reverse-list->bitvector" '(1 0 1) (bitvector->list/int (reverse-list->bitvector '(1 0 1))))
(test-equal "bitvector->vector/int" #(1 0 1) (bitvector->vector/int (bitvector 1 0 1)))
(test-equal "vector->bitvector" '(1 0 1) (bitvector->list/int (vector->bitvector #(1 0 1))))
(test-equal "bitvector->string" "#*101" (bitvector->string (bitvector 1 0 1)))
(test-equal "string->bitvector" '(1 0 1) (bitvector->list/int (string->bitvector "#*101")))
(test-equal "string->bitvector: bad format" #f (string->bitvector "101"))
(test-equal "bitvector->integer" 5 (bitvector->integer (bitvector 1 0 1)))
(test-equal "integer->bitvector" '(1 0 1) (bitvector->list/int (integer->bitvector 5 3)))
(test-equal "bitvector<->integer roundtrip" 42 (bitvector->integer (integer->bitvector 42)))

;;; --- generators / accumulator ---
(test-equal "make-bitvector/int-generator"
  '(1 0 1)
  (let ((gen (make-bitvector/int-generator (bitvector 1 0 1))) (acc '()))
    (let loop ((v (gen)))
      (if (eof-object? v)
          (reverse acc)
          (begin (set! acc (cons v acc)) (loop (gen)))))))

;; Non-palindrome input: a double-reversal bug would round-trip (1 0 1)
;; correctly by accident but reveals itself here.
(test-equal "make-bitvector-accumulator"
  '(1 1 0)
  (let ((accum (make-bitvector-accumulator)))
    (accum 1) (accum 1) (accum 0)
    (bitvector->list/int (accum (eof-object)))))

;;; --- bitwise combinators ---
(test-equal "bitvector-and" '(1 0 0 0) (bitvector->list/int (bitvector-and (bitvector 1 1 0 0) (bitvector 1 0 0 1))))
(test-equal "bitvector-ior" '(1 1 0 1) (bitvector->list/int (bitvector-ior (bitvector 1 1 0 0) (bitvector 1 0 0 1))))
(test-equal "bitvector-xor" '(0 1 0 1) (bitvector->list/int (bitvector-xor (bitvector 1 1 0 0) (bitvector 1 0 0 1))))
(test-equal "bitvector-eqv" '(1 0 1 0) (bitvector->list/int (bitvector-eqv (bitvector 1 1 0 0) (bitvector 1 0 0 1))))
(test-equal "bitvector-not" '(0 1 0) (bitvector->list/int (bitvector-not (bitvector 1 0 1))))
(test-equal "bitvector-nand" '(0 1 1 1) (bitvector->list/int (bitvector-nand (bitvector 1 1 0 0) (bitvector 1 0 0 1))))
(test-equal "bitvector-nor" '(0 0 1 0) (bitvector->list/int (bitvector-nor (bitvector 1 1 0 0) (bitvector 1 0 0 1))))
(test-equal "bitvector-andc1" '(0 0 0 1) (bitvector->list/int (bitvector-andc1 (bitvector 1 1 0 0) (bitvector 1 0 0 1))))
(test-equal "bitvector-andc2" '(0 1 0 0) (bitvector->list/int (bitvector-andc2 (bitvector 1 1 0 0) (bitvector 1 0 0 1))))

;;; --- quasi-integer ops ---
(test-equal "bitvector-logical-shift: left" '(0 1 1 0) (bitvector->list/int (bitvector-logical-shift (bitvector 1 1 0 0) 1 0)))
(test-equal "bitvector-logical-shift: right" '(1 0 0 0) (bitvector->list/int (bitvector-logical-shift (bitvector 1 1 0 0) -1 0)))
(test-equal "bitvector-count" 3 (bitvector-count 1 (bitvector 1 1 0 1)))
(test-equal "bitvector-count-run" 2 (bitvector-count-run 1 (bitvector 1 1 0 1) 0))
(test-equal "bitvector-if" '(1 0 1) (bitvector->list/int (bitvector-if (bitvector 1 0 1) (bitvector 1 1 1) (bitvector 0 0 0))))
(test-equal "bitvector-first-bit" 2 (bitvector-first-bit 1 (bitvector 0 0 1 1)))
(test-equal "bitvector-first-bit: not found" -1 (bitvector-first-bit 1 (bitvector 0 0 0)))

;;; --- bit field operations ---
(test-assert "bitvector-field-any?: true" (bitvector-field-any? (bitvector 0 1 0) 0 3))
(test-assert "bitvector-field-any?: false" (not (bitvector-field-any? (bitvector 0 0 0) 0 3)))
(test-assert "bitvector-field-every?: true" (bitvector-field-every? (bitvector 1 1 1) 0 3))
(test-equal "bitvector-field-clear" '(1 0 0 1) (bitvector->list/int (bitvector-field-clear (bitvector 1 1 1 1) 1 3)))
(test-equal "bitvector-field-set" '(0 1 1 0) (bitvector->list/int (bitvector-field-set (bitvector 0 0 0 0) 1 3)))
(test-equal "bitvector-field-replace"
  '(1 0 1 1)
  (bitvector->list/int (bitvector-field-replace (bitvector 1 1 1 1) (bitvector 0 1) 1 3)))
(test-equal "bitvector-field-rotate"
  '(1 0 1 1)
  (bitvector->list/int (bitvector-field-rotate (bitvector 1 1 0 1) 1 1 4)))
(test-equal "bitvector-field-flip" '(1 0 1 1) (bitvector->list/int (bitvector-field-flip (bitvector 1 1 0 1) 1 3)))

(let ((runner (test-runner-current)))
  (test-end "srfi-178")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
