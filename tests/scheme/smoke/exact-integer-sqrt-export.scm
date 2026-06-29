;; Regression test for #420: exact-integer-sqrt missing from (scheme base)

(import (only (scheme base) exact-integer-sqrt))
(import (scheme base) (scheme write))

(call-with-values (lambda () (exact-integer-sqrt 14))
  (lambda (s r)
    (unless (and (= s 3) (= r 5))
      (error "(exact-integer-sqrt 14) should return 3 and 5"))))

(display "PASS")
(newline)
