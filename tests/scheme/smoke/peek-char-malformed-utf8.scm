;; Regression test for #518: peek-char must restore exact consumed bytes,
;; not re-encode the codepoint, to avoid stream desync on malformed UTF-8.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "peek-char-malformed-utf8")

;; Truncated 4-byte sequence: #xF0 #x90 #x80 (missing 4th byte)
;; peek-char should return some character for the lead byte and
;; a subsequent read-u8 must return #xF0 (the first byte), not skip it.
(let ((p (open-input-bytevector (bytevector #xF0 #x90 #x80))))
  (peek-char p)
  (test-equal "read-u8 after peek on truncated 4-byte seq returns lead byte"
    #xF0 (read-u8 p)))

;; Truncated 2-byte sequence: #xCE (missing continuation)
(let ((p (open-input-bytevector (bytevector #xCE #x41))))
  (peek-char p)
  (test-equal "read-u8 after peek on truncated 2-byte seq returns lead byte"
    #xCE (read-u8 p)))

;; Valid 2-byte char followed by ASCII — peek must not desync
(let ((p (open-input-bytevector (bytevector #xCE #xBB #x78)))) ; λx
  (test-equal "peek-char returns lambda" #\λ (peek-char p))
  (test-equal "read-char returns lambda" #\λ (read-char p))
  (test-equal "read-char returns x" #\x (read-char p)))

;; Valid 3-byte char — peek/read roundtrip
(let ((p (open-input-bytevector (bytevector #xE2 #x9C #x93 #x79)))) ; ✓y
  (test-equal "peek-char returns checkmark" #\✓ (peek-char p))
  (test-equal "peek-char idempotent" #\✓ (peek-char p))
  (test-equal "read-char returns checkmark" #\✓ (read-char p))
  (test-equal "read-char returns y" #\y (read-char p)))

(let ((runner (test-runner-current)))
  (test-end "peek-char-malformed-utf8")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
