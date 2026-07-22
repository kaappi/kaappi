;; SRFI-207 (String-notated bytevectors) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi207.scm
;;
;; The #u8"..." reader syntax is implemented in the engine (see
;; lib/srfi/207.sld's header); this library adds the four procedures
;; most directly tied to the notation itself, not the full ~25-procedure
;; bytestring-processing library the full spec defines.

(import (scheme base) (scheme read) (scheme process-context) (srfi 207) (srfi 64))

(test-begin "srfi-207")

;;; --- reader syntax ---

(test-equal "basic ASCII content" (bytevector 104 101 108 108 111) #u8"hello")
(test-equal "empty" (bytevector) #u8"")
(test-equal "mnemonic escapes" (bytevector 7 8 9 10 13 124 34 92) #u8"\a\b\t\n\r\|\"\\")
(test-equal "the spec's own PNG-header hex-escape example"
  (bytevector 137 80 78 71 13 10 26 10)
  #u8"\x89;PNG\r\n\x1A;\n")
(test-equal "hex escape with leading zero" (bytevector 65) #u8"\x0041;")

;; The spec's own explicitly-invalid examples: a direct non-ASCII
;; character, and a hex escape too large to be a single byte. Built as
;; runtime strings and fed through `read` -- embedding either directly
;; in this file's own source would fail to parse the test file itself.
(test-assert "a direct non-ASCII character (the spec's own iota example) is a read error"
  (guard (e (#t #t)) (read (open-input-string "#u8\"ι\"")) #f))
(test-assert "a hex escape too large for one byte (the spec's own example) is a read error"
  (guard (e (#t #t)) (read (open-input-string "#u8\"\\xE000;\"")) #f))

;;; --- bytestring: variadic constructor ---

(test-equal "bytestring: mixing integers, chars, strings, bytevectors"
  (bytevector 104 105 33 65 66)
  (bytestring "hi" #\! (bytevector 65 66)))
(test-equal "bytestring: integers 0-255" (bytevector 0 255) (bytestring 0 255))
(test-assert "bytestring: a non-ASCII string is an error" (guard (e (#t (bytestring-error? e))) (bytestring "caf\x00e9;")))
(test-assert "bytestring: an out-of-range integer is an error" (guard (e (#t (bytestring-error? e))) (bytestring 256)))

;;; --- hex string round-trip ---

(test-equal "bytevector->hex-string" "48656c6c6f" (bytevector->hex-string (bytestring "Hello")))
(test-equal "hex-string->bytevector" (bytestring "Hello") (hex-string->bytevector "48656c6c6f"))
(test-equal "hex-string->bytevector accepts uppercase" (bytestring "Hello") (hex-string->bytevector "48656C6C6F"))
(test-assert "hex-string->bytevector: odd-length is an error" (guard (e (#t (bytestring-error? e))) (hex-string->bytevector "abc")))
(test-assert "hex-string->bytevector: non-hex digit is an error" (guard (e (#t (bytestring-error? e))) (hex-string->bytevector "zz")))

;;; --- write-textual-bytestring: the notation's writer counterpart ---

(define (written->string bv)
  (let ((port (open-output-string)))
    (write-textual-bytestring bv port)
    (get-output-string port)))

(test-equal "write: printable ASCII passes through unescaped" "#u8\"hello\"" (written->string #u8"hello"))
(test-equal "write: control bytes use mnemonic escapes" "#u8\"\\t\\n\"" (written->string (bytestring 9 10)))
(test-equal "write: quote and backslash are escaped" "#u8\"\\\"\\\\\"" (written->string (bytestring 34 92)))
(test-equal "write: a non-mnemonic control byte uses \\x" "#u8\"\\x01;\"" (written->string (bytestring 1)))

;; Round-trip through the reader.
(define (roundtrips? bv) (equal? bv (hex-string->bytevector (bytevector->hex-string bv))))
(test-assert "round-trip via hex string: PNG header" (roundtrips? (bytestring 137 80 78 71 13 10 26 10)))

;; Regression: bytevector->hex-string/hex-string->bytevector/%ascii-string?
;; used indexed string-ref/string-set! loops, which are O(n) *per call* in
;; Kaappi (strings are UTF-8 byte arrays with no fast codepoint-index path),
;; making the whole loop O(n^2). Rewritten to walk string->list/list->string
;; sequentially instead. A larger input exercises the rewritten iteration
;; order (backward-building cons chain for the encoder, two-at-a-time list
;; walk for the decoder) enough to catch an off-by-one that a handful of
;; bytes could hide.
(define %big-bv
  (let ((bv (make-bytevector 1000)))
    (do ((i 0 (+ i 1))) ((= i 1000) bv)
      (bytevector-u8-set! bv i (modulo i 256)))))
(define %big-hex (bytevector->hex-string %big-bv))
(test-equal "bytevector->hex-string: output length is exactly 2x the input, at scale"
  2000
  (string-length %big-hex))
(test-equal "bytevector->hex-string: first byte (0x00) encodes correctly"
  "00"
  (substring %big-hex 0 2))
(test-equal "bytevector->hex-string: byte at index 255 (0xff) encodes correctly"
  "ff"
  (substring %big-hex 510 512))
(test-equal "bytevector->hex-string: last byte (999 mod 256 = 0xe7) encodes correctly"
  "e7"
  (substring %big-hex 1998 2000))
(test-equal "hex-string->bytevector: round-trips a larger input exactly"
  %big-bv
  (hex-string->bytevector %big-hex))

(let ((runner (test-runner-current)))
  (test-end "srfi-207")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
