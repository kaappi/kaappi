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

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "reader-numerics")
(if (> %test-fail-count 0) (exit 1))
