;; R7RS sections 6.1-6.5 conformance gap tests — audit Phase 1B.
;; Covers spec requirements not exercised by tests/scheme/r7rs/r7rs-tests.scm
;; sections 6.1 (equivalence), 6.2 (numbers), 6.3 (booleans), 6.4 (lists),
;; 6.5 (symbols). Spec references cite docs/errata-corrected-r7rs.pdf.

(import (scheme base) (scheme write) (scheme read) (scheme process-context)
        (srfi 64))

(test-begin "r7rs-datatypes-gaps")

;; --- 6.1 eqv? ---
;; "one of obj1 and obj2 is an exact number but the other is an inexact
;; number" => #f (p. 30)
(test-equal "eqv? mixed exactness" #f (eqv? 2 2.0))
;; "(eqv? 0.0 +nan.0) => #f" (p. 31)
(test-equal "eqv? 0.0 vs +nan.0" #f (eqv? 0.0 +nan.0))
;; "both inexact numbers ... numerically equal" => #t
(test-equal "eqv? equal flonums" #t (eqv? 2.0 2.0))
;; "Note that (eqv? 0.0 -0.0) will return #f if negative zero is
;; distinguished" (p. 31) — Kaappi distinguishes negative zero (IEEE 754),
;; so this pins the distinguished behavior; = must still treat them equal.
(test-equal "eqv? distinguishes negative zero" #f (eqv? 0.0 -0.0))
(test-equal "= treats negative zero as equal" #t (= 0.0 -0.0))
;; "both exact numbers and are numerically equal" — exercises the bignum
;; heap path (fixnums are immediates; bignums must compare by value).
(test-equal "eqv? equal bignums" #t (eqv? (expt 2 100) (expt 2 100)))
;; records: same location => #t, distinct locations => #f (p. 30)
(define-record-type <eqv-rec> (mk-eqv-rec a) eqv-rec? (a eqv-rec-a))
(let ((r (mk-eqv-rec 1)))
  (test-equal "eqv? same record" #t (eqv? r r)))
(test-equal "eqv? distinct records" #f (eqv? (mk-eqv-rec 1) (mk-eqv-rec 1)))

;; --- 6.1 equal? ---
;; "Even if its arguments are circular data structures, equal? must always
;; terminate." (p. 32) — a hang here is a conformance failure.
(test-equal "equal? on equivalent circular lists terminates"
  #t
  (let ((x (list 'a 'b))
        (y (list 'a 'b 'a 'b)))
    (set-cdr! (cdr x) x)                 ; x = #1=(a b . #1#)
    (set-cdr! (cdr (cdr (cdr y))) y)     ; y = #2=(a b a b . #2#)
    (equal? x y)))
(test-equal "equal? on circular vectors terminates"
  #t
  (let ((v1 (make-vector 2 0)) (v2 (make-vector 2 0)))
    (vector-set! v1 0 v1) (vector-set! v1 1 v1)
    (vector-set! v2 0 v2) (vector-set! v2 1 v2)
    (equal? v1 v2)))
(test-equal "equal? on mixed pair/vector cycles terminates"
  #t
  (let ((p1 (list 1 2)) (p2 (list 1 2)))
    (set-cdr! (cdr p1) (vector p1))
    (set-cdr! (cdr p2) (vector p2))
    (equal? p1 p2)))
;; equal? recursively compares bytevectors (p. 32)
(test-equal "equal? bytevectors" #t (equal? #u8(1 2 3) #u8(1 2 3)))
(test-equal "equal? unequal bytevectors" #f (equal? #u8(1 2 3) #u8(1 2 4)))

;; --- 6.2.7 Numerical input and output ---
;; number->string/string->number round-trip in every radix (p. 39):
;; (eqv? number (string->number (number->string number radix) radix)) => #t
(test-equal "number->string radix 16" "ff" (number->string 255 16))
(test-equal "number->string radix 2" "11111111" (number->string 255 2))
(test-equal "number->string radix 8" "377" (number->string 255 8))
(test-equal "radix round-trip 16" 255 (string->number (number->string 255 16) 16))
(test-equal "inexact round-trip via decimal"
  #t (eqv? 0.1 (string->number (number->string 0.1))))
;; exactness prefixes, radix prefixes, and their combination (6.2.5, p. 34)
(test-equal "string->number #o octal" 127 (string->number "#o177"))
(test-equal "string->number #e decimal" 3/2 (string->number "#e1.5"))
(test-equal "string->number #i rational" 1.5 (string->number "#i6/4"))
(test-equal "string->number #e#x combined" 16 (string->number "#e#x10"))
(test-equal "string->number #x#e combined" 16 (string->number "#x#e10"))
;; "a default radix that will be overridden if an explicit radix prefix is
;; present in string" (p. 40)
(test-equal "explicit prefix overrides radix argument"
  127 (string->number "#o177" 10))
;; invalid notations return #f, never an error (p. 40)
(test-equal "string->number 1/0 is #f" #f (string->number "1/0"))
(test-equal "string->number empty is #f" #f (string->number ""))
(test-equal "string->number bare sign is #f" #f (string->number "+"))

;; --- 6.2.6 exact / numerator / denominator edges ---
(test-equal "exact of .5 is 1/2" 1/2 (exact .5))
;; "The denominator of 0 is defined to be 1." (p. 37)
(test-equal "denominator of 0" 1 (denominator 0))

;; --- 6.3 Booleans ---
;; "they can be written #true and #false, respectively" (p. 40)
(test-equal "#true long literal" #t #true)
(test-equal "#false long literal" #f #false)
(test-equal "not of #true" #f (not #true))

;; --- 6.4 Pairs and lists ---
;; append: "If there are no arguments, the empty list is returned. If there
;; is exactly one argument, it is returned." (p. 42)
(test-equal "append with no arguments" '() (append))
(let ((x (list 1 2)))
  (test-equal "append single argument returned itself" #t (eq? x (append x))))
;; "the resulting list is always newly allocated, except that it shares
;; structure with the last argument" (p. 42)
(let ((tail (list 'c 'd)))
  (test-equal "append shares the last argument" #t
    (eq? tail (cddr (append '(a b) tail)))))
;; list-tail returns the shared sublist, not a copy (definition, p. 42)
(let ((x (list 'a 'b 'c 'd)))
  (test-equal "list-tail shares structure" #t (eq? (cddr x) (list-tail x 2))))
;; "The list argument can be circular" for list-ref (p. 42)
(test-equal "list-ref on circular list"
  2
  (let ((c (list 1 2 3)))
    (set-cdr! (cddr c) c)
    (list-ref c 7)))
;; make-list without fill still has the right length (p. 42)
(test-equal "make-list without fill" 2 (length (make-list 2)))

;; --- 6.5 Symbols ---
;; "any symbol ... written out using the write procedure, will read back in
;; as the identical symbol" (p. 43) — requires |...| pipe notation for
;; symbols containing delimiters.
(let* ((s (string->symbol "he llo"))
       (p (open-output-string)))
  (write s p)
  (test-equal "write/read symbol round-trip" #t
    (eq? s (read (open-input-string (get-output-string p))))))
(let* ((s (string->symbol "K. Harper, M.D."))
       (p (open-output-string)))
  (write s p)
  (test-equal "write/read round-trip with punctuation" #t
    (eq? s (read (open-input-string (get-output-string p))))))

(let ((runner (test-runner-current)))
  (test-end "r7rs-datatypes-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
