;; Reader / port read-buffer refill boundary — audit v2 Phase 1C.
;;
;; `(read port)` on an fd-backed port reads the fd in 4096-byte chunks
;; (`read_chunk_size`, src/primitives_io.zig) and re-parses the accumulated
;; buffer after each chunk.  It treats `ReadError.UnexpectedEof` as
;; "incomplete datum, read more" and every other outcome as final.  A token
;; whose bytes straddle a chunk boundary therefore only survives if its
;; scanner reports truncation as exactly `UnexpectedEof`.
;;
;; Two failure modes exist:
;;   (a) the scanner reports truncation as some other error
;;       (UnterminatedString / InvalidEscape / UnexpectedChar) — the read
;;       raises instead of refilling;
;;   (b) the scanner treats end-of-buffer as a legitimate token terminator —
;;       the read silently returns a *truncated* datum and resumes in the
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

;; --- failure mode (a): truncation reported as a non-refillable error ------

;; FAIL: #1893 (string literal straddling the boundary raises KP3000 read error)
;; (test-equal "string literal, every split" #t (all-splits-ok? p-string))
;; FAIL: #1893 (a \n escape does not change it — readString's UnterminatedString)
;; (test-equal "string with \\n escape, every split" #t (all-splits-ok? p-string-esc))
;; FAIL: #1893 (\x41; escape truncated mid-escape reports InvalidEscape)
;; (test-equal "string with \\x escape, every split" #t (all-splits-ok? p-string-hex))
;; FAIL: #1893 (multi-byte string content is the same scanner)
;; (test-equal "string with UTF-8 content, every split" #t (all-splits-ok? p-string-utf8))
;; FAIL: #1893 (a string longer than the whole buffer can never be read)
;; (test-assert "string longer than the buffer" (refill-ok-from? 2000 p-long-string))

;; FAIL: #1940 (SRFI 267 raw string: readRawString returns UnterminatedString)
;; (test-equal "raw string, every split" #t (all-splits-ok? p-rawstring))
;; FAIL: #1940 (SRFI 207 #u8"...": readByteStringLiteral returns UnterminatedString)
;; (test-equal "byte string, every split" #t (all-splits-ok? p-bytestring))
;; FAIL: #1940 (|sym\x41;| truncated mid-escape reports InvalidEscape, splits 18-20)
;; (test-equal "|quoted symbol| with \\x escape, every split" #t (all-splits-ok? p-qsymbol-hex))
;; FAIL: #1940 (#u8( prefix truncated after #u or #u8 reports UnexpectedChar)
;; (test-equal "bytevector, every split" #t (all-splits-ok? p-bytevector))
;; FAIL: #1920 (dotted pair truncated after the . reports UnexpectedChar/DotNotInList)
;; (test-equal "dotted pair, every split" #t (all-splits-ok? p-dotted))

;; A multi-byte codepoint whose own bytes straddle the boundary — distinct
;; from a token straddling it.  nextToken (src/reader.zig) reports a
;; truncated UTF-8 sequence as UnexpectedChar, so even a list, which refills
;; correctly for every ASCII payload, fails.
;; FAIL: #1945 (multi-byte UTF-8 codepoint split across the boundary)
;; (test-assert "UTF-8 codepoint split inside a list"
;;   (and (refill-ok? p-utf8-list 4) (refill-ok? p-utf8-list 5)))

;; --- failure mode (b): silent truncation, no error at all -----------------
;; These are strictly worse: `read` returns a datum that is a prefix of the
;; real one and then resumes mid-token, so the caller sees extra datums it
;; never wrote.  #1893's own stated discriminating control — "the same file
;; with a bare symbol payload reads all 1024 datums" — is compromised by the
;; first case here: the symbol only survived because #1893 wrapped it in a
;; list (which does refill) and counted datums rather than comparing them.

;; FAIL: #1940 (bare symbol split at the boundary reads as TWO symbols, silently)
;; (test-equal "symbol, every split" #t (all-splits-ok? p-symbol))
;; FAIL: #1945 (UTF-8 symbol: splits between codepoints truncate, splits inside raise)
;; (test-equal "UTF-8 symbol, every split" #t (all-splits-ok? p-symbol-utf8))
;; FAIL: #1940 (number split at the boundary reads as TWO numbers, silently)
;; (test-equal "number, every split" #t (all-splits-ok? p-number))
;; FAIL: #1940 (#x number: silent split plus InvalidNumber on a truncated prefix)
;; (test-equal "hex number, every split" #t (all-splits-ok? p-number-hex))
;; FAIL: #1940 (#\space truncated to #\s plus the symbol `pace')
;; (test-equal "#\\space, every split" #t (all-splits-ok? p-char-space))
;; FAIL: #1940 (#\x41 truncated to #\x plus the number 41)
;; (test-equal "#\\x41, every split" #t (all-splits-ok? p-char-hex))
;; FAIL: #1940 (#true truncated to #t plus the symbol `rue')
;; (test-equal "#true, every split" #t (all-splits-ok? p-true))
;; FAIL: #1940 (line comment truncated at the boundary: the REST OF THE COMMENT
;;            is read as program data, because a buffer holding only a comment
;;            is discarded and reading resumes inside it)
;; (test-equal "line comment, every split" #t (all-splits-ok? p-linecmt))
;; FAIL: #1940 (symbol longer than the whole buffer splits into two symbols)
;; (test-assert "symbol longer than the buffer" (refill-ok-from? 2000 p-long-symbol))
;; FAIL: #1940 (line comment longer than the whole buffer leaks its body as data)
;; (test-assert "line comment longer than the buffer" (refill-ok-from? 2000 p-long-linecmt))

;; --- the same failures repeat at every later boundary ---------------------
;; FAIL: #1893 (nothing about the boundary is specific to the first chunk)
;; (test-equal "string literal at the 8192 boundary, every split" #t
;;   (let ((n (utf8-length p-string)))
;;     (let loop ((i 1))
;;       (cond ((>= i n) #t)
;;             ((refill-ok-at? 8192 p-string i) (loop (+ i 1)))
;;             (else i)))))
;; FAIL: #1940 (symbol splits identically at 8192)
;; (test-equal "symbol at the 8192 boundary, every split" #t
;;   (let ((n (utf8-length p-symbol)))
;;     (let loop ((i 1))
;;       (cond ((>= i n) #t)
;;             ((refill-ok-at? 8192 p-symbol i) (loop (+ i 1)))
;;             (else i)))))

(if (file-exists? fixture-file) (delete-file fixture-file))

(let ((runner (test-runner-current)))
  (test-end "reader-port-refill-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
