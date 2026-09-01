;; End-to-end tests for (kaappi process) — KEP-0022 Phase 1 (POSIX).
;;
;; Children are spawned through the portable POSIX helpers (/bin/sh, cat,
;; echo); the kaappi-as-a-child round trip lives in process-child-script.scm
;; and the OS-independent matrix in process-portable.scm. The whole file
;; skips where those children do not exist (Windows) or the library is
;; absent (WASM), via the cond-expand gates below.

(import (scheme base) (scheme write) (srfi 64))

;; Two gates, both before the first `spawn-process` reference (kaappi
;; compiles forms one at a time, so the later ones never compile either).
;; Windows first: since KEP-0022 Phase 3 the library IS present there, but
;; every child below is a POSIX program (/bin/sh, cat, kill -9), so the
;; portable matrix lives in process-portable.scm and the Windows-specific
;; mechanisms in src/tests_process_win.zig. Then the library gate, for WASM.
(cond-expand
  (windows
   (display "POSIX-only suite; Windows is covered by process-portable.scm\n")
   (exit 0))
  (else))
(cond-expand
  ((library (kaappi process))
   (import (kaappi process)))
  (else (display "no (kaappi process) on this platform\n") (exit 0)))

(test-begin "kaappi-process")

;; ---------------------------------------------------------------- helpers

