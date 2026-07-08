;; SRFI-233 (INI files) conformance tests
;; Regression test for #1223: char-whitespace? was unbound because
;; (scheme char) was not imported.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi233.scm

(import (scheme base) (srfi 233) (srfi 64))

(test-begin "srfi-233")

(define (parse str)
  (ini-file->alist (open-input-string str)))

;; empty input
(test-equal "empty input" '() (parse ""))

;;; --- the writer ---
(define (unparse alist)
  (let ((p (open-output-string)))
    (alist->ini-file alist p)
    (get-output-string p)))

(test-equal "write single section" "[sec]\nk = v\n\n" (unparse '(("sec" ("k" . "v")))))
(test-equal "write empty" "" (unparse '()))

;;; --- parsing ---
(let ((r (parse "[server]\nhost=localhost\nport=8080\n")))
  (test-equal "single section count" 1 (length r))
  (test-equal "section name" "server" (car (car r)))
  (let ((entries (cdr (car r))))
    (test-equal "host value" "localhost" (cdr (assoc "host" entries)))
    (test-equal "port value" "8080" (cdr (assoc "port" entries)))))

(let ((r (parse "[a]\nx=1\n[b]\ny=2\n")))
  (test-equal "multi-section count" 2 (length r))
  (test-equal "first section value" "1" (cdr (assoc "x" (cdr (car r))))))

(let ((r (parse "[s]\n; comment\n\nk=v\n")))
  (test-equal "comments and blanks skipped" "v" (cdr (assoc "k" (cdr (car r))))))

;; round trip
(let* ((out (unparse '(("sec" ("k" . "v")))))
       (back (parse out)))
  (test-equal "round trip" "v" (cdr (assoc "k" (cdr (car back))))))

(let ((runner (test-runner-current)))
  (test-end "srfi-233")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
