;; (kaappi process): the one-shot `run-process` layer — KEP-0022 Phase 4.
;;
;; Same portability trick as process-portable.scm next door: the child is
;; *kaappi itself*, the one program guaranteed to exist on a bare POSIX box
;; and a bare Windows box alike, so every assertion here runs on both tiers.
;; run-all.sh exports KAAPPI; the suite skips cleanly without it.

(import (scheme base) (scheme write) (scheme file) (scheme process-context)
        (scheme time) (srfi 64))

;; Gate before the import: on WASM there is no subprocess support at all, so
;; this exits 0 before `run-process` is ever referenced, and kaappi compiles
;; forms one at a time so the later unbound references never compile.
(cond-expand
  ((library (kaappi process))
   (import (kaappi process) (kaappi fibers)))
  (else (display "no (kaappi process) on this platform\n") (exit 0)))

(define kaappi-binary (get-environment-variable "KAAPPI"))

(when (not kaappi-binary)
  (display "KAAPPI not set; skipping the run-process suite\n")
  (exit 0))

(define scratch
  (or (get-environment-variable "KAAPPI_HOME")
      (get-environment-variable "TMPDIR")
      (get-environment-variable "TEMP")
      "/tmp"))

(define (scratch-path name) (string-append scratch "/" name))

(define (write-script name text)
  (let ((path (scratch-path name)))
    (call-with-output-file path (lambda (port) (write-string text port)))
    path))

