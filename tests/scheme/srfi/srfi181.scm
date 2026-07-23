;; SRFI-181 (Custom Ports and Transcoded Ports) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi181.scm
;;
;; lib/srfi/181.sld imports the native srfi_181_primitives sub-library and
;; re-exports its full surface: the 5 custom-port constructors
;; (make-custom-binary-input-port, -output-port,
;; make-custom-textual-input-port, -output-port,
;; make-custom-binary-input/output-port) plus make-file-error, and the
;; transcoded-port layer (make-transcoder, native-transcoder, codecs,
;; eol-styles, the raise error-handling mode) tested in its own section
;; below.
;;
;; Custom port callbacks run through vm.callWithArgs, which always
;; executes with dispatched_from_scheduler forced false: a callback that
;; tries to block (another port's I/O, thread-sleep!) is rejected with a
;; catchable error rather than risking a native-stack-overflow recursive
;; scheduler drive -- callbacks must be effectively synchronous,
;; non-blocking code. See the "blocking callback" section below.
;;
;; The transcoded-port section below is deliberately narrower than
;; src/tests_srfi181.zig's own coverage of the decode/encode loop itself
;; (byte-level UTF-8 validity, CRLF lookahead pushback, raiseContinuable
;; wiring) -- those are proven once, directly against the Zig
;; implementation, independent of this portable layer. This section
;; instead covers what only exists at this layer: make-codec,
;; native-transcoder's defaults, unknown-encoding-error?,
;; bytevector->string/string->bytevector, and end-to-end wiring through
;; the compiled .sld (including a case the Zig tests don't reach at all:
;; a multi-byte character split across many single-byte read! calls on a
;; *custom* wrapped port, and a bidirectional transcoded port).

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 181) (srfi 192) (srfi 64))

(test-begin "srfi-181")

;;; --- binary input port ---

