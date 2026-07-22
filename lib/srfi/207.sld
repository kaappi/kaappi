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

    ;; Walks a list of characters, not indexed string-ref calls: Kaappi
    ;; strings are UTF-8 byte arrays, so string-ref/string-set! locate the
    ;; k-th codepoint by scanning from the start every time (O(k) per
    ;; call) -- an indexed loop over a whole string is O(n^2), whereas
    ;; string->list decodes each codepoint once, in one forward pass.
    (define (%ascii-string? s)
      (let loop ((cs (string->list s)))
        (or (null? cs)
            (and (< (char->integer (car cs)) 128) (loop (cdr cs))))))

    (define (bytestring . args)
      (apply bytevector-append (map %arg->bytevector args)))

    ;; --- hex string conversions ---

    (define %hex-digits "0123456789abcdef")

    ;; Builds the result as a list of characters, back to front (so a
    ;; single cons chain lands each byte's two digits in the right final
    ;; order), then converts once via list->string -- writing into a
    ;; string by increasing index via string-set! would be O(n^2) for the
    ;; same reason noted on %ascii-string? above.
    (define (bytevector->hex-string bv)
      (let ((len (bytevector-length bv)))
        (let loop ((i (- len 1)) (acc '()))
          (if (< i 0)
              (list->string acc)
              (let ((b (bytevector-u8-ref bv i)))
                (loop (- i 1)
                      (cons (string-ref %hex-digits (quotient b 16))
                            (cons (string-ref %hex-digits (remainder b 16))
                                  acc))))))))

    (define (%hex-digit-value c)
      (cond
        ((and (char>=? c #\0) (char<=? c #\9)) (- (char->integer c) (char->integer #\0)))
        ((and (char>=? c #\a) (char<=? c #\f)) (+ 10 (- (char->integer c) (char->integer #\a))))
        ((and (char>=? c #\A) (char<=? c #\F)) (+ 10 (- (char->integer c) (char->integer #\A))))
        (else #f)))

    ;; Walks the input as a list (see %ascii-string? above for why: an
    ;; indexed string-ref loop over the whole string is O(n^2) here) two
    ;; characters at a time, writing into the bytevector by increasing
    ;; index -- bytevector-u8-set! has no such cost, since bytevectors are
    ;; plain byte arrays with true O(1) indexing.
    (define (hex-string->bytevector s)
      (if (odd? (string-length s))
          (%bytestring-fail "hex-string->bytevector: odd number of hex digits" s)
          (let* ((len (quotient (string-length s) 2))
                 (out (make-bytevector len)))
            (let loop ((cs (string->list s)) (i 0))
              (if (null? cs)
                  out
                  (let ((hi (%hex-digit-value (car cs)))
                        (lo (%hex-digit-value (cadr cs))))
                    (if (and hi lo)
                        (begin
                          (bytevector-u8-set! out i (+ (* hi 16) lo))
                          (loop (cddr cs) (+ i 1)))
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
