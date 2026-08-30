;; (kaappi process) — Phase 1 end-to-end tests (KEP-0022, kaappi#2414).
;;
;; POSIX only: run-all.sh runs the native binary, and the library is present on
;; every POSIX target. Driven against portable helpers (sh, printf, cat, ls).

(import (scheme base) (scheme write) (kaappi process) (srfi 64))

(test-begin "kaappi-process")

;; The cond-expand (library ...) gate is true on this (POSIX) build.
(test-assert "library present via cond-expand"
  (cond-expand ((library (kaappi process)) #t) (else #f)))

(define (drain port)
  (let loop ((acc '()))
    (let ((b (read-u8 port)))
      (if (eof-object? b)
          (list->string (map integer->char (reverse acc)))
          (loop (cons b acc))))))

;; Naive substring test (no (srfi 13) dependency), used to recognise the
;; specific "directory: unsupported" error on NetBSD/OpenBSD.
(define (substring? needle hay)
  (let ((nl (string-length needle)) (hl (string-length hay)))
    (let loop ((i 0))
      (cond ((> (+ i nl) hl) #f)
            ((string=? needle (substring hay i (+ i nl))) #t)
            (else (loop (+ i 1)))))))

;; --- exit-status matrix -----------------------------------------------------
(test-equal "exit 0" 0 (process-wait (spawn-process '("sh" "-c" "exit 0"))))
(test-equal "exit 42" 42 (process-wait (spawn-process '("sh" "-c" "exit 42"))))

;; --- predicate & accessors --------------------------------------------------
(test-assert "process? on a process"
  (let ((p (spawn-process '("sh" "-c" "exit 0"))))
    (let ((ok (process? p))) (process-wait p) ok)))
(test-assert "process? on a non-process" (not (process? 5)))
(test-assert "positive pid"
  (let ((p (spawn-process '("sh" "-c" "exit 0"))))
    (let ((ok (> (process-pid p) 0))) (process-wait p) ok)))
(test-assert "inherit accessors are #f"
  (let ((p (spawn-process '("sh" "-c" "exit 0"))))
    (let ((ok (and (not (process-stdin p))
                   (not (process-stdout p))
                   (not (process-stderr p)))))
      (process-wait p) ok)))

;; --- pipes ------------------------------------------------------------------
(test-equal "capture stdout" "hello"
  (let ((p (spawn-process '("sh" "-c" "printf hello") 'stdout: 'pipe)))
    (let ((s (drain (process-stdout p)))) (process-wait p) s)))

(test-equal "bidirectional cat" "round-trip"
  (let ((p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'pipe)))
    (for-each (lambda (ch) (write-u8 (char->integer ch) (process-stdin p)))
              (string->list "round-trip"))
    (close-port (process-stdin p))
    (let ((s (drain (process-stdout p)))) (process-wait p) s)))

;; --- redirection matrix -----------------------------------------------------
(test-equal "stderr 'null discards; stdout kept" "OUT"
  (let ((p (spawn-process '("sh" "-c" "printf OUT; printf ERR 1>&2")
                          'stdout: 'pipe 'stderr: 'null)))
    (let ((s (drain (process-stdout p)))) (process-wait p) s)))

(test-assert "stderr 'null accessor is #f"
  (let ((p (spawn-process '("sh" "-c" "exit 0") 'stderr: 'null)))
    (let ((r (not (process-stderr p)))) (process-wait p) r)))

(test-equal "stderr 'stdout merge" "OE"
  (let ((p (spawn-process '("sh" "-c" "printf O; printf E 1>&2")
                          'stdout: 'pipe 'stderr: 'stdout)))
    (let ((s (drain (process-stdout p)))) (process-wait p) s)))

;; 'inherit must leave the child a working stream: writing to inherited stderr
;; succeeds (exit 0), it is not closed under it (the macOS
;; POSIX_SPAWN_CLOEXEC_DEFAULT regression would exit 7 on EBADF).
(test-equal "'inherit leaves the child a working stream" 0
  (process-wait (spawn-process '("sh" "-c" "printf x 1>&2 || exit 7")
                               'stderr: 'inherit)))

;; --- status encoding --------------------------------------------------------
;; SIGKILL is uncatchable, so the child always dies by the signal on every
;; platform; a shell can turn SIGTERM into a plain exit code (OpenBSD's /bin/sh
;; does), so drive the kill through Kaappi rather than `kill -TERM $$`.
(test-equal "signal death is (signaled . 9)" '(signaled . 9)
  (let ((p (spawn-process '("sleep" "60"))))
    (process-kill p 'signal: 9)
    (process-wait p)))

(test-assert "status is stable and wait is idempotent"
  (let ((p (spawn-process '("sh" "-c" "exit 4"))))
    (and (= 4 (process-wait p)) (= 4 (process-wait p)) (= 4 (process-status p)))))

;; --- directory: and env: ----------------------------------------------------
;; Strict where supported (asserts the child's cwd is "/"); on NetBSD/OpenBSD,
;; where posix_spawn has no chdir file action, spawn-process raises a specific
;; "directory: is not supported" error, which we accept — but only that one, so
;; a real regression elsewhere still fails.
(test-assert "directory: changes cwd (unsupported platforms excepted)"
  (guard (e ((and (error-object? e)
                  (substring? "directory: is not supported" (error-object-message e)))
             #t))
    (let ((p (spawn-process '("sh" "-c" "pwd") 'stdout: 'pipe 'directory: "/")))
      (let ((s (drain (process-stdout p)))) (process-wait p) (string=? s "/\n")))))

(test-equal "env: replaces the environment wholesale" "kaappi-2414"
  (let ((p (spawn-process '("sh" "-c" "printf %s \"$KP_TEST_VAR\"")
                          'stdout: 'pipe
                          'env: '(("KP_TEST_VAR" . "kaappi-2414")
                                  ("PATH" . "/usr/bin:/bin")))))
    (let ((s (drain (process-stdout p)))) (process-wait p) s)))

(test-assert "process-environment is a non-empty alist"
  (let ((e (process-environment)))
    (and (pair? e) (pair? (car e)) (string? (caar e)) (string? (cdar e)))))

;; --- kill -------------------------------------------------------------------
(test-equal "kill terminates a child" '(signaled . 15)
  (let ((p (spawn-process '("sleep" "60"))))
    (process-kill p)
    (process-wait p)))

(test-assert "kill after reap is a no-op"
  (let ((p (spawn-process '("sh" "-c" "exit 0"))))
    (process-wait p)
    (process-kill p 'signal: 9)   ; must not error, must not re-signal
    (= 0 (process-status p))))

(test-assert "new-group: gives the child its own group; group kill works"
  (let ((p (spawn-process '("sleep" "60") 'new-group: #t)))
    (let ((own (= (process-group p) (process-pid p))))
      (process-kill p 'group: #t 'signal: 9)
      (and own (equal? '(signaled . 9) (process-wait p))))))

;; --- fd hygiene (CLOEXEC audit, kaappi#2414) --------------------------------
;; Absolute fd counts are not portable: a CI shell can hand kaappi extra
;; inherited descriptors that pass straight through to any child. What must
;; hold is that a descriptor *Kaappi itself* opens does not leak into a later
;; child. Measure a child's fd count with nothing extra held, then again while
;; a second child's pipe port is held open in the parent: that read end is
;; close-on-exec, so the two counts match — a leak would add exactly one.
(define (child-fd-count)
  (let ((p (spawn-process '("sh" "-c" "printf %s $(ls /dev/fd | wc -l)")
                          'stdout: 'pipe 'stderr: 'null)))
    (let ((n (string->number (drain (process-stdout p)))))
      (process-wait p)
      n)))

;; `ls /dev/fd | wc -l` only reflects the real descriptor table where /dev/fd
;; is procfs-backed (Linux, macOS). On FreeBSD's default fdescfs and on the
;; static /dev/fd nodes of NetBSD/OpenBSD it returns a constant regardless of
;; what is open, so the leak comparison below would pass vacuously. Prove the
;; mechanism is live first: a child that opens an extra descriptor (fd 9) must
;; see a higher count than one that does not. Skip the leak assertion when it
;; cannot — on those platforms the direct fcntl FD_CLOEXEC unit tests
;; (tests_process.zig) are the real coverage.
(define (fd-count-mechanism-live?)
  (let ((plain (child-fd-count))
        (extra (let ((p (spawn-process
                         '("sh" "-c" "exec 9>/dev/null; printf %s $(ls /dev/fd | wc -l)")
                         'stdout: 'pipe 'stderr: 'null)))
                 (let ((n (string->number (drain (process-stdout p)))))
                   (process-wait p) n))))
    (and plain extra (> extra plain))))

(test-assert "Kaappi-opened pipe fds do not leak into a later child"
  (if (not (fd-count-mechanism-live?))
      #t ; /dev/fd is not procfs-backed here; the probe cannot observe a leak
      (let ((baseline (child-fd-count)))
        (let ((holder (spawn-process '("sleep" "60") 'stdout: 'pipe)))
          (let ((held (child-fd-count)))
            (process-kill holder)
            (process-wait holder)
            (and baseline held (= held baseline)))))))

(let ((runner (test-runner-current)))
  (test-end "kaappi-process")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
