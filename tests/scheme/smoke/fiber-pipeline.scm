;; Regression tests for the fiber scheduler give-up path.
;;
;; runSchedulerUntil used to return an unspecified value (VOID) when no
;; fiber was runnable while intermediate fibers were blocked in nested
;; channel-receive calls. Multi-stage pipelines therefore received garbage
;; instead of data (consumer loops spun forever), and a genuinely
;; deadlocked channel-receive returned VOID instead of raising an error.
;;
;; Now: a spawned fiber that cannot make progress parks on the channel and
;; is woken by channel-send; a blocked main fiber (or a receive that can
;; never be satisfied) raises a catchable deadlock error.

(import (scheme base)
        (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " got=") (write got)
        (display " expected=") (write expected)
        (newline))))

;; --- deadlock with no scheduler (must run before any spawn) --------------
;; No fiber exists, so nothing can ever send: receive must raise, not hang
;; and not return an unspecified value.
(check "receive with no fibers raises catchable deadlock error"
  (guard (e (#t 'deadlock))
    (channel-receive (make-channel)))
  'deadlock)

;; --- multi-stage pipeline (issue repro) ----------------------------------
;; Values must flow through two intermediate fiber stages. Each stage
;; blocks on a channel fed by another fiber that the recursive scheduler
;; could not resume (non-LIFO blocking).
(define (add-stage in-ch proc)
  (let ((out-ch (make-channel)))
    (spawn (lambda ()
      (let process ()
        (let ((val (channel-receive in-ch)))
          (unless (eq? val 'eof)
            (channel-send out-ch (proc val))
            (process))))
      (channel-send out-ch 'eof)))
    out-ch))

(define source (make-channel))
(define output
  (add-stage (add-stage source (lambda (x) (* x x)))
             (lambda (x) (+ x 1))))

(define producer
  (spawn (lambda ()
    (for-each (lambda (n) (channel-send source n)) '(1 2 3 4 5))
    (channel-send source 'eof))))

(check "two-stage pipeline delivers all values"
  (let loop ((acc '()))
    (let ((val (channel-receive output)))
      (if (eq? val 'eof)
          (reverse acc)
          (loop (cons val acc)))))
  '(2 5 10 17 26))

;; --- three-stage pipeline -------------------------------------------------
(define src3 (make-channel))
(define out3
  (add-stage (add-stage (add-stage src3 (lambda (x) (+ x 1)))
                        (lambda (x) (* x 10)))
             (lambda (x) (- x 5))))
(define producer3
  (spawn (lambda ()
    (channel-send src3 1)
    (channel-send src3 2)
    (channel-send src3 'eof))))

(check "three-stage pipeline delivers all values"
  (let loop ((acc '()))
    (let ((val (channel-receive out3)))
      (if (eq? val 'eof)
          (reverse acc)
          (loop (cons val acc)))))
  '(15 25))

;; --- generic variadic pipeline builder (kaappi-book shape) ---------------
;; The book's `pipeline` builds every stage inside one recursive `let loop`,
;; so each spawned fiber closes over the loop-local `ch` and `procs`. A
;; two-or-more-stage pipeline built this way used to make the scheduler
;; return void (the consumer spun forever emitting garbage / the program
;; dropped remaining forms). Verify it now delivers every value in order.
(define (pipeline input-ch . stages)
  (let loop ((ch input-ch) (procs stages))
    (if (null? procs)
        ch
        (let ((out-ch (make-channel)))
          (spawn (lambda ()
            (let process ()
              (let ((val (channel-receive ch)))
                (unless (eq? val 'eof)
                  (channel-send out-ch ((car procs) val))
                  (process))))
            (channel-send out-ch 'eof)))
          (loop out-ch (cdr procs))))))

(define gsrc (make-channel))
(define gout
  (pipeline gsrc
            (lambda (x) (* x x))   ; square
            (lambda (x) (+ x 1))   ; add 1
            (lambda (x) (* x 10)))) ; scale
(define gproducer
  (spawn (lambda ()
    (for-each (lambda (n) (channel-send gsrc n)) '(1 2 3 4 5))
    (channel-send gsrc 'eof))))

(check "variadic pipeline (three stages) delivers all values"
  (let loop ((acc '()))
    (let ((val (channel-receive gout)))
      (if (eq? val 'eof)
          (reverse acc)
          (loop (cons val acc)))))
  '(20 50 100 170 260))

;; --- deadlock with a blocked fiber ---------------------------------------
;; Main and a spawned fiber both wait on a channel nobody sends to:
;; the main receive must raise, not return an unspecified value.
(define dead-ch (make-channel))
(define dead-fiber (spawn (lambda () (channel-receive dead-ch))))
(check "receive that can never be satisfied raises"
  (guard (e (#t 'deadlock))
    (channel-receive dead-ch))
  'deadlock)

;; --- fiber-join on a permanently blocked fiber ---------------------------
(define join-ch (make-channel))
(define blocked-fiber (spawn (lambda () (channel-receive join-ch))))
(check "fiber-join on blocked fiber raises"
  (guard (e (#t 'deadlock))
    (fiber-join blocked-fiber))
  'deadlock)

;; --- parked fiber is woken by a later send -------------------------------
;; The deadlock above parked the fiber; sending on its channel must wake it
;; so the join can complete.
(channel-send join-ch 21)
(check "parked fiber resumes after send and join completes"
  (fiber-join blocked-fiber)
  21)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (error "fiber pipeline tests failed" fail))
