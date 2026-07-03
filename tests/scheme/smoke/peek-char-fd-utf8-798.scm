;; Regression test for #798: peek-char returns raw lead byte when a
;; pushed-back byte starts a multi-byte UTF-8 char on a file port.

(import (scheme base) (scheme write) (scheme file) (scheme process-context))

(define pass #t)
(define (check name actual expected)
  (unless (equal? actual expected)
    (display "FAIL ") (display name)
    (display ": expected ") (display expected)
    (display " got ") (display actual) (newline)
    (set! pass #f)))

;; Test 1: read-line consumes \r, pushes back lead byte of multi-byte char
;; File contents: a \r € x  (bytes: 61 0D E2 82 AC 78)
(define f1 "/tmp/kaappi-test-798-1.txt")
(let ((p (open-output-file f1)))
  (write-bytevector (bytevector #x61 #x0D #xE2 #x82 #xAC #x78) p)
  (close-output-port p))

(let ((p (open-input-file f1)))
  (let ((line (read-line p)))
    (check "read-line" line "a")
    (let ((pc (peek-char p))
          (rc (read-char p)))
      (check "peek-char after read-line" (char->integer pc) 8364)
      (check "read-char after peek-char" (char->integer rc) 8364)
      (check "peek-char == read-char" (eqv? pc rc) #t)
      (let ((x (read-char p)))
        (check "next char" x #\x))))
  (close-input-port p))

;; Test 2: peek-u8 sets peek_byte, then peek-char on multi-byte char
;; File contents: € a b c  (bytes: E2 82 AC 61 62 63)
(define f2 "/tmp/kaappi-test-798-2.txt")
(let ((p (open-output-file f2)))
  (write-bytevector (bytevector #xE2 #x82 #xAC #x61 #x62 #x63) p)
  (close-output-port p))

(let ((p (open-input-file f2)))
  (let ((pb (peek-u8 p)))
    (check "peek-u8" pb #xE2)
    (let ((pc (peek-char p))
          (rc (read-char p)))
      (check "peek-char after peek-u8" (char->integer pc) 8364)
      (check "read-char after peek-u8+peek-char" (char->integer rc) 8364)
      (check "peek==read after peek-u8" (eqv? pc rc) #t)))
  (close-input-port p))

;; Test 3: 2-byte UTF-8 char (é = U+00E9, bytes C3 A9)
(define f3 "/tmp/kaappi-test-798-3.txt")
(let ((p (open-output-file f3)))
  (write-bytevector (bytevector #x61 #x0D #xC3 #xA9 #x62) p)
  (close-output-port p))

(let ((p (open-input-file f3)))
  (read-line p)
  (let ((pc (peek-char p))
        (rc (read-char p)))
    (check "2-byte peek-char" (char->integer pc) #xE9)
    (check "2-byte read-char" (char->integer rc) #xE9)
    (check "2-byte peek==read" (eqv? pc rc) #t))
  (close-input-port p))

;; Test 4: 4-byte UTF-8 char (𝄞 = U+1D11E, bytes F0 9D 84 9E)
(define f4 "/tmp/kaappi-test-798-4.txt")
(let ((p (open-output-file f4)))
  (write-bytevector (bytevector #x61 #x0D #xF0 #x9D #x84 #x9E #x62) p)
  (close-output-port p))

(let ((p (open-input-file f4)))
  (read-line p)
  (let ((pc (peek-char p))
        (rc (read-char p)))
    (check "4-byte peek-char" (char->integer pc) #x1D11E)
    (check "4-byte read-char" (char->integer rc) #x1D11E)
    (check "4-byte peek==read" (eqv? pc rc) #t))
  (close-input-port p))

;; Cleanup
(delete-file f1)
(delete-file f2)
(delete-file f3)
(delete-file f4)

(if pass
    (begin (display "All peek-char fd UTF-8 tests passed") (newline))
    (begin (display "SOME TESTS FAILED") (newline) (exit 1)))
