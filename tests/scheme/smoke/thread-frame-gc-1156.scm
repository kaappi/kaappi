;; Regression test for #1156: GC crash on stale fiber frame closure pointer.
;; OS thread fibers had a dead frame[0] with a raw *Closure that became
;; stale under gc-stress. Exercises multiple thread start/join cycles
;; with timeout patterns to reproduce the original allocation pressure.

(import (scheme base) (scheme write) (srfi 18))

(define (run-test)
  ;; Basic start/join cycle
  (let ((t (make-thread (lambda () 'done))))
    (thread-start! t)
    (let ((r (thread-join! t)))
      (unless (eq? r 'done)
        (error "basic join failed" r))))

  ;; Timeout join then successful join (the pattern from the crash)
  (let ((t (make-thread (lambda () (thread-sleep! 0.3) 'slow))))
    (thread-start! t)
    (let ((r (thread-join! t 0.01 'timeout)))
      (unless (eq? r 'timeout)
        (error "timeout join failed" r)))
    (let ((r (thread-join! t)))
      (unless (eq? r 'slow)
        (error "re-join failed" r))))

  ;; Multiple cycles to increase allocation pressure
  (let loop ((i 0))
    (when (< i 5)
      (let ((t (make-thread (lambda () (+ i 1)))))
        (thread-start! t)
        (let ((r (thread-join! t)))
          (unless (= r (+ i 1))
            (error "cycle join failed" i r))))
      (loop (+ i 1)))))

(run-test)
(display "thread-frame-gc-1156: PASS")
(newline)
