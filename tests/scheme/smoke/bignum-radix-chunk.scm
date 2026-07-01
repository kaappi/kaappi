;;; Regression test for issue #631: parseBignumString CHUNK_DIGITS overflow
;;; for radix 12-36. The chunk size must be computed per-radix to avoid
;;; overflowing u64 during parsing.

(import (scheme base) (scheme write))

;; Base 36: 32 Z's — verified against Python int("ZZZ...Z", 36)
(let ((r (string->number "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ" 36)))
  (unless (and (integer? r) (exact? r)
               (= r 63340286662973277706162286946811886609896461828095))
    (display "FAIL: base-36 bignum")
    (newline)
    (exit 1)))

;; Base 17
(let ((r (string->number "11111111111111111111111111111111" 17)))
  (unless (and (integer? r) (exact? r)
               (= r 147994474672529202865256643582559452960))
    (display "FAIL: base-17 bignum")
    (newline)
    (exit 1)))

;; Base 12 — right at the boundary where old CHUNK_DIGITS=18 overflowed
(let ((r (string->number "BBBBBBBBBBBBBBBBBBBBB" 12)))
  (unless (and (integer? r) (exact? r))
    (display "FAIL: base-12 bignum")
    (newline)
    (exit 1)))

;; Negative bignum in high radix
(let ((r (string->number "-ZZZZZZ" 36)))
  (unless (and (integer? r) (exact? r) (negative? r))
    (display "FAIL: negative base-36 bignum")
    (newline)
    (exit 1)))

(display "OK")
(newline)
