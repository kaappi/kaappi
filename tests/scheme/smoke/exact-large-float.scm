;; Regression test for #414: exact returns flonum instead of bignum for large values

(import (scheme base) (scheme write))

;; exact of integer-valued floats outside i64 range must return exact integers
(unless (exact? (exact 1e19))
  (error "(exact 1e19) should be exact"))

(unless (= (exact 1e19) 10000000000000000000)
  (error "(exact 1e19) should equal 10000000000000000000"))

(unless (exact? (exact -1e19))
  (error "(exact -1e19) should be exact"))

(unless (= (exact -1e19) -10000000000000000000)
  (error "(exact -1e19) should equal -10000000000000000000"))

(unless (exact? (exact 1e20))
  (error "(exact 1e20) should be exact"))

(unless (exact? (exact 1e100))
  (error "(exact 1e100) should be exact"))

;; Small values should still produce fixnums
(unless (exact? (exact 42.0))
  (error "(exact 42.0) should be exact"))

(unless (= (exact 42.0) 42)
  (error "(exact 42.0) should equal 42"))

;; Non-integer floats should produce exact rationals
(unless (exact? (exact 0.5))
  (error "(exact 0.5) should be exact"))

(unless (= (exact 0.5) 1/2)
  (error "(exact 0.5) should equal 1/2"))

(display "PASS")
(newline)
