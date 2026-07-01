;;; Regression test for #638: read-bytevector allocates full k-byte buffer
;;; upfront, hanging on huge k even under --sandbox.
;;; With the fix, read-bytevector grows incrementally and returns promptly.

(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check name expected actual)
  (if (equal? expected actual)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display name) (newline)
      (display "  expected: ") (display expected) (newline)
      (display "  actual:   ") (display actual) (newline))))

;; A huge k on a small port should return only available bytes, not hang
(check "large k reads only available bytes"
  #u8(97 98 99)
  (let ((p (open-input-bytevector #u8(97 98 99))))
    (read-bytevector 999999999 p)))

;; EOF on empty port
(check "large k on empty port returns eof"
  #t
  (eof-object?
    (let ((p (open-input-bytevector #u8())))
      (read-bytevector 999999999 p))))

;; Normal small reads still work
(check "small read works"
  #u8(104 101)
  (let ((p (open-input-bytevector #u8(104 101 108 108 111))))
    (read-bytevector 2 p)))

(display pass) (display " pass, ") (display fail) (display " fail") (newline)
(when (> fail 0) (exit 1))
