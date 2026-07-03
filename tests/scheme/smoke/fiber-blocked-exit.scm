;; Regression test: a program whose worker fibers are still blocked on
;; channel-receive when the main program ends must exit cleanly.
;;
;; Fibers only run while the main program blocks or yields; when the main
;; program finishes, blocked fibers are discarded (Go-style). Previously a
;; worker's blocked receive returned an unspecified value instead, so a
;; sentinel-less worker loop spun forever and the process never exited
;; (this test then times out).

(import (scheme base)
        (scheme write))

(define work (make-channel))
(define done (make-channel))

;; Worker with no stop sentinel: after draining the two jobs it blocks on
;; channel-receive forever.
(define worker
  (spawn (lambda ()
    (let loop ((acc '()))
      (let ((v (channel-receive work)))
        (when (= (length (cons v acc)) 2)
          (channel-send done (reverse (cons v acc))))
        (loop (cons v acc)))))))

(channel-send work 'a)
(channel-send work 'b)

(let ((jobs (channel-receive done)))
  (unless (equal? jobs '(a b))
    (error "worker did not process jobs" jobs)))

(display "1 passed, 0 failed")
(newline)
;; Reaching here with the worker still parked on `work` must not prevent
;; process exit.