;; Writes its first argument to stdout and its second to stderr, then exits
;; with the third — the whole (values status out err) contract in one child.
(define say-script
  (write-script "kaappi-2417-say.scm"
    "(import (scheme base) (scheme write) (scheme process-context))
     (let ((args (cdr (command-line))))
       (write-string (car args))
       (write-string (cadr args) (current-error-port))
       (flush-output-port (current-output-port))
       (flush-output-port (current-error-port))
       (exit (string->number (caddr args))))"))

;; Copies stdin to stdout, byte for byte, to EOF.
(define cat-script
  (write-script "kaappi-2417-cat.scm"
    "(import (scheme base))
     (let loop ()
       (let ((b (read-u8)))
         (unless (eof-object? b)
           (write-u8 b)
           (loop))))
     (flush-output-port (current-output-port))"))

;; Reads nothing and exits at once: the parent's feed hits EPIPE mid-write.
(define deaf-script
  (write-script "kaappi-2417-deaf.scm"
    "(import (scheme base) (scheme process-context))
     (exit 0)"))

;; Emits n bytes on stdout and n on stderr *after* draining stdin, so the
;; only way through is to feed and drain all three at once.
(define flood-script
  (write-script "kaappi-2417-flood.scm"
    "(import (scheme base) (scheme process-context))
     (let loop () (unless (eof-object? (read-u8)) (loop)))
     (let ((n (string->number (cadr (command-line))))
           (out (current-output-port))
           (err (current-error-port)))
       (let loop ((i 0))
         (when (< i n)
           (write-u8 111 out)
           (write-u8 101 err)
           (loop (+ i 1))))
       (flush-output-port out)
       (flush-output-port err))"))

;; Prints, then blocks forever — the timeout fixture.
(define stall-script
  (write-script "kaappi-2417-stall.scm"
    "(import (scheme base) (srfi 18))
     (write-string (cadr (command-line)))
     (flush-output-port (current-output-port))
     (let loop () (thread-sleep! 1) (loop))"))

;; Spawns a grandchild that inherits this process's stdout and then stalls:
;; the parent's read end reaches EOF only once the whole tree is dead, so a
;; child-only kill would hang the drain instead of returning.
(define tree-script
  (write-script "kaappi-2417-tree.scm"
    "(import (scheme base) (scheme process-context) (kaappi process) (srfi 18))
     (let ((args (cdr (command-line))))
       (spawn-process (list (car args) (cadr args) \"\"))
       (write-string \"up\")
       (flush-output-port (current-output-port))
       (let loop () (thread-sleep! 1) (loop)))"))

(define (run script . args) (cons kaappi-binary (cons script args)))

(test-begin "kaappi-process-run")

;; ------------------------------------------------------------ three values

(test-equal "status, stdout and stderr come back as three values"
  '(3 "to-out" "to-err")
  (call-with-values
      (lambda () (run-process (run say-script "to-out" "to-err" "3")))
    list))

(test-equal "a clean exit reports 0 and empty strings"
  '(0 "" "")
  (call-with-values (lambda () (run-process (run say-script "" "" "0"))) list))

;; ------------------------------------------------------------------ input:

(test-equal "input: feeds the child as a string"
  "round trip"
  (call-with-values (lambda () (run-process (run cat-script) 'input: "round trip"))
    (lambda (st out err) out)))

(test-equal "input: accepts a bytevector"
  "bytes"
  (call-with-values
      (lambda () (run-process (run cat-script) 'input: (string->utf8 "bytes")))
    (lambda (st out err) out)))

(test-equal "stdin is empty, not inherited, when input: is omitted"
  '(0 "")
  (call-with-values (lambda () (run-process (run cat-script)))
    (lambda (st out err) (list st out))))

(test-equal "a child that never reads its stdin is not an error"
  0
  ;; 256 KiB, not 64: Linux's default pipe capacity is *exactly* 65536, so a
  ;; 64 KiB feed can land in the buffer whole and never break at all -- the
  ;; assertion would then pass without the swallow it exists to check.
  ;; Unaffected by kaappi#2459: the child is gone before the second write,
  ;; so the quota query fails outright and the write surfaces the real error
  ;; instead of parking.
  (call-with-values
      (lambda () (run-process (run deaf-script) 'input: (make-string 262144 #\x)))
    (lambda (st out err) st)))

;; --------------------------------------------------- concurrent draining

;; The deadlock this whole API exists to avoid: stdin, stdout and stderr all
;; past the pipe buffer at the same time. Feed-then-read, or read-stdout-
;; then-stderr, hangs forever here.
;;
;; The stdin leg is capped at the pipe buffer on Windows: a write past it
;; from a fiber-scheduled program hangs there outright (kaappi#2459 — the
;; `WriteQuotaAvailable` readiness query reads 0 both when the pipe is full
;; and when a reader is waiting, and the writer parks on a number that never
;; moves). Both *output* legs stay at full size on every platform, so what
;; is lost on Windows is the stdin half of the assertion, not the test.
(define feed-size (cond-expand (windows 4096) (else 40000)))

(test-equal "stdin, stdout and stderr all move at once"
  (list 0 40000 40000)
  (call-with-values
      (lambda () (run-process (run flood-script "40000")
                              'input: (make-string feed-size #\i)))
    (lambda (st out err) (list st (string-length out) (string-length err)))))

;; ----------------------------------------------------------------- output:

(test-equal "output: 'bytevector returns raw bytes"
  #u8(104 105)
  (call-with-values
      (lambda () (run-process (run say-script "hi" "" "0") 'output: 'bytevector))
    (lambda (st out err) out)))

;; ------------------------------------------------------- env: / directory:

(test-equal "env: reaches the child"
  "phase-four"
  (call-with-values
      (lambda ()
        (run-process (run (write-script "kaappi-2417-env.scm"
                            "(import (scheme base) (scheme process-context))
                             (write-string (or (get-environment-variable \"KAAPPI_2417\") \"unset\"))
                             (flush-output-port (current-output-port))"))
                     'env: (cons (cons "KAAPPI_2417" "phase-four") (process-environment))))
    (lambda (st out err) out)))

;; ----------------------------------------------------------------- timeout:

(test-assert "a child finishing inside its timeout returns normally"
  (call-with-values (lambda () (run-process (run say-script "in-time" "" "0") 'timeout: 60))
    (lambda (st out err) (and (= st 0) (string=? out "in-time")))))

(test-assert "timeout: raises process-timeout carrying the partial output"
  (guard (e ((process-timeout? e)
             (and (string=? (process-timeout-stdout e) "printed")
                  (string=? (process-timeout-stderr e) "")
                  (error-object? e))))
    (run-process (run stall-script "printed") 'timeout: 0.25)
    #f))

;; Reaching the guard clause at all is the assertion: the grandchild holds
;; the same stdout pipe, so only a group kill lets the drain reach EOF. A
;; child-only kill hangs here instead of raising.
(test-assert "the timeout kill reaches a grandchild holding the same pipe"
  (guard (e ((process-timeout? e) (string=? (process-timeout-stdout e) "up")))
    (run-process (run tree-script kaappi-binary stall-script) 'timeout: 0.5)
    #f))

;; ------------------------------------------------------------------ errors

;; An absolute path, deliberately kept as its own assertion alongside the
;; bare-name one below: a path has exactly one candidate file, so the
;; failure is attributed at the spawn on every platform by construction.
(test-assert "a program that does not exist is a file error, not a timeout"
  (guard (e (#t (and (file-error? e) (not (process-timeout? e)))))
    (run-process '("/kaappi/no/such/program/2417"))
    #f))

;; The bare-name case. POSIX leaves it unspecified whether a PATH search
;; that finds nothing fails at posix_spawnp or lets the child exec fail
;; and exit 127, and OpenBSD's libc took the second option — so this used
;; to be pinned leniently (an error, or a non-zero status with no
;; output). Since kaappi#2456 that platform spawns through fork+exec
;; with a CLOEXEC error pipe, and the strict contract holds everywhere:
;; a miss is a file error at the spawn, never an ordinary exit status a
;; program that really ran could also have produced.
(test-assert "a bare name that resolves to nothing is a file error"
  (guard (e (#t (file-error? e))
            (else #f))
    (run-process '("kaappi-no-such-program-2417"))
    #f))

;; `timeout:` promises a bound, and a child-only kill cannot deliver one: a
;; grandchild holding the pipes would keep the drains from ever reaching EOF,
;; and process-kill refuses 'group: on a child sharing our own group. The
;; combination is refused rather than silently unbounded.
(test-assert "timeout: with an explicit new-group: #f is refused, not unbounded"
  (guard (e ((process-timeout? e) #f) (#t #t))
    (run-process (run stall-script "x") 'timeout: 0.25 'new-group: #f)
    #f))

(test-assert "option errors are loud"
  (let ((bad (lambda (thunk) (guard (e (#t #t)) (thunk) #f))))
    (and (bad (lambda () (run-process (run say-script "" "" "0") 'nonsense: 1)))
         (bad (lambda () (run-process (run say-script "" "" "0") 'input:)))
         (bad (lambda () (run-process (run say-script "" "" "0") 'input: 42)))
         (bad (lambda () (run-process (run say-script "" "" "0") 'output: 'utf16))))))

(test-assert "the accessors reject every other condition"
  (let ((plain (guard (e (#t e)) (error "plain"))))
    (and (not (process-timeout? plain))
         (not (process-timeout? 42))
         (guard (e (#t #t)) (process-timeout-stdout plain) #f))))

;; ---------------------------------------------------- fiber cooperation

;; Two calls whose children outlive each other's start. The assertion is
;; that their lifetimes *intersect*, not that the pair finishes inside a
;; wall-clock budget: a budget reports a concurrency bug whenever a shared
;; CI runner is merely slow, which is exactly what it did on macOS. A
;; serialized implementation gives disjoint intervals however slow the
;; machine is, since the second call could not start until the first
;; returned.
(define (now) (/ (current-jiffy) (jiffies-per-second)))

(test-assert "two run-process calls in sibling fibers overlap"
  (let* ((sleeper (lambda ()
                    (spawn (lambda ()
                             (let* ((t0 (now))
                                    (r (guard (e ((process-timeout? e)
                                                  (process-timeout-stdout e)))
                                         (call-with-values
                                             (lambda () (run-process (run stall-script "x")
                                                                     'timeout: 0.6))
                                           (lambda (st out err) out)))))
                               (list t0 (now) r))))))
         ;; Both spawned before either is joined; joining the first would
         ;; serialize them by hand and make the assertion unsatisfiable.
         (fa (sleeper))
         (fb (sleeper))
         (a (fiber-join fa))
         (b (fiber-join fb)))
    (and (string=? (caddr a) "x")
         (string=? (caddr b) "x")
         (< (car a) (cadr b))
         (< (car b) (cadr a)))))

(let ((runner (test-runner-current)))
  (test-end "kaappi-process-run")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