(let* ((src (bytevector 10 20 30 40 50))
       (pos 0)
       (p (make-custom-binary-input-port
            "src"
            (lambda (bv start count)
              (let ((n (min count (- (bytevector-length src) pos))))
                (let loop ((i 0))
                  (when (< i n)
                    (bytevector-u8-set! bv (+ start i) (bytevector-u8-ref src (+ pos i)))
                    (loop (+ i 1))))
                (set! pos (+ pos n))
                n))
            #f #f #f)))
  (test-assert "binary input port: port? and input-port?" (and (port? p) (input-port? p)))
  (test-assert "binary input port: binary-port?, not textual-port?"
    (and (binary-port? p) (not (textual-port? p))))
  (test-equal "binary input port: read-u8 sequence" 10 (read-u8 p))
  (test-equal "binary input port: read-u8 sequence 2" 20 (read-u8 p))
  (test-equal "binary input port: read-bytevector drains the rest"
    (bytevector 30 40 50)
    (read-bytevector 10 p))
  (test-assert "binary input port: EOF after exhaustion" (eof-object? (read-u8 p))))

;;; --- textual input port ---

(let* ((src "hello\nworld")
       (pos 0)
       (p (make-custom-textual-input-port
            "src"
            (lambda (s start count)
              (let ((n (min count (- (string-length src) pos))))
                (let loop ((i 0))
                  (when (< i n)
                    (string-set! s (+ start i) (string-ref src (+ pos i)))
                    (loop (+ i 1))))
                (set! pos (+ pos n))
                n))
            #f #f #f)))
  (test-assert "textual input port: textual-port?, not binary-port?"
    (and (textual-port? p) (not (binary-port? p))))
  (test-equal "textual input port: read-char" #\h (read-char p))
  (test-equal "textual input port: read-line reads to newline" "ello" (read-line p))
  (test-equal "textual input port: read-line again reads the rest" "world" (read-line p))
  (test-assert "textual input port: EOF after exhaustion" (eof-object? (read-char p))))

;; A read! that writes a multi-byte UTF-8 character forces Kaappi's string
;; internals to reallocate the backing buffer in place (differing byte
;; width) -- regression for the use-after-free trap this must avoid
;; (never cache a string's byte slice across the callWithArgs call).
(let* ((src "aéz") ; 1-byte, 2-byte (e-acute), 1-byte
       (pos 0)
       (p (make-custom-textual-input-port
            "utf8"
            (lambda (s start count)
              (if (>= pos (string-length src)) 0
                  (begin (string-set! s start (string-ref src pos))
                         (set! pos (+ pos 1))
                         1)))
            #f #f #f)))
  (test-equal "textual input port: multi-byte character read one at a time"
    "aéz"
    (read-string 10 p)))

;;; --- binary output port ---

(let* ((collected '())
       (p (make-custom-binary-output-port
            "sink"
            (lambda (bv start count)
              (let loop ((i start) (n 0))
                (if (>= n count)
                    n
                    (begin (set! collected (cons (bytevector-u8-ref bv i) collected))
                           (loop (+ i 1) (+ n 1))))))
            #f #f #f)))
  (test-assert "binary output port: port? and output-port?" (and (port? p) (output-port? p)))
  (write-u8 1 p)
  (write-bytevector (bytevector 2 3 4) p)
  (test-equal "binary output port: bytes arrive in order" '(1 2 3 4) (reverse collected)))

;;; --- textual output port ---

(let* ((acc (open-output-string))
       (p (make-custom-textual-output-port
            "sink"
            (lambda (s start count)
              (write-string (substring s start (+ start count)) acc)
              count)
            #f #f #f)))
  (write-string "hello " p)
  (write-char #\w p)
  (write-string "orld" p)
  (test-equal "textual output port: chars arrive in order" "hello world" (get-output-string acc)))

;;; --- partial reads/writes: the callback need not fill/drain in one call ---

(let* ((src (bytevector 1 2 3 4 5))
       (pos 0)
       (p (make-custom-binary-input-port
            "one-at-a-time"
            (lambda (bv start count)
              (if (>= pos (bytevector-length src)) 0
                  (begin (bytevector-u8-set! bv start (bytevector-u8-ref src pos))
                         (set! pos (+ pos 1))
                         1))) ; always exactly 1 byte, forcing readOneByte's caller to loop
            #f #f #f)))
  (test-equal "binary input port: read-bytevector across many 1-byte read! calls"
    (bytevector 1 2 3 4 5)
    (read-bytevector 5 p)))

(let* ((collected '())
       (p (make-custom-binary-output-port
            "one-at-a-time"
            (lambda (bv start count)
              (set! collected (cons (bytevector-u8-ref bv start) collected))
              1) ; always accept exactly 1 byte, forcing the write loop to iterate
            #f #f #f)))
  (write-bytevector (bytevector 9 8 7 6) p)
  (test-equal "binary output port: write-bytevector across many 1-byte write! calls"
    '(9 8 7 6)
    (reverse collected)))

;;; --- bidirectional port ---

(let* ((state '())
       (p (make-custom-binary-input/output-port
            "bidi"
            (lambda (bv start count) 0) ; EOF on read
            (lambda (bv start count)
              (set! state (cons (bytevector-u8-ref bv start) state))
              count)
            #f #f #f)))
  (test-assert "bidirectional port: both input-port? and output-port?"
    (and (input-port? p) (output-port? p)))
  (write-u8 42 p)
  (test-assert "bidirectional port: EOF on read side" (eof-object? (read-u8 p)))
  (test-equal "bidirectional port: write side received the byte" '(42) state))

;;; --- get-position / set-position! (integrates with SRFI 192) ---

(let* ((data (bytevector 100 101 102 103 104))
       (pos 0)
       (p (make-custom-binary-input-port
            "posn"
            (lambda (bv start count)
              (if (>= pos (bytevector-length data)) 0
                  (begin (bytevector-u8-set! bv start (bytevector-u8-ref data pos))
                         (set! pos (+ pos 1))
                         1)))
            (lambda () pos)
            (lambda (new-pos) (set! pos new-pos))
            #f)))
  (test-assert "custom port: port-has-port-position? is true when get-position is supplied"
    (port-has-port-position? p))
  (read-u8 p)
  (test-equal "custom port: port-position reflects get-position" 1 (port-position p))
  (set-port-position! p 3)
  (test-equal "custom port: read after set-port-position! honors the new position" 103 (read-u8 p)))

;; A port with no get-position/set-position! reports it cleanly rather
;; than falling through to fd-based positioning on the fd=-1 sentinel.
(let ((p (make-custom-binary-input-port "no-posn" (lambda (bv s c) 0) #f #f #f)))
  (test-assert "custom port: port-has-port-position? is false without get-position"
    (not (port-has-port-position? p)))
  (test-error "custom port: port-position without get-position signals an error"
    (port-position p)))

;;; --- close semantics ---

(let ((close-count 0))
  (let ((p (make-custom-binary-input-port
             "c" (lambda (bv s c) 0) #f #f
             (lambda () (set! close-count (+ close-count 1))))))
    (close-port p)
    (close-port p) ; a second close must not re-invoke close_proc
    (test-equal "custom port: close_proc invoked exactly once across a double close-port"
      1 close-count)))

;; close is optional (#f) -- close-port must still succeed.
(let ((p (make-custom-binary-input-port "no-close" (lambda (bv s c) 0) #f #f #f)))
  (close-port p)
  (test-assert "custom port: close-port succeeds when close_proc is #f" #t))

;;; --- flush semantics ---

(let ((flush-count 0))
  (let ((p (make-custom-binary-output-port
             "f" (lambda (bv s c) c) #f #f #f
             (lambda () (set! flush-count (+ flush-count 1))))))
    (flush-output-port p)
    (flush-output-port p)
    (test-equal "custom port: flush_proc invoked once per flush-output-port call"
      2 flush-count)))

;; flush is optional (#f) -- flush-output-port must still succeed, and
;; must not attempt to call #f as a procedure.
(let ((p (make-custom-binary-output-port "no-flush" (lambda (bv s c) c) #f #f #f)))
  (flush-output-port p)
  (test-assert "custom port: flush-output-port succeeds when flush_proc is #f" #t))

;; R7RS: "If port is an output port, it is flushed before being closed."
;; A custom port whose write! buffers internally (relying on flush! to
;; actually emit) must not lose that data on close-port without an
;; explicit flush-output-port call first.
(let* ((internal-buffer '())
       (emitted '())
       (p (make-custom-binary-output-port
            "buffered"
            (lambda (bv start count)
              (let loop ((i start) (n 0))
                (when (< n count)
                  (set! internal-buffer (cons (bytevector-u8-ref bv i) internal-buffer))
                  (loop (+ i 1) (+ n 1))))
              count)
            #f #f  ; get-position, set-position!
            #f     ; close
            (lambda () (set! emitted internal-buffer))))) ; flush
  (write-u8 65 p)
  (write-u8 66 p)
  (test-equal "custom port: nothing emitted before close (flush_proc not yet called)"
    '() emitted)
  (close-port p)
  (test-equal "custom port: close-port flushes an output port before closing it"
    '(66 65) emitted))

;;; --- error propagation ---

(test-error "custom port: a read! that raises propagates the error"
  (read-u8 (make-custom-binary-input-port
             "boom" (lambda (bv s c) (error "read! boom")) #f #f #f)))

(test-error "custom port: a write! that raises propagates the error"
  (write-u8 1 (make-custom-binary-output-port
                "boom" (lambda (bv s c) (error "write! boom")) #f #f #f)))

;;; --- misbehaving callbacks are rejected, not trusted blindly ---

(test-error "custom port: read! returning a negative count is rejected"
  (read-u8 (make-custom-binary-input-port "bad" (lambda (bv s c) -1) #f #f #f)))

(test-error "custom port: read! returning a too-large count is rejected"
  (read-u8 (make-custom-binary-input-port "bad" (lambda (bv s c) (+ c 1)) #f #f #f)))

(test-error "custom port: write! returning zero progress on a non-empty write is rejected"
  (write-u8 1 (make-custom-binary-output-port "stuck" (lambda (bv s c) 0) #f #f #f)))

(test-error "custom port: a non-procedure read! argument is rejected at construction"
  (make-custom-binary-input-port "bad" 42 #f #f #f))

(test-error "custom port: a non-#f non-procedure get-position is rejected at construction"
  (make-custom-binary-input-port "bad" (lambda (bv s c) 0) 42 #f #f))

;;; --- blocking callback guard ---
;;; A custom port callback runs with dispatched_from_scheduler forced
;;; false; it must not be able to block on another port's I/O or
;;; thread-sleep! without a clean, catchable rejection.

(let* ((p (make-custom-binary-input-port
            "blocks"
            (lambda (bv s c) (thread-sleep! 0.01) 0)
            #f #f #f))
       (f (spawn (lambda ()
            (guard (e (#t 'caught))
              (read-u8 p)
              'did-not-raise)))))
  (test-equal "blocking callback: thread-sleep! inside read! is rejected, not hung"
    'caught
    (fiber-join f)))

;;; --- make-file-error ---

(test-assert "make-file-error: satisfies file-error?" (file-error? (make-file-error "boom")))
(test-assert "make-file-error: does not satisfy read-error?" (not (read-error? (make-file-error "boom"))))
(test-assert "make-file-error: no arguments still constructs a file-error" (file-error? (make-file-error)))

;;; ==================================================================
;;; Transcoded ports
;;; ==================================================================

;;; --- native-transcoder / transcoder? ---

(test-assert "native-transcoder: satisfies transcoder?" (transcoder? (native-transcoder)))

;;; --- codecs ---

(test-assert "utf-8-codec: eqv? to itself across calls" (eqv? (utf-8-codec) (utf-8-codec)))
(test-assert "make-codec: matches \"UTF-8\" case-insensitively"
  (eqv? (utf-8-codec) (make-codec "UTF-8")))
(test-assert "make-codec: matches \"utf8\" (no hyphen)"
  (eqv? (utf-8-codec) (make-codec "utf8")))
(test-assert "make-codec: an unrecognized name signals unknown-encoding-error?"
  (guard (e (#t (unknown-encoding-error? e)))
    (make-codec "shift-jis")
    #f))
(test-equal "unknown-encoding-error-name: reports the rejected name"
  "shift-jis"
  (guard (e (#t (unknown-encoding-error-name e)))
    (make-codec "shift-jis")))

;; SRFI 181: "It is an error to mutate this string" -- Kaappi enforces this
;; the same way it already does for symbol->string's result (both check
;; the same flags.immutable bit string-set! consults). Must pass a
;; genuinely mutable string (string-copy, not a literal): a string
;; literal is already immutable via the reader's own quoted-data handling
;; regardless of make-codec's own behavior, which would make this test
;; pass even without make-codec freezing anything itself.
(test-error "unknown-encoding-error-name: the returned string is immutable"
  (string-set! (guard (e (#t (unknown-encoding-error-name e)))
                 (make-codec (string-copy "shift-jis")))
               0 #\X))

;; The condition must not alias the caller's own (mutable) argument string
;; -- mutating it after the fact must not retroactively corrupt the
;; already-raised condition's name.
(let* ((name (string-copy "shift-jis"))
       (reported (guard (e (#t (unknown-encoding-error-name e)))
                   (make-codec name))))
  (string-set! name 0 #\X)
  (test-equal "unknown-encoding-error-name: does not alias the caller's argument string"
    "shift-jis"
    reported))

;;; --- native-eol-style ---

(test-assert "native-eol-style: one of the two implemented eol-styles"
  (memv (native-eol-style) '(lf crlf)))

;;; --- transcoded-port: decode ---

(let* ((t (native-transcoder))
       (bp (open-input-bytevector (string->utf8 "hello")))
       (tp (transcoded-port bp t)))
  (test-assert "transcoded-port: textual-port?, not binary-port?"
    (and (textual-port? tp) (not (binary-port? tp))))
  (test-equal "transcoded-port: decodes ASCII via read-char" #\h (read-char tp))
  (test-equal "transcoded-port: read-line decodes the rest" "ello" (read-line tp))
  (test-assert "transcoded-port: EOF after exhaustion" (eof-object? (read-char tp))))

;;; --- transcoded-port: encode ---

(let* ((t (native-transcoder))
       (bp (open-output-bytevector))
       (tp (transcoded-port bp t)))
  (write-string "hello" tp)
  (test-equal "transcoded-port: write-string encodes to the wrapped bytevector"
    (string->utf8 "hello")
    (get-output-bytevector bp)))

;;; --- multi-byte UTF-8 split across many 1-byte read! calls ---
;;; Wraps a *custom* binary port that only ever yields one byte per read!
;;; call (the same technique the custom-port suite above uses to force
;;; readOneByte's caller to loop) underneath a transcoded port, so decoding
;;; a multi-byte character genuinely requires several separate readOneByte
;;; calls into the wrapped port -- not just indexing into an
;;; already-fully-buffered bytevector port.

(let* ((src (string->utf8 "aéz")) ; 1-byte, 2-byte (e-acute), 1-byte
       (pos 0)
       (bp (make-custom-binary-input-port
             "one-byte-at-a-time"
             (lambda (bv start count)
               (if (>= pos (bytevector-length src)) 0
                   (begin (bytevector-u8-set! bv start (bytevector-u8-ref src pos))
                          (set! pos (+ pos 1))
                          1)))
             #f #f #f))
       (tp (transcoded-port bp (native-transcoder))))
  (test-equal "transcoded-port: multi-byte character decoded across many 1-byte read! calls"
    "aéz"
    (read-string 10 tp)))

;;; --- eol-style ---

(let* ((t (make-transcoder (utf-8-codec) 'crlf 'replace))
       (bp (open-input-bytevector (string->utf8 "a\r\nb\rc\nd")))
       (tp (transcoded-port bp t)))
  (test-equal "transcoded-port: eol-style crlf collapses CR/LF/CRLF on read"
    "a\nb\nc\nd"
    (read-string 10 tp)))

(let* ((t (make-transcoder (utf-8-codec) 'crlf 'replace))
       (bp (open-output-bytevector))
       (tp (transcoded-port bp t)))
  (write-string "a\nb" tp)
  (test-equal "transcoded-port: eol-style crlf expands newline to CRLF on write"
    (string->utf8 "a\r\nb")
    (get-output-bytevector bp)))

;;; --- replace mode ---

(let* ((t (make-transcoder (utf-8-codec) 'none 'replace))
       (bp (open-input-bytevector (bytevector 65 255 66))) ; A, invalid, B
       (tp (transcoded-port bp t)))
  (test-equal "transcoded-port: replace mode substitutes U+FFFD for invalid UTF-8"
    "A\xFFFD;B"
    (read-string 10 tp)))

;;; --- raise mode ---

(let* ((t (make-transcoder (utf-8-codec) 'none 'raise))
       (bp (open-input-bytevector (bytevector 65 255 66))) ; A, invalid, B
       (tp (transcoded-port bp t))
       (handler-calls 0)
       (last-condition #f))
  (define decoded
    (with-exception-handler
      (lambda (e)
        (set! handler-calls (+ handler-calls 1))
        (set! last-condition e)
        'ignored)
      (lambda ()
        (let* ((c1 (read-char tp))
               (c2 (read-char tp)))
          (list c1 c2)))))
  (test-equal "transcoded-port: raise mode decodes 'A' then, after signaling, 'B'"
    (list #\A #\B)
    decoded)
  (test-equal "transcoded-port: raise mode's handler runs exactly once"
    1 handler-calls)
  (test-assert "transcoded-port: raise mode's condition satisfies i/o-decoding-error?"
    (i/o-decoding-error? last-condition)))

;;; --- wrapped port closed underneath ---

(let* ((bp (open-input-bytevector (string->utf8 "hi")))
       (tp (transcoded-port bp (native-transcoder))))
  (close-port bp)
  (test-error "transcoded-port: reading after the wrapped port is closed underneath it raises"
    (read-char tp)))

;;; --- close cascade ---

(let* ((bp (open-input-bytevector (string->utf8 "hi")))
       (tp (transcoded-port bp (native-transcoder))))
  (close-port tp)
  (test-assert "transcoded-port: closing it also closes the wrapped port"
    (not (input-port-open? bp))))

;;; --- port-position unsupported ---

(let* ((bp (open-input-bytevector (string->utf8 "hi")))
       (tp (transcoded-port bp (native-transcoder))))
  (test-assert "transcoded-port: port-has-port-position? is false"
    (not (port-has-port-position? tp)))
  (test-error "transcoded-port: port-position signals an error"
    (port-position tp)))

;;; --- bidirectional transcoded port ---

(let* ((state '())
       (bp (make-custom-binary-input/output-port
             "bidi"
             (lambda (bv start count) 0) ; EOF on read
             (lambda (bv start count)
               (let loop ((i start) (n 0))
                 (when (< n count)
                   (set! state (cons (bytevector-u8-ref bv i) state))
                   (loop (+ i 1) (+ n 1))))
               count)
             #f #f #f))
       (tp (transcoded-port bp (native-transcoder))))
  (test-assert "transcoded-port: bidirectional wrapping is both input and output"
    (and (input-port? tp) (output-port? tp)))
  (write-char #\A tp)
  (test-assert "transcoded-port: bidirectional EOF on the read side" (eof-object? (read-char tp)))
  (test-equal "transcoded-port: bidirectional write side received the byte"
    '(65)
    (reverse state)))

;;; --- bytevector->string / string->bytevector ---

(test-equal "bytevector->string: decodes UTF-8 bytes to a string"
  "café"
  (bytevector->string (string->utf8 "café") (native-transcoder)))

(test-equal "string->bytevector: encodes a string to UTF-8 bytes"
  (string->utf8 "café")
  (string->bytevector "café" (native-transcoder)))

(test-equal "bytevector->string / string->bytevector: round trip"
  "hello world"
  (bytevector->string (string->bytevector "hello world" (native-transcoder)) (native-transcoder)))

;;; --- invalid transcoder components are rejected at first use ---

(test-error "transcoded-port: an unrecognized codec symbol is rejected"
  (transcoded-port (open-input-bytevector #u8()) (make-transcoder 'bogus 'none 'replace)))

(test-error "transcoded-port: an unrecognized eol-style symbol is rejected"
  (transcoded-port (open-input-bytevector #u8()) (make-transcoder (utf-8-codec) 'bogus 'replace)))

(test-error "transcoded-port: an unrecognized error-handling-mode symbol is rejected"
  (transcoded-port (open-input-bytevector #u8()) (make-transcoder (utf-8-codec) 'none 'bogus)))

(test-error "transcoded-port: a non-binary wrapped port is rejected"
  (transcoded-port (open-input-string "hi") (native-transcoder)))

(let ((runner (test-runner-current)))
  (test-end "srfi-181")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
