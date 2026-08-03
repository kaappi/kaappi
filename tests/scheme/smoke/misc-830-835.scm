;; Regression tests for #830 (string-replace clamping) and #835 (bignum parse error)

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "misc-830-835")

;; #830: string-replace should error on out-of-range indices
(test-equal "string-replace raises on out-of-range indices"
            'caught
            (guard (e (#t 'caught))
              (string-replace "abc" "XY" 10 20)))

;; #835: string->number should return #f for invalid bignum strings
(test-equal "string->number rejects a 37-digit string with a trailing x"
            #f (string->number "9999999999999999999999999999999999999x"))
(test-equal "string->number rejects a 20-digit string with a trailing x"
            #f (string->number "99999999999999999999x"))

;; Valid bignum strings should work
(test-equal "string->number accepts a valid bignum"
            12345678901234567890 (string->number "12345678901234567890"))

(let ((runner (test-runner-current)))
  (test-end "misc-830-835")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
