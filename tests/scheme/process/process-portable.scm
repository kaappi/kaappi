;; (kaappi process): the platform-independent matrix — KEP-0022 Phase 3.
;;
;; The Phase 1/2 suites next to this one drive POSIX children (/bin/sh, cat,
;; kill -9), so they say nothing about Windows. This file re-runs the same
;; contract with *kaappi itself* as the child: exit codes, the three
;; redirections, pipes in both directions, argv quoting, env:, timeout:,
;; fiber non-starvation, and the tree kill — every one of them through the
;; real spawn path of whichever OS is running it.
;;
;; Using kaappi as the child is what makes that possible: there is no program
;; both a bare POSIX box and a bare Windows box are guaranteed to have, but
;; the binary under test is by definition present. run-all.sh exports KAAPPI;
;; the suite skips cleanly without it (ad-hoc runs).

(import (scheme base) (scheme write) (scheme file) (scheme process-context) (srfi 64))

;; Gate before the import: on WASM there is no subprocess support at all, so
;; this exits 0 before `spawn-process` is ever referenced, and kaappi
;; compiles forms one at a time so the later unbound references never compile.
(cond-expand
  ((library (kaappi process))
   (import (kaappi process) (kaappi fibers) (srfi 18)))
  (else (display "no (kaappi process) on this platform\n") (exit 0)))

(define kaappi-binary (get-environment-variable "KAAPPI"))

(when (not kaappi-binary)
  (display "KAAPPI not set; skipping the portable process matrix\n")
  (exit 0))

;; --------------------------------------------------------------- fixtures

(define scratch
  (or (get-environment-variable "KAAPPI_HOME")
      (get-environment-variable "TMPDIR")
      (get-environment-variable "TEMP")
      "/tmp"))

;; Forward slashes are accepted by both platforms' path resolvers, so one
;; join works everywhere.
(define (scratch-path name) (string-append scratch "/" name))

(define (write-script name text)
  (let ((path (scratch-path name)))
    (call-with-output-file path (lambda (port) (write-string text port)))
    path))

