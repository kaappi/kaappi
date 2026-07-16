;; Regression test for #795: narrow int parameter types (int8/uint8/int16/
;; uint16/uint32/char) must be range-checked against the declared type,
;; not just the carrier (c_int/c_long).

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "narrow-range")

;; libm on POSIX; on Windows the CRT (ucrtbase.dll) hosts abs — there is
;; no libm.dll.
(define libm (ffi-open (cond-expand (windows "ucrtbase") (else "libm"))))
(define libc (ffi-open #f))

;; ---- uint8 [0, 255] ----
(define abs-u8 (ffi-fn libm "abs" '(uint8) 'int))
(test-equal "uint8 valid: 0" 0 (abs-u8 0))
(test-equal "uint8 valid: 42" 42 (abs-u8 42))
(test-equal "uint8 valid: 255" 255 (abs-u8 255))
(test-error "uint8 reject: 256" (abs-u8 256))
(test-error "uint8 reject: -1" (abs-u8 -1))
(test-error "uint8 reject: 300" (abs-u8 300))

;; ---- int8 [-128, 127] ----
(define abs-i8 (ffi-fn libm "abs" '(int8) 'int))
(test-equal "int8 valid: 42" 42 (abs-i8 42))
(test-equal "int8 valid: -42" 42 (abs-i8 -42))
(test-equal "int8 valid: 127" 127 (abs-i8 127))
(test-equal "int8 valid: -128" 128 (abs-i8 -128))
(test-error "int8 reject: 128" (abs-i8 128))
(test-error "int8 reject: -129" (abs-i8 -129))
(test-error "int8 reject: 200" (abs-i8 200))

;; ---- int16 [-32768, 32767] ----
(define abs-i16 (ffi-fn libm "abs" '(int16) 'int))
(test-equal "int16 valid: 1000" 1000 (abs-i16 1000))
(test-equal "int16 valid: 32767" 32767 (abs-i16 32767))
(test-equal "int16 valid: -32768" 32768 (abs-i16 -32768))
(test-error "int16 reject: 32768" (abs-i16 32768))
(test-error "int16 reject: -32769" (abs-i16 -32769))
(test-error "int16 reject: 40000" (abs-i16 40000))

;; ---- uint16 [0, 65535] ----
(define abs-u16 (ffi-fn libm "abs" '(uint16) 'int))
(test-equal "uint16 valid: 1000" 1000 (abs-u16 1000))
(test-equal "uint16 valid: 65535" 65535 (abs-u16 65535))
(test-error "uint16 reject: 65536" (abs-u16 65536))
(test-error "uint16 reject: -1" (abs-u16 -1))
(test-error "uint16 reject: 70000" (abs-u16 70000))

;; ---- char [0, 255] ----
(define abs-char (ffi-fn libm "abs" '(char) 'int))
(test-equal "char valid: 65" 65 (abs-char 65))
(test-equal "char valid: 0" 0 (abs-char 0))
(test-equal "char valid: 255" 255 (abs-char 255))
(test-error "char reject: 256" (abs-char 256))
(test-error "char reject: -1" (abs-char -1))
(test-error "char reject: 300" (abs-char 300))

;; ---- uint32 [0, 4294967295] ----
;; Any uint32 -> uint32 function does here: htonl from the process's libc
;; on POSIX; on Windows htonl lives in ws2_32.dll (not loaded), so use the
;; CRT's byte-swap equivalent.
(define c-htonl
  (cond-expand
    (windows (ffi-fn libc "_byteswap_ulong" '(uint32) 'uint32))
    (else (ffi-fn libc "htonl" '(uint32) 'uint32))))
(test-assert "uint32 valid: 0" (number? (c-htonl 0)))
(test-assert "uint32 valid: 2^31" (number? (c-htonl 2147483648)))
(test-assert "uint32 valid: 2^32-1" (number? (c-htonl 4294967295)))
(test-error "uint32 reject: -1" (c-htonl -1))
(test-error "uint32 reject: 2^32" (c-htonl 4294967296))
(test-error "uint32 reject: 2^35" (c-htonl (expt 2 35)))

(ffi-close libm)
(ffi-close libc)

(let ((runner (test-runner-current)))
  (test-end "narrow-range")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