(define (drain port)
  ;; Read every line of an output pipe into a list of strings.
  (let loop ((acc '()))
    (let ((line (read-line port)))
      (if (eof-object? line)
          (reverse acc)
          (loop (cons line acc))))))

;; ------------------------------------------------- spawn/wait/status matrix

(test-equal "exit 0"
  0 (process-wait (spawn-process '("true"))))

(test-equal "nonzero exit code propagates"
  7 (process-wait (spawn-process '("/bin/sh" "-c" "exit 7"))))

(test-assert "status is #f while running, code after; re-wait returns stored"
  ;; The child blocks on its stdin pipe, so the pre-exit poll cannot race
  ;; its exit (process-status reaps on its own, so an exited child would
  ;; report a code, not #f).
  (let* ((p (spawn-process '("/bin/sh" "-c" "read x; exit 3") 'stdin: 'pipe))
         (s1 (process-status p)))
    (write-string "go\n" (process-stdin p))
    (close-output-port (process-stdin p))
    (let* ((w1 (process-wait p))
           (s2 (process-status p))
           (w2 (process-wait p)))
      (and (eq? s1 #f) (= w1 3) (= s2 3) (= w2 3)))))

(test-assert "abnormal death is (signaled . n)"
  (let* ((p (spawn-process '("/bin/sh" "-c" "kill -9 $$")))
         (st (process-wait p)))
    (and (pair? st) (eq? (car st) 'signaled) (= (cdr st) 9))))

(test-assert "process-kill defaults to SIGTERM"
  (let* ((p (spawn-process '("/bin/sleep" "30")))
         (st (and (process-kill p) (process-wait p))))
    (and (pair? st) (= (cdr st) 15))))

(test-assert "kill after reap is a quiet no-op"
  (let* ((p (spawn-process '("true")))
         (st (process-wait p)))
    (and (= st 0) (process-kill p) (process-kill p 'signal: 9) #t)))

;; --------------------------------------------------------- pipes and specs

(test-equal "stdin/stdout pipe round trip via cat"
  '("round-trip")
  (let* ((p (spawn-process '("/bin/cat") 'stdin: 'pipe 'stdout: 'pipe))
         (in (process-stdin p))
         (out (process-stdout p)))
    (write-string "round-trip" in)
    (flush-output-port in)
    (close-output-port in)             ; EOF so cat can finish
    (let ((lines (drain out)))
      (process-wait p)
      lines)))

(test-equal "stderr 'stdout merges both streams onto the stdout pipe"
  '("out" "err")
  (let* ((p (spawn-process '("/bin/sh" "-c" "echo out; echo err 1>&2")
                           'stdout: 'pipe 'stderr: 'stdout)))
    (let ((lines (drain (process-stdout p))))
      (process-wait p)
      lines)))

(test-assert "non-pipe specs leave #f accessors"
  (let ((p (spawn-process '("true") 'stdout: 'null)))
    (and (eq? (process-stdin p) #f)
         (eq? (process-stdout p) #f)
         (eq? (process-stderr p) #f)
         (= (process-wait p) 0))))

;; ---------------------------------------------------------- env and groups

(test-equal "env: replaces the environment wholesale"
  '("one:two")
  (let* ((p (spawn-process '("/bin/sh" "-c" "echo $KAPVAR1:$KAPVAR2")
                           'stdout: 'pipe
                           'env: '(("KAPVAR1" . "one") ("KAPVAR2" . "two")))))
    (let ((lines (drain (process-stdout p))))
      (process-wait p)
      lines)))

(test-equal "env: '() is an empty environment, not inheritance"
  '("unset")
  (let* ((p (spawn-process '("/bin/sh" "-c" "echo ${HOME:-unset}")
                           'stdout: 'pipe 'env: '())))
    (let ((lines (drain (process-stdout p))))
      (process-wait p)
      lines)))

(test-assert "process-environment feeds copy-and-extend"
  (let* ((env (process-environment))
         (p (spawn-process '("/bin/sh" "-c" "echo $KAPNEW")
                           'stdout: 'pipe
                           'env: (append env '(("KAPNEW" . "extended"))))))
    (let ((lines (drain (process-stdout p))))
      (process-wait p)
      (equal? lines '("extended")))))

(test-assert "new-group: makes the child its own group leader"
  (let ((p (spawn-process '("true") 'new-group: #t)))
    (and (= (process-group p) (process-pid p))
         (= (process-wait p) 0))))

(test-assert "group kill reaches the whole group"
  ;; The child sh starts a sleeper grandchild in ITS group (setsid-free:
  ;; the child sh shares the new group), the group kill must terminate both.
  (let ((p (spawn-process '("/bin/sh" "-c" "sleep 30 & wait")
                          'new-group: #t)))
    (process-kill p 'group: #t)
    (let ((st (process-wait p)))
      (and (pair? st) (eq? (car st) 'signaled) (= (cdr st) 15)))))

;; ------------------------------------------------------------- predicates

(test-assert "process? is a total predicate"
  (and (process? (spawn-process '("true")))
       (not (process? 42))
       (not (process? "process"))
       (not (process? (open-input-string "s")))))

(test-assert "the printed form carries pid and state"
  (let* ((p (spawn-process '("true")))
         (sp1 (open-output-string)))
    (write p sp1)
    (let ((running (get-output-string sp1)))
      (process-wait p)
      (let* ((sp2 (open-output-string))
             (dead (begin (write p sp2) (get-output-string sp2))))
        (and (string-prefix? "#<process " running)
             (string-suffix? "running>" running)
             (string-suffix? "exited 0>" dead))))))

;; ------------------------------------------------------------- fd hygiene

(test-equal
  "a spawned child inherits only the three stdio slots"
  '()
  ;; Fresh kaappi process: every descriptor it holds is CLOEXEC (and the
  ;; spawner closes inherited strays), so the child must see nothing open at
  ;; 3..24. Openness is probed by duplicating the fd (`: <&N` in a subshell)
  ;; — a stat of /dev/fd/N would false-positive on the BSDs, where those
  ;; entries are static device nodes that exist whether or not the fd does.
  ;; Two probe-artifact guards: stderr goes to 'null rather than a
  ;; per-command `2>/dev/null`, and stdin is closed up front (`exec 0<&-`)
  ;; — bash implements a per-command redirection by parking the real
  ;; descriptor at fd 10+ for the command's duration, so probing `<&10`
  ;; while stdin is open would detect the shell's own save of it.
  (let* ((p (spawn-process
             '("/bin/sh" "-c"
               "exec 0<&-; i=3; while [ $i -le 24 ]; do if (eval \": <&$i\"); then echo $i; fi; i=$((i+1)); done")
             'stdout: 'pipe 'stderr: 'null)))
    (let ((lines (drain (process-stdout p))))
      (process-wait p)
      lines)))

;; ----------------------------------------------------------- error report

(test-assert "spawning a missing program raises a catchable file error"
  (guard (e ((file-error? e) #t)
            (else 'wrong-kind))
    (spawn-process '("/nonexistent/kaappi-process-test"))))

(let ((runner (test-runner-current)))
  (test-end "kaappi-process")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
