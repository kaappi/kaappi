;; A Kaappi child under (kaappi process): bidirectional stdio round trips.
;;
;; Spawns a *kaappi* child (the same binary, via the KAAPPI environment
;; variable run-all.sh exports) running a reader-loop script, and exchanges
;; lines with it in both directions — the streaming shape of the KEP's
;; driving workload (a long-lived tool speaking line protocol over pipes).
;; Skips cleanly when KAAPPI is not in the environment (ad-hoc runs).

(import (scheme base) (scheme write) (srfi 64))

;; Gate before the import (see process-test.scm for why the exit-0 guard
;; must precede the first spawn-process reference).
(cond-expand
  ((library (kaappi process))
   (import (kaappi process)))
  (else (display "no (kaappi process) on this platform\n") (exit 0)))

(define kaappi-binary (get-environment-variable "KAAPPI"))

;; The child script: read a line, echo it wrapped in angle brackets, stop at
;; EOF. Written to a temp file because argv-only spawn takes no -c strings
;; from us — the file IS the portable way to hand a program its code.
(define child-source
  "(import (scheme base) (scheme read) (scheme write))
(let loop ()
  (let ((line (read-line)))
    (unless (eof-object? line)
      (write-string \"<\") (write-string line) (write-string \">\") (newline)
      (flush-output-port (current-output-port))
      (loop))))")

;; Written under KAAPPI_HOME when the runner provides it (a fresh mktemp
;; dir per run-all.sh invocation — unique against parallel runs), TMPDIR
;; otherwise. No other test file uses this name either way.
(define script-path
  (string-append (or (get-environment-variable "KAAPPI_HOME")
                     (get-environment-variable "TMPDIR")
                     "/tmp")
                 "/kaappi-process-child.scm"))

(if (not kaappi-binary)
    (begin
      (display "KAAPPI not set; skipping child-script round trip\n")
      (exit 0))
    (begin
      (test-begin "kaappi-process-child")

      (call-with-output-file script-path
        (lambda (port) (write-string child-source port)))

      (define p (spawn-process (list kaappi-binary script-path)
                               'stdin: 'pipe 'stdout: 'pipe 'stderr: 'inherit))

      (test-assert "the child is a kaappi process with live pipes"
        (and (process? p) (port? (process-stdin p)) (port? (process-stdout p))))

      (test-equal "bidirectional line exchange with a kaappi child"
        '("<one>" "<two>" "<three>")
        (begin
          (write-string "one" (process-stdin p)) (newline (process-stdin p))
          (write-string "two" (process-stdin p)) (newline (process-stdin p))
          (write-string "three" (process-stdin p)) (newline (process-stdin p))
          (flush-output-port (process-stdin p))
          ;; Exactly three reads: the child echoes one line per input line
          ;; and then blocks on its own read, so a fourth read here would
          ;; deadlock the pair (the lesson this test exists to teach).
          (let ((out (process-stdout p)))
            (let loop ((acc '()) (n 0))
              (if (= n 3)
                  (reverse acc)
                  (loop (cons (read-line out) acc) (+ n 1)))))))

      ;; Half-close: the child sees EOF on stdin and exits cleanly.
      (close-output-port (process-stdin p))
      (test-equal "child exits 0 after stdin EOF" 0 (process-wait p))

      (let ((runner (test-runner-current)))
        (test-end "kaappi-process-child")
        (when (> (test-runner-fail-count runner) 0) (exit 1)))))
