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
;; The #2516 review round added: char-ready? must hold the guarantee at
;; *character* granularity (a lone UTF-8 lead byte is #f until its
;; continuation arrives — byte-granular u8-ready? stays #t for it), custom
;; ports are #f unless a character is buffered (read! has no readiness
;; contract), and u8-ready? gets positive assertions at data and EOF so an
;; always-#f oracle cannot pass.
;;
;; The writer sleeps a generous 5s before echoing: no load spike can
;; shrink that below this test's own setup time, so the #f assertions
;; cannot flake. The blocking read and process-wait that follow absorb
;; the sleep exactly once.

(import (scheme base) (scheme write) (scheme file) (scheme process-context)
        (scheme char) (srfi 64) (srfi 18))

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
   (import (kaappi process) (srfi 181)))
  (else (display "no (kaappi process) on this platform\n") (exit 0)))

(test-begin "char-ready-pipe-2511")

;; The filing repro's shape: nothing written yet -> both predicates #f,
;; then the data still arrives through a subsequent read. The wait comes
;; before the EOF assertions on purpose: it reaps the child, which is what
;; guarantees the pipe's write end is closed — between read-line returning
;; "ate" and the child's actual exit the writer is still alive, and #f
;; would be the truthful answer there. After the reap, EOF is certain and
;; reports ready (the kaappi#1179 rule on the fd path). u8-ready? is
;; asserted positively both with data buffered and at EOF (#2516 review:
;; the #f-only version of this test would pass against an always-#f
;; oracle).
(test-assert "predicates are #f on an empty pipe, #t once data or EOF arrives"
  (let* ((p (spawn-process (list "/bin/sh" "-c" "sleep 5; echo late")
                           'stdout: 'pipe))
         (out (process-stdout p)))
    (and (eq? #f (char-ready? out))
         (eq? #f (u8-ready? out))
         (char=? #\l (read-char out))
         (eq? #t (u8-ready? out))   ; "ate\n" is buffered behind the read
         (eq? #t (char-ready? out)) ; ...and #\a is a complete character
         (string=? "ate" (read-line out))
         (= 0 (process-wait p))
         (eq? #t (char-ready? out))
         (eq? #t (u8-ready? out))   ; EOF answers at once
         (eof-object? (read-line out)))))

;; kaappi#2516 review: the child writes only the UTF-8 lead byte 0xC3,
;; waits 2s, then writes the continuation 0xA9 (together they are #\é).
;; While the lead byte alone sits in the pipe, u8-ready? is #t (a byte IS
;; ready) but char-ready? must be #f — read-char would consume the lead
;; byte and then block for the continuation, the exact hang R7RS 6.13.1
;; forbids a #t to lead into. The bounded poll first waits for the lead
;; byte to land, so both mid-window assertions are deterministic.
(test-assert "char-ready? stays #f while only a UTF-8 lead byte has arrived"
  (let* ((p (spawn-process
             (list "/bin/sh" "-c" "printf '\\303'; sleep 2; printf '\\251'")
             'stdout: 'pipe))
         (out (process-stdout p)))
    (let loop ((i 0))
      (when (and (eq? #f (u8-ready? out)) (< i 40))
        (thread-sleep! 0.1)
        (loop (+ i 1))))
    (and (eq? #t (u8-ready? out))     ; the lead byte is one ready byte
         (eq? #f (char-ready? out))   ; ...but half a character is not a ready char
         (char=? #\é (read-char out)) ; blocks exactly until 0xA9 lands
         (= 0 (process-wait p))
         (eq? #t (char-ready? out))   ; EOF still ready
         (eq? #t (u8-ready? out))
         (eof-object? (read-char out)))))

;; kaappi#2516 review: a custom port whose read! delegates to the pipe has
;; no readiness contract — the pre-review #t let read-char block inside
;; the callback. Chosen semantics (port_readiness.zig): #f unless a
;; character is already buffered, or read! is absent; probing would mean
;; invoking user code from a predicate. Data arriving on the underlying
;; pipe changes nothing (still unknowable), a read through the custom port
;; buffers the burst and turns the predicates #t, and at EOF the read
;; answers eof-object at once.
(test-assert "custom port readiness: #f until a character is buffered"
  (let* ((p (spawn-process (list "/bin/sh" "-c" "sleep 5; echo late")
                           'stdout: 'pipe))
         (out (process-stdout p))
         (cp (make-custom-binary-input-port
              "cp"
              (lambda (bv start count)
                ;; Bounded on purpose: kaappi's read-bytevector! fills the
                ;; whole requested span or blocks, so the callback must cap
                ;; its own burst (a real custom-port author does the same).
                (let ((n (read-bytevector! bv out start (+ start 1))))
                  (if (eof-object? n) 0 n)))
              #f #f #f)))
    (and (eq? #f (char-ready? cp))
         (eq? #f (u8-ready? cp))
         (string=? "late" (read-line out)) ; data arrives on the pipe...
         (eq? #f (char-ready? cp))         ; ...read!'s readiness is still unknowable
         (= 0 (process-wait p))
         (eof-object? (read-char cp)))))   ; and a read answers EOF at once

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
