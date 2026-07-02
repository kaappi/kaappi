;; Regression tests for #830 (string-replace clamping) and #835 (bignum parse error)

;; #830: string-replace should error on out-of-range indices
(guard (e (#t (display "caught") (newline)))
  (string-replace "abc" "XY" 10 20))

;; #835: string->number should return #f for invalid bignum strings
(display (eq? (string->number "9999999999999999999999999999999999999x") #f))
(newline)
(display (eq? (string->number "99999999999999999999x") #f))
(newline)
;; Valid bignum strings should work
(display (= (string->number "12345678901234567890") 12345678901234567890))
(newline)