;; (command-line) is (script-path arg ...), so a child's own arguments start
;; at index 1.
(define exit-script
  (write-script "kaappi-2416-exit.scm"
    "(import (scheme base) (scheme process-context))
     (exit (string->number (cadr (command-line))))"))

(define echo-script
  (write-script "kaappi-2416-echo.scm"
    "(import (scheme base) (scheme write) (scheme process-context))
     (let ((args (cdr (command-line))))
       (write-string (car args)) (newline)
       (flush-output-port (current-output-port))
       (write-string (cadr args) (current-error-port)) (newline (current-error-port))
       (flush-output-port (current-error-port)))"))

;; Reads stdin to EOF, echoing each line — so the *parent* decides when this
;; child exits, with no sleeps anywhere in an assertion path.
(define cat-script
  (write-script "kaappi-2416-cat.scm"
    "(import (scheme base) (scheme write))
     (let loop ()
       (let ((line (read-line)))
         (unless (eof-object? line)
           (write-string line) (newline)
           (flush-output-port (current-output-port))
           (loop))))"))

(define sleep-script
  (write-script "kaappi-2416-sleep.scm"
    "(import (scheme base) (srfi 18))
     (let loop () (thread-sleep! 1) (loop))"))

(define args-script
  (write-script "kaappi-2416-args.scm"
    "(import (scheme base) (scheme write) (scheme process-context))
     (write (cdr (command-line))) (newline)
     (flush-output-port (current-output-port))"))

(define env-script
  (write-script "kaappi-2416-env.scm"
    "(import (scheme base) (scheme write) (scheme process-context))
     (write-string (or (get-environment-variable \"KAAPPI_2416\") \"unset\")) (newline)
     (flush-output-port (current-output-port))"))

;; Spawns a grandchild that inherits *this* process's stdout — so the
;; parent's read end only reaches EOF once the grandchild is dead too. That
;; is the whole tree-kill assertion, and it needs no way to name the
;; grandchild's pid.
(define tree-script
  (write-script "kaappi-2416-tree.scm"
    "(import (scheme base) (scheme write) (scheme process-context)
             (kaappi process) (srfi 18))
     (let ((args (cdr (command-line))))
       (spawn-process (list (car args) (cadr args)))
       (write-string \"child-up\") (newline)
       (flush-output-port (current-output-port))
       (let loop () (thread-sleep! 1) (loop)))"))

(define (run script . args) (cons kaappi-binary (cons script args)))

;; Windows has no signal delivery: `signal:` folds into the exit code
;; TerminateProcess stamps (128 + n, the shell convention), so a killed child
;; reports an integer where POSIX reports `(signaled . n)`.
(define (killed-status sig)
  (cond-expand (windows (+ 128 sig))
               (else (cons 'signaled sig))))

(test-begin "kaappi-process-portable")

;; -------------------------------------------------- spawn / wait / status

(test-equal "exit 0" 0 (process-wait (spawn-process (run exit-script "0"))))
(test-equal "a nonzero exit code propagates" 7 (process-wait (spawn-process (run exit-script "7"))))

(test-assert "status is #f while running, the code after, and a re-wait returns the stored one"
  ;; The child blocks on its stdin pipe, so the pre-exit poll cannot race its
  ;; exit (process-status reaps on its own, so an exited child would report a
  ;; code rather than #f).
  (let* ((p (spawn-process (run cat-script) 'stdin: 'pipe 'stdout: 'null))
         (s1 (process-status p)))
    (close-output-port (process-stdin p))
    (let* ((w1 (process-wait p))
           (s2 (process-status p))
           (w2 (process-wait p)))
      (and (eq? s1 #f) (= w1 0) (= s2 0) (= w2 0)))))

(test-assert "process? and the pid/group accessors"
  (let ((p (spawn-process (run exit-script "0"))))
    (process-wait p)
    (and (process? p)
         (exact-integer? (process-pid p))
         (positive? (process-pid p))
         (eq? #f (process-group p)))))

;; ------------------------------------------------------------ redirection

(test-equal "stdout: 'pipe captures the child's output"
  "out-line"
  (let ((p (spawn-process (run echo-script "out-line" "err-line") 'stdout: 'pipe 'stderr: 'null)))
    (let ((line (read-line (process-stdout p))))
      (process-wait p)
      line)))

(test-equal "stderr: 'pipe is a separate stream"
  '("out-line" "err-line")
  (let ((p (spawn-process (run echo-script "out-line" "err-line") 'stdout: 'pipe 'stderr: 'pipe)))
    (let ((o (read-line (process-stdout p)))
          (e (read-line (process-stderr p))))
      (process-wait p)
      (list o e))))

(test-assert "stderr: 'stdout merges both streams onto one pipe"
  (let ((p (spawn-process (run echo-script "first" "second") 'stdout: 'pipe 'stderr: 'stdout)))
    (let* ((a (read-line (process-stdout p)))
           (b (read-line (process-stdout p))))
      (process-wait p)
      (and (eq? #f (process-stderr p))
           (string=? a "first")
           (string=? b "second")))))

(test-assert "'null discards the stream and leaves the accessor #f"
  (let ((p (spawn-process (run echo-script "gone" "gone") 'stdout: 'null 'stderr: 'null)))
    (and (eq? #f (process-stdout p))
         (eq? #f (process-stderr p))
         (= 0 (process-wait p)))))

(test-equal "stdin: 'pipe feeds the child, and closing it is what ends the child"
  '("alpha" "beta")
  (let ((p (spawn-process (run cat-script) 'stdin: 'pipe 'stdout: 'pipe)))
    (write-string "alpha\nbeta\n" (process-stdin p))
    (flush-output-port (process-stdin p))
    (let* ((a (read-line (process-stdout p)))
           (b (read-line (process-stdout p))))
      (close-output-port (process-stdin p))
      (process-wait p)
      (list a b))))

;; --------------------------------------------------------- argv integrity

;; Windows has no argv vector: CreateProcess takes one command line, and the
;; child's C runtime parses it back with CommandLineToArgvW's rules. An
;; argument carrying a space, a double quote and a backslash is exactly what
;; a naive join corrupts, so this is the round trip that proves the encoder.
(test-equal "argv survives spaces, quotes and backslashes unchanged"
  '("a b" "say \"hi\"" "back\\slash" "trailing\\")
  (let ((p (spawn-process (run args-script "a b" "say \"hi\"" "back\\slash" "trailing\\")
                          'stdout: 'pipe)))
    (let ((line (read-line (process-stdout p))))
      (process-wait p)
      (read (open-input-string line)))))

;; --------------------------------------------------------------- env:

(test-equal "env: extends the inherited environment for the child"
  "phase-three"
  ;; Copy-and-extend, the idiom (process-environment) exists for: a wholesale
  ;; replacement that dropped the platform's own variables would leave the
  ;; child unable to start at all on Windows.
  (let ((p (spawn-process (run env-script)
                          'stdout: 'pipe
                          'env: (cons (cons "KAAPPI_2416" "phase-three")
                                      (process-environment)))))
    (let ((line (read-line (process-stdout p))))
      (process-wait p)
      line)))

(test-equal "without env: the variable is simply absent"
  "unset"
  (let ((p (spawn-process (run env-script) 'stdout: 'pipe)))
    (let ((line (read-line (process-stdout p))))
      (process-wait p)
      line)))

;; ------------------------------------------------------- kill and timeout

(test-equal "process-kill defaults to SIGTERM's encoding"
  (killed-status 15)
  (let ((p (spawn-process (run sleep-script))))
    (process-kill p)
    (process-wait p)))

(test-equal "process-kill 'signal: 9"
  (killed-status 9)
  (let ((p (spawn-process (run sleep-script))))
    (process-kill p 'signal: 9)
    (process-wait p)))

(test-assert "a kill after the reap is a quiet no-op"
  (let ((p (spawn-process (run exit-script "0"))))
    (process-wait p)
    (process-kill p)
    (= 0 (process-status p))))

(test-assert "timeout: expires to #f with the child still alive; a later kill reaps it"
  (let ((p (spawn-process (run sleep-script))))
    (and (eq? #f (process-wait p 'timeout: 0.05))
         (eq? #f (process-status p))
         (begin (process-kill p 'signal: 9)
                (equal? (killed-status 9) (process-wait p))))))

;; ------------------------------------------------------ fiber cooperation

;; KEP-0001 acceptance pattern: the wait can only resolve after the sibling
;; has run 11 turns — its 11th turn is what closes the child's stdin. Under a
;; blocking wait this deadlocks; under the parking wait the sibling keeps
;; running while the main fiber is parked on child-exit readiness.
(test-assert "a slow child does not starve a sibling fiber"
  (let ((p (spawn-process (run cat-script) 'stdin: 'pipe 'stdout: 'null))
        (counter 0))
    (spawn (lambda ()
             (let loop ((i 0))
               (set! counter (+ counter 1))
               (if (< i 10)
                   (begin (yield) (loop (+ i 1)))
                   (close-port (process-stdin p))))))
    (and (= 0 (process-wait p))
         (>= counter 11))))

;; ------------------------------------------------------------- tree kill

;; The acceptance criterion of kaappi#2416: after a group kill the
;; *grandchild* is dead too. It holds the same stdout pipe the child does, so
;; the read end reaches EOF only once every descendant is gone — no way to
;; name the grandchild's pid is needed, and the assertion works identically on
;; a POSIX process group and a Windows Job Object.
;;
;; The read runs in a fiber so a failed tree kill times out and reports
;; instead of hanging the suite.
(test-assert "'new-group: #t + 'group: #t kills the grandchild, not just the child"
  (let ((p (spawn-process (run tree-script kaappi-binary sleep-script)
                          'stdout: 'pipe 'new-group: #t)))
    (let ((out (process-stdout p))
          (state 'reading))
      ;; The child announces itself only after the grandchild exists, so
      ;; reading this line orders the kill after the tree is built.
      (let ((first (read-line out)))
        (and
         (string=? first "child-up")
         ;; A real group: the leader's id is its own pid on both platforms.
         (equal? (process-group p) (process-pid p))
         (begin
           (process-kill p 'group: #t)
           (equal? (killed-status 15) (process-wait p))
           (spawn (lambda ()
                    (let loop ()
                      (let ((line (read-line out)))
                        (if (eof-object? line)
                            (set! state 'eof)
                            (loop))))))
           (let poll ((i 0))
             (cond ((eq? state 'eof) #t)
                   ((> i 400) #f)   ; ~4s: the grandchild still holds the pipe
                   (else (thread-sleep! 0.01) (poll (+ i 1))))))))) ))

(let ((runner (test-runner-current)))
  (test-end "kaappi-process-portable")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
