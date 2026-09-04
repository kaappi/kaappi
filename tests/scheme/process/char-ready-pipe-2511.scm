;; char-ready? / u8-ready? on a subprocess pipe — kaappi#2511 regression.
;;
;; R7RS 6.13.1: "If char-ready? returns #t then the next read-char
;; operation on the given port is guaranteed not to hang." Both predicates
;; returned #t unconditionally, so a poll-then-read drive loop on a pipe
;; with no data fell straight into the blocking read it was polling to
;; avoid (2s in the filing repro). The fix polls the underlying fd with a
;; zero timeout: buffered bytes / string sources / EOF are #t, an empty
;; fd with the writer alive is #f.
;;
;; The writer sleeps a generous 5s before echoing: no load spike can
;; shrink that below this test's own setup time, so the #f assertions
;; cannot flake. The blocking read and process-wait that follow absorb
;; the sleep exactly once.

(import (scheme base) (scheme write) (scheme file) (scheme process-context) (srfi 64))

;; Two gates, both before the first spawn-process reference (kaappi
;; compiles forms one at a time, so the later ones never compile either):
;; Windows has no /bin/sh child to spawn, and WASM has no subprocess
;; support at all (the same gating as process-test.scm next to this).
(cond-expand
  (windows
   (display "POSIX-only suite; pipe readiness is covered by src/tests_port_io.zig\n")
   (exit 0))
  (else))
(cond-expand
  ((library (kaappi process))
   (import (kaappi process)))
  (else (display "no (kaappi process) on this platform\n") (exit 0)))

(test-begin "char-ready-pipe-2511")

;; The filing repro's shape: nothing written yet -> both predicates #f,
;; then the data still arrives through a subsequent read. The wait comes
;; before the EOF assertions on purpose: it reaps the child, which is what
;; guarantees the pipe's write end is closed — between read-line returning
;; "late" and the child's actual exit the writer is still alive, and #f
;; would be the truthful answer there. After the reap, EOF is certain and
;; reports ready (the kaappi#1179 rule on the fd path).
(test-assert "predicates are #f on an empty pipe, #t once data or EOF arrives"
  (let* ((p (spawn-process (list "/bin/sh" "-c" "sleep 5; echo late")
                           'stdout: 'pipe))
         (out (process-stdout p)))
    (and (eq? #f (char-ready? out))
         (eq? #f (u8-ready? out))
         (string=? "late" (read-line out))
         (= 0 (process-wait p))
         (eq? #t (char-ready? out))
         (eof-object? (read-line out)))))

;; A regular file port: a read always has kernel data (or EOF) and never
;; blocks, so #t must hold — before the fix this was indistinguishable
;; from the pipe's fake #t; now it is the truthful branch.
(test-assert "char-ready? on a regular file port"
  (let ((path (string-append (or (get-environment-variable "KAAPPI_HOME")
                                 (get-environment-variable "TMPDIR")
                                 "/tmp")
                             "/kaappi-2511-ready.scm")))
    (call-with-output-file path (lambda (port) (write-string "data" port)))
    (let ((result
           (call-with-input-file path
             (lambda (port)
               (and (eq? #t (char-ready? port))
                    (string=? "data" (read-line port))
                    ;; at EOF a file port stays ready
                    (eq? #t (char-ready? port)))))))
      (delete-file path)
      result)))

(let ((runner (test-runner-current)))
  (test-end "char-ready-pipe-2511")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
