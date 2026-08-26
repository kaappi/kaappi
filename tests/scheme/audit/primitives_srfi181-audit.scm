;;; Audit: src/primitives_srfi181.zig (SRFI 181 — Custom ports, including
;;; transcoded ports) + the portable layer in lib/srfi/181.sld.
;;; Systematic audit v2, Phase 2.3 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: https://srfi.schemers.org/srfi-181/srfi-181.html, quoted inline
;;; beside the assertions each sentence justifies. Where SRFI 181 defers to
;;; another spec the quote comes from there instead (R7RS 6.13.1 for
;;; close-*-port; SRFI 192 for port-position).
;;;
;;; Covers all 10 specs in primitives_srfi181.zig — the five
;;; make-custom-*-port constructors, make-file-error, %transcoded-port, and
;;; the three i/o-*-error accessors — plus every name lib/srfi/181.sld adds
;;; on top (transcoder?, make-transcoder, native-transcoder,
;;; native-eol-style, utf-8-codec, make-codec, transcoded-port,
;;; bytevector->string, string->bytevector, unknown-encoding-error?,
;;; unknown-encoding-error-name).
;;;
;;; Deliberately complementary to tests/scheme/srfi/srfi181.scm (77
;;; assertions, all green) and src/tests_srfi181.zig. This file targets the
;;; audit dimensions those do not ask about: the read!/write! *argument*
;;; contract the spec imposes on the implementation (D4), callback
;;; misbehaviour and re-entrancy (D5), positioning × lookahead, cross-heap
;;; deep copy (D6), datum-level I/O, and the eol-style/error-mode matrix in
;;; both directions.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/audit/primitives_srfi181-audit.scm

(import (scheme base) (scheme write) (scheme process-context)
        (scheme eval) (scheme repl)
        (srfi 18) (srfi 64) (srfi 181) (srfi 192))

(test-begin "primitives_srfi181 audit")

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

