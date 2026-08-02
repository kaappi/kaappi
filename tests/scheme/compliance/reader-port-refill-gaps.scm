;; Reader / port read-buffer refill boundary — audit v2 Phase 1C, fixed by
;; the incomplete-input reader mode (#1893/#1920/#1940/#1945).
;;
;; `(read port)` on an fd-backed port reads the fd in 4096-byte chunks
;; (`read_chunk_size`, src/primitives_io.zig) and re-parses the accumulated
;; buffer after each chunk.  It treats `ReadError.UnexpectedEof` as
;; "incomplete datum, read more" and every other outcome as final.  A token
;; whose bytes straddle a chunk boundary therefore only survives if its
;; scanner reports truncation as exactly `UnexpectedEof` — which is what
;; `Reader.incomplete_input` (src/reader.zig) now guarantees.
;;
;; Two failure modes existed:
;;   (a) the scanner reported truncation as some other error
;;       (UnterminatedString / InvalidEscape / UnexpectedChar) — the read
;;       raised instead of refilling;
;;   (b) the scanner treated end-of-buffer as a legitimate token terminator —
;;       the read silently returned a *truncated* datum and resumed in the
;;       middle of the token, with no error at all.
;;
;; The invariant every case below asserts is the same: the identical bytes
;; must yield the identical datum sequence whether read incrementally from a
;; file port (which refills) or from a string port (which reads the whole
;; source at once and structurally cannot refill).  The string port is the
;; oracle.
;;
;; Reproducing this needs `(read p)` over an `open-input-file` port.
;; `open-input-string` and whole-program file loading both read the source
;; into memory first and cannot reach the refill path — a sweep using either
;; reports zero failures and looks like the bug is fixed.
;;
;; Fixtures are generated at run time into the system temp directory and
;; deleted again; nothing 4 KB is committed.

(import (scheme base) (scheme read) (scheme write) (scheme file)
        (scheme time) (scheme process-context) (srfi 64))

;; --- fixture plumbing -----------------------------------------------------

(define tmp-dir
  (let loop ((names '("TMPDIR" "TMP" "TEMP")))
    (if (null? names)
        "/tmp"
        (let ((v (get-environment-variable (car names))))
          (if (and v (> (string-length v) 0))
              (if (char=? (string-ref v (- (string-length v) 1)) #\/)
                  (substring v 0 (- (string-length v) 1))
                  v)
              (loop (cdr names)))))))

(define fixture-file
  (string-append tmp-dir "/kaappi-refill-"
                 (number->string (current-jiffy)) ".scm"))

(define (repeat-string s n)
  (let ((p (open-output-string)))
    (let loop ((i 0))
      (if (< i n)
          (begin (write-string s p) (loop (+ i 1)))))
    (get-output-string p)))

;; UTF-8 byte length; `string-length` counts codepoints.
(define (utf8-length s)
  (let loop ((i 0) (n 0))
    (if (>= i (string-length s))
        n
        (let ((c (char->integer (string-ref s i))))
          (loop (+ i 1)
                (+ n (cond ((< c #x80) 1)
                           ((< c #x800) 2)
                           ((< c #x10000) 3)
                           (else 4))))))))

;; One well-formed list datum padded to exactly `start` bytes, then the
;; payload, then three trailing datums.  A single big head datum (rather than
;; a thousand small ones) keeps the fixture cheap to re-read while still
;; putting the payload at the requested byte offset.
(define (fixture-text start payload)
  (let* ((head (string-append "(" (repeat-string "x " (quotient (- start 2) 2)) ")"))
         (pad (make-string (- start (string-length head)) #\space)))
    (string-append head pad payload "\n(b)\n(c)\n(d)\n")))

(define (write-fixture text)
  (if (file-exists? fixture-file) (delete-file fixture-file))
  (call-with-output-file fixture-file
    (lambda (p) (write-string text p))))

(define (drain-file)
  (let ((p (open-input-file fixture-file)))
    (guard (e (#t (close-port p) 'read-error))
      (let loop ((acc '()))
        (let ((d (read p)))
          (if (eof-object? d)
              (begin (close-port p) (reverse acc))
              (loop (cons d acc))))))))

(define (drain-string text)
  (let ((p (open-input-string text)))
    (guard (e (#t 'read-error))
      (let loop ((acc '()))
        (let ((d (read p)))
          (if (eof-object? d) (reverse acc) (loop (cons d acc))))))))

;; #t when the file port agrees with the string-port oracle for a payload
;; placed at byte offset `start`.
(define (refill-ok-from? start payload)
  (let ((text (fixture-text start payload)))
    (write-fixture text)
    (let* ((from-file (drain-file))
           (from-string (drain-string text)))
      (delete-file fixture-file)
      (equal? from-file from-string))))

;; `split-at` = how many of the payload's bytes land before the boundary.
;; 0 = payload starts exactly at the boundary; (utf8-length payload) = it
;; ends exactly there.  Both extremes are controls and must pass.
(define (refill-ok-at? boundary payload split-at)
  (refill-ok-from? (- boundary split-at) payload))

(define (refill-ok? payload split-at)
  (refill-ok-at? 4096 payload split-at))

;; Sweeps every interior split point.  Returns #t, or the first split-at that
;; disagreed (so a failure report names the offset).
(define (all-splits-ok? payload)
  (let ((n (utf8-length payload)))
    (let loop ((i 1))
      (cond ((>= i n) #t)
            ((refill-ok? payload i) (loop (+ i 1)))
            (else i)))))

;; Both boundary controls for a payload: entirely before, entirely after.
(define (both-controls-ok? payload)
  (let ((n (utf8-length payload)))
    (and (refill-ok? payload 0) (refill-ok? payload n))))

;; --- payloads -------------------------------------------------------------

(define p-list        "(aaaaaaaaaa bbbbbbbbbb cccccccccc dddddd)")
(define p-vector      "#(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)")
(define p-quoted      "'(aaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbb)")
(define p-qsymbol     "|zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz|")
(define p-blockcmt    "#|zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz|#")
(define p-datumcmt    "#;(zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz)")
(define p-datumlabel  "#0=(zzzzzzzzzzzzzzzzzzzzzz #0#)")
(define p-char-a      "#\\a")
(define p-char-utf8   "#\\\x3bb;")
(define p-directive   "#!no-fold-case")
(define p-ascii-list  "(qqAAAqq)")

(define p-string      "\"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\"")
(define p-string-esc  "\"aaaaaaaaaaaaaaaa\\nbbbbbbbbbbbbbbbbbb\"")
(define p-string-hex  "\"aaaaaaaaaaaaaaaa\\x41;bbbbbbbbbbbbbbbb\"")
(define p-string-utf8 "\"\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\"")
(define p-symbol      "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
(define p-symbol-utf8 "\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;\x3bb;")
(define p-utf8-list   "(qq\x3bb;qq)")
(define p-qsymbol-hex "|aaaaaaaaaaaaaaa\\x41;bbbbbbbbbbbbbbbbb|")
(define p-number      "12345678901234567890123456789012345678")
(define p-number-hex  "#x1234567890abcdef1234567890abcdef")
(define p-complex     "12.5+3.25i")
(define p-complex-pfx "#d12.5+3.25i")
(define p-exact-inf   "#e+inf.0")
(define p-char-space  "#\\space")
(define p-char-hex    "#\\x41")
(define p-true        "#true")
(define p-linecmt     ";zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
(define p-bytevector  "#u8(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)")
(define p-bytestring  "#u8\"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\"")
(define p-rawstring   "#\"Q\"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\"Q\"")
(define p-dotted      "(aaaaaaaaaaaaaaaaaaaa . bbbbbbbbbbbbbbbb)")

;; Payloads longer than the whole 4096-byte buffer, placed at offset 2000 so
;; they cross the first boundary from well inside the first chunk.
(define p-long-list   (string-append "(" (repeat-string "z " 2500) ")"))
(define p-long-qsym   (string-append "|" (repeat-string "z" 5000) "|"))
(define p-long-block  (string-append "#|" (repeat-string "z" 5000) "|#"))
(define p-long-string (string-append "\"" (repeat-string "z" 5000) "\""))
(define p-long-symbol (repeat-string "z" 5000))
(define p-long-linecmt (string-append ";" (repeat-string "z" 5000)))

(test-begin "reader-port-refill-gaps")

;; --- tokens that refill correctly today -----------------------------------
;; Every one of these signals truncation as UnexpectedEof, so the incremental
;; loop reads another chunk and re-parses.  Sweeping every interior split
;; point is the regression guard.

(test-equal "plain list, every split" #t (all-splits-ok? p-list))
(test-equal "vector, every split" #t (all-splits-ok? p-vector))
(test-equal "quote form, every split" #t (all-splits-ok? p-quoted))
(test-equal "|quoted symbol|, every split" #t (all-splits-ok? p-qsymbol))
(test-equal "block comment, every split" #t (all-splits-ok? p-blockcmt))
(test-equal "datum comment, every split" #t (all-splits-ok? p-datumcmt))
(test-equal "datum label, every split" #t (all-splits-ok? p-datumlabel))
(test-equal "#\\a, every split" #t (all-splits-ok? p-char-a))
(test-equal "#\\lambda, every split" #t (all-splits-ok? p-char-utf8))
(test-equal "#! directive, every split" #t (all-splits-ok? p-directive))

;; Payloads longer than the entire read buffer still refill for these kinds.
(test-assert "list longer than the buffer" (refill-ok-from? 2000 p-long-list))
(test-assert "|symbol| longer than the buffer" (refill-ok-from? 2000 p-long-qsym))
(test-assert "block comment longer than the buffer" (refill-ok-from? 2000 p-long-block))

;; --- boundary controls ----------------------------------------------------
;; Every failing payload below reads correctly when it does not straddle the
;; boundary.  These controls are what make each failure a *boundary* finding
;; rather than a claim that the payload is unreadable.

(test-assert "control: string clear of the boundary" (both-controls-ok? p-string))
(test-assert "control: symbol clear of the boundary" (both-controls-ok? p-symbol))
(test-assert "control: line comment clear of the boundary" (both-controls-ok? p-linecmt))
(test-assert "control: raw string clear of the boundary" (both-controls-ok? p-rawstring))
(test-assert "control: dotted pair clear of the boundary" (both-controls-ok? p-dotted))
(test-assert "control: #\\space clear of the boundary" (both-controls-ok? p-char-space))
(test-assert "control: number clear of the boundary" (both-controls-ok? p-number))

;; The discriminating control for the multi-byte-UTF-8 finding: the same list
;; shape with an ASCII payload of the same byte length, split at the same two
;; points, reads correctly.
(test-assert "control: ASCII list at the UTF-8 split points"
  (and (refill-ok? p-ascii-list 4) (refill-ok? p-ascii-list 5)))

;; The boundary is every 4096 bytes, not only the first one.
(test-equal "plain list at the 8192 boundary, every split" #t
  (let ((n (utf8-length p-list)))
    (let loop ((i 1))
      (cond ((>= i n) #t)
            ((refill-ok-at? 8192 p-list i) (loop (+ i 1)))
            (else i)))))
(test-assert "control: string clear of the 8192 boundary"
  (and (refill-ok-at? 8192 p-string 0)
       (refill-ok-at? 8192 p-string (utf8-length p-string))))

;; --- failure mode (a): truncation once reported as a non-refillable error -

;; #1893: string literal straddling the boundary raised KP3000 read error
(test-equal "string literal, every split" #t (all-splits-ok? p-string))
;; #1893: a \n escape did not change it — readString's UnterminatedString
(test-equal "string with \\n escape, every split" #t (all-splits-ok? p-string-esc))
;; #1893: \x41; escape truncated mid-escape reported InvalidEscape
(test-equal "string with \\x escape, every split" #t (all-splits-ok? p-string-hex))
;; #1893: multi-byte string content is the same scanner
(test-equal "string with UTF-8 content, every split" #t (all-splits-ok? p-string-utf8))
;; #1893: a string longer than the whole buffer could never be read
(test-assert "string longer than the buffer" (refill-ok-from? 2000 p-long-string))

;; #1940: SRFI 267 raw string — readRawString returned UnterminatedString
(test-equal "raw string, every split" #t (all-splits-ok? p-rawstring))
;; #1940: SRFI 207 #u8"..." — readByteStringLiteral returned UnterminatedString
(test-equal "byte string, every split" #t (all-splits-ok? p-bytestring))
;; #1940: |sym\x41;| truncated mid-escape reported InvalidEscape
(test-equal "|quoted symbol| with \\x escape, every split" #t (all-splits-ok? p-qsymbol-hex))
;; #1940: #u8( prefix truncated after #u or #u8 reported UnexpectedChar
(test-equal "bytevector, every split" #t (all-splits-ok? p-bytevector))
;; #1920: dotted pair truncated after the . reported UnexpectedChar/DotNotInList
(test-equal "dotted pair, every split" #t (all-splits-ok? p-dotted))

;; A multi-byte codepoint whose own bytes straddle the boundary — distinct
;; from a token straddling it.  nextToken (src/reader.zig) reported a
;; truncated UTF-8 sequence as UnexpectedChar, so even a list, which refills
;; correctly for every ASCII payload, failed.
;; #1945: multi-byte UTF-8 codepoint split across the boundary
(test-assert "UTF-8 codepoint split inside a list"
  (and (refill-ok? p-utf8-list 4) (refill-ok? p-utf8-list 5)))

;; --- failure mode (b): silent truncation, no error at all -----------------
;; These were strictly worse: `read` returned a datum that is a prefix of the
;; real one and then resumed mid-token, so the caller saw extra datums it
;; never wrote.

;; #1940: bare symbol split at the boundary read as TWO symbols, silently
(test-equal "symbol, every split" #t (all-splits-ok? p-symbol))
;; #1945: UTF-8 symbol — splits between codepoints truncated, splits inside raised
(test-equal "UTF-8 symbol, every split" #t (all-splits-ok? p-symbol-utf8))
;; #1940: number split at the boundary read as TWO numbers, silently
(test-equal "number, every split" #t (all-splits-ok? p-number))
;; #1940: #x number — silent split plus InvalidNumber on a truncated prefix
(test-equal "hex number, every split" #t (all-splits-ok? p-number-hex))
;; #1940: #\space truncated to #\s plus the symbol `pace'
(test-equal "#\\space, every split" #t (all-splits-ok? p-char-space))
;; #1940: #\x41 truncated to #\x plus the number 41
(test-equal "#\\x41, every split" #t (all-splits-ok? p-char-hex))
;; #1940: #true truncated to #t plus the symbol `rue'
(test-equal "#true, every split" #t (all-splits-ok? p-true))
;; #1940: line comment truncated at the boundary — the rest of the comment
;; was read as program data, because a buffer holding only a comment was
;; discarded and reading resumed inside it
(test-equal "line comment, every split" #t (all-splits-ok? p-linecmt))
;; A complex literal exercises the backtracking scan: a straddled "1+2" is a
;; committed fixnum 1 unless the delimiter-free tail defers the verdict.
(test-equal "complex number, every split" #t (all-splits-ok? p-complex))
(test-equal "#d-prefixed complex, every split" #t (all-splits-ok? p-complex-pfx))
;; An exactness-prefixed inf: "#e+in" is InvalidNumber only once the whole
;; token is known.
(test-equal "#e+inf.0, every split" #t (all-splits-ok? p-exact-inf))
;; #1940: symbol longer than the whole buffer split into two symbols
(test-assert "symbol longer than the buffer" (refill-ok-from? 2000 p-long-symbol))
;; #1940: line comment longer than the whole buffer leaked its body as data
(test-assert "line comment longer than the buffer" (refill-ok-from? 2000 p-long-linecmt))

;; --- the same failures repeated at every later boundary --------------------
;; #1893: nothing about the boundary is specific to the first chunk
(test-equal "string literal at the 8192 boundary, every split" #t
  (let ((n (utf8-length p-string)))
    (let loop ((i 1))
      (cond ((>= i n) #t)
            ((refill-ok-at? 8192 p-string i) (loop (+ i 1)))
            (else i)))))
;; #1940: symbol split identically at 8192
(test-equal "symbol at the 8192 boundary, every split" #t
  (let ((n (utf8-length p-symbol)))
    (let loop ((i 1))
      (cond ((>= i n) #t)
            ((refill-ok-at? 8192 p-symbol i) (loop (+ i 1)))
            (else i)))))

;; --- read-loop state the fix must preserve --------------------------------

;; A #! directive whose buffer holds nothing else is NOT discarded the way
;; pure whitespace/comments are: fold-case state must survive into the next
;; chunk, where each refill's fresh Reader recovers it by re-parsing the
;; buffer from its start.
(test-equal "fold-case directive separated from its datum by the boundary"
  '((foo))
  (let ()
    (write-fixture (string-append "#!fold-case"
                                  (make-string (- 4096 11) #\space)
                                  "(FOO)\n"))
    (let ((r (drain-file)))
      (delete-file fixture-file)
      r)))

;; A trailing #! directive is trivia, so read must answer with the EOF
;; object — not a read error (hasMore()+readDatum used to conflate this
;; with a truncated datum).
(test-assert "trailing directive on a file port yields eof"
  (let ()
    (write-fixture "42 #!fold-case")
    (let* ((p (open-input-file fixture-file))
           (d1 (read p))
           (d2 (guard (e (#t 'read-error)) (read p))))
      (close-port p)
      (delete-file fixture-file)
      (and (equal? d1 42) (eof-object? d2)))))
(test-assert "trailing directive on a string port yields eof"
  (eof-object? (read (open-input-string "#!fold-case"))))

;; #1920's diagnostic half: the raised error names what failed instead of a
;; bare "read error".
(test-equal "read error message names the failure"
  "read error: unterminated string literal"
  (guard (e (#t (error-object-message e)))
    (read (open-input-string "\"abc"))))

(if (file-exists? fixture-file) (delete-file fixture-file))

(let ((runner (test-runner-current)))
  (test-end "reader-port-refill-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
