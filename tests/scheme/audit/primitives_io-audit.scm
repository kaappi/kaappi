;; Audit tests for src/primitives_io.zig — ports, file I/O, read/write.
;; Audit campaign Phase 2.4 (#1137). Complements compliance/r7rs-control-io-gaps.scm
;; (port lifecycle, CRLF read-line, bytevector ports) and the R7RS suite.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.
;;
;; Extended by audit campaign v2 Phase 2.2 (docs/audit-strategy.md): everything
;; below the "v2 Phase 2.2" banner covers the ~1100 lines this file gained after
;; the original audit — SRFI 181 custom ports, SRFI 181 transcoded ports, the
;; 8 KiB write-buffering layer, close-port's flush/wake/unregister discipline,
;; and SRFI 192 port positions across every port kind.

(import (scheme base) (scheme write) (scheme read) (scheme file) (scheme char))
(import (scheme process-context) (srfi 64) (srfi 181) (srfi 192))
(import (only (kaappi ffi) fd->port))
(import (only (srfi 18) thread-sleep! thread-start! thread-join! make-thread))

(test-begin "primitives_io audit")

;;; --- closed-port operations raise catchable errors ---
(let ((cp (open-input-string "x")))
  (close-port cp)
  (test-equal #t (guard (e (#t #t)) (read-char cp)))
  (test-equal #t (guard (e (#t #t)) (peek-char cp)))
  (test-equal #t (guard (e (#t #t)) (read-line cp)))
  ;; "These routines have no effect if the port has already been closed."
  (test-equal 'ok (begin (close-port cp) 'ok)))
(let ((cop (open-output-string)))
  (close-port cop)
  (test-equal #t (guard (e (#t #t)) (write-char #\a cop)))
  (test-equal #t (guard (e (#t #t)) (write-string "s" cop))))

;;; --- read-string boundaries ---
(let ((rs (open-input-string "hello")))
  (test-equal "hel" (read-string 3 rs))
  (test-equal "lo" (read-string 10 rs))          ; short read at end
  (test-equal #t (eof-object? (read-string 1 rs))))
(test-equal "" (read-string 0 (open-input-string "x")))
(test-equal #t (eof-object? (read-string 5 (open-input-string ""))))

;;; --- port type predicates ---
(let ((sp (open-input-string "a")))
  (test-equal #t (port? sp))
  (test-equal #t (input-port? sp))
  (test-equal #f (output-port? sp))
  (test-equal #t (textual-port? sp))
  (test-equal #f (binary-port? sp))
  (test-equal #t (char-ready? sp)))
(test-equal #f (port? 42))
(test-equal #f (input-port? "not a port"))

;;; --- write / write-shared / write-simple label semantics (R7RS 6.13.3) ---
;; write: "Datum labels must not be used if there are no cycles."
(test-equal "((1 2) (1 2))"
  (let ((x (list 1 2)) (po (open-output-string)))
    (write (list x x) po) (get-output-string po)))
;; write-shared: labels for ALL shared structure
(test-equal "(#0=(1 2) #0#)"
  (let ((x (list 1 2)) (po (open-output-string)))
    (write-shared (list x x) po) (get-output-string po)))
;; write-simple: never labels
(test-equal "(1 2)"
  (let ((po (open-output-string)))
    (write-simple '(1 2) po) (get-output-string po)))

;;; --- write escape behavior (R7RS 6.13.3) ---
(test-equal "\"a\\\"b\\\\c\""
  (let ((po (open-output-string))) (write "a\"b\\c" po) (get-output-string po)))
(test-equal "a\"b"
  (let ((po (open-output-string))) (display "a\"b" po) (get-output-string po)))
(test-equal "#\\a" (let ((po (open-output-string))) (write #\a po) (get-output-string po)))
(test-equal "#\\space" (let ((po (open-output-string))) (write #\space po) (get-output-string po)))
(test-equal "#\\newline" (let ((po (open-output-string))) (write #\newline po) (get-output-string po)))
(test-equal "#\\null" (let ((po (open-output-string))) (write #\null po) (get-output-string po)))
(test-equal "a" (let ((po (open-output-string))) (display #\a po) (get-output-string po)))

;;; --- file I/O round trips ---
(let ((path "/tmp/kaappi-audit-io-test.txt"))
  (with-output-to-file path (lambda () (display "filedata")))
  (test-equal "filedata" (with-input-from-file path (lambda () (read-line))))
  (test-equal "file" (call-with-input-file path (lambda (port) (read-string 4 port))))
  (call-with-output-file path (lambda (port) (write-string "over" port)))
  (test-equal "over" (call-with-input-file path (lambda (port) (read-line port))))
  (delete-file path)
  (test-equal #f (file-exists? path)))
;; binary file ports
(let ((path "/tmp/kaappi-audit-io-bin.bin"))
  (let ((bp (open-binary-output-file path)))
    (write-u8 200 bp)
    (close-port bp))
  (let ((bp (open-binary-input-file path)))
    (test-equal #t (binary-port? bp))
    (test-equal 200 (read-u8 bp))
    (test-equal #t (eof-object? (read-u8 bp)))
    (close-port bp))
  (delete-file path))

;;; --- error signalling ---
(test-equal #t (guard (e ((file-error? e) #t) (#t 'wrong-type))
  (open-input-file "/nonexistent-kaappi-io-audit")))
(test-equal #t (guard (e ((file-error? e) #t) (#t 'wrong-type))
  (delete-file "/nonexistent-kaappi-io-audit")))
(test-equal #t (guard (e (#t #t)) (call-with-input-file "/nonexistent-kaappi-io-audit" values)))

;;; --- eof objects ---
(test-equal #t (eof-object? (eof-object)))
(test-equal #f (eof-object? 'eof))
(test-equal #t (eof-object? (read (open-input-string ""))))
(test-equal #t (eof-object? (read-char (open-input-string ""))))

;;; --- type errors are catchable ---
(test-equal #t (guard (e (#t #t)) (read-char 42)))
(test-equal #t (guard (e (#t #t)) (write 1 42)))
(test-equal #t (guard (e (#t #t)) (open-input-file 42)))
(test-equal #t (guard (e (#t #t)) (get-output-string (open-input-string "x"))))
(test-equal #t (guard (e (#t #t)) (read-string "n" (open-input-string "x"))))
(test-equal #t (guard (e (#t #t)) (with-input-from-file 42 (lambda () 1))))

;;; ==========================================================================
;;; v2 Phase 2.2 — coverage for the ~1100 lines added since the audit above
;;; ==========================================================================

;; Shared helpers.
(define (err-message thunk)
  (guard (e (#t (if (error-object? e) (error-object-message e) (list 'non-error e))))
    (thunk)))
(define (raises? thunk) (guard (e (#t #t)) (begin (thunk) #f)))
(define (bv->list bv)
  (let loop ((i 0) (acc '()))
    (if (= i (bytevector-length bv))
        (reverse acc)
        (loop (+ i 1) (cons (bytevector-u8-ref bv i) acc)))))
(define (file-byte-count path)
  (let ((p (open-binary-input-file path)))
    (let loop ((n 0))
      (if (eof-object? (read-u8 p)) (begin (close-port p) n) (loop (+ n 1))))))
(define (file-head path k)
  (let ((p (open-binary-input-file path)))
    (let loop ((i 0) (acc '()))
      (if (= i k)
          (begin (close-port p) (reverse acc))
          (loop (+ i 1) (cons (read-u8 p) acc))))))

;;; --- SRFI 192: string ports ------------------------------------------------
(let ((p (open-input-string "abcde")))
  (test-equal 0 (port-position p))
  (read-char p)
  (test-equal 1 (port-position p))
  (test-equal #t (port-has-port-position? p))
  (set-port-position! p 3)
  (test-equal #\d (read-char p))
  (set-port-position! p 0)
  (test-equal #\a (read-char p)))

;; Output string port: seeking back overwrites in place; the tail survives,
;; and get-output-string still reports the full extent (string_out_len).
(let ((o (open-output-string)))
  (write-string "abcdef" o)
  (test-equal 6 (port-position o))
  (set-port-position! o 2)
  (test-equal 2 (port-position o))
  (write-string "XY" o)
  (test-equal "abXYef" (get-output-string o))
  (test-equal 4 (port-position o)))

;; Out-of-range positions raise (SRFI 192 leaves the condition type to the
;; implementation; CONFORMANCE.md says "an ordinary error").
(test-equal #t (raises? (lambda () (set-port-position! (open-output-string) 5))))
(test-equal #t (raises? (lambda () (set-port-position! (open-input-string "ab") 9))))
(test-equal #t (raises? (lambda () (set-port-position! (open-input-string "ab") -1))))
(test-equal #t (raises? (lambda () (set-port-position! (open-input-string "ab") 1.5))))
(test-equal #t (raises? (lambda () (port-position 42))))
(test-equal #t (raises? (lambda () (set-port-position! 42 0))))
(test-equal #t (raises? (lambda () (port-has-port-position? 'nope))))

;; The string-port branches of portPosition/setPortPositionBang ignore the
;; port's own peek-byte read-ahead. The fd branch corrects for it (see the
;; two file-port controls immediately below), so the two port kinds disagree.
;;
;; CONTROL: with an LF line ending nothing is pushed back, and position and
;; the next read agree.
(let ((p (open-input-string "a\nb")))
  (read-line p)
  (test-equal 2 (port-position p))
  (test-equal #\b (read-char p)))
;; CONTROL: the same CR case on an fd-backed file port answers correctly.
(let ((path "/tmp/kaappi-audit-io-cr.txt"))
  (call-with-output-file path (lambda (o) (write-string "a\rb" o)))
  (let ((p (open-input-file path)))
    (read-line p)
    (test-equal 2 (port-position p))
    (test-equal #\b (read-char p))
    (close-port p))
  (delete-file path))
;; #1941 (fixed): the string branch subtracts the pushed-back peek byte the
;; same way the fd branch always did.
(let ((p (open-input-string "a\rb")))
  (read-line p)
  (test-equal 2 (port-position p))
  (test-equal #\b (read-char p)))

;; CONTROL: a seek with no stale read-ahead discards nothing and re-reads
;; from the requested offset.
(let ((p (open-input-string "abcd")))
  (read-char p) (read-char p)
  (set-port-position! p 0)
  (test-equal #\a (read-char p)))
;; CONTROL: the same stale-peek seek on an fd-backed file port is correct —
;; setPortPositionBang's fd branch clears peek_byte/peek_extra/read_buf.
(let ((path "/tmp/kaappi-audit-io-cr2.txt"))
  (call-with-output-file path (lambda (o) (write-string "a\rXbcd" o)))
  (let ((p (open-input-file path)))
    (read-line p)
    (set-port-position! p 0)
    (test-equal #\a (read-char p))
    (close-port p))
  (delete-file path))
;; #1941 (fixed): the string branch discards stale read-ahead on seek the
;; same way the fd branch always did.
(let ((p (open-input-string "a\rXbcd")))
  (read-line p)
  (set-port-position! p 0)
  (test-equal #\a (read-char p)))

;;; --- SRFI 192: bytevector ports --------------------------------------------
(let ((p (open-input-bytevector (bytevector 10 20 30))))
  (test-equal #t (port-has-port-position? p))
  (test-equal 0 (port-position p))
  (test-equal 10 (read-u8 p))
  (test-equal 1 (port-position p))
  (set-port-position! p 2)
  (test-equal 30 (read-u8 p)))
(let ((o (open-output-bytevector)))
  (write-u8 9 o)
  (test-equal 1 (port-position o))
  (test-equal #t (port-has-port-position? o)))

;;; --- SRFI 192: fd-backed ports, corrected for software buffering -----------
;; readOneByte fills read_buf a chunk at a time, so the raw lseek offset runs
;; well ahead of the logical position; portPosition subtracts read_buf_len,
;; peek_byte and peek_extra to compensate.
(let ((path "/tmp/kaappi-audit-io-pos.bin"))
  (let ((o (open-binary-output-file path)))
    (do ((i 0 (+ i 1))) ((= i 100)) (write-u8 i o))
    (close-port o))
  (let ((p (open-binary-input-file path)))
    (test-equal 0 (port-position p))
    (read-u8 p)
    (test-equal 1 (port-position p))       ; not 100, despite a 4096-byte chunk read
    (peek-u8 p)
    (test-equal 1 (port-position p))       ; peek_byte does not advance the position
    (read-u8 p)
    (test-equal 2 (port-position p))
    (set-port-position! p 50)
    (test-equal 50 (port-position p))
    (test-equal 50 (read-u8 p))            ; stale read-ahead was discarded
    (close-port p))
  ;; An output port's position counts the bytes still sitting in write_buf.
  (let ((o (open-binary-output-file path)))
    (write-u8 1 o) (write-u8 2 o) (write-u8 3 o)
    (test-equal 3 (port-position o))
    (set-port-position! o 1)               ; drains write_buf, then seeks
    (test-equal 1 (port-position o))
    (write-u8 99 o)
    (close-port o))
  (test-equal '(1 99 3) (file-head path 3))
  (delete-file path))

;;; --- SRFI 192: closed ports and predicates ---------------------------------
;; A closed fd's number can be recycled by the OS, so positioning a closed
;; port must not silently reposition an unrelated file.
(let ((p (open-input-string "x")))
  (close-port p)
  (test-equal #t (raises? (lambda () (port-position p))))
  (test-equal #t (raises? (lambda () (set-port-position! p 0))))
  (test-equal #f (port-has-port-position? p)))

;; CONTROL: a custom port with BOTH get-position and set-position! answers #t
;; to both predicates, and set-port-position! really works.
(let ((q (make-custom-binary-input-port "both"
           (lambda (bv start count) 0) (lambda () 0) (lambda (k) k) #f)))
  (test-equal #t (port-has-port-position? q))
  (test-equal #t (port-has-set-port-position!? q))
  (test-equal #t (begin (set-port-position! q 0) #t)))
;; CONTROL: a custom port with NEITHER answers #f to both.
(let ((r (make-custom-binary-input-port "neither"
           (lambda (bv start count) 0) #f #f #f)))
  (test-equal #f (port-has-port-position? r))
  (test-equal #f (port-has-set-port-position!? r)))
;; #1942 (fixed): the two predicates are now separate functions — the setter
;; predicate inspects set_position_proc, so the two mixed cases each answer
;; for their own operation.
(let ((p (make-custom-binary-input-port "gp-only"
           (lambda (bv start count) 0) (lambda () 0) #f #f)))
  (test-equal #t (port-has-port-position? p))
  (test-equal #f (port-has-set-port-position!? p))
  (test-equal #t (raises? (lambda () (set-port-position! p 0)))))
(let ((p (make-custom-binary-input-port "sp-only"
           (lambda (bv start count) 0) #f (lambda (k) k) #f)))
  (test-equal #f (port-has-port-position? p))
  (test-equal #t (port-has-set-port-position!? p))
  (test-equal #t (begin (set-port-position! p 0) #t)))

;;; --- Write buffering: the 8 KiB high-water mark and its triggers -----------
;; Ports on fd > 2 accumulate in write_buf and drain when the pending span
;; plus the new write crosses write_high_water (8192), at flush-output-port,
;; and at close-port.
(let ((path "/tmp/kaappi-audit-io-hw.txt"))
  (let ((o (open-output-file path)))
    (write-string (make-string 8191 #\x) o)
    (test-equal 0 (file-byte-count path))        ; entirely buffered
    (write-string "yy" o)                        ; 8191 + 2 > 8192 -> drain first
    (test-equal 8191 (file-byte-count path))     ; the drain wrote 8191; "yy" is buffered
    (flush-output-port o)
    (test-equal 8193 (file-byte-count path))
    (close-port o))
  (test-equal 8193 (file-byte-count path))
  (delete-file path))

;; close-port flushes what flush-output-port never got to.
(let ((path "/tmp/kaappi-audit-io-cf.txt"))
  (let ((o (open-output-file path)))
    (write-string "abc" o)
    (test-equal 0 (file-byte-count path))
    (close-port o))
  (test-equal 3 (file-byte-count path))
  (delete-file path))

;; A read on the same port drains pending writes first. Only a bidirectional
;; buffered fd port can reach that branch, and the only way to build one from
;; Scheme is (kaappi ffi)'s fd->port over a raw descriptor — verified manually
;; during the audit, deliberately not committed here (it needs a libc dlopen
;; and hard-coded O_RDWR, neither of which is portable across this project's
;; supported platforms). fd->port's own argument validation is covered below.

;;; --- close-port semantics --------------------------------------------------
(let ((path "/tmp/kaappi-audit-io-dc.txt"))
  (let ((o (open-output-file path)))
    (write-string "z" o)
    (close-port o)
    (test-equal #f (output-port-open? o))
    (test-equal 'ok (begin (close-port o) 'ok))      ; double close is a no-op
    (test-equal #t (raises? (lambda () (write-string "more" o))))
    (test-equal #t (raises? (lambda () (flush-output-port o)))))
  (delete-file path))

;; A custom port's close callback runs exactly once, however many times
;; close-port is called.
(let ((closes 0))
  (let ((p (make-custom-binary-input-port "cl"
             (lambda (bv start count) 0) #f #f (lambda () (set! closes (+ closes 1))))))
    (close-port p)
    (close-port p)
    (close-port p)
    (test-equal 1 closes)))

;; A raising close callback propagates catchably. The port stays open, since
;; the error escapes before the is_open transition — pinned as current
;; behaviour, not asserted as ideal.
(let ((p (make-custom-binary-input-port "cl2"
           (lambda (bv start count) 0) #f #f (lambda () (error "close boom")))))
  (test-equal "close boom" (err-message (lambda () (close-port p))))
  (test-equal #t (input-port-open? p)))

;;; --- SRFI 181 custom ports: the read!/write! contract ----------------------
;; A textual read! reports a CHARACTER count; the byte span is recovered from
;; the buffer's FRESHLY re-read data, so a width-changing string-set! inside
;; the callback (which reallocates the whole backing buffer) is safe.
(let ((n 0))
  (let ((p (make-custom-textual-input-port "wide"
             (lambda (str start count)
               (if (< n 3)
                   (begin (string-set! str start #\x3bb)        ; 1 -> 2 bytes
                          (string-set! str (+ start 1) #\x4e2d)  ; 1 -> 3 bytes
                          (set! n (+ n 1))
                          2)
                   0))
             #f #f #f)))
    (test-equal #\x3bb (read-char p))
    (test-equal #\x4e2d (read-char p))
    (test-equal #\x3bb (read-char p))))

;; A textual write! also counts CHARACTERS, and a partial write loops.
(let ((chunks '()))
  (let ((p (make-custom-textual-output-port "chunky"
             (lambda (str start count)
               (set! chunks (cons (substring str start (+ start 1)) chunks))
               1)                                   ; accept one character per call
             #f #f #f #f)))
    (write-string "a\x3bb;b" p)
    (test-equal '("a" "\x3bb;" "b") (reverse chunks))))

;; Misbehaving callbacks are rejected catchably rather than trusted.
(define (custom-reading v)
  (make-custom-binary-input-port "bad" (lambda (bv start count) v) #f #f #f))
(test-equal #t (raises? (lambda () (read-u8 (custom-reading 'not-a-number)))))
(test-equal #t (raises? (lambda () (read-u8 (custom-reading -1)))))
(test-equal #t (raises? (lambda () (read-u8 (custom-reading 999999)))))
(test-equal #t (raises? (lambda () (write-u8 1 (make-custom-binary-output-port
                                                 "w0" (lambda (bv s c) 0) #f #f #f #f)))))
;; An error raised inside a callback propagates to the caller unchanged.
(test-equal "boom"
  (err-message (lambda () (read-u8 (make-custom-binary-input-port
                                     "raiser" (lambda (bv s c) (error "boom")) #f #f #f)))))
;; D5: a callback that tries to block is rejected with a catchable error,
;; not a native-stack overflow from a recursive scheduler drive.
(test-equal #t
  (raises? (lambda ()
             (read-u8 (make-custom-binary-input-port
                        "blocker"
                        (lambda (bv s c) (thread-sleep! 0.01) 0)
                        #f #f #f)))))

;; get-position / set-position! / flush callbacks.
(let ((flushes 0) (sink '()))
  (let ((p (make-custom-textual-output-port "fl"
             (lambda (str start count)
               (set! sink (cons (substring str start (+ start count)) sink))
               count)
             #f #f #f (lambda () (set! flushes (+ flushes 1))))))
    (write-string "hi" p)
    (flush-output-port p)
    (test-equal 1 flushes)
    (test-equal '("hi") (reverse sink))
    (close-port p)
    (test-equal 2 flushes)))               ; close-port flushes before closing
;; A get-position callback returning a non-integer is rejected, not passed on.
(test-equal #t
  (raises? (lambda () (port-position (make-custom-binary-input-port
                                       "gp" (lambda (bv s c) 0) (lambda () 'weird) #f #f)))))
;; A custom port with no get-position raises rather than reporting a bogus offset.
(test-equal #t
  (raises? (lambda () (port-position (make-custom-binary-input-port
                                       "np" (lambda (bv s c) 0) #f #f #f)))))

;;; --- SRFI 181 custom ports: re-entrancy ------------------------------------
;; readOneByte hands out one byte and stashes the rest of a read! burst in the
;; port's single read_buf slot, asserting that slot is empty first. A read!
;; callback that re-enters a read on its OWN port breaks that invariant.
;;
;; CONTROL: the identical re-entrant shape with every read! returning exactly
;; one byte never populates read_buf, so it completes cleanly.
(let ((self #f) (depth 0) (n 0))
  (let ((p (make-custom-binary-input-port "reentrant-1byte"
             (lambda (bv start count)
               (set! depth (+ depth 1))
               (if (= depth 1) (read-u8 self))
               (set! depth (- depth 1))
               (if (< n 8)
                   (begin (bytevector-u8-set! bv start 65) (set! n (+ n 1)) 1)
                   0))
             #f #f #f)))
    (set! self p)
    (test-equal 65 (read-u8 p))))
;; FAIL: #1939 (a custom-port read! that re-enters a read on the same port and returns >1 byte trips std.debug.assert(port.read_buf == null) — process ABORTS, uncatchable; kept commented out because a panic would kill the whole suite)
;; (let ((self #f) (depth 0) (n 0))
;;   (let ((p (make-custom-binary-input-port "reentrant-2byte"
;;              (lambda (bv start count)
;;                (set! depth (+ depth 1))
;;                (if (= depth 1) (read-u8 self))
;;                (set! depth (- depth 1))
;;                (if (< n 8)
;;                    (begin (bytevector-u8-set! bv start 65)
;;                           (bytevector-u8-set! bv (+ start 1) 66)
;;                           (set! n (+ n 1)) 2)
;;                    0))
;;              #f #f #f)))
;;     (set! self p)
;;     (test-equal #t (raises? (lambda () (read-u8 p))))))
;;
;; The non-aborting sibling of the same root cause: when the outer read!
;; returns exactly one byte the assert never fires, but the byte the inner
;; call had already buffered — chronologically EARLIER in the stream — is
;; served after it, so the stream is silently reordered.
;; FAIL: #1939 (re-entrant custom-port read! reorders the byte stream: the outer call's byte precedes bytes the inner call already buffered)
;; (let ((self #f) (depth 0))
;;   (let ((p (make-custom-binary-input-port "reentrant-order"
;;              (lambda (bv start count)
;;                (set! depth (+ depth 1))
;;                (cond ((= depth 1)
;;                       (read-u8 self)
;;                       (set! depth (- depth 1))
;;                       (bytevector-u8-set! bv start 90) 1)
;;                      (else
;;                       (set! depth (- depth 1))
;;                       (bytevector-u8-set! bv start 65)
;;                       (bytevector-u8-set! bv (+ start 1) 66) 2)))
;;              #f #f #f)))
;;     (set! self p)
;;     (test-equal 66 (read-u8 p))
;;     (test-equal 90 (read-u8 p))))
;;
;; readOneByteFromTranscodedPort has the identical single-slot assert, reached
;; when a re-entrant read consumes only PART of a multi-byte character (here a
;; read-u8 that takes the lead byte and leaves the continuation byte behind).
;; FAIL: #1939 (same root cause one level up: a re-entrant read through a transcoded port trips std.debug.assert(port.read_buf == null) in readOneByteFromTranscodedPort — process ABORTS)
;; (let ((tp #f) (depth 0) (n 0))
;;   (let ((bp (make-custom-binary-input-port "tbase"
;;               (lambda (bv start count)
;;                 (set! depth (+ depth 1))
;;                 (if (= depth 1) (read-u8 tp))
;;                 (set! depth (- depth 1))
;;                 (if (< n 8)
;;                     (begin (bytevector-u8-set! bv start #xC3)
;;                            (bytevector-u8-set! bv (+ start 1) #xA9)
;;                            (set! n (+ n 1)) 2)
;;                     0))
;;               #f #f #f)))
;;     (set! tp (transcoded-port bp (make-transcoder (utf-8-codec) 'none 'replace)))
;;     (test-equal #t (raises? (lambda () (read-char tp))))))

;;; --- D6: ports do not cross a SRFI-18 thread boundary ----------------------
;; Ports are structurally uncopyable, so gc_deep_copy must reject them at the
;; join boundary with a catchable error rather than handing back a port whose
;; fd/buffers belong to a heap that is about to be freed.
(test-equal #t
  (raises? (lambda ()
             (thread-join! (thread-start! (make-thread (lambda () (open-input-string "abc"))))))))
(test-equal #t
  (raises? (lambda ()
             (thread-join! (thread-start! (make-thread (lambda ()
               (make-custom-binary-input-port "x" (lambda (bv s c) 0) #f #f #f))))))))

;;; --- SRFI 181 transcoded ports ---------------------------------------------
(define (transcode-read bytes eol)
  (let* ((bp (open-input-bytevector (apply bytevector bytes)))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) eol 'replace))))
    (let loop ((acc '()))
      (let ((c (read-char tp)))
        (if (eof-object? c) (reverse acc) (loop (cons c acc)))))))
;; crlf and lf both collapse CR, LF and CRLF alike to one #\newline; none does
;; no translation at all. The CRLF lookahead reuses the wrapped port's peek_byte.
(test-equal '(#\a #\newline #\b) (transcode-read '(97 13 10 98) 'crlf))
(test-equal '(#\a #\newline #\b) (transcode-read '(97 13 98) 'crlf))
(test-equal '(#\a #\newline #\b) (transcode-read '(97 10 98) 'crlf))
(test-equal '(#\a #\newline #\b) (transcode-read '(97 13 10 98) 'lf))
(test-equal '(#\a #\return #\newline #\b) (transcode-read '(97 13 10 98) 'none))
;; A CR at end of input still yields one newline and then EOF.
(test-equal '(#\a #\newline) (transcode-read '(97 13) 'crlf))
;; Multi-byte characters decode one at a time through the single read_buf slot.
(test-equal '(#\x3bb #\x4e2d) (transcode-read '(#xCE #xBB #xE4 #xB8 #xAD) 'none))

(define (transcode-write s eol)
  (let* ((bo (open-output-bytevector))
         (tp (transcoded-port bo (make-transcoder (utf-8-codec) eol 'replace))))
    (write-string s tp)
    (bv->list (get-output-bytevector bo))))
(test-equal '(97 13 10 98) (transcode-write "a\nb" 'crlf))
(test-equal '(97 10 98) (transcode-write "a\nb" 'lf))
(test-equal '(97 10 98) (transcode-write "a\nb" 'none))

;; error-handling-mode: replace substitutes U+FFFD, raise signals a condition
;; satisfying i/o-decoding-error? and then resumes from the next byte.
(define (transcode-decode bytes mode)
  (let* ((bp (open-input-bytevector (apply bytevector bytes)))
         (tp (transcoded-port bp (make-transcoder (utf-8-codec) 'none mode))))
    (guard (e ((i/o-decoding-error? e) 'decoding-error))
      (let loop ((acc '()))
        (let ((c (read-char tp)))
          (if (eof-object? c) (reverse acc) (loop (cons c acc))))))))
(test-equal '(#\a #\xfffd #\b) (transcode-decode '(97 #xFF 98) 'replace))
(test-equal 'decoding-error (transcode-decode '(97 #xFF 98) 'raise))
(test-equal '(#\a #\xfffd) (transcode-decode '(97 #xC3) 'replace))   ; truncated at EOF
(test-equal 'decoding-error (transcode-decode '(97 #xC3) 'raise))
;; A bad continuation byte is distinguished from a bad lead byte.
(test-equal 'decoding-error (transcode-decode '(#xC3 #x41) 'raise))

;; close-port on a transcoded port cascades to the port it wraps.
(let* ((bo (open-output-bytevector))
       (tp (transcoded-port bo (make-transcoder (utf-8-codec) 'none 'replace))))
  (write-string "z" tp)
  (close-port tp)
  (test-equal #f (output-port-open? tp))
  (test-equal #f (output-port-open? bo)))
;; Reading through a transcoded port whose wrapped port was closed underneath
;; raises rather than reading freed state.
(let* ((bp (open-input-bytevector (bytevector 97 98)))
       (tp (transcoded-port bp (make-transcoder (utf-8-codec) 'none 'replace))))
  (close-port bp)
  (test-equal #t (raises? (lambda () (read-char tp)))))
;; A transcoded port declines positioning (fd -1, no custom backend).
(let* ((bp (open-input-bytevector (bytevector 97)))
       (tp (transcoded-port bp (make-transcoder (utf-8-codec) 'none 'replace))))
  (test-equal #f (port-has-port-position? tp))
  (test-equal #t (raises? (lambda () (port-position tp))))
  (test-equal #t (raises? (lambda () (set-port-position! tp 0)))))
;; transcoded-port requires a binary port.
(test-equal #t (raises? (lambda () (transcoded-port (open-output-string)
                                                    (make-transcoder (utf-8-codec) 'none 'replace)))))

;; CONTROL: flushing the WRAPPED port does reach the device.
(let ((path "/tmp/kaappi-audit-io-tcw.txt"))
  (let* ((bo (open-binary-output-file path))
         (tp (transcoded-port bo (make-transcoder (utf-8-codec) 'none 'replace))))
    (write-string "hello" tp)
    (test-equal 0 (file-byte-count path))
    (flush-output-port bo)
    (test-equal 5 (file-byte-count path))
    (close-port tp))
  (delete-file path))
;; CONTROL: close-port on the transcoded port does cascade the flush.
(let ((path "/tmp/kaappi-audit-io-tcc.txt"))
  (let* ((bo (open-binary-output-file path))
         (tp (transcoded-port bo (make-transcoder (utf-8-codec) 'none 'replace))))
    (write-string "hello" tp)
    (close-port tp))
  (test-equal 5 (file-byte-count path))
  (delete-file path))
;; #1943 (fixed): flushing a transcoded port cascades to the wrapped port —
;; where all of its pending output lives — so the bytes are durable without
;; a close.
(let ((path "/tmp/kaappi-audit-io-tcf.txt"))
  (let* ((bo (open-binary-output-file path))
         (tp (transcoded-port bo (make-transcoder (utf-8-codec) 'none 'replace))))
    (write-string "hello" tp)
    (flush-output-port tp)
    (test-equal 5 (file-byte-count path))
    (close-port tp))
  (delete-file path))

;;; --- Standard surface: gaps the original audit left ------------------------
;; write-string start/end are codepoint indices, not byte offsets.
(test-equal "\x4e2d;c"
  (let ((o (open-output-string))) (write-string "a\x3bb;\x4e2d;c" o 2) (get-output-string o)))
(test-equal "\x3bb;"
  (let ((o (open-output-string))) (write-string "a\x3bb;\x4e2d;c" o 1 2) (get-output-string o)))
(test-equal "" (let ((o (open-output-string))) (write-string "abc" o 1 1) (get-output-string o)))
(test-equal #t (raises? (lambda () (write-string "abc" (open-output-string) 5))))
(test-equal #t (raises? (lambda () (write-string "abc" (open-output-string) 0 9))))
(test-equal #t (raises? (lambda () (write-string "abc" (open-output-string) 2 1))))
(test-equal #t (raises? (lambda () (write-string "abc" (open-output-string) -1))))
(test-equal #t (raises? (lambda () (write-string "abc" (open-output-string) 'x))))

;; read-string, peek-char and read-line index by codepoint through a real fd.
(let ((path "/tmp/kaappi-audit-io-u8.txt"))
  (call-with-output-file path (lambda (o) (write-string "\x3bb;\x4e2d;x\ny\r\nz" o)))
  (let ((p (open-input-file path)))
    (test-equal #\x3bb (peek-char p))
    (test-equal #\x3bb (peek-char p))          ; idempotent
    (test-equal "\x3bb;\x4e2d;x" (read-string 3 p))
    (test-equal "" (read-line p))
    (test-equal "y" (read-line p))              ; CRLF terminated
    (test-equal "z" (read-line p))
    (test-equal #t (eof-object? (read-line p)))
    (close-port p))
  (delete-file path))

;; char-ready? at EOF is #t (R7RS 6.13.2: a port at end of file is "ready").
(test-equal #t (char-ready? (open-input-string "")))

;; Port-kind predicates never raise on a non-port; the *-open? pair does.
(test-equal #f (textual-port? 'x))
(test-equal #f (binary-port? 'x))
(test-equal #f (output-port? '()))
(test-equal #t (raises? (lambda () (input-port-open? 'x))))
(test-equal #t (raises? (lambda () (output-port-open? 'x))))
(test-equal #t (binary-port? (open-input-bytevector (bytevector 1))))
(test-equal #f (textual-port? (open-input-bytevector (bytevector 1))))

;; fd->port rejects the standard streams and anything out of fd_t range.
(test-equal #t (raises? (lambda () (fd->port 0))))
(test-equal #t (raises? (lambda () (fd->port 2))))
(test-equal #t (raises? (lambda () (fd->port -5))))
(test-equal #t (raises? (lambda () (fd->port "3"))))

;; newline writes exactly one LF and honours the optional port argument.
(test-equal "\n" (let ((o (open-output-string))) (newline o) (get-output-string o)))
(test-equal "a\nb"
  (let ((o (open-output-string)))
    (parameterize ((current-output-port o)) (display "a") (newline) (display "b"))
    (get-output-string o)))
(test-equal #t (raises? (lambda () (newline 42))))
(test-equal #t (raises? (lambda () (newline (open-input-string "x")))))

;; close-input-port / close-output-port are registered to the same body as
;; close-port, so neither checks the port's direction — pinned as current
;; behaviour (R7RS says the argument "must be" the matching kind, without
;; requiring the implementation to signal).
(let ((p (open-input-string "x")))
  (close-input-port p)
  (test-equal #f (input-port-open? p)))
(let ((o (open-output-string)))
  (close-output-port o)
  (test-equal #f (output-port-open? o)))
(let ((p (open-input-string "x")))
  (close-output-port p)                    ; direction-mismatched, still closes
  (test-equal #f (input-port-open? p)))
(test-equal #t (raises? (lambda () (close-input-port 'x))))
(test-equal #t (raises? (lambda () (close-output-port 'x))))

;; Arity is enforced on the fixed-arity entries.
(test-equal #t (raises? (lambda () (port?))))
(test-equal #t (raises? (lambda () (eof-object 1))))
(test-equal #t (raises? (lambda () (open-output-string 'x))))

;; call-with-port closes the port on both the normal and the escaping path.
(let ((p (open-input-string "abc")))
  (test-equal #\a (call-with-port p read-char))
  (test-equal #f (input-port-open? p)))
(let ((p (open-input-string "abc")))
  (test-equal #t (raises? (lambda () (call-with-port p (lambda (q) (error "x"))))))
  (test-equal #f (input-port-open? p)))
(test-equal #t (raises? (lambda () (call-with-port 42 values))))

;;; --- #1944: error taxonomy -------------------------------------------------
;; Every assertion above only ever asked whether a bad call *raises*, which is
;; why this file's messages could all be the wrong kind and still pass. These
;; pin the message text, so a regression to the pre-#1944 wording fails here.

;; A closed port is a port: rejecting it is argError, not typeError. The
;; direction is still reported, since the direction check runs first.
(test-equal "write-string: output port is closed"
  (err-message (lambda () (let ((p (open-output-string))) (close-port p) (write-string "x" p)))))
(test-equal "read-char: input port is closed"
  (err-message (lambda () (let ((p (open-input-string "x"))) (close-port p) (read-char p)))))
(test-equal "port-position: port is closed"
  (err-message (lambda () (let ((p (open-input-string "x"))) (close-port p) (port-position p)))))
(test-equal "set-port-position!: port is closed"
  (err-message (lambda () (let ((p (open-input-string "x"))) (close-port p) (set-port-position! p 0)))))
;; CONTROL: a genuinely wrong type — and a right-type/wrong-direction port —
;; must still be a type error, or the fix above would have flattened the
;; distinction instead of drawing it.
(test-equal "type error in 'write-string': expected output port, got #<symbol>"
  (err-message (lambda () (write-string "x" 'not-a-port))))
(test-equal "type error in 'write-string': expected output port, got #<port>"
  (err-message (lambda () (write-string "x" (open-input-string "y")))))

;; set-port-position! past the end of a string port reports index and length
;; (it was a detail-less "invalid argument in 'set-port-position!'").
(test-equal "set-port-position!: index 99 out of range for length 3"
  (err-message (lambda () (set-port-position! (open-input-string "abc") 99))))
(test-equal "set-port-position!: index 99 out of range for length 0"
  (err-message (lambda () (set-port-position! (open-output-string) 99))))
;; CONTROL: position == length is the legal end-of-input seek, not an error.
(test-equal #t
  (let ((p (open-input-string "abc"))) (set-port-position! p 3) (eof-object? (read-char p))))

;; write-string range errors name the offending index, not args[0] — the
;; string is the one argument that is never at fault here.
(test-equal "write-string: index 5 out of range for length 3"
  (err-message (lambda () (write-string "abc" (open-output-string) 5))))
(test-equal "write-string: index 9 out of range for length 3"
  (err-message (lambda () (write-string "abc" (open-output-string) 1 9))))
;; An in-range but inverted pair is neither a type nor a range fault.
(test-equal "write-string: start 2 is greater than end 1"
  (err-message (lambda () (write-string "abc" (open-output-string) 2 1))))
;; CONTROL: a valid sub-range still writes exactly that slice.
(test-equal "bc"
  (let ((o (open-output-string))) (write-string "abcde" o 1 3) (get-output-string o)))

;;; --- #1972: fd->port range constraints are not type errors -----------------
;; 0/1/2 and an out-of-range number are all fixnums — the type fd->port wants —
;; so "expected socket/pipe file descriptor (> 2)" put a range rule where the
;; expected *type* belongs. They are argError (KP3007), not indexError: neither
;; bound is an index into anything with a length.
;;
;; The four sibling sites this issue covers are `comptime is_wasm` gates, so
;; they cannot be reached from a native build at all — tests/wasm/platform-gates.scm
;; covers those under wasmtime.
(test-equal "fd->port: descriptor 0 is a standard stream; 0, 1 and 2 stay blocking"
  (err-message (lambda () (fd->port 0))))
(test-equal "fd->port: descriptor 2 is a standard stream; 0, 1 and 2 stay blocking"
  (err-message (lambda () (fd->port 2))))
(test-equal "fd->port: -1 is outside the file-descriptor range"
  (err-message (lambda () (fd->port -1))))
(test-equal "fd->port: 999999999999 is outside the file-descriptor range"
  (err-message (lambda () (fd->port 999999999999))))
;; CONTROL: a genuinely wrong type is still a type error, so the fix drew the
;; distinction rather than flattening every rejection into one kind.
(test-equal "type error in 'fd->port': expected file descriptor, got #<symbol>"
  (err-message (lambda () (fd->port 'nope))))
(test-equal "type error in 'fd->port': expected file descriptor, got 3.0"
  (err-message (lambda () (fd->port 3.0))))
;; CONTROL: a number past the reserved range is accepted — the lower bound is
;; the rule being enforced, not a blanket rejection. fd->port never probes the
;; descriptor, so the number need not be open, and it deliberately is *not*:
;; the port takes ownership and gc_sweep closes any fd > 2 it collects, which
;; over a live descriptor would silently close something this run still needs.
;;
;; POSIX-only, because the eventual close is what makes the number matter.
;; close(2) on an unopened descriptor is a plain EBADF, but the Windows CRT's
;; _close invokes the invalid-parameter handler, whose default terminates the
;; process — so this control would turn a passing suite into a crash there.
(cond-expand
  (windows)
  (else
   (test-equal #t (let ((p (fd->port 4096)))
                    (and (port? p) (binary-port? p))))))

;; with-output-to-file restores current-output-port even when the thunk raises.
(let ((path "/tmp/kaappi-audit-io-wo.txt"))
  (test-equal #t (raises? (lambda () (with-output-to-file path (lambda () (error "x"))))))
  (test-equal "restored"
    (let ((o (open-output-string)))
      (parameterize ((current-output-port o)) (display "restored"))
      (get-output-string o)))
  (delete-file path))

(let ((runner (test-runner-current)))
  (test-end "primitives_io audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
