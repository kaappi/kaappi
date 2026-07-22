;;; SRFI 207 — String-notated bytevectors
;;;
;;; Defines `#u8"..."` reader syntax: an ASCII-only, escape-based textual
;;; notation for bytevectors (distinct from R7RS's `#u8(...)` list
;;; notation). Escapes are a closed grammar the spec defines from scratch
;;; rather than inheriting R7RS string escapes wholesale -- `\a \b \t \n
;;; \r \| \" \\` mean the same thing, but a direct (unescaped) character
;;; must be printable ASCII (0x20-0x7E); anything else, including a
;;; syntactically valid non-ASCII UTF-8 character, is a read error (the
;;; spec's own example: `#u8"\xE000;"` and a literal Greek iota are both
;;; explicitly invalid). `\xHH;` decodes to exactly one raw byte 0-255,
;;; not a Unicode codepoint UTF-8-encoded into however many bytes that
;;; would take. This is a genuine reader change with no portable-library
;;; equivalent, implemented in `readByteStringLiteral`
;;; (src/reader_tokens.zig) as a deliberately separate function from the
;;; ordinary string reader, not a shared/refactored one, since the two
;;; escape grammars and direct-character rules differ in exactly the ways
;;; above.
;;;
;;; SRFI 207's full spec is much larger than its reader syntax: an
;;; extensive bytestring-processing library (padding, trimming, index/
;;; search, comparison, join/split, base64, generators -- ~25 procedures
;;; total). The issue tracking this work (#1705) scoped in only the
;;; `#u8"..."` syntax itself ("also needs array type support" was SRFI 58's
;;; note, not this one -- 207's own issue line says just "syntax"). This
;;; library implements the reader syntax plus the four procedures most
;;; directly tied to the notation itself -- `bytestring` (the constructor
;;; that mirrors what the notation builds), `bytevector->hex-string` /
;;; `hex-string->bytevector` (the hex-escape half of the notation, exposed
;;; as a full round-trip), and `write-textual-bytestring` (the writer
;;; counterpart of the reader syntax) -- and deliberately does not
;;; implement the rest of the processing library, which is independent of
;;; the notation and large enough to be its own follow-up if wanted.

(define-library (srfi 207)
  (export bytestring bytestring-error? bytevector->hex-string hex-string->bytevector
          write-textual-bytestring)
  (import (scheme base) (scheme write) (scheme char))
  (begin

    (define-record-type <bytestring-error>
      (make-bytestring-error message irritants)
      bytestring-error?
      (message bytestring-error-message)
      (irritants bytestring-error-irritants))

    (define (%bytestring-fail message . irritants)
      (raise (make-bytestring-error message irritants)))

    ;; --- bytestring: variadic constructor ---

    (define (%arg->bytevector arg)
      (cond
        ((and (exact-integer? arg) (<= 0 arg 255)) (bytevector arg))
        ((and (char? arg) (< (char->integer arg) 128)) (bytevector (char->integer arg)))
        ((bytevector? arg) arg)
        ((and (string? arg) (%ascii-string? arg)) (string->utf8 arg))
        (else (%bytestring-fail "bytestring: invalid argument" arg))))

    (define (%ascii-string? s)
      (let loop ((i 0))
        (or (>= i (string-length s))
            (and (< (char->integer (string-ref s i)) 128) (loop (+ i 1))))))

    (define (bytestring . args)
      (apply bytevector-append (map %arg->bytevector args)))

    ;; --- hex string conversions ---

    (define %hex-digits "0123456789abcdef")

    (define (bytevector->hex-string bv)
      (let* ((len (bytevector-length bv))
             (out (make-string (* 2 len))))
        (let loop ((i 0))
          (if (>= i len)
              out
              (let ((b (bytevector-u8-ref bv i)))
                (string-set! out (* 2 i) (string-ref %hex-digits (quotient b 16)))
                (string-set! out (+ (* 2 i) 1) (string-ref %hex-digits (remainder b 16)))
                (loop (+ i 1)))))))

    (define (%hex-digit-value c)
      (cond
        ((and (char>=? c #\0) (char<=? c #\9)) (- (char->integer c) (char->integer #\0)))
        ((and (char>=? c #\a) (char<=? c #\f)) (+ 10 (- (char->integer c) (char->integer #\a))))
        ((and (char>=? c #\A) (char<=? c #\F)) (+ 10 (- (char->integer c) (char->integer #\A))))
        (else #f)))

    (define (hex-string->bytevector s)
      (if (odd? (string-length s))
          (%bytestring-fail "hex-string->bytevector: odd number of hex digits" s)
          (let* ((len (quotient (string-length s) 2))
                 (out (make-bytevector len)))
            (let loop ((i 0))
              (if (>= i len)
                  out
                  (let ((hi (%hex-digit-value (string-ref s (* 2 i))))
                        (lo (%hex-digit-value (string-ref s (+ (* 2 i) 1)))))
                    (if (and hi lo)
                        (begin
                          (bytevector-u8-set! out i (+ (* hi 16) lo))
                          (loop (+ i 1)))
                        (%bytestring-fail "hex-string->bytevector: invalid hex digit" s))))))))

    ;; --- writer: the #u8"..." notation, escaping only what must be ---

    (define (%mnemonic-escape b)
      (case b
        ((7) "\\a") ((8) "\\b") ((9) "\\t") ((10) "\\n") ((13) "\\r") ((124) "\\|")
        ((34) "\\\"") ((92) "\\\\")
        (else #f)))

    (define (%hex-escape b)
      (string-append "\\x" (bytevector->hex-string (bytevector b)) ";"))

    (define (write-textual-bytestring bv . maybe-port)
      (let ((port (if (pair? maybe-port) (car maybe-port) (current-output-port))))
        (display "#u8\"" port)
        (let ((len (bytevector-length bv)))
          (let loop ((i 0))
            (when (< i len)
              (let ((b (bytevector-u8-ref bv i)))
                (display
                  (or (%mnemonic-escape b)
                      (if (<= 32 b 126) (string (integer->char b)) (%hex-escape b)))
                  port))
              (loop (+ i 1)))))
        (display "\"" port)))))
