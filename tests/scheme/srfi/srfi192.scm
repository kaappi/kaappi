;; SRFI-192 (Port Positioning) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi192.scm
;;
;; Built in (no lib/srfi/192.sld -- see src/primitives_io.zig's
;; port-position/set-port-position!/port-has-port-position?/
;; port-has-set-port-position!?, gated behind the srfi_192 Lib tag).
;; Scope: positions are always plain exact-integer byte offsets (the
;; spec's "opaque object" alternative for textual ports isn't needed
;; here), and the dedicated i/o-invalid-position-error condition type
;; isn't implemented -- any failure raises an ordinary error instead.

(import (scheme base) (scheme file) (scheme process-context) (srfi 192) (srfi 64))

(test-begin "srfi-192")

;;; --- string input ports ---

(let ((p (open-input-string "hello world")))
  (test-equal "string input port: position starts at 0" 0 (port-position p))
  (read-char p)
  (test-equal "string input port: position advances after a read" 1 (port-position p))
  (set-port-position! p 6)
  (test-equal "string input port: set-port-position! then read" #\w (read-char p)))

;;; --- string output ports ---

(let ((p (open-output-string)))
  (write-string "hello" p)
  (test-equal "string output port: position is the written length" 5 (port-position p))
  (set-port-position! p 0)
  (write-string "HELLO" p)
  (test-equal "string output port: seek back then overwrite (same length)" "HELLO" (get-output-string p)))

;; Regression: a backward seek followed by a *shorter* write used to
;; truncate everything after it (set-port-position! directly overwrote
;; string_out_len, the buffer's total extent) instead of overwriting in
;; place and preserving the untouched suffix -- inconsistent with how a
;; seekable fd-backed output port already behaves for free via the OS's
;; own lseek+write (verified directly: write "hello" to a file port,
;; seek to 0, write "X", re-read the file -- it already read back
;; "Xello", not "X", before this fix touched anything fd-related).
(let ((p (open-output-string)))
  (write-string "hello" p)
  (set-port-position! p 0)
  (write-string "X" p)
  (test-equal "string output port: a shorter write after seeking back overwrites in place, preserving the suffix"
    "Xello" (get-output-string p)))
(let ((p (open-output-string)))
  (write-string "hello" p)
  (set-port-position! p 2)
  (write-string "LL" p)
  (test-equal "string output port: overwriting in the middle preserves both the prefix and the suffix"
    "heLLo" (get-output-string p)))
(let ((p (open-output-string)))
  (write-string "hello" p)
  (set-port-position! p 3)
  (write-string "LOWORLD" p)
  (test-equal "string output port: a write extending past the old end still overwrites the overlap and appends the rest"
    "helLOWORLD" (get-output-string p)))
(let ((p (open-output-string)))
  (write-string "hello" p)
  (set-port-position! p 2)
  (test-equal "string output port: port-position after a seek reports the cursor, not the total length"
    2 (port-position p))
  (write-string "!" p)
  (test-equal "string output port: port-position after a write from a seeked cursor advances from the cursor"
    3 (port-position p)))

;;; --- binary (bytevector) ports ---

(let ((p (open-input-bytevector (bytevector 10 20 30 40 50))))
  (read-u8 p)
  (test-equal "binary port: position after one read-u8" 1 (port-position p))
  (set-port-position! p 3)
  (test-equal "binary port: set-port-position! then read-u8" 40 (read-u8 p)))

;;; --- file (fd-backed) ports: the actual engine change ---

(define %test-path "/tmp/srfi192-test-file.txt")

(dynamic-wind
  (lambda () #f)
  (lambda ()
    (call-with-output-file %test-path (lambda (p) (write-string "0123456789" p)))

    (let ((p (open-input-file %test-path)))
      (test-assert "file port: port-has-port-position? is true" (port-has-port-position? p))
      (test-assert "file port: port-has-set-port-position!? is true" (port-has-set-port-position!? p))
      (read-char p)
      (test-equal "file port: position after one read-char" 1 (port-position p))
      (set-port-position! p 5)
      (test-equal "file port: read after seeking forward" #\5 (read-char p))
      (set-port-position! p 0)
      (test-equal "file port: read after seeking back to the start" #\0 (read-char p))
      (close-port p))

    ;; Regression: port-position must correct for read-ahead buffering
    ;; (readOneByte buffers a whole chunk on the first read), not just
    ;; report the OS's raw, further-ahead file offset.
    (let ((p (open-input-file %test-path)))
      (read-char p)
      (test-equal "file port: position accounts for buffered read-ahead, not the raw OS offset"
        1 (port-position p))
      (read-char p)
      (test-equal "file port: position after a second (buffer-served) read" 2 (port-position p))
      (set-port-position! p 0)
      (test-equal "file port: seeking after buffered reads discards the stale buffer"
        #\0 (read-char p))
      (close-port p))

    ;; set-port-position! on an output port must flush first (spec:
    ;; "even if the port position will not change") -- write, seek, close
    ;; without further writes, then confirm the data actually reached disk.
    (let ((p (open-output-file %test-path)))
      (write-string "buffered-data" p)
      (set-port-position! p 0)
      (close-port p))
    (let ((p (open-input-file %test-path)))
      (test-equal "file port: set-port-position! flushed pending writes first"
        "buffered-data" (read-line p))
      (close-port p)))
  (lambda () (when (file-exists? %test-path) (delete-file %test-path))))

;;; --- error cases ---

(test-assert "set-port-position!: beyond the end of a string input port errors"
  (guard (e (#t #t)) (set-port-position! (open-input-string "hi") 100) #f))
(test-assert "set-port-position!: a negative position errors"
  (guard (e (#t #t)) (set-port-position! (open-input-string "hi") -1) #f))
(test-assert "port-position: a non-port argument errors"
  (guard (e (#t #t)) (port-position "not-a-port") #f))
(test-assert "set-port-position!: a non-integer position errors"
  (guard (e (#t #t)) (set-port-position! (open-input-string "hi") 1.5) #f))

;; Regression: a closed fd-backed port's fd number can be reused by the OS
;; for a completely unrelated, newly opened file. Operating on the closed
;; port must error rather than silently repositioning that unrelated
;; file. Provoked by opening/closing/reopening enough files that the OS
;; is likely to hand back the just-freed fd number.
(let ((path1 "/tmp/srfi192-closed-port-1.txt")
      (path2 "/tmp/srfi192-closed-port-2.txt"))
  (dynamic-wind
    (lambda () #f)
    (lambda ()
      (call-with-output-file path1 (lambda (p) (write-string "0123456789" p)))
      (call-with-output-file path2 (lambda (p) (write-string "abcdefghij" p)))
      (let ((p1 (open-input-file path1)))
        (read-char p1)
        (close-port p1)
        (test-assert "port-position: a closed port errors instead of reporting stale state"
          (guard (e (#t #t)) (port-position p1) #f))
        (test-assert "set-port-position!: a closed port errors instead of silently repositioning a reused fd"
          (guard (e (#t #t)) (set-port-position! p1 5) #f))
        (test-assert "port-has-port-position?: a closed port answers false, not true"
          (not (port-has-port-position? p1))))
      ;; The actual fd-reuse hazard: confirm a fresh port opened after the
      ;; close still reads its own file from the start, unaffected by the
      ;; (correctly rejected) attempted seek on the closed handle above.
      (let ((p2 (open-input-file path2)))
        (test-equal "a freshly opened port is unaffected by a rejected seek on a since-closed port"
          #\a (read-char p2))
        (close-port p2)))
    (lambda ()
      (when (file-exists? path1) (delete-file path1))
      (when (file-exists? path2) (delete-file path2)))))

(let ((runner (test-runner-current)))
  (test-end "srfi-192")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
