;; SRFI-181 custom-port callback × fiber blocking (kaappi#2000).
;;
;; Why this file exists
;; --------------------
;; Every custom-port callback (read!/write!/get-position/set-position!/
;; close/flush) runs through vm.callWithArgs, which forces
;; dispatched_from_scheduler false. A fiber in that state cannot PARK, so a
;; blocking primitive reached from inside a callback had only one option
;; left: drive the scheduler recursively, in place, on the native stack.
;; vm.in_custom_port_callback exists to reject that -- but it used to be
;; read at exactly two sites (fiber.waitForFd, primitives_srfi18
;; .threadSleepFn), and channel-receive/channel-send/fiber-join and
;; SRFI-18's thread-join!/mutex-lock!/condition-variable-wait were not among
;; them. They drove.
;;
;; The rejection itself is pinned by the D5 blocks in
;; tests/scheme/audit/primitives_fiber-audit.scm and
;; tests/scheme/audit/primitives_srfi181-audit.scm. What is pinned HERE is
;; the consequence those cannot show: the drive NESTS. One native drive per
;; level, each a nested runUntil *plus* a runSchedulerStep -- so the OS stack
;; ran out long before callReentrant's own max_native_depth = 3000 guard
;; could fire (that cap is calibrated for a plain re-entrant call, which is
;; much cheaper per level). n fibers all reading one such port took the whole
;; process down with a bus error and exit 134 at n = 2500, while n = 2400 was
;; fine -- a cliff, not a limit anyone could design around.
;;
;; The guard now also sits in fiber.runSchedulerStep, the single shared body
;; behind every in-place drive, so a newly added blocking primitive is
;; covered without anyone remembering to add it here.
;;
;; A regression re-aborts the process rather than failing an assertion, which
;; is exactly the signal wanted: this file cannot report "0 failures" while
;; the bug is back.

(import (scheme base) (scheme write) (srfi 64) (srfi 181) (kaappi fibers))

(test-begin "srfi181-callback-drive-2000")

;; Well past the observed 2500-fiber cliff.
(define n 3000)

(define ch (make-channel))

;; read! blocks on an empty channel. Nothing is ever sent, so every reader
;; must be REJECTED; if any one of them drives instead, the next reader
;; nests inside it.
(define port
  (make-custom-textual-input-port
   "drv"
   (lambda (str start count)
     (channel-receive ch)
     (string-set! str start #\X)
     1)
   #f #f #f))

;; Deliberately unguarded: a `guard` around the read would add frames of its
;; own to every level, and the shape confirmed to abort pre-fix is the bare
;; one. An uncaught error in a spawned fiber is recorded on the fiber and
;; harms nothing here.
(let loop ((i 0))
  (when (< i n)
    (spawn (lambda () (read-char port)))
    (loop (+ i 1))))

;; The main fiber's own read-char is what starts the cascade: its callback
;; blocks, and each fiber the drive would dispatch blocks the same way.
(test-equal "n fibers blocking in one custom port's read! do not exhaust the native stack"
  'rejected
  (guard (e (#t 'rejected)) (read-char port)))

;; And the rejection is the documented one, not some other error that
;; happens to be catchable.
(test-assert "the rejection names the custom-port callback rule"
  (guard (e (#t (let* ((m (if (error-object? e) (error-object-message e) ""))
                       (needle "custom port callback blocked")
                       (nl (string-length needle))
                       (ml (string-length m)))
                  (let scan ((i 0))
                    (cond ((> (+ i nl) ml) #f)
                          ((string=? (substring m i (+ i nl)) needle) #t)
                          (else (scan (+ i 1))))))))
    (read-char port)
    #f))

(let ((runner (test-runner-current)))
  (test-end "srfi181-callback-drive-2000")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
