;; Audit tests for src/primitives_io.zig — ports, file I/O, read/write.
;; Audit campaign Phase 2.4 (#1137). Complements compliance/r7rs-control-io-gaps.scm
;; (port lifecycle, CRLF read-line, bytevector ports) and the R7RS suite.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme read) (scheme file) (scheme char))
(import (scheme process-context) (srfi 64))

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

(let ((runner (test-runner-current)))
  (test-end "primitives_io audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
