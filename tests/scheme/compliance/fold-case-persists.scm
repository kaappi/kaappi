;; Regression test for #2175: a #!fold-case directive does not persist
;; across separate `(read port)` calls on the same port.
;;
;; R7RS 7.1.1: a #!fold-case directive affects reading "from the same
;; port" from the point it appears on. readDatumFn built a fresh Reader per
;; call, so the flag died with it: the first (read p) folded, the second
;; did not. The mode now lives on the Port (Port.fold_case), seeding each
;; call's Reader and written back after a successful parse.
;;
;; Both port kinds readDatumFn serves are covered: fd-backed file ports
;; (the incremental refill path) and string ports (whole-source path), plus
;; the 4096-byte chunk-boundary straddle that the refill machinery must not
;; regress.

(import (scheme base) (scheme read) (scheme write) (scheme file)
        (scheme time) (scheme process-context) (srfi 64))

(test-begin "fold-case-persists")

;; --- fixture plumbing (same temp-dir dance as reader-port-refill-gaps) ---

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
  (string-append tmp-dir "/kaappi-fold-case-"
                 (number->string (current-jiffy)) ".scm"))

(define (write-fixture text)
  (if (file-exists? fixture-file) (delete-file fixture-file))
  (call-with-output-file fixture-file
    (lambda (p) (write-string text p))))

;; The repro from the issue: the directive and the first datum arrive in the
;; same read call, the second datum in a separate call. Both must fold.
(test-equal "fold-case persists across read calls on a file port"
  '(foo bar)
  (let ()
    (write-fixture "#!fold-case\nFOO\nBAR\n")
    (let* ((p (open-input-file fixture-file))
           (r (list (read p) (read p))))
      (close-port p)
      (delete-file fixture-file)
      r)))

;; String ports take the whole-source path in readDatumFn (a different
;; fresh-Reader site); the mode must persist there too.
(test-equal "fold-case persists across read calls on a string port"
  '(foo bar)
  (let ((p (open-input-string "#!fold-case\nFOO\nBAR\n")))
    (list (read p) (read p))))

;; #!no-fold-case resets the mode, and the reset also persists.
(test-equal "no-fold-case reset persists across read calls"
  '(foo BAR BAZ)
  (let ((p (open-input-string "#!fold-case\nFOO\n#!no-fold-case\nBAR\nBAZ\n")))
    (list (read p) (read p) (read p))))

;; A directive that appears after the first datum applies from that point
;; on — the folded state must not leak backwards either.
(test-equal "mid-stream directive applies to later read calls"
  '(FOO bar)
  (let ((p (open-input-string "FOO #!fold-case\nBAR\n")))
    (list (read p) (read p))))

;; Directive straddling the 4096-byte read chunk boundary (it starts at
;; byte 4089 of the file). The within-call refill must still fold the first
;; datum — the saw_directive buffer-keep behavior — and the folded state
;; must then carry into the next read call.
(test-equal "boundary-straddling directive persists to next read"
  '(foo bar)
  (let ()
    (write-fixture (string-append (make-string 4089 #\space)
                                  "#!fold-case\nFOO\nBAR\n"))
    (let* ((p (open-input-file fixture-file))
           (r (list (read p) (read p))))
      (close-port p)
      (delete-file fixture-file)
      r)))

(if (file-exists? fixture-file) (delete-file fixture-file))

(let ((runner (test-runner-current)))
  (test-end "fold-case-persists")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