;; #t iff the thunk raises anything catchable.
(define (raises? thunk)
  (call-with-current-continuation
    (lambda (k)
      (with-exception-handler (lambda (c) (k #t))
                              (lambda () (thunk) #f)))))

;; The raised message, or 'no-raise. Used instead of a bare raises? wherever
;; the message is the only thing distinguishing "rejected for the right
;; reason" from "rejected for some unrelated reason".
(define (message-of thunk)
  (call-with-current-continuation
    (lambda (k)
      (with-exception-handler
        (lambda (c) (k (if (error-object? c) (error-object-message c) c)))
        (lambda () (thunk) 'no-raise)))))

;; #t iff `needle` occurs in `hay`.
(define (has-substring? hay needle)
  (and (string? hay)
       (let ((h (string-length hay)) (n (string-length needle)))
         (and (>= h n)
              (let loop ((i 0))
                (cond ((> (+ i n) h) #f)
                      ((string=? (substring hay i (+ i n)) needle) #t)
                      (else (loop (+ i 1)))))))))

(define (raises-with? thunk needle)
  (has-substring? (message-of thunk) needle))

(define (bv->list bv)
  (let loop ((i (- (bytevector-length bv) 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons (bytevector-u8-ref bv i) acc)))))

;; A binary input port that serves `src` `chunk` bytes per read! call, with
;; get-position reporting how many bytes the SOURCE has handed over.
(define (byte-source src chunk)
  (let ((pos 0))
    (values
      (make-custom-binary-input-port "byte-source"
        (lambda (bv start count)
          (let loop ((i 0))
            (if (or (= i chunk) (= i count) (>= pos (bytevector-length src)))
                i
                (begin (bytevector-u8-set! bv (+ start i) (bytevector-u8-ref src pos))
                       (set! pos (+ pos 1))
                       (loop (+ i 1))))))
        (lambda () pos) #f #f)
      (lambda () pos))))

;; A textual input port serving `str` one character per read! call.
(define (char-source str)
  (let ((i 0))
    (make-custom-textual-input-port "char-source"
      (lambda (s start count)
        (if (>= i (string-length str))
            0
            (begin (string-set! s start (string-ref str i))
                   (set! i (+ i 1))
                   1)))
      #f #f #f)))

;; A binary output port collecting every byte handed to write! into a list.
(define (byte-sink)
  (let ((acc '()))
    (values
      (make-custom-binary-output-port "byte-sink"
        (lambda (bv start count)
          (do ((i 0 (+ i 1))) ((= i count))
            (set! acc (cons (bytevector-u8-ref bv (+ start i)) acc)))
          count)
        #f #f #f)
      (lambda () (reverse acc)))))

(define (decode-bytes byte-list eol mode)
  (let* ((bp (open-input-bytevector (apply bytevector byte-list)))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) eol mode))))
    (let loop ((acc '()))
      (let ((c (read-char tp)))
        (if (eof-object? c) (reverse acc) (loop (cons (char->integer c) acc)))))))

(define (encode-string s eol)
  (let* ((bp (open-output-bytevector))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) eol 'replace))))
    (write-string s tp)
    (bv->list (get-output-bytevector bp))))

;;; ==================================================================
;;; 1. Registration table vs. spec signatures  (dimension D4)
;;; ==================================================================
;;;
;;; "(make-custom-binary-input-port id read! get-position set-position!
;;;  close)" — 5 arguments, no flush; the two output constructors take
;;; "[flush]" as a 6th; the input/output constructor takes read! AND write!
;;; before them.

(test-assert "D4: all five constructors and make-file-error are procedures"
  (and (procedure? make-custom-binary-input-port)
       (procedure? make-custom-binary-output-port)
       (procedure? make-custom-textual-input-port)
       (procedure? make-custom-textual-output-port)
       (procedure? make-custom-binary-input/output-port)
       (procedure? make-file-error)))

(test-assert "D4: the three i/o-*-error accessors are procedures"
  (and (procedure? i/o-decoding-error?)
       (procedure? i/o-encoding-error?)
       (procedure? i/o-encoding-error-char)))

(test-assert "D4: the transcoder surface lib/srfi/181.sld adds is present"
  (and (procedure? transcoder?) (procedure? make-transcoder)
       (procedure? native-transcoder) (procedure? native-eol-style)
       (procedure? utf-8-codec) (procedure? make-codec)
       (procedure? transcoded-port)
       (procedure? bytevector->string) (procedure? string->bytevector)
       (procedure? unknown-encoding-error?)
       (procedure? unknown-encoding-error-name)))

;; The three export probes below use (environment '(srfi 181)), which only
;; discriminates if a name that IS exported resolves through it. (srfi 181)
;; is already imported by this file, so the probe never triggers a first
;; file-backed .sld load — see #2012 for why that would matter.
(test-assert "D4 control: an exported name DOES resolve through (environment '(srfi 181))"
  (and (procedure? (eval 'utf-8-codec (environment '(srfi 181))))
       (procedure? (eval 'make-custom-textual-output-port (environment '(srfi 181))))))

;; "Note: R6RS provides custom textual input/output ports ... they have been
;; removed from this SRFI." Nothing should define one.
(test-assert "D4: make-custom-textual-input/output-port is absent, per the SRFI's own Note"
  (raises? (lambda () (eval 'make-custom-textual-input/output-port
                            (environment '(scheme base) '(srfi 181))))))

;; latin-1-codec/utf-16-codec are spec procedures this build deliberately
;; does not export (CONFORMANCE.md § SRFI 181: UTF-8-only v1). Pinned so a
;; later codec expansion has to touch this file.
(test-assert "D4: latin-1-codec is not exported (documented UTF-8-only scope)"
  (raises? (lambda () (eval 'latin-1-codec (environment '(srfi 181))))))
(test-assert "D4: utf-16-codec is not exported (documented UTF-8-only scope)"
  (raises? (lambda () (eval 'utf-16-codec (environment '(srfi 181))))))
(test-assert "D4: make-codec rejects \"latin-1\" rather than half-supporting it"
  (guard (e ((unknown-encoding-error? e) #t)) (make-codec "latin-1") #f))
(test-assert "D4: make-codec rejects \"utf-16\" rather than half-supporting it"
  (guard (e ((unknown-encoding-error? e) #t)) (make-codec "utf-16") #f))

;; Arity: exact 5 for the input constructors, at most 6 / 7 for the rest.
(test-assert "arity: binary input constructor rejects a 6th argument"
  (raises-with? (lambda () (make-custom-binary-input-port "x" (lambda (a b c) 0) #f #f #f 'extra))
                "expected 5 arguments"))
(test-assert "arity: textual input constructor rejects a 6th argument"
  (raises-with? (lambda () (make-custom-textual-input-port "x" (lambda (a b c) 0) #f #f #f 'extra))
                "expected 5 arguments"))
(test-assert "arity: binary output constructor rejects a 7th argument"
  (raises-with? (lambda () (make-custom-binary-output-port "x" (lambda (a b c) 0) #f #f #f #f 'x))
                "at most 6 arguments"))
(test-assert "arity: textual output constructor rejects a 7th argument"
  (raises-with? (lambda () (make-custom-textual-output-port "x" (lambda (a b c) 0) #f #f #f #f 'x))
                "at most 6 arguments"))
(test-assert "arity: binary input/output constructor rejects an 8th argument"
  (raises-with? (lambda () (make-custom-binary-input/output-port
                             "x" (lambda (a b c) 0) (lambda (a b c) 0) #f #f #f #f 'x))
                "at most 7 arguments"))
(test-assert "arity: binary output constructor accepts the optional flush (6 arguments)"
  (port? (make-custom-binary-output-port "x" (lambda (a b c) 0) #f #f #f (lambda () #t))))
(test-assert "arity: textual output constructor accepts the optional flush (6 arguments)"
  (port? (make-custom-textual-output-port "x" (lambda (a b c) 0) #f #f #f (lambda () #t))))
(test-assert "arity: input/output constructor accepts the optional flush (7 arguments)"
  (port? (make-custom-binary-input/output-port "x" (lambda (a b c) 0) (lambda (a b c) 0)
                                               #f #f #f (lambda () #t))))
(test-assert "arity: constructors reject too few arguments"
  (raises? (lambda () (make-custom-binary-input-port "x" (lambda (a b c) 0) #f #f))))

;; "The id is an arbitrary object." No accessor exists, so the only
;; observable contract is that every object is accepted.
(test-assert "spec: id is an arbitrary object — string, fixnum, #f, list, vector, procedure all accepted"
  (let ((r (lambda (id) (port? (make-custom-binary-input-port id (lambda (a b c) 0) #f #f #f)))))
    (and (r "s") (r 42) (r #f) (r '(1 2)) (r (vector 1)) (r car) (r (if #f #f)))))

;; "The read! and write! arguments are procedures" — mandatory, no #f.
(test-assert "spec: read! must be a procedure, not #f"
  (raises-with? (lambda () (make-custom-binary-input-port "x" #f #f #f #f))
                "expected procedure"))
(test-assert "spec: write! must be a procedure, not #f"
  (raises-with? (lambda () (make-custom-binary-output-port "x" #f #f #f #f))
                "expected procedure"))
(test-assert "spec: input/output constructor requires BOTH read! and write!"
  (and (raises? (lambda () (make-custom-binary-input/output-port "x" #f (lambda (a b c) 0) #f #f #f)))
       (raises? (lambda () (make-custom-binary-input/output-port "x" (lambda (a b c) 0) #f #f #f #f)))))
(test-assert "spec: a non-procedure non-#f read! is a type error naming the constructor"
  (raises-with? (lambda () (make-custom-binary-input-port "x" 5 #f #f #f))
                "make-custom-binary-input-port"))

;; "The get-position and set-position! arguments may be procedures or #f";
;; "The close argument may be a procedure ... or #f"; likewise flush.
(test-assert "spec: get-position/set-position!/close/flush accept #f"
  (port? (make-custom-binary-output-port "x" (lambda (a b c) 0) #f #f #f #f)))
(test-assert "spec: get-position rejects a non-procedure non-#f"
  (raises-with? (lambda () (make-custom-binary-input-port "x" (lambda (a b c) 0) 5 #f #f))
                "procedure or #f"))
(test-assert "spec: set-position! rejects a non-procedure non-#f"
  (raises-with? (lambda () (make-custom-binary-input-port "x" (lambda (a b c) 0) #f "s" #f))
                "procedure or #f"))
(test-assert "spec: close rejects a non-procedure non-#f"
  (raises-with? (lambda () (make-custom-binary-input-port "x" (lambda (a b c) 0) #f #f 'sym))
                "procedure or #f"))
(test-assert "spec: flush rejects a non-procedure non-#f"
  (raises-with? (lambda () (make-custom-binary-output-port "x" (lambda (a b c) 0) #f #f #f 7))
                "procedure or #f"))

;;; ==================================================================
;;; 2. The read!/write! argument contract the SRFI imposes on US
;;; ==================================================================
;;;
;;; These are obligations on the implementation, not on the callback, and
;;; nothing else in the tree checks them.
;;;
;;; "It is an error if the following conditions on the arguments are not
;;;  met: start is a non-negative exact integer, count is a positive exact
;;;  integer, and bytevector is a bytevector whose length is at least
;;;  start + count."

(define binary-read-args '())
(let ((p (make-custom-binary-input-port "contract"
           (lambda (bv start count)
             (set! binary-read-args
                   (cons (list (bytevector? bv) (bytevector-length bv) start count)
                         binary-read-args))
             (bytevector-u8-set! bv start 65)
             1)
           #f #f #f)))
  (read-u8 p)
  (if #f #f))
(define bra (car binary-read-args))

(test-assert "binary read!: first argument is a bytevector" (list-ref bra 0))
(test-assert "binary read!: start is a non-negative exact integer"
  (and (exact-integer? (list-ref bra 2)) (>= (list-ref bra 2) 0)))
(test-assert "binary read!: count is a POSITIVE exact integer"
  (and (exact-integer? (list-ref bra 3)) (> (list-ref bra 3) 0)))
(test-assert "binary read!: bytevector length is at least start + count"
  (>= (list-ref bra 1) (+ (list-ref bra 2) (list-ref bra 3))))

;;; "string-or-char-vector is either a string or a vector containing
;;;  characters, at the implementations's option. In either case its length
;;;  is at least start + count."
;;; Kaappi's option is `string` (the Implementation section notes R6RS
;;; implementations "will never be passed a vector of characters, but always
;;; a string"), and its counts are in CHARACTERS, not bytes.

(define textual-read-args '())
(let ((p (make-custom-textual-input-port "contract"
           (lambda (s start count)
             (set! textual-read-args
                   (cons (list (string? s) (vector? s) (string-length s) start count)
                         textual-read-args))
             (string-set! s start #\x)
             1)
           #f #f #f)))
  (read-char p)
  (if #f #f))
(define tra (car textual-read-args))

(test-assert "textual read!: buffer is a string (this implementation's option)"
  (and (list-ref tra 0) (not (list-ref tra 1))))
(test-assert "textual read!: start is a non-negative exact integer"
  (and (exact-integer? (list-ref tra 3)) (>= (list-ref tra 3) 0)))
(test-assert "textual read!: count is a POSITIVE exact integer"
  (and (exact-integer? (list-ref tra 4)) (> (list-ref tra 4) 0)))
(test-assert "textual read!: string LENGTH (in characters) is at least start + count"
  (>= (list-ref tra 2) (+ (list-ref tra 3) (list-ref tra 4))))

;;; write!: "start and count are non-negative exact integers, and
;;;  bytevector is a bytevector whose length is at least start + count."

(define binary-write-args '())
(let ((p (make-custom-binary-output-port "contract"
           (lambda (bv start count)
             (set! binary-write-args
                   (cons (list (bytevector? bv) (bytevector-length bv) start count)
                         binary-write-args))
             count)
           #f #f #f)))
  (write-bytevector (bytevector 1 2 3) p))
(define bwa (car binary-write-args))

(test-assert "binary write!: first argument is a bytevector" (list-ref bwa 0))
(test-assert "binary write!: start and count are non-negative exact integers"
  (and (exact-integer? (list-ref bwa 2)) (>= (list-ref bwa 2) 0)
       (exact-integer? (list-ref bwa 3)) (>= (list-ref bwa 3) 0)))
(test-assert "binary write!: bytevector length is at least start + count"
  (>= (list-ref bwa 1) (+ (list-ref bwa 2) (list-ref bwa 3))))
(test-equal "binary write!: count is the number of bytes offered" 3 (list-ref bwa 3))

(define textual-write-args '())
(let ((p (make-custom-textual-output-port "contract"
           (lambda (s start count)
             (set! textual-write-args
                   (cons (list (string? s) (string-length s) start count) textual-write-args))
             count)
           #f #f #f)))
  (write-string "h\x00e9;llo" p))          ; 5 characters, 6 UTF-8 bytes
(define twa (car textual-write-args))

(test-assert "textual write!: buffer is a string" (list-ref twa 0))
(test-equal "textual write!: count is in CHARACTERS, not bytes (5, not 6)" 5 (list-ref twa 3))
(test-assert "textual write!: string length is at least start + count"
  (>= (list-ref twa 1) (+ (list-ref twa 2) (list-ref twa 3))))

;; A write! that accepts one character at a time must be re-offered the
;; remainder with a correctly advanced start, in characters.
(define partial-write-log '())
(let ((p (make-custom-textual-output-port "partial"
           (lambda (s start count)
             (set! partial-write-log
                   (cons (list start count (string-ref s start)) partial-write-log))
             1)
           #f #f #f)))
  (write-string "a\x03a9;b" p))            ; a, GREEK CAPITAL OMEGA, b
(test-equal "textual write!: a one-character-at-a-time sink sees each character exactly once, in order"
  '((0 3 #\a) (1 2 #\x03a9) (2 1 #\b))
  (reverse partial-write-log))

(test-equal "write-string with start/end offers only the requested substring"
  '("cde")
  (let ((acc '()))
    (let ((p (make-custom-textual-output-port "range"
               (lambda (s st c) (set! acc (cons (substring s st (+ st c)) acc)) c)
               #f #f #f)))
      (write-string "abcdef" p 2 5))
    (reverse acc)))

;;; ==================================================================
;;; 3. EOF, and callbacks that misbehave
;;; ==================================================================
;;;
;;; "To indicate an end of file, the read! procedure writes no bytes to its
;;;  bytevector and returns 0."

(test-assert "EOF: read! returning 0 immediately yields an eof object"
  (eof-object? (read-u8 (make-custom-binary-input-port "e" (lambda (b s c) 0) #f #f #f))))
(test-assert "EOF: a textual read! returning 0 yields an eof object"
  (eof-object? (read-char (make-custom-textual-input-port "e" (lambda (b s c) 0) #f #f #f))))
(test-assert "EOF: read! returning 0 is sticky across repeated reads"
  (let ((p (make-custom-binary-input-port "e" (lambda (b s c) 0) #f #f #f)))
    (and (eof-object? (read-u8 p)) (eof-object? (read-u8 p)) (eof-object? (read-u8 p)))))

;; The spec leaves misbehaving callbacks to the implementation; the only
;; requirement this file imposes is that every one stays CATCHABLE and names
;; the offending callback.
(define (bad-read-port ret) (make-custom-binary-input-port "bad" (lambda (b s c) ret) #f #f #f))

(test-assert "bad read!: a flonum count is rejected, catchably, naming read!"
  (raises-with? (lambda () (read-u8 (bad-read-port 1.5))) "read!"))
(test-assert "bad read!: an INTEGRAL flonum count is still rejected (exactness matters)"
  (raises-with? (lambda () (read-u8 (bad-read-port 1.0))) "read!"))
(test-assert "bad read!: a negative count is rejected"
  (raises-with? (lambda () (read-u8 (bad-read-port -1))) "read!"))
(test-assert "bad read!: a count beyond the offered buffer is rejected"
  (raises-with? (lambda () (read-u8 (bad-read-port 99999))) "read!"))
(test-assert "bad read!: a string count is rejected"
  (raises-with? (lambda () (read-u8 (bad-read-port "3"))) "read!"))
(test-assert "bad read!: a bignum count is rejected without overflow"
  (raises-with? (lambda () (read-u8 (bad-read-port (* 99999999999 99999999999)))) "read!"))
(test-assert "bad read!: zero values returned is rejected"
  (raises? (lambda () (read-u8 (make-custom-binary-input-port "bad" (lambda (b s c) (values)) #f #f #f)))))
(test-assert "bad read!: a wrong-arity read! raises, catchably"
  (raises? (lambda () (read-u8 (make-custom-binary-input-port "bad" (lambda (b) 1) #f #f #f)))))

(define (bad-write-port ret) (make-custom-binary-output-port "bad" (lambda (b s c) ret) #f #f #f))
(test-assert "bad write!: a non-integer return is rejected, naming write!"
  (raises-with? (lambda () (write-bytevector (bytevector 1 2 3) (bad-write-port 'x))) "write!"))
(test-assert "bad write!: a negative return is rejected"
  (raises-with? (lambda () (write-bytevector (bytevector 1 2 3) (bad-write-port -1))) "write!"))
(test-assert "bad write!: a return larger than count is rejected"
  (raises-with? (lambda () (write-bytevector (bytevector 1 2 3) (bad-write-port 99))) "write!"))
(test-assert "bad write!: zero progress on a non-empty write is rejected, not retried forever"
  (raises-with? (lambda () (write-bytevector (bytevector 1 2 3) (bad-write-port 0))) "write!"))

(test-assert "bad get-position: a non-integer result is rejected, naming get-position"
  (raises-with? (lambda () (port-position (make-custom-binary-input-port
                                            "g" (lambda (b s c) 0) (lambda () 'sym) #f #f)))
                "get-position"))

(test-assert "a read! that raises propagates the condition unchanged"
  (raises-with? (lambda () (read-u8 (make-custom-binary-input-port
                                      "r" (lambda (b s c) (error "boom-read")) #f #f #f)))
                "boom-read"))
(test-assert "a write! that raises propagates the condition unchanged"
  (raises-with? (lambda () (write-u8 1 (make-custom-binary-output-port
                                         "r" (lambda (b s c) (error "boom-write")) #f #f #f)))
                "boom-write"))
(test-assert "a close that raises propagates the condition unchanged"
  (raises-with? (lambda () (close-port (make-custom-binary-input-port
                                         "r" (lambda (b s c) 0) #f #f (lambda () (error "boom-close")))))
                "boom-close"))
(test-assert "a flush that raises propagates the condition unchanged"
  (raises-with? (lambda () (flush-output-port (make-custom-binary-output-port
                                                "r" (lambda (b s c) c) #f #f #f
                                                (lambda () (error "boom-flush")))))
                "boom-flush"))

;; A textual read! that widens a character mid-call reallocates the string's
;; backing buffer; the implementation must re-read data/len AFTER the call.
(test-equal "textual read!: a string-set! that widens a character mid-call is decoded correctly"
  #\x03a9
  (read-char (make-custom-textual-input-port "wide"
               (lambda (s start count) (string-set! s start #\x03a9) 1) #f #f #f)))
(test-equal "textual read!: a 4-byte astral character written by read! survives"
  #\x1f600
  (read-char (make-custom-textual-input-port "astral"
               (lambda (s start count) (string-set! s start #\x1f600) 1) #f #f #f)))
(test-equal "textual read!: a multi-character burst including a wide character is served in order"
  '(#\a #\x03a9 #\b)
  (let ((done #f))
    (let ((p (make-custom-textual-input-port "burst"
               (lambda (s start count)
                 (if done 0
                     (begin (set! done #t)
                            (string-set! s start #\a)
                            (string-set! s (+ start 1) #\x03a9)
                            (string-set! s (+ start 2) #\b)
                            3)))
               #f #f #f)))
      (list (read-char p) (read-char p) (read-char p)))))

;;; ==================================================================
;;; 4. Blocking rejection at all six callback sites  (dimension D5)
;;; ==================================================================
;;;
;;; Not a spec requirement — an engine invariant documented in
;;; src/primitives_srfi181.zig's header: every callback runs with
;;; dispatched_from_scheduler forced false, so a callback that tries to
;;; block is rejected with a CATCHABLE error rather than driving the
;;; scheduler recursively. `callCustomPortProc`'s own doc comment claims all
;;; six sites go through it; these six assertions are what pins that.

(define (blocks!) (thread-sleep! 0.01))
(define blocked-msg "custom port callback blocked")

(test-assert "D5: a blocking read! is rejected catchably"
  (raises-with? (lambda () (read-u8 (make-custom-binary-input-port
                                      "b" (lambda (b s c) (blocks!) 1) #f #f #f)))
                blocked-msg))
(test-assert "D5: a blocking write! is rejected catchably"
  (raises-with? (lambda () (write-u8 1 (make-custom-binary-output-port
                                         "b" (lambda (b s c) (blocks!) c) #f #f #f)))
                blocked-msg))
(test-assert "D5: a blocking get-position is rejected catchably"
  (raises-with? (lambda () (port-position (make-custom-binary-input-port
                                            "b" (lambda (b s c) 1) (lambda () (blocks!) 0) #f #f)))
                blocked-msg))
(test-assert "D5: a blocking set-position! is rejected catchably"
  (raises-with? (lambda () (set-port-position!
                             (make-custom-binary-input-port
                               "b" (lambda (b s c) 1) (lambda () 0) (lambda (p) (blocks!)) #f)
                             0))
                blocked-msg))
(test-assert "D5: a blocking close is rejected catchably"
  (raises-with? (lambda () (close-port (make-custom-binary-input-port
                                         "b" (lambda (b s c) 1) #f #f (lambda () (blocks!)))))
                blocked-msg))
(test-assert "D5: a blocking flush is rejected catchably"
  (raises-with? (lambda () (flush-output-port (make-custom-binary-output-port
                                                "b" (lambda (b s c) c) #f #f #f (lambda () (blocks!)))))
                blocked-msg))

;; The guard is about BLOCKING, not about doing work: a callback that runs
;; another thread to completion, or reads a regular file (never EAGAIN), is
;; not rejected. This is the discriminating control for the six above.
(test-equal "D5: a read! that joins a short-lived thread is NOT rejected"
  7
  (read-u8 (make-custom-binary-input-port "ok"
             (lambda (bv s c)
               (bytevector-u8-set! bv s (thread-join! (thread-start! (make-thread (lambda () 7)))))
               1)
             #f #f #f)))
(test-equal "D5: a read! doing ordinary allocation and arithmetic is NOT rejected"
  42
  (read-u8 (make-custom-binary-input-port "ok"
             (lambda (bv s c)
               (bytevector-u8-set! bv s (length (list 1 2 3 4 5 6 7 8 9 10 11 12
                                                     13 14 15 16 17 18 19 20 21 22
                                                     23 24 25 26 27 28 29 30 31 32
                                                     33 34 35 36 37 38 39 40 41 42)))
               1)
             #f #f #f)))

;;; ==================================================================
;;; 5. Re-entrancy  (dimension D5, second half)
;;; ==================================================================
;;;
;;; #1939 covered the one shape that ABORTED the process: a read! that
;;; re-enters a read on its OWN port while returning >= 2 elements tripped
;;; std.debug.assert(port.read_buf == null). The inner re-entry runs a whole
;;; EARLIER read! to completion, so the bytes it leaves buffered are
;;; chronologically ahead of the ones the outer invocation then produces —
;;; the single read_buf slot had both, and asserted instead. At exactly one
;;; outer byte the assert did not fire and the stream was silently reordered
;;; instead. An outer return of 0 (EOF) had the same class of bug: it
;;; reported EOF while the inner leftover still sat in read_buf. All three
;;; sizes are pinned below.
;;;
;;; Also pinned here: every neighbouring re-entrant shape completes cleanly.

(test-equal "re-entrant read!: an inner read on the same port preserves stream order"
  '(1 2 3 4 5 6 7)
  (let ((self #f) (depth 0) (next 1) (got '()))
    (set! self (make-custom-binary-input-port "reent"
      (lambda (bv start count)
        (set! depth (+ depth 1))
        ;; Only the outermost invocation re-enters, so the nesting is
        ;; exactly two deep and every burst is a clean pair.
        (when (= depth 1) (set! got (cons (read-u8 self) got)))
        (set! depth (- depth 1))
        (bytevector-u8-set! bv start next)
        (bytevector-u8-set! bv (+ start 1) (+ next 1))
        (set! next (+ next 2))
        2)
      #f #f #f))
    ;; 5 outer reads + the 2 inner ones they trigger = the first 7 bytes,
    ;; in the order read! produced them.
    (do ((i 0 (+ i 1))) ((= i 5)) (set! got (cons (read-u8 self) got)))
    (reverse got)))

(test-equal "re-entrant read!: a one-element outer burst does not overtake the inner burst"
  '(65 66 90)
  (let ((self #f) (depth 0) (got '()))
    (set! self (make-custom-binary-input-port "reent1"
      (lambda (bv start count)
        (set! depth (+ depth 1))
        (cond ((= depth 1)
               (set! got (cons (read-u8 self) got))
               (set! depth (- depth 1))
               (bytevector-u8-set! bv start 90)   ; outer: Z, one byte
               1)
              (else
               (set! depth (- depth 1))
               (bytevector-u8-set! bv start 65)   ; inner: A B
               (bytevector-u8-set! bv (+ start 1) 66)
               2)))
      #f #f #f))
    (set! got (cons (read-u8 self) got))
    (set! got (cons (read-u8 self) got))
    (reverse got)))

;; Same nesting as the one-byte reorder case, but the outer callback
;; returns 0 (EOF). The inner fill left a leftover in read_buf; serving
;; EOF before that leftover would report a spurious EOF while the next
;; read still yields the buffered byte.
(test-equal "re-entrant read!: outer EOF still serves inner leftover before eof-object"
  66
  (let ((self #f) (depth 0))
    (set! self (make-custom-binary-input-port "eof-reent"
      (lambda (bv start count)
        (set! depth (+ depth 1))
        (cond ((= depth 1)
               (read-u8 self) ; inner fill leaves a leftover in read_buf
               (set! depth (- depth 1))
               0)            ; outer reports EOF
              (else
               (set! depth (- depth 1))
               (bytevector-u8-set! bv start 65)
               (bytevector-u8-set! bv (+ start 1) 66)
               2)))
      #f #f #f))
    (read-u8 self)))

(test-equal "re-entrant read!: a textual inner read on the same port preserves stream order"
  '(#\a #\b #\c)
  (let ((self #f) (depth 0) (got '()))
    (set! self (make-custom-textual-input-port "reent-t"
      (lambda (str start count)
        (set! depth (+ depth 1))
        (cond ((= depth 1)
               (set! got (cons (read-char self) got))
               (set! depth (- depth 1))
               (string-set! str start #\c)
               1)
              (else
               (set! depth (- depth 1))
               (string-set! str start #\a)
               (string-set! str (+ start 1) #\b)
               2)))
      #f #f #f))
    (set! got (cons (read-char self) got))
    (set! got (cons (read-char self) got))
    (reverse got)))

(test-equal "re-entrant write!: an inner write on the same port completes, inner data first"
  '(99 1)
  (let ((self #f) (depth 0) (out '()))
    (set! self (make-custom-binary-output-port "reent"
                 (lambda (bv start count)
                   (set! depth (+ depth 1))
                   (when (= depth 1) (write-u8 99 self))
                   (set! depth (- depth 1))
                   (set! out (cons (bytevector-u8-ref bv start) out))
                   count)
                 #f #f #f))
    (write-bytevector (bytevector 1 2 3) self)
    (reverse out)))

(test-equal "re-entrant flush: a flush callback writing to its own port completes"
  '(5 77)
  (let ((self #f) (depth 0) (out '()))
    (set! self (make-custom-binary-output-port "reent"
                 (lambda (bv s c) (set! out (cons (bytevector-u8-ref bv s) out)) c)
                 #f #f #f
                 (lambda ()
                   (set! depth (+ depth 1))
                   (when (= depth 1) (write-u8 77 self))
                   (set! depth (- depth 1)))))
    (write-u8 5 self)
    (flush-output-port self)
    (reverse out)))

(test-assert "re-entrant get-position: an inner read on the same port completes without aborting"
  (let ((self #f) (depth 0))
    (set! self (make-custom-binary-input-port "reent"
                 (lambda (bv s c) (bytevector-u8-set! bv s 65) 1)
                 (lambda () (set! depth (+ depth 1))
                            (if (= depth 1) (read-u8 self))
                            (set! depth (- depth 1))
                            0)
                 #f #f))
    (exact-integer? (port-position self))))

(test-assert "a read! that closes its own port mid-read still delivers the byte it produced"
  (let ((self #f))
    (set! self (make-custom-binary-input-port "selfclose"
                 (lambda (bv s c) (close-port self) (bytevector-u8-set! bv s 65) 1)
                 #f #f (lambda () #t)))
    (and (= 65 (read-u8 self)) (not (input-port-open? self)))))

;;; ==================================================================
;;; 6. Positioning: SRFI 192 over a custom port
;;; ==================================================================

(test-assert "port-has-port-position? is true exactly when get-position is a procedure"
  (and (port-has-port-position?
         (make-custom-binary-input-port "p" (lambda (b s c) 0) (lambda () 0) #f #f))
       (not (port-has-port-position?
              (make-custom-binary-input-port "p" (lambda (b s c) 0) #f (lambda (x) x) #f)))))

(test-assert "port-position without get-position is an error, per the spec's #f contract"
  (raises-with? (lambda () (port-position
                             (make-custom-binary-input-port "p" (lambda (b s c) 0) #f #f #f)))
                "does not support positioning"))
(test-assert "set-port-position! without set-position! is an error, per the spec's #f contract"
  (raises-with? (lambda () (set-port-position!
                             (make-custom-binary-input-port "p" (lambda (b s c) 0) (lambda () 0) #f #f)
                             0))
                "does not support positioning"))
(test-assert "set-port-position! rejects a negative position"
  (raises? (lambda () (set-port-position!
                        (make-custom-binary-input-port "p" (lambda (b s c) 0) (lambda () 0)
                                                       (lambda (x) x) #f)
                        -1))))

(test-equal "set-position! receives the requested position verbatim"
  '(7)
  (let ((seen '()))
    (set-port-position!
      (make-custom-binary-input-port "p" (lambda (b s c) 0) (lambda () 0)
                                     (lambda (x) (set! seen (cons x seen)) x) #f)
      7)
    seen))

(test-equal "set-port-position! on an output port flushes before repositioning"
  '(flush set 3)
  (let ((log '()))
    (let ((p (make-custom-binary-output-port "p"
               (lambda (b s c) c) (lambda () 0)
               (lambda (x) (set! log (cons 'set log)) (set! log (cons x log)) x)
               #f
               (lambda () (set! log (cons 'flush log))))))
      (set-port-position! p 3))
    (reverse log)))

(test-equal "an output custom port's port-position is its get-position result"
  '(3 1)
  (let ((n 0))
    (let ((p (make-custom-binary-output-port "p"
               (lambda (b s c) (set! n (+ n c)) c)
               (lambda () n) (lambda (x) (set! n x) x) #f)))
      (write-bytevector (bytevector 1 2 3) p)
      (let ((a (port-position p)))
        (set-port-position! p 1)
        (list a (port-position p))))))

;; A one-element-per-call read! leaves no lookahead, so the source position
;; and the port position coincide. This is the discriminating control for
;; the two disabled assertions below.
(test-equal "port-position is correct when read! hands over exactly one element per call"
  '(0 1 2 3)
  (call-with-values (lambda () (byte-source (bytevector 10 20 30 40 50 60) 1))
    (lambda (p src-pos)
      (let ((a (port-position p)))
        (read-u8 p)
        (let ((b (port-position p)))
          (read-u8 p)
          (let ((c (port-position p)))
            (read-u8 p)
            (list a b c (port-position p))))))))

;; #1996 (fixed): port-position subtracts the unconsumed remainder of a burst
;; read! (port.read_buf) instead of returning the raw get-position result.
(test-equal "port-position subtracts the unconsumed remainder of a burst read!"
  '(1 2 3)
  (call-with-values (lambda () (byte-source (bytevector 10 20 30 40 50 60) 3))
    (lambda (p src-pos)
      (read-u8 p)
      (let ((a (port-position p)))
        (read-u8 p)
        (let ((b (port-position p)))
          (read-u8 p)
          (list a b (port-position p)))))))

;; SRFI 181 § Port positioning and peeking: "But if port-position is called
;; before the peeked character is read, the port must return its cached
;; position rather than calling the get-position procedure."
;; #1996 (fixed): the peeked byte is unconsumed lookahead, so port-position
;; subtracts it rather than reporting the post-peek source position.
(test-equal "port-position after a peek returns the cached pre-peek position"
  '(0 1)
  (call-with-values (lambda () (byte-source (bytevector 10 20 30) 1))
    (lambda (p src-pos)
      (peek-u8 p)
      (let ((a (port-position p)))
        (read-u8 p)
        (list a (port-position p))))))

;; #1942 (fixed): the setter predicate is its own function inspecting
;; set_position_proc, no longer an alias of the getter predicate.
(test-assert "port-has-set-port-position!? tracks set-position!, not get-position"
  (and (port-has-set-port-position!?
         (make-custom-binary-input-port "p" (lambda (b s c) 0) #f (lambda (x) x) #f))
       (not (port-has-set-port-position!?
              (make-custom-binary-input-port "p" (lambda (b s c) 0) (lambda () 0) #f #f)))))

;;; ==================================================================
;;; 7. Datum-level I/O over custom and transcoded ports
;;; ==================================================================

(test-equal "write on a custom textual output port emits the full external representation"
  "(1 \"two\" #\\3) (4 5)"
  (let ((acc (open-output-string)))
    (let ((p (make-custom-textual-output-port "w"
               (lambda (s st c) (write-string (substring s st (+ st c)) acc) c) #f #f #f)))
      (write '(1 "two" #\3) p)
      (display " " p)
      (display '(4 5) p))
    (get-output-string acc)))

(test-equal "read-char/read-line/read-string/peek-char all work on a custom textual port"
  '(#\( "(1 2 3)" #\a "bc")
  (list (read-char (char-source "(1 2 3)"))
        (read-line (char-source "(1 2 3)\nrest"))
        (peek-char (char-source "abc"))
        (read-string 2 (char-source "bc"))))

;; #1995 (fixed): readDatumFn refills through readOneByte on custom and
;; transcoded ports (which have no fd), so `read` drives the read! callback
;; / transcoder decode like every other input primitive.
(test-equal "read parses a datum from a custom TEXTUAL port"
  '(1 2 3) (read (char-source "(1 2 3)")))
(test-equal "read parses a datum from a custom BINARY port"
  '(1 2 3)
  (call-with-values (lambda () (byte-source (string->utf8 "(1 2 3)") 1))
    (lambda (p src-pos) (read p))))
(test-equal "read parses a datum from a TRANSCODED port"
  '(1 2 3)
  (read (transcoded-port (open-input-bytevector (string->utf8 "(1 2 3)")) (native-transcoder))))
(test-equal "read after a peek-char on a custom port does not raise a spurious read error"
  '(1 2 3)
  (let ((p (char-source "(1 2 3)"))) (peek-char p) (read p)))

;; The control that makes #1995 a port-kind bug rather than a reader bug:
;; the identical datum reads correctly from a string port and a file port.
(test-equal "control for #1995: read works on a string port with the same datum"
  '(1 2 3) (read (open-input-string "(1 2 3)")))

;;; ==================================================================
;;; 8. Transcoders, codecs, eol-styles, error modes
;;; ==================================================================

(test-assert "make-transcoder builds a transcoder?" (transcoder? (make-transcoder (utf-8-codec) 'none 'replace)))
(test-assert "native-transcoder builds a transcoder?" (transcoder? (native-transcoder)))
(test-assert "transcoder? is false for non-transcoders"
  (not (or (transcoder? 5) (transcoder? "t") (transcoder? '(1 2)) (transcoder? (vector 1))
           (transcoder? (utf-8-codec)) (transcoder? (make-file-error "x")))))

;; "make-transcoder ... Returns a transcoder with the behavior specified by
;; its arguments." Nothing requires eager validation, and this build defers
;; it to first use in transcoded-port.
(test-assert "make-transcoder does not validate eagerly (deferred to transcoded-port)"
  (transcoder? (make-transcoder 'bogus-codec 'bogus-eol 'bogus-mode)))

;; "A call to any of these procedures returns a value that is equal in the
;; sense of eqv? to the result of any other call to the same procedure."
(test-assert "utf-8-codec: eqv? across calls, as the spec requires"
  (eqv? (utf-8-codec) (utf-8-codec)))
(test-assert "make-codec \"utf-8\" is eqv? to (utf-8-codec)"
  (eqv? (make-codec "utf-8") (utf-8-codec)))
(test-assert "make-codec matches case-insensitively, per the spec"
  (and (eqv? (make-codec "UTF-8") (utf-8-codec))
       (eqv? (make-codec "Utf-8") (utf-8-codec))
       (eqv? (make-codec "uTf-8") (utf-8-codec))))
(test-assert "make-codec accepts the alternate name \"utf8\""
  (and (eqv? (make-codec "utf8") (utf-8-codec))
       (eqv? (make-codec "UTF8") (utf-8-codec))))

;; "If make-codec is called on a string that the implementation does not
;; support, an error satisfying unknown-encoding-error? is signaled."
(test-assert "make-codec on an unsupported name signals unknown-encoding-error?"
  (guard (e ((unknown-encoding-error? e) #t)) (make-codec "shift-jis") #f))
(test-equal "unknown-encoding-error-name reports the rejected name verbatim"
  "shift-jis"
  (guard (e ((unknown-encoding-error? e) (unknown-encoding-error-name e))) (make-codec "shift-jis")))
(test-equal "unknown-encoding-error-name handles an empty name"
  ""
  (guard (e ((unknown-encoding-error? e) (unknown-encoding-error-name e))) (make-codec "")))
(test-assert "unknown-encoding-error-name result is a string"
  (string? (guard (e ((unknown-encoding-error? e) (unknown-encoding-error-name e)))
             (make-codec "no-such-codec"))))
;; "It is an error to mutate this string."
(test-assert "unknown-encoding-error-name result is immutable, per the spec"
  (raises? (lambda ()
             (string-set! (guard (e ((unknown-encoding-error? e) (unknown-encoding-error-name e)))
                            (make-codec "no-such-codec"))
                          0 #\X))))
(test-assert "unknown-encoding-error? is false for unrelated objects"
  (not (or (unknown-encoding-error? 5)
           (unknown-encoding-error? (make-file-error "x"))
           (unknown-encoding-error? (native-transcoder)))))
(test-assert "make-codec rejects a non-string name"
  (raises? (lambda () (make-codec 'utf-8))))

;; "(native-eol-style) Returns the default end-of-line style of the
;; underlying platform, typically lf on Unix and crlf on Windows."
;; Platform-decided — assert membership, never a specific symbol.
(test-assert "native-eol-style returns one of the three implemented styles"
  (memq (native-eol-style) '(none lf crlf)))
(test-assert "native-transcoder's components are all recognized by transcoded-port"
  (port? (transcoded-port (open-input-bytevector (bytevector 65)) (native-transcoder))))

;;; --- eol-style, decode direction ---
;;; "The end-of-line style symbol none means that no line ending conversion
;;;  is performed in either direction. On an input port, any other symbol
;;;  will convert any line ending into a #\newline character."
;;; 97=a 98=b 13=CR 10=LF

(test-equal "eol none: a lone CR is not converted on input" '(97 13 98) (decode-bytes '(97 13 98) 'none 'replace))
(test-equal "eol none: a CRLF is not converted on input" '(97 13 10 98) (decode-bytes '(97 13 10 98) 'none 'replace))
(test-equal "eol crlf: a lone CR becomes newline on input" '(97 10 98) (decode-bytes '(97 13 98) 'crlf 'replace))
(test-equal "eol crlf: a CRLF becomes one newline on input" '(97 10 98) (decode-bytes '(97 13 10 98) 'crlf 'replace))
(test-equal "eol crlf: a lone LF stays one newline on input" '(97 10 98) (decode-bytes '(97 10 98) 'crlf 'replace))
;; The `lf` input direction was untested before this file, and is required
;; by the spec's "any other symbol" wording just as much as `crlf` is.
(test-equal "eol lf: a lone CR becomes newline on input" '(97 10 98) (decode-bytes '(97 13 98) 'lf 'replace))
(test-equal "eol lf: a CRLF becomes one newline on input" '(97 10 98) (decode-bytes '(97 13 10 98) 'lf 'replace))
(test-equal "eol lf: a lone LF stays one newline on input" '(97 10 98) (decode-bytes '(97 10 98) 'lf 'replace))
(test-equal "eol crlf: a trailing CR at EOF becomes newline" '(97 10) (decode-bytes '(97 13) 'crlf 'replace))
(test-equal "eol crlf: CR CR LF is two line endings" '(10 10) (decode-bytes '(13 13 10) 'crlf 'replace))

;;; --- eol-style, encode direction ---

(test-equal "eol none: newline passes through unchanged on output" '(97 10 98) (encode-string "a\nb" 'none))
(test-equal "eol lf: newline is written as LF" '(97 10 98) (encode-string "a\nb" 'lf))
(test-equal "eol crlf: newline is written as CRLF" '(97 13 10 98) (encode-string "a\nb" 'crlf))
(test-equal "eol none: a lone CR passes through unchanged on output" '(97 13 98) (encode-string "a\rb" 'none))

;; "On an output port, the symbol crlf causes any line ending to be output
;;  as a CRLF sequence, whereas the symbol lf causes any line ending to be
;;  output as a #\newline character" — and a lone #\return IS one of the
;;  three line endings the spec requires support for.
;; #1997 (fixed): the encode direction recognizes all three line endings —
;; bare LF, bare CR, and the CRLF pair — matching what its own decode
;; direction always did.
(test-equal "eol crlf: a lone CR is written as CRLF" '(97 13 10 98) (encode-string "a\rb" 'crlf))
(test-equal "eol lf: a lone CR is written as LF" '(97 10 98) (encode-string "a\rb" 'lf))
(test-equal "eol crlf: a CRLF in the string is written as ONE CRLF, not CR CR LF"
  '(97 13 10 98) (encode-string "a\r\nb" 'crlf))
(test-equal "eol lf: a CRLF in the string is written as one LF"
  '(97 10 98) (encode-string "a\r\nb" 'lf))
(test-equal "a crlf transcoder round-trips a CRLF without doubling the line break"
  "a\nb"
  (let ((t (make-transcoder (utf-8-codec) 'crlf 'replace)))
    (bytevector->string (string->bytevector "a\r\nb" t) t)))

;; The pin that documented the pre-fix behaviour (4 characters), flipped by
;; #1997's fix as intended.
(test-equal "a crlf round trip keeps one CRLF as one line break"
  3
  (let ((t (make-transcoder (utf-8-codec) 'crlf 'replace)))
    (string-length (bytevector->string (string->bytevector "a\r\nb" t) t))))

;; A CRLF split across two write-char calls is still ONE line ending: the
;; trailing CR is rendered eagerly and the opening LF of the next write is
;; recognized as the same pair's second half (TranscodeState.pending_cr).
(test-equal "eol crlf: a CRLF split across two write-char calls stays one CRLF"
  '(97 13 10 98)
  (let* ((bp (open-output-bytevector))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) 'crlf 'replace))))
    (write-char #\a tp) (write-char #\return tp) (write-char #\newline tp) (write-char #\b tp)
    (bv->list (get-output-bytevector bp))))
(test-equal "eol lf: a CRLF split across two write-char calls stays one LF"
  '(97 10 98)
  (let* ((bp (open-output-bytevector))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) 'lf 'replace))))
    (write-char #\a tp) (write-char #\return tp) (write-char #\newline tp) (write-char #\b tp)
    (bv->list (get-output-bytevector bp))))
(test-equal "eol crlf: two consecutive lone CRs across calls are two line endings"
  '(13 10 13 10)
  (let* ((bp (open-output-bytevector))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) 'crlf 'replace))))
    (write-char #\return tp) (write-char #\return tp)
    (bv->list (get-output-bytevector bp))))
(test-equal "eol crlf: a CR followed by a non-LF character was a lone line ending"
  '(13 10 98)
  (let* ((bp (open-output-bytevector))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) 'crlf 'replace))))
    (write-char #\return tp) (write-char #\b tp)
    (bv->list (get-output-bytevector bp))))

;; A newline-only round trip is unaffected, which localises #1997 to CR.
(test-equal "control for #1997: a newline-only crlf round trip is lossless"
  "a\nb"
  (let ((t (make-transcoder (utf-8-codec) 'crlf 'replace)))
    (bytevector->string (string->bytevector "a\nb" t) t)))

;;; --- error-handling modes ---
;;; "if the error-handling mode is replace, the erroneous bytes are treated
;;;  as the character #\xFFFD;"

(test-equal "replace mode: a bad UTF-8 lead byte becomes U+FFFD" '(65 65533 66) (decode-bytes '(65 255 66) 'none 'replace))
(test-equal "replace mode: a truncated 2-byte sequence at EOF becomes U+FFFD" '(97 65533) (decode-bytes '(97 195) 'none 'replace))
(test-equal "replace mode: a truncated 3-byte sequence becomes U+FFFD" '(65533) (decode-bytes '(226 130) 'none 'replace))
(test-equal "replace mode: an overlong encoding of '/' becomes U+FFFD" '(65533) (decode-bytes '(192 175) 'none 'replace))
(test-equal "replace mode: a UTF-8-encoded surrogate becomes U+FFFD" '(65533) (decode-bytes '(237 160 128) 'none 'replace))
(test-equal "replace mode: a valid 4-byte astral sequence decodes, not replaced"
  '(128512) (decode-bytes '(240 159 152 128) 'none 'replace))

;;; "But if the error-handling mode is raise, an error satisfying
;;;  i/o-decoding-error? is signaled, an appropriate number of bytes are
;;;  ignored, and decoding continues with the following bytes."

(define raise-conditions '())
(define raise-chars
  (let* ((bp (open-input-bytevector (bytevector 65 255 66)))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) 'none 'raise))))
    (with-exception-handler
      (lambda (c) (set! raise-conditions (cons c raise-conditions)) #\?)
      (lambda () (list (read-char tp) (read-char tp) (eof-object? (read-char tp)))))))

(test-equal "raise mode: decoding continues with the following bytes after the condition"
  '(#\A #\B #t) raise-chars)
(test-equal "raise mode: the handler runs exactly once for one invalid byte"
  1 (length raise-conditions))
(test-assert "raise mode: the condition satisfies i/o-decoding-error?"
  (i/o-decoding-error? (car raise-conditions)))
(test-assert "raise mode: the condition does NOT satisfy i/o-encoding-error?"
  (not (i/o-encoding-error? (car raise-conditions))))
(test-assert "raise mode: the condition is a first-class error object"
  (error-object? (car raise-conditions)))
(test-assert "raise mode: a guard can escape from the decoding condition"
  (raises? (lambda () (bytevector->string (bytevector 65 255 66)
                                          (make-transcoder (utf-8-codec) 'none 'raise)))))
(test-assert "raise mode: a truncated sequence at EOF also signals"
  (raises? (lambda () (decode-bytes '(97 195) 'none 'raise))))

(test-assert "i/o-decoding-error? is false for unrelated objects"
  (not (or (i/o-decoding-error? 5) (i/o-decoding-error? "s")
           (i/o-decoding-error? (make-file-error "x"))
           (i/o-decoding-error? (native-transcoder)))))
;; i/o-encoding-error? is unreachable by construction: UTF-8 encodes every
;; character this implementation can represent (integer->char rejects the
;; surrogate range outright), so no output can be unencodable. Pinned as
;; always-#f rather than left untested.
(test-assert "i/o-encoding-error? is false for every object reachable today"
  (not (or (i/o-encoding-error? 5) (i/o-encoding-error? (make-file-error "x"))
           (i/o-encoding-error? (car raise-conditions)))))
(test-assert "the surrogate range is unrepresentable, so nothing can be unencodable in UTF-8"
  (raises? (lambda () (integer->char #xD800))))
(test-assert "i/o-encoding-error-char rejects a decoding condition"
  (raises-with? (lambda () (i/o-encoding-error-char (car raise-conditions)))
                "i/o-encoding-error"))
(test-assert "i/o-encoding-error-char rejects a non-condition"
  (raises-with? (lambda () (i/o-encoding-error-char 5)) "i/o-encoding-error"))

;;; --- transcoded-port validation and composition ---

(test-assert "transcoded-port rejects an unrecognized codec symbol"
  (raises-with? (lambda () (transcoded-port (open-input-bytevector (bytevector 65))
                                            (make-transcoder 'ebcdic 'none 'replace)))
                "codec must be the symbol utf-8"))
(test-assert "transcoded-port rejects an unrecognized eol-style symbol"
  (raises-with? (lambda () (transcoded-port (open-input-bytevector (bytevector 65))
                                            (make-transcoder (utf-8-codec) 'nel 'replace)))
                "eol-style must be one of"))
(test-assert "transcoded-port rejects an unrecognized error-handling-mode symbol"
  (raises-with? (lambda () (transcoded-port (open-input-bytevector (bytevector 65))
                                            (make-transcoder (utf-8-codec) 'none 'ignore)))
                "error-handling-mode must be one of"))
(test-assert "transcoded-port rejects a TEXTUAL port as its binary-port argument"
  (raises-with? (lambda () (transcoded-port (open-input-string "x") (native-transcoder)))
                "binary port"))
(test-assert "transcoded-port rejects an already-transcoded (textual) port"
  (raises? (lambda () (transcoded-port
                        (transcoded-port (open-input-bytevector (bytevector 65)) (native-transcoder))
                        (native-transcoder)))))
(test-assert "transcoded-port rejects a non-port first argument"
  (raises-with? (lambda () (transcoded-port 5 (native-transcoder))) "port"))
(test-assert "transcoded-port rejects a non-transcoder second argument"
  (raises? (lambda () (transcoded-port (open-input-bytevector (bytevector 65)) 'nope))))

;; "If binary-port is an input port, the new textual port will be an input
;;  port ... If binary-port is an output port, the new textual port will be
;;  an output port" — direction is inherited, never passed separately.
(test-assert "transcoded-port inherits input direction from the wrapped port"
  (let ((tp (transcoded-port (open-input-bytevector (bytevector 65)) (native-transcoder))))
    (and (input-port? tp) (not (output-port? tp)) (textual-port? tp) (not (binary-port? tp)))))
(test-assert "transcoded-port inherits output direction from the wrapped port"
  (let ((tp (transcoded-port (open-output-bytevector) (native-transcoder))))
    (and (output-port? tp) (not (input-port? tp)) (textual-port? tp))))
(test-assert "transcoded-port inherits BOTH directions from a bidirectional custom port"
  (let ((tp (transcoded-port (make-custom-binary-input/output-port
                               "io" (lambda (b s c) 0) (lambda (b s c) c) #f #f #f)
                             (native-transcoder))))
    (and (input-port? tp) (output-port? tp))))

(test-equal "transcoded-port over a CUSTOM binary port decodes across one-byte read! calls"
  '(#\h #\i #\x00e9 #t)
  (call-with-values (lambda () (byte-source (string->utf8 "hi\x00e9;") 1))
    (lambda (cp src-pos)
      (let ((tp (transcoded-port cp (native-transcoder))))
        (list (read-char tp) (read-char tp) (read-char tp) (eof-object? (read-char tp)))))))

(test-equal "transcoded-port over a CUSTOM binary output port encodes to UTF-8"
  '(104 195 169)
  (let ((out '()))
    (let* ((cop (make-custom-binary-output-port "o"
                  (lambda (bv s c)
                    (do ((i 0 (+ i 1))) ((= i c))
                      (set! out (cons (bytevector-u8-ref bv (+ s i)) out)))
                    c)
                  #f #f #f))
           (top (transcoded-port cop (native-transcoder))))
      (write-string "h\x00e9;" top)
      (close-port top))
    (reverse out)))

(test-assert "transcoded-port: port-position is unsupported (documented reduced scope)"
  (and (not (port-has-port-position?
              (transcoded-port (open-input-bytevector (bytevector 65)) (native-transcoder))))
       (raises? (lambda () (port-position (transcoded-port (open-input-bytevector (bytevector 65))
                                                           (native-transcoder)))))))

(test-assert "closing a transcoded port also closes the port it wraps"
  (let* ((bp (open-input-bytevector (bytevector 65)))
         (tp (transcoded-port bp (native-transcoder))))
    (close-port tp)
    (and (not (input-port-open? tp)) (not (input-port-open? bp)))))
(test-assert "closing the wrapped port underneath a transcoded port makes reads raise cleanly"
  (let* ((bp (open-input-bytevector (bytevector 65 66)))
         (tp (transcoded-port bp (native-transcoder))))
    (close-port bp)
    (raises? (lambda () (read-char tp)))))

;; #1943 (fixed): flush-output-port on a transcoded port cascades to the
;; wrapped port, where every pending byte lives.
(test-equal "flush-output-port on a transcoded port reaches the wrapped port's flush"
  '(w f)
  (let ((out '()))
    (let* ((cop (make-custom-binary-output-port "o"
                  (lambda (bv s c) (set! out (cons 'w out)) c) #f #f #f
                  (lambda () (set! out (cons 'f out)))))
           (top (transcoded-port cop (native-transcoder))))
      (write-string "x" top)
      (flush-output-port top))
    (reverse out)))

;;; --- bytevector->string / string->bytevector ---

(test-equal "bytevector->string decodes UTF-8" "caf\x00e9;"
  (bytevector->string (bytevector 99 97 102 195 169) (native-transcoder)))
(test-equal "string->bytevector encodes UTF-8" '(99 97 102 195 169)
  (bv->list (string->bytevector "caf\x00e9;" (native-transcoder))))
(test-equal "bytevector->string of an empty bytevector is the empty string" ""
  (bytevector->string (bytevector) (native-transcoder)))
(test-equal "string->bytevector of the empty string is an empty bytevector" 0
  (bytevector-length (string->bytevector "" (native-transcoder))))
(test-equal "bytevector->string / string->bytevector round trip preserves astral characters"
  "a\x1f600;b"
  (bytevector->string (string->bytevector "a\x1f600;b" (native-transcoder)) (native-transcoder)))
(test-assert "bytevector->string rejects a non-bytevector" (raises? (lambda () (bytevector->string "s" (native-transcoder)))))
(test-assert "string->bytevector rejects a non-string" (raises? (lambda () (string->bytevector (bytevector 1) (native-transcoder)))))
(test-equal "bytevector->string honours the transcoder's replace mode"
  '(65 65533 66)
  (map char->integer (string->list (bytevector->string (bytevector 65 255 66)
                                                       (make-transcoder (utf-8-codec) 'none 'replace)))))

;;; ==================================================================
;;; 9. make-file-error
;;; ==================================================================
;;;
;;; "Returns an object which satisfies the R7RS-small predicate file-error?.
;;;  The use of the objs is implementation-defined."

(test-assert "make-file-error with no arguments satisfies file-error?" (file-error? (make-file-error)))
(test-assert "make-file-error with a message satisfies file-error?" (file-error? (make-file-error "boom")))
(test-assert "make-file-error results are error objects" (error-object? (make-file-error "boom" 1 2)))
(test-assert "make-file-error does NOT satisfy read-error?" (not (read-error? (make-file-error "boom"))))
(test-assert "make-file-error does NOT satisfy i/o-decoding-error?" (not (i/o-decoding-error? (make-file-error "boom"))))
(test-equal "make-file-error: the first object is the message" "boom" (error-object-message (make-file-error "boom" 1 2)))
(test-equal "make-file-error: remaining objects are the irritants" '(1 2) (error-object-irritants (make-file-error "boom" 1 2)))
(test-equal "make-file-error with no arguments has no irritants" '() (error-object-irritants (make-file-error)))
(test-assert "make-file-error accepts non-string objects in every position"
  (file-error? (make-file-error 'sym (vector 1) '(a . b))))
(test-assert "make-file-error results are catchable by guard as file errors"
  (guard (e ((file-error? e) #t)) (raise (make-file-error "boom")) #f))

;;; ==================================================================
;;; 10. Cross-heap deep copy  (dimension D6)
;;; ==================================================================
;;;
;;; docs/dev/thread-value-sharing.md lists port among the tags
;;; gc_deep_copy refuses. A custom port additionally carries Scheme
;;; callbacks and a transcoded port carries a wrapped port, so the refusal
;;; must hold at BOTH SRFI-18 boundaries and must be clean, not a crash.

(define (custom-port-for-copy)
  (make-custom-binary-input-port "copy" (lambda (bv s c) (bytevector-u8-set! bv s 65) 1) #f #f #f))
(define (transcoded-port-for-copy)
  (transcoded-port (open-input-bytevector (bytevector 104 105)) (native-transcoder)))

(test-assert "D6: a custom port captured by a thread thunk is refused at the START boundary"
  (let ((p (custom-port-for-copy)))
    (raises? (lambda () (thread-join! (thread-start! (make-thread (lambda () (port? p)))))))))
(test-assert "D6: a transcoded port captured by a thread thunk is refused at the START boundary"
  (let ((p (transcoded-port-for-copy)))
    (raises? (lambda () (thread-join! (thread-start! (make-thread (lambda () (port? p)))))))))
(test-assert "D6: a custom port returned from a thread is refused at the JOIN boundary"
  (raises-with? (lambda () (thread-join! (thread-start! (make-thread custom-port-for-copy))))
                "uncopyable"))
(test-assert "D6: a transcoded port returned from a thread is refused at the JOIN boundary"
  (raises-with? (lambda () (thread-join! (thread-start! (make-thread transcoded-port-for-copy))))
                "uncopyable"))
(test-assert "D6: the refusal is clean — the parent keeps running and its own port still works"
  (let ((p (custom-port-for-copy)))
    (raises? (lambda () (thread-join! (thread-start! (make-thread (lambda () (port? p)))))))
    (= 65 (read-u8 p))))

;; A transcoder is a plain record and a file-error is a plain error object;
;; neither is on the refusal list, so both must cross a join.
(test-assert "D6: a file-error object survives thread-join! and stays a file error"
  (file-error? (thread-join! (thread-start! (make-thread (lambda () (make-file-error "boom" 1)))))))
(test-assert "D6: a codec symbol survives thread-join! with eqv? identity intact"
  (eqv? (utf-8-codec) (thread-join! (thread-start! (make-thread (lambda () (utf-8-codec)))))))

;; Enabled by #1932: a record's type now survives the copy at the join.
(test-assert "D6: a transcoder record survives thread-join! and stays a transcoder?"
  (transcoder? (thread-join! (thread-start! (make-thread (lambda () (native-transcoder)))))))

;;; ==================================================================
;;; 11. Port lifecycle
;;; ==================================================================

(test-assert "a fresh custom port of each direction reports the right open state"
  (let ((ip (make-custom-binary-input-port "i" (lambda (b s c) 0) #f #f #f))
        (op (make-custom-binary-output-port "o" (lambda (b s c) c) #f #f #f))
        (io (make-custom-binary-input/output-port "x" (lambda (b s c) 0) (lambda (b s c) c) #f #f #f)))
    (and (input-port? ip) (not (output-port? ip)) (input-port-open? ip)
         (output-port? op) (not (input-port? op)) (output-port-open? op)
         (input-port? io) (output-port? io) (input-port-open? io) (output-port-open? io))))

(test-assert "writing to an input-only custom port is a type error, not a silent drop"
  (raises? (lambda () (write-u8 1 (make-custom-binary-input-port "i" (lambda (b s c) 0) #f #f #f)))))
(test-assert "reading from an output-only custom port is a type error"
  (raises? (lambda () (read-u8 (make-custom-binary-output-port "o" (lambda (b s c) c) #f #f #f)))))

(test-equal "close-port runs the close callback exactly once across a double close"
  1
  (let ((n 0))
    (let ((p (make-custom-binary-input-port "c" (lambda (b s c) 0) #f #f (lambda () (set! n (+ n 1))))))
      (close-port p)
      (close-port p))
    n))
(test-assert "close-port succeeds when close is #f"
  (begin (close-port (make-custom-binary-input-port "c" (lambda (b s c) 0) #f #f #f)) #t))
(test-equal "close-port flushes an output port before closing it, per R7RS 6.13.1"
  '(flush close)
  (let ((log '()))
    (close-port (make-custom-binary-output-port "c" (lambda (b s c) c) #f #f
                                                (lambda () (set! log (cons 'close log)))
                                                (lambda () (set! log (cons 'flush log)))))
    (reverse log)))
(test-assert "reading from a closed custom port raises rather than calling read! again"
  (let ((n 0))
    (let ((p (make-custom-binary-input-port "c" (lambda (b s c) (set! n (+ n 1)) 0) #f #f #f)))
      (close-port p)
      (and (raises? (lambda () (read-u8 p))) (= n 0)))))

(test-equal "close-port on a bidirectional custom port closes both sides and runs close once"
  '(#f #f 1)
  (let ((n 0))
    (let ((io (make-custom-binary-input/output-port "x" (lambda (b s c) 0) (lambda (b s c) c)
                                                    #f #f (lambda () (set! n (+ n 1))))))
      (close-port io)
      (list (input-port-open? io) (output-port-open? io) n))))

;; R7RS 6.13.1: "the close-input-port and close-output-port procedures can
;; then be used to close the input and output sides of the port
;; independently."
;; #1998 (fixed): close-input-port / close-output-port close the two sides
;; of a bidirectional port independently; the close callback runs only when
;; the second side goes.
(test-equal "close-input-port on a bidirectional port leaves the output side open"
  '(#f #t 0)
  (let ((n 0))
    (let ((io (make-custom-binary-input/output-port "x" (lambda (b s c) 0) (lambda (b s c) c)
                                                    #f #f (lambda () (set! n (+ n 1))))))
      (close-input-port io)
      (list (input-port-open? io) (output-port-open? io) n))))
(test-equal "close-output-port on a bidirectional port leaves the input side open"
  '(#t #f 0)
  (let ((n 0))
    (let ((io (make-custom-binary-input/output-port "x" (lambda (b s c) 0) (lambda (b s c) c)
                                                    #f #f (lambda () (set! n (+ n 1))))))
      (close-output-port io)
      (list (input-port-open? io) (output-port-open? io) n))))
(test-equal "closing the second side of a bidirectional port runs close exactly once"
  '(#f #f 1)
  (let ((n 0))
    (let ((io (make-custom-binary-input/output-port "x" (lambda (b s c) 0) (lambda (b s c) c)
                                                    #f #f (lambda () (set! n (+ n 1))))))
      (close-input-port io)
      (close-output-port io)
      (close-output-port io)          ; idempotent: no second callback
      (list (input-port-open? io) (output-port-open? io) n))))
(test-equal "close-port on a half-closed bidirectional port completes the close, callback once"
  '(#f #f 1)
  (let ((n 0))
    (let ((io (make-custom-binary-input/output-port "x" (lambda (b s c) 0) (lambda (b s c) c)
                                                    #f #f (lambda () (set! n (+ n 1))))))
      (close-input-port io)
      (close-port io)
      (list (input-port-open? io) (output-port-open? io) n))))
(test-assert "the closed output side rejects writes while the open input side still reads"
  (let ((io (make-custom-binary-input/output-port "x"
              (lambda (b s c) (if (= c 0) 0 (begin (bytevector-u8-set! b s 65) 1)))
              (lambda (b s c) c) #f #f #f)))
    (close-output-port io)
    (and (raises? (lambda () (write-u8 66 io)))
         (= 65 (read-u8 io)))))

;;; ==================================================================
;;; 12. Bulk I/O through the readOneByte / portWriteBytes funnel
;;; ==================================================================

(test-equal "read-bytevector drains a custom binary port across many one-byte read! calls"
  '(1 2 3 4 5)
  (call-with-values (lambda () (byte-source (bytevector 1 2 3 4 5) 1))
    (lambda (p src-pos) (bv->list (read-bytevector 10 p)))))
(test-equal "read-bytevector! fills a caller-supplied bytevector from a custom port"
  '(5 (1 2 3 4 5))
  (call-with-values (lambda () (byte-source (bytevector 1 2 3 4 5) 1))
    (lambda (p src-pos)
      (let ((dst (make-bytevector 5 0)))
        (list (read-bytevector! dst p) (bv->list dst))))))
(test-equal "write-bytevector reaches a custom binary sink in order"
  '(1 2 3 4)
  (call-with-values byte-sink
    (lambda (p collected) (write-bytevector (bytevector 1 2 3 4) p) (collected))))
(test-equal "a 5000-byte write exceeds the 4096 chunk size and still arrives intact"
  '(5000 0 255 0 135)
  (call-with-values byte-sink
    (lambda (p collected)
      (let ((bv (make-bytevector 5000 0)))
        (do ((i 0 (+ i 1))) ((= i 5000)) (bytevector-u8-set! bv i (modulo i 256)))
        (write-bytevector bv p)
        (let ((got (list->vector (collected))))
          (list (vector-length got)
                (vector-ref got 0) (vector-ref got 4095)
                (vector-ref got 4096) (vector-ref got 4999)))))))   ; i mod 256
(test-equal "a read! burst larger than one call's worth is served in full, in order"
  '(1 2 3 4 5 6)
  (call-with-values (lambda () (byte-source (bytevector 1 2 3 4 5 6) 4))
    (lambda (p src-pos)
      (let loop ((acc '()))
        (let ((b (read-u8 p)))
          (if (eof-object? b) (reverse acc) (loop (cons b acc))))))))

;;; ==================================================================

(let ((runner (test-runner-current)))
  (test-end "primitives_srfi181 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
