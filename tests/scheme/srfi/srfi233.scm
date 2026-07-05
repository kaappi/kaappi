;; SRFI-233 (INI files) conformance tests — audit Phase 3e
;; ini-file->alist fails on any non-empty input (#1223): the library's
;; string-trim calls char-whitespace? without importing (scheme char).
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi233.scm

(import (scheme base) (srfi 233) (chibi test))

(test-begin "srfi-233")

(define (parse str)
  (ini-file->alist (open-input-string str)))

;; empty input works (never reaches the broken string-trim)
(test '() (parse ""))

;;; --- the writer is unaffected ---
(define (unparse alist)
  (let ((p (open-output-string)))
    (alist->ini-file alist p)
    (get-output-string p)))

(test "[sec]\nk = v\n\n" (unparse '(("sec" ("k" . "v")))))
(test "" (unparse '()))

;;; --- parsing (all blocked on #1223) ---
;; FAIL: #1223 (ini-file->alist: char-whitespace? unbound — every parse fails)
;; (let ((r (parse "[server]\nhost=localhost\nport=8080\n")))
;;   (test 1 (length r))
;;   (test "server" (car (car r)))
;;   (let ((entries (cdr (car r))))
;;     (test "localhost" (cdr (assoc "host" entries)))
;;     (test "8080" (cdr (assoc "port" entries)))))
;; FAIL: #1223 (ini-file->alist: char-whitespace? unbound)
;; (let ((r (parse "[a]\nx=1\n[b]\ny=2\n")))
;;   (test 2 (length r))
;;   (test "1" (cdr (assoc "x" (cdr (car r))))))
;; FAIL: #1223 (ini-file->alist: char-whitespace? unbound)
;; (let ((r (parse "[s]\n; comment\n\nk=v\n")))
;;   (test "v" (cdr (assoc "k" (cdr (car r))))))
;; FAIL: #1223 (round trip blocked on the parser)
;; (let* ((out (unparse '(("sec" ("k" . "v")))))
;;        (back (parse out)))
;;   (test "v" (cdr (assoc "k" (cdr (car back))))))

(test-end "srfi-233")
