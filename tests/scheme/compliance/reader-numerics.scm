;;; Reader numeric literal tests — non-decimal bignums and surrogate rejection

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "reader-numerics")

;; #230: Non-decimal integers that overflow i64 must promote to bignum
(test-group "non-decimal bignum promotion"
  (test-eqv "hex bignum value"
    18446744073709551615
    #xFFFFFFFFFFFFFFFF)

  (test-eqv "hex bignum negative"
    -18446744073709551615
    #x-FFFFFFFFFFFFFFFF)

  (test-eqv "binary bignum value"
    73786976294838206463
    #b111111111111111111111111111111111111111111111111111111111111111111)

  (test-eqv "octal bignum value"
    1152921504606846975
    #o77777777777777777777)

  (test-assert "hex bignum is exact integer"
    (exact? #xFFFFFFFFFFFFFFFF))

  (test-assert "hex bignum arithmetic"
    (= (+ #xFFFFFFFFFFFFFFFF 1) #x10000000000000000))

  ;; Non-overflow non-decimal should still work
  (test-eqv "hex fixnum" 255 #xFF)
  (test-eqv "binary fixnum" 7 #b111)
  (test-eqv "octal fixnum" 63 #o77))

;; #230: string->number with non-decimal radix and overflow
(test-group "string->number non-decimal bignum"
  (test-eqv "string->number hex bignum"
    18446744073709551615
    (string->number "FFFFFFFFFFFFFFFF" 16))

  (test-eqv "string->number binary bignum"
    73786976294838206463
    (string->number "111111111111111111111111111111111111111111111111111111111111111111" 2))

  (test-eqv "string->number octal bignum"
    1152921504606846975
    (string->number "77777777777777777777" 8)))

;; Rational literals whose numerator or denominator overflows i64 must fall
;; back to bignum parsing instead of failing with a read error.
;; 36893488147419103232 = 2^65, 18446744073709551616 = 2^64.
(test-group "bignum rational literals"
  ;; bignum/bignum reducing to a fixnum
  (test-eqv "bignum/bignum reduces to fixnum"
    2
    36893488147419103232/18446744073709551616)

  (test-eqv "negative bignum/bignum"
    -2
    -36893488147419103232/18446744073709551616)

  ;; bignum/fixnum reducing to a bignum integer
  (test-eqv "bignum/fixnum reduces to bignum"
    18446744073709551616
    36893488147419103232/2)

  ;; Irreducible variants keep exact bignum parts
  (test-eqv "bignum/fixnum numerator preserved"
    36893488147419103232
    (numerator 36893488147419103232/3))

  (test-eqv "bignum/fixnum denominator preserved"
    3
    (denominator 36893488147419103232/3))

  (test-eqv "negative bignum/fixnum numerator"
    -36893488147419103232
    (numerator -36893488147419103232/3))

  (test-eqv "fixnum/bignum denominator preserved"
    18446744073709551616
    (denominator 3/18446744073709551616))

  (test-eqv "bignum/bignum irreducible numerator"
    36893488147419103232
    (numerator 36893488147419103232/18446744073709551617))

  (test-assert "bignum rational is exact"
    (exact? 36893488147419103232/3))

  (test-assert "matches string->number"
    (= 36893488147419103232/3
       (string->number "36893488147419103232/3")))

  ;; Radix prefixes
  (test-eqv "hex bignum rational" 2 #x20000000000000000/10000000000000000)
  (test-eqv "octal bignum rational" 2 #o4000000000000000000000/2000000000000000000000)
  (test-assert "binary bignum/fixnum rational"
    (= #b100000000000000000000000000000000000000000000000000000000000000000/10
       18446744073709551616))

  ;; Exactness prefixes
  (test-eqv "#e bignum rational" 2 #e36893488147419103232/18446744073709551616)
  (test-eqv "#e#x bignum rational" 2 #e#x20000000000000000/10000000000000000)
  (test-assert "#i bignum rational is inexact"
    (and (inexact? #i36893488147419103232/18446744073709551616)
         (= #i36893488147419103232/18446744073709551616 2.0)))

  ;; Via (read ...) rather than a literal
  (test-eqv "read from string port"
    2
    (read (open-input-string "36893488147419103232/18446744073709551616")))

  ;; Zero denominator is a read error, matching 1/0
  (test-assert "bignum/0 is a read error"
    (guard (e ((read-error? e) #t) (#t #f))
      (read (open-input-string "36893488147419103232/0"))))

  (test-assert "bignum/00 is a read error"
    (guard (e ((read-error? e) #t) (#t #f))
      (read (open-input-string "36893488147419103232/00")))))

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "reader-numerics")
(if (> %test-fail-count 0) (exit 1))
