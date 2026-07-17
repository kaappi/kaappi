(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

;; Test that uint32 FFI parameters accept the full [0, 2^32-1] range.
;; Previously, uint32 was normalized to c_int (i32), causing @intCast
;; to panic for values > 2^31-1.

(define libc (ffi-open #f))
;; htonl from the process's libc on POSIX; on Windows htonl lives in
;; ws2_32.dll (not loaded), so use the CRT's _byteswap_ulong — same
;; uint32 -> uint32 byte swap on this little-endian target.
(define c-htonl
  (cond-expand
    (windows (ffi-fn libc "_byteswap_ulong" '(uint32) 'uint32))
    (else (ffi-fn libc "htonl" '(uint32) 'uint32))))

;; Values within i32 range should still work
(check "htonl(0)" (c-htonl 0) 0)
(check "htonl(1)" (c-htonl 1) 16777216)

;; Values > 2^31-1 that previously caused panic
(check "htonl(2^31) no panic" (number? (c-htonl 2147483648)) #t)
(check "htonl(3e9) no panic" (number? (c-htonl 3000000000)) #t)
(check "htonl(2^32-1) no panic" (number? (c-htonl 4294967295)) #t)

(ffi-close libc)
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "FFI uint32 range tests failed" fail))
