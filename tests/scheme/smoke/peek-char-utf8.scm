(import (scheme base) (scheme write) (scheme file))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; Write a file with multi-byte UTF-8 characters, then peek/read them
(define test-file "/tmp/kaappi-peek-utf8-test.txt")

(let ((p (open-output-file test-file)))
  (display "λx" p)  ; λ = U+03BB (2 bytes: 0xCE 0xBB), then ASCII x
  (close-port p))

(let ((p (open-input-file test-file)))
  (check "peek-char lambda" (peek-char p) #\λ)
  (check "read-char lambda" (read-char p) #\λ)
  (check "read-char x" (read-char p) #\x)
  (check "read-char eof" (read-char p) (eof-object))
  (close-port p))

;; Test with 3-byte UTF-8 char: ✓ = U+2713 (3 bytes: 0xE2 0x9C 0x93)
(let ((p (open-output-file test-file)))
  (display "✓y" p)
  (close-port p))

(let ((p (open-input-file test-file)))
  (check "peek-char checkmark" (peek-char p) #\✓)
  (check "peek-char checkmark again" (peek-char p) #\✓)
  (check "read-char checkmark" (read-char p) #\✓)
  (check "read-char y" (read-char p) #\y)
  (close-port p))

;; Test with 4-byte UTF-8 char: 𝕜 = U+1D55C (4 bytes)
(let ((p (open-output-file test-file)))
  (display "𝕜z" p)
  (close-port p))

(let ((p (open-input-file test-file)))
  (check "peek-char 4byte" (peek-char p) #\𝕜)
  (check "read-char 4byte" (read-char p) #\𝕜)
  (check "read-char z" (read-char p) #\z)
  (close-port p))

;; Clean up
(delete-file test-file)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "peek-char UTF-8 tests failed" fail))
