;; (kaappi process): the one-shot `run-process` layer — KEP-0022 Phase 4.
;;
;; Same portability trick as process-portable.scm next door: the child is
;; *kaappi itself*, the one program guaranteed to exist on a bare POSIX box
;; and a bare Windows box alike, so every assertion here runs on both tiers.
;; run-all.sh exports KAAPPI; the suite skips cleanly without it.

(import (scheme base) (scheme write) (scheme file) (scheme process-context) (srfi 64))

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
  ;; 64 KiB is past every platform's pipe buffer, so the feed really does
  ;; fail; the child's exit status is the verdict, not the broken pipe.
  (call-with-values
      (lambda () (run-process (run deaf-script) 'input: (make-string 65536 #\x)))
    (lambda (st out err) st)))

;; --------------------------------------------------- concurrent draining

;; The deadlock this whole API exists to avoid: stdin, stdout and stderr all
;; past the pipe buffer at the same time. Feed-then-read, or read-stdout-
;; then-stderr, hangs forever here.
(test-equal "stdin, stdout and stderr all move at once"
  (list 0 40000 40000)
  (call-with-values
      (lambda () (run-process (run flood-script "40000")
                              'input: (make-string 40000 #\i)))
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

(test-assert "a program that does not exist is a file error, not a timeout"
  (guard (e (#t (and (file-error? e) (not (process-timeout? e)))))
    (run-process '("kaappi-no-such-program-2417"))
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

;; Two calls, each with a child that outlives the other's start: if either
;; call's drain fibers blocked the other's wait, the pair would take twice as
;; long. The bound is generous — this is a "did they overlap at all" check,
;; not a benchmark.
(test-assert "two run-process calls in sibling fibers overlap"
  (let* ((sleeper (lambda ()
                    (spawn (lambda ()
                             (call-with-values
                                 (lambda () (run-process (run stall-script "x") 'timeout: 0.6))
                               (lambda (st out err) out))))))
         (t0 (current-jiffy))
         (a (sleeper))
         (b (sleeper))
         (finish (lambda (f) (guard (e ((process-timeout? e) (process-timeout-stdout e)))
                               (fiber-join f))))
         (ra (finish a))
         (rb (finish b))
         (dt (/ (- (current-jiffy) t0) (jiffies-per-second))))
    (and (string=? ra "x") (string=? rb "x") (< dt 1.1))))

(let ((runner (test-runner-current)))
  (test-end "kaappi-process-run")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
