;; KEP-0022 Phase 2 (kaappi#2415): fiber-parking process-wait, timeout:,
;; group kill via the reactor's child-exit readiness.
;;
;; The exit-triggering idiom is `cat` on a stdin pipe — closing the pipe EOFs
;; the child, so a test controls *when* the exit happens (and from which
;; fiber) with no sleeps in the assertion path.

(import (scheme base) (scheme write) (srfi 64))

;; Gate before the import: on platforms without subprocess support (WASM;
;; Windows until KEP-0022 Phase 3) this exits 0 before `spawn-process` is
;; ever referenced.
(cond-expand
  ((library (kaappi process))
   (import (kaappi process) (kaappi fibers)))
  (else (display "no (kaappi process) on this platform\n") (exit 0)))

(test-begin "kaappi-process-wait")

;; ------------------------------------------------------- fiber starvation

;; KEP-0001 acceptance pattern: the wait can only resolve after the sibling
;; has run 11 turns — its 11th turn is what closes the child's stdin. Under
;; the Phase-1 blocking wait this deadlocks; under the fiber-parking wait the
;; sibling keeps running while the main fiber waits.
(test-assert "a slow child does not starve a sibling fiber"
  (let ((p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
        (counter 0))
    (spawn (lambda ()
             (let loop ((i 0))
               (set! counter (+ counter 1))
               (if (< i 10)
                   (begin (yield) (loop (+ i 1)))
                   (close-port (process-stdin p))))))
    (and (= 0 (process-wait p))
         (>= counter 11))))

;; ------------------------------------------------------- timeout contract

;; Python's contract: expiry returns #f and the child lives on; a later
;; process-kill + wait reaps it.
(test-assert "timeout: expires -> #f, child still running, kill, final wait reaps"
  (let ((p (spawn-process '("/bin/sleep" "30"))))
    (and (eq? #f (process-wait p 'timeout: 0.05))
         (eq? #f (process-status p))
         (begin (process-kill p)
                (equal? '(signaled . 15) (process-wait p))))))

(test-assert "delivery wins over a generous timeout"
  (let ((p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null)))
    (spawn (lambda () (close-port (process-stdin p))))
    (= 0 (process-wait p 'timeout: 30))))

(test-assert "timeout: #f means no timeout"
  (let ((p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null)))
    (spawn (lambda () (close-port (process-stdin p))))
    (= 0 (process-wait p 'timeout: #f))))

;; -------------------------------------------------- waits from fibers

(test-assert "two fiber waiters are both woken with the same status"
  (let* ((p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
         (f1 (spawn (lambda () (process-wait p))))
         (f2 (spawn (lambda () (process-wait p))))
         (g  (spawn (lambda ()
                      (let loop ((i 0))
                        (if (< i 5)
                            (begin (yield) (loop (+ i 1)))
                            (close-port (process-stdin p))))))))
    (fiber-join g)
    (and (= 0 (fiber-join f1))
         (= 0 (fiber-join f2)))))

(test-assert "a dispatched fiber's timeout fires while the child lives"
  (let* ((p (spawn-process '("/bin/sleep" "30")))
         (f (spawn (lambda () (process-wait p 'timeout: 0.05)))))
    (and (eq? #f (fiber-join f))
         (eq? #f (process-status p))
         (begin (process-kill p 'signal: 9)
                (equal? '(signaled . 9) (process-wait p))))))

(test-assert "a sibling's process-status reap wakes a parked waiter"
  (let* ((p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
         (f (spawn (lambda () (process-wait p))))
         (g (spawn (lambda ()
                     (let loop ((i 0))
                       (cond ((process-status p) 'saw-it)
                             (else (when (= i 5) (close-port (process-stdin p)))
                                   (yield)
                                   (loop (+ i 1)))))))))
    (and (= 0 (fiber-join f))
         (eq? 'saw-it (fiber-join g)))))

;; ----------------------------------------------------------- group kill

;; The shell backgrounds a sleeper (its own child, same fresh process group)
;; and reports its pid; `group: #t` must bring both down. The grandchild's
;; death is observed via its pipe: `wait` keeps the shell alive until the
;; grandchild is gone, and the shell's own exit closes the stdout pipe.
(test-assert "group kill reaches the child's own child"
  (let* ((p (spawn-process '("/bin/sh" "-c" "sleep 30 & echo $!; wait")
                           'stdout: 'pipe 'new-group: #t))
         (gpid (string->number (read-line (process-stdout p)))))
    (and (integer? gpid)
         (begin (process-kill p 'group: #t)
                (let ((st (process-wait p)))
                  ;; the shell died by the signal (or exited after its own
                  ;; child was signaled — shell-dependent); either way the
                  ;; wait resolves promptly instead of running out the
                  ;; grandchild's 30-second sleep
                  (or (pair? st) (integer? st))))
         ;; stdout EOF proves the whole group is gone: the backgrounded
         ;; grandchild inherited the pipe's write end, so EOF arrives only
         ;; once BOTH the shell and the sleeper have died.
         (eof-object? (read-line (process-stdout p))))))

;; ------------------------------------------------------------ hygiene

(test-assert "re-waiting a reaped process returns the stored status"
  (let ((p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null)))
    (spawn (lambda () (close-port (process-stdin p))))
    (and (= 0 (process-wait p))
         (= 0 (process-wait p))
         (= 0 (process-status p))
         (= 0 (process-wait p 'timeout: 0.01)))))

(test-assert "process-wait option errors are loud"
  (let ((p (spawn-process '("true"))))
    (define (bad thunk) (guard (e (#t #t)) (thunk) #f))
    (and (bad (lambda () (process-wait p 'timeout:)))
         (bad (lambda () (process-wait p 'nonsense: 1)))
         (bad (lambda () (process-wait p 'timeout: 'soon)))
         (begin (process-wait p) #t))))

(let ((runner (test-runner-current)))
  (test-end "kaappi-process-wait")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
