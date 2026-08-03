;; Audit tests for src/primitives_fiber.zig — (kaappi fibers): spawn, yield,
;; fiber-join, fiber?, make-channel, channel-send, channel-receive, channel?,
;; channel-close!, channel-closed?, channel-timeout-exception?.
;;
;; Originally written for audit campaign v1 Phase 2.12 (#1137, 32 assertions).
;; Re-audited for campaign v2 Phase 2.6 (#1890): the file grew +1241/−110 lines
;; since v1 — the largest churn-to-coverage ratio in the primitives table — and
;; all 11 specs, KEP-0002 §6 (capacity/rendezvous/close/timeouts) and the
;; KEP-0001 park-vs-drive protocol are covered here now.
;; Complements tests/scheme/smoke/fiber-*.scm.
;;
;; NOTE: test order matters. Deadlock tests leak permanently-parked fibers
;; (that is inherent — there is no fiber-kill), and the spawn test at the
;; end deliberately spawns 70 more permanently-parked fibers. Nothing
;; requiring a bounded fiber count may run after it. Put new tests ABOVE
;; the "deadlock detection" section.
;;
;; PORTABILITY: this file runs in CI on FreeBSD/NetBSD/OpenBSD/s390x/ppc64le,
;; several under emulation. Never assert wall-clock durations — only relative
;; ordering and the fact that a bounded wait terminates.

(import (scheme base) (scheme write) (kaappi fibers))
(import (scheme process-context) (srfi 64) (srfi 18) (srfi 181))

(test-begin "primitives_fiber audit")

;; Returns 'raised + the message for a raised error object, else the value.
(define (try thunk)
  (guard (e (#t (list 'raised (if (error-object? e) (error-object-message e) e))))
    (thunk)))
;; Just the tag, for cases where the message is not the thing under test.
(define (raises? thunk) (guard (e (#t #t)) (thunk) #f))
;; Substring search, so message assertions pin the *claim* rather than
;; punctuation that a future reword would break.
(define (msg-has? thunk sub)
  (guard (e (#t (and (error-object? e)
                     (let* ((s (error-object-message e))
                            (n (string-length s))
                            (m (string-length sub)))
                       (let loop ((i 0))
                         (cond ((> (+ i m) n) #f)
                               ((string=? (substring s i (+ i m)) sub) #t)
                               (else (loop (+ i 1)))))))))
    (thunk)
    #f))

;;; --- channels without any fibers ---
;; receive on an empty channel with no scheduler must raise, not hang
(test-equal "channel-receive on an empty channel with no fibers raises rather than hanging"
    'deadlock-caught
    (guard (e (#t 'deadlock-caught)) (channel-receive (make-channel))))
(test-equal "send then receive round-trips a value on an unbounded channel"
    42 (let ((ch (make-channel))) (channel-send ch 42) (channel-receive ch)))
;; FIFO ordering
(test-equal "an unbounded channel delivers in FIFO order"
    '(1 2 3)
    (let ((ch (make-channel)))
      (channel-send ch 1) (channel-send ch 2) (channel-send ch 3)
      (list (channel-receive ch) (channel-receive ch) (channel-receive ch))))
;; values pass through by reference (same heap object)
(test-equal "a same-thread channel passes the payload by reference, not by copy"
    #t (let ((ch (make-channel)) (x (list 1 2)))
         (channel-send ch x)
         (eq? x (channel-receive ch))))
;; interleaved send/receive
(test-equal "interleaved send/receive on one channel preserves order"
    '(1 2)
    (let ((ch (make-channel)))
      (channel-send ch 1)
      (let ((a (channel-receive ch)))
        (channel-send ch 2)
        (list a (channel-receive ch)))))

;;; --- predicates ---
(test-equal "channel? is true for a fresh channel" #t (channel? (make-channel)))
(test-equal "channel? is false for a fixnum" #f (channel? 42))
(test-equal "channel? is false for the empty list" #f (channel? '()))
(test-equal "fiber? is false for a channel" #f (fiber? (make-channel)))
(test-equal "fiber? is false for a fixnum" #f (fiber? 42))
(test-equal "fiber? is true for a spawned fiber" #t (fiber? (spawn (lambda () 1))))
(test-equal "channel? is false for a fiber" #f (channel? (spawn (lambda () 1))))

;;; --- type errors are catchable ---
(test-equal "channel-send on a non-channel raises catchably"
    'caught (guard (e (#t 'caught)) (channel-send 42 'v)))
(test-equal "channel-receive on a non-channel raises catchably"
    'caught (guard (e (#t 'caught)) (channel-receive "not-a-channel")))
(test-equal "fiber-join on a non-fiber raises catchably"
    'caught (guard (e (#t 'caught)) (fiber-join 42)))
(test-equal "spawn on a non-procedure raises catchably"
    'caught (guard (e (#t 'caught)) (spawn 42)))
(test-equal "channel-close! on a non-channel raises catchably"
    'caught (guard (e (#t 'caught)) (channel-close! 42)))
(test-equal "channel-closed? on a non-channel raises catchably"
    'caught (guard (e (#t 'caught)) (channel-closed? 'nope)))
;; The four type errors name the offending procedure, not a helper.
(test-assert "channel-send's type error names channel-send"
    (msg-has? (lambda () (channel-send 42 'v)) "channel-send"))
(test-assert "channel-receive's type error names channel-receive"
    (msg-has? (lambda () (channel-receive 42)) "channel-receive"))
(test-assert "fiber-join's type error names fiber-join"
    (msg-has? (lambda () (fiber-join 42)) "fiber-join"))
(test-assert "spawn's type error names spawn"
    (msg-has? (lambda () (spawn 42)) "spawn"))

;;; --- yield ---
;; top-level yield with no scheduler is a no-op
(test-equal "top-level yield with no scheduler is a no-op" 'ok (begin (yield) 'ok))
(test-equal "yield returns an unspecified (void) value"
    #t (let ((v (yield))) (eq? v (if #f #f))))
(test-equal "yield inside map (bootstrapped Scheme, not a native frame) is a no-op"
    'ok (begin (map (lambda (ignored) (yield)) '(a b)) 'ok))

;;; --- make-channel argument validation (D2/D4) ---
(test-equal "make-channel with no argument builds an unbounded channel"
    #t (channel? (make-channel)))
(test-equal "make-channel accepts capacity 0 (rendezvous)"
    #t (channel? (make-channel 0)))
(test-equal "make-channel accepts the largest u32 capacity"
    #t (channel? (make-channel 4294967295)))
(test-assert "make-channel rejects a negative capacity" (raises? (lambda () (make-channel -1))))
(test-assert "make-channel rejects an inexact capacity" (raises? (lambda () (make-channel 1.0))))
(test-assert "make-channel rejects a symbol capacity" (raises? (lambda () (make-channel 'x))))
(test-assert "make-channel rejects a capacity above u32" (raises? (lambda () (make-channel 4294967296))))
(test-assert "make-channel rejects a bignum capacity"
    (raises? (lambda () (make-channel 100000000000000000000000))))
(test-assert "make-channel's rejection names make-channel"
    (msg-has? (lambda () (make-channel -1)) "make-channel"))
;; Surplus arguments are silently ignored — matches the codebase-wide
;; convention for variadic primitives (string->number, make-vector,
;; thread-join!, make-mutex all do the same), so this pins the convention
;; rather than reporting it.
(test-equal "make-channel ignores surplus arguments, like other variadic primitives"
    #t (channel? (make-channel 1 'junk 'more)))

;;; --- KEP-0002 §6: close! / closed? ---
(test-equal "channel-closed? is false for a fresh channel" #f (channel-closed? (make-channel)))
(test-equal "channel-close! makes channel-closed? true"
    #t (let ((ch (make-channel))) (channel-close! ch) (channel-closed? ch)))
(test-equal "a closed channel still drains its already-queued values, then reports eof"
    '(1 2 #t #t)
    (let ((ch (make-channel)))
      (channel-send ch 1) (channel-send ch 2) (channel-close! ch)
      (list (channel-receive ch) (channel-receive ch)
            (eof-object? (channel-receive ch)) (eof-object? (channel-receive ch)))))
(test-assert "channel-send on a closed channel raises"
    (raises? (lambda () (let ((ch (make-channel))) (channel-close! ch) (channel-send ch 1)))))
(test-assert "the closed-channel send error says so"
    (msg-has? (lambda () (let ((ch (make-channel))) (channel-close! ch) (channel-send ch 1)))
              "closed channel"))
(test-equal "channel-close! is idempotent"
    #t (let ((ch (make-channel))) (channel-close! ch) (channel-close! ch) (channel-closed? ch)))
(test-equal "channel-close! returns an unspecified (void) value"
    #t (let ((ch (make-channel))) (eq? (channel-close! ch) (if #f #f))))
;; eof is reserved as the end-of-stream marker, so it cannot be a payload.
(test-assert "channel-send refuses to send an eof-object"
    (raises? (lambda () (channel-send (make-channel) (eof-object)))))
(test-assert "the eof rejection points at channel-close!"
    (msg-has? (lambda () (channel-send (make-channel) (eof-object))) "channel-close!"))
(test-equal "eof rejection is checked before capacity — even a full channel reports it"
    #t (let ((ch (make-channel 1)))
         (channel-send ch 'fill)
         (msg-has? (lambda () (channel-send ch (eof-object))) "eof-object")))

;;; --- KEP-0002 §6: bounded capacity ---
(test-equal "a capacity-N channel admits exactly N sends without a receiver"
    '(a b) (let ((ch (make-channel 2)))
             (channel-send ch 'a) (channel-send ch 'b)
             (list (channel-receive ch) (channel-receive ch))))
(test-assert "the N+1st send on a full channel with no fibers raises rather than hanging"
    (raises? (lambda () (let ((ch (make-channel 2)))
                          (channel-send ch 'a) (channel-send ch 'b) (channel-send ch 'c)))))
(test-assert "the full-channel deadlock error says the channel is full"
    (msg-has? (lambda () (let ((ch (make-channel 1)))
                           (channel-send ch 'a) (channel-send ch 'b)))
              "full"))
(test-equal "a freed slot re-admits a parked sender: 5 values through a capacity-1 channel"
    '(0 1 2 3 4)
    (let ((ch (make-channel 1)))
      (spawn (lambda ()
               (do ((i 0 (+ i 1))) ((= i 5)) (channel-send ch i))
               (channel-close! ch)))
      (let loop ((acc '()))
        (let ((v (channel-receive ch)))
          (if (eof-object? v) (reverse acc) (loop (cons v acc)))))))

;;; --- KEP-0002 §6 as amended (#1601/#1602/#1603): rendezvous, capacity 0 ---
(test-assert "a rendezvous send with no receiver and no fibers raises rather than hanging"
    (raises? (lambda () (channel-send (make-channel 0) 'v))))
(test-assert "the rendezvous send error names the missing receiver"
    (msg-has? (lambda () (channel-send (make-channel 0) 'v)) "rendezvous"))
(test-assert "a rendezvous receive with no sender and no fibers raises rather than hanging"
    (raises? (lambda () (channel-receive (make-channel 0)))))
(test-equal "a rendezvous handoff completes when a fiber sends"
    'rv (let ((ch (make-channel 0)))
          (spawn (lambda () (channel-send ch 'rv)))
          (channel-receive ch)))
(test-equal "a rendezvous handoff completes when the main fiber sends to a parked receiver"
    'ok (let ((ch (make-channel 0)) (out (make-channel)))
          (spawn (lambda () (channel-send out (channel-receive ch))))
          (channel-send ch 'ok)
          (channel-receive out)))
(test-equal "a rendezvous channel transfers repeatedly, in order"
    '(0 1 2)
    (let ((ch (make-channel 0)))
      (spawn (lambda () (do ((i 0 (+ i 1))) ((= i 3)) (channel-send ch i))))
      (list (channel-receive ch) (channel-receive ch) (channel-receive ch))))

;;; --- KEP-0002 Phase 4: timeouts ---
;; Only termination and the returned value are asserted — never a duration.
(test-assert "channel-receive with a timeout terminates on an empty channel"
    (raises? (lambda () (channel-receive (make-channel) 0.05))))
(test-assert "the receive timeout error says it timed out"
    (msg-has? (lambda () (channel-receive (make-channel) 0.05)) "timed out"))
(test-equal "channel-receive returns the supplied timeout value instead of raising"
    'TO (channel-receive (make-channel) 0.05 'TO))
(test-equal "channel-send returns the supplied timeout value instead of raising"
    'STO (let ((ch (make-channel 1))) (channel-send ch 1) (channel-send ch 2 0.05 'STO)))
(test-assert "channel-send with a timeout terminates on a full channel"
    (raises? (lambda () (let ((ch (make-channel 1))) (channel-send ch 1) (channel-send ch 2 0.05)))))
(test-equal "a zero timeout is honoured, not treated as no-timeout"
    'ZT (channel-receive (make-channel) 0 'ZT))
(test-equal "a negative timeout is clamped to an immediate expiry"
    'NT (channel-receive (make-channel) -5 'NT))
(test-equal "channel-timeout-exception? is true for a receive timeout"
    #t (guard (e (#t (channel-timeout-exception? e))) (channel-receive (make-channel) 0.05)))
(test-equal "channel-timeout-exception? is true for a send timeout"
    #t (guard (e (#t (channel-timeout-exception? e)))
         (let ((ch (make-channel 1))) (channel-send ch 1) (channel-send ch 2 0.05))))
(test-equal "channel-timeout-exception? is false for a deadlock error"
    #f (guard (e (#t (channel-timeout-exception? e))) (channel-receive (make-channel))))
(test-equal "channel-timeout-exception? is a total predicate over non-errors"
    '(#f #f #f)
    (list (channel-timeout-exception? 42)
          (channel-timeout-exception? (make-channel))
          (channel-timeout-exception? '())))
(test-equal "a timeout never discards a value that is already queued"
    'delivered (let ((ch (make-channel))) (channel-send ch 'delivered) (channel-receive ch 0 'TO)))
(test-equal "a timeout never discards an already-admitted send"
    'sent (let ((ch (make-channel 1)))
            (if (eq? (channel-send ch 'v 0 'TO) 'TO) 'timed-out 'sent)))

;;; --- spawn / fiber-join ---
;; native procedures are now accepted as spawn thunks (#1155)
(test-equal "spawn accepts a native procedure as a thunk"
    #t (let ((f (spawn newline))) (fiber-join f) (fiber? f)))
(test-equal "fiber-join returns the thunk's value" 42 (fiber-join (spawn (lambda () (* 6 7)))))
(test-equal "a fiber thunk returning multiple values delivers them through fiber-join"
    '(1 2) (call-with-values (lambda () (fiber-join (spawn (lambda () (values 1 2))))) list))
;; yield with a runnable scheduler is fine
(test-equal "yield with a scheduler present is still a no-op from the main fiber"
    'ok (begin (yield) 'ok))
;; join is memoized: joining twice returns the same result
(test-equal "fiber-join is memoized — joining twice returns the same result"
    '(once once)
    (let ((f (spawn (lambda () 'once))))
      (list (fiber-join f) (fiber-join f))))
;; fibers spawning fibers
(test-equal "a fiber can spawn and join a nested fiber"
    11 (fiber-join (spawn (lambda () (+ 1 (fiber-join (spawn (lambda () 10))))))))
;; producer fiber wakes a blocked main receive
(test-equal "a producer fiber wakes a blocked main-fiber receive"
    'hello (let ((ch (make-channel)))
             (spawn (lambda () (channel-send ch 'hello)))
             (channel-receive ch)))
;; two-stage pipeline through the scheduler
(test-equal "a two-stage fiber pipeline delivers through the scheduler"
    30 (let ((a (make-channel)) (b (make-channel)))
         (spawn (lambda () (channel-send b (* 3 (channel-receive a)))))
         (spawn (lambda () (channel-send a 10)))
         (channel-receive b)))
(test-equal "channel-close! wakes a receiver parked in another fiber"
    #t (let ((ch (make-channel)))
         (spawn (lambda () (channel-close! ch)))
         (eof-object? (channel-receive ch))))

;;; --- spawn thunk arity (#1999) ---
;; spawnFiber (src/fiber.zig) builds the fiber's first call frame by hand and
;; never performs the arity check or the rest-list construction an ordinary
;; call does, so a non-thunk runs anyway with its parameters bound to
;; internal values. Controls: the same procedure called directly with zero
;; arguments raises, and SRFI-18's make-thread rejects the same mismatch.
(test-assert "CONTROL: calling a 1-argument procedure with no arguments raises"
    (raises? (lambda () ((lambda (x) 'body-ran)))))
(test-assert "CONTROL: make-thread with a 1-argument thunk fails the thread"
    (raises? (lambda ()
               (let ((t (make-thread (lambda (x) (list 'got x)))))
                 (thread-start! t) (thread-join! t)))))
(test-equal "CONTROL: a pure-variadic procedure called with no arguments binds the empty list"
    '() ((lambda args args)))
(test-equal "CONTROL: make-thread runs a pure-variadic thunk correctly"
    0 (let ((t (make-thread (lambda args (length args))))) (thread-start! t) (thread-join! t)))
;; FAIL: #1999 (spawn runs a 1-argument procedure instead of raising an arity error)
;; (test-assert "spawn rejects a procedure that is not a thunk"
;;     (raises? (lambda () (fiber-join (spawn (lambda (x) 'body-ran))))))
;; FAIL: #1999 (a spawned lambda's rest parameter is #<undefined>, not a list)
;; (test-equal "a spawned procedure's rest parameter is a list"
;;     '(#t #t) (fiber-join (spawn (lambda (a . rest) (list (list? rest) (null? rest))))))
;; FAIL: #1999 (a pure-variadic spawn thunk errors with "fiber error (no exception value)")
;; (test-equal "spawn runs a pure-variadic thunk with no arguments"
;;     0 (fiber-join (spawn (lambda args (length args)))))
;; FAIL: #1999 (a native procedure of arity >= 1 errors with no exception value)
;; (test-assert "spawn of a native procedure needing arguments raises a described error"
;;     (msg-has? (lambda () (fiber-join (spawn car))) "car"))

;;; --- errors inside fibers ---
;; join re-raises the fiber's exception, with the error object intact
(test-equal "fiber-join re-raises the fiber's exception with the message intact"
    '(caught "fiber-boom")
    (guard (e (#t (list 'caught (error-object-message e))))
      (fiber-join (spawn (lambda () (error "fiber-boom"))))))
(test-equal "fiber-join preserves the irritants of a fiber's error"
    '(1 2)
    (guard (e (#t (error-object-irritants e)))
      (fiber-join (spawn (lambda () (error "boom" 1 2))))))
(test-equal "fiber-join propagates a raise of a non-error object unchanged"
    42 (guard (e (#t e)) (fiber-join (spawn (lambda () (raise 42))))))
;; re-raised on every join
(test-equal "a fiber's error is re-raised on every join, not just the first"
    '(c1 c2)
    (let ((f (spawn (lambda () (error "boom2")))))
      (list (guard (e (#t 'c1)) (fiber-join f))
            (guard (e (#t 'c2)) (fiber-join f)))))
;; a guard inside the fiber handles its own error normally
(test-equal "a guard inside a fiber handles the fiber's own error"
    'handled (fiber-join (spawn (lambda () (guard (e (#t 'handled)) (error "x"))))))

;;; --- D5: parking discipline (KEP-0001) ---
;; #1959: map/for-each and dynamic-wind are bootstrapped Scheme, not native
;; frames, so a fiber parks inside them. guard's body likewise.
(test-equal "a fiber parks inside map — map is bootstrapped Scheme, not a native frame"
    '(1 2) (let ((ch (make-channel)))
             (spawn (lambda () (channel-send ch 1) (channel-send ch 2)))
             (map (lambda (ignored) (channel-receive ch)) '(a b))))
(test-equal "a fiber parks inside for-each"
    '(2 1) (let ((ch (make-channel)) (acc '()))
             (spawn (lambda () (channel-send ch 1) (channel-send ch 2)))
             (for-each (lambda (ignored) (set! acc (cons (channel-receive ch) acc))) '(a b))
             acc))
(test-equal "a fiber parks inside a guard body"
    'g (let ((ch (make-channel)))
         (spawn (lambda () (channel-send ch 'g)))
         (guard (e (#t 'unreached)) (channel-receive ch))))
(test-equal "a fiber parks inside a dynamic-wind body"
    'dw (let ((ch (make-channel)))
          (spawn (lambda () (channel-send ch 'dw)))
          (dynamic-wind (lambda () #f) (lambda () (channel-receive ch)) (lambda () #f))))
(test-equal "a fiber parks inside a with-exception-handler thunk"
    'weh (let ((ch (make-channel)))
           (spawn (lambda () (channel-send ch 'weh)))
           (with-exception-handler (lambda (e) 'h) (lambda () (channel-receive ch)))))

;;; --- D5: SRFI-181 custom-port callbacks may not block (#2000) ---
;; vm.in_custom_port_callback exists so a callback that tries to block raises
;; a catchable error rather than recursively driving the scheduler on the
;; native stack. It used to be checked at exactly two sites (fiber.waitForFd
;; and primitives_srfi18.threadSleepFn), so the (kaappi fibers) blocking
;; primitives drove instead — and with enough nesting the drive exhausted the
;; native stack (SIGBUS, exit 134). The check now also lives at the shared
;; choke point every in-place drive passes through, fiber.runSchedulerStep,
;; which covers these three and SRFI-18's thread-join!/mutex-lock!/
;; condition-variable-wait as well.
(define (port-whose-read! body)
  (make-custom-textual-input-port
   "probe"
   (lambda (str start count) (body) (string-set! str start #\X) 1)
   #f #f #f))
(test-assert "CONTROL: a custom-port read! that calls thread-sleep! is rejected"
    (msg-has? (lambda () (read-char (port-whose-read! (lambda () (thread-sleep! 0.05)))))
              "custom port callback blocked"))
(test-assert "a custom-port read! that blocks on a channel is rejected"
    (let ((ch (make-channel)))
      (spawn (lambda () (channel-send ch 'v)))
      (msg-has? (lambda () (read-char (port-whose-read! (lambda () (channel-receive ch)))))
                "custom port callback blocked")))
(test-assert "a custom-port read! that blocks on a full channel is rejected"
    (let ((ch (make-channel 1)))
      (channel-send ch 'fill)
      (spawn (lambda () (channel-receive ch)))
      (msg-has? (lambda () (read-char (port-whose-read! (lambda () (channel-send ch 'v)))))
                "custom port callback blocked")))
(test-assert "a custom-port read! that blocks in fiber-join is rejected"
    (let ((f (spawn (lambda () 'joined))))
      (msg-has? (lambda () (read-char (port-whose-read! (lambda () (fiber-join f)))))
                "custom port callback blocked")))
;; The sibling SRFI-18 waits reach the same choke point. mutex-lock! on a
;; mutex another fiber holds is the one that blocks with no channel involved
;; at all. The holder must still be alive when the callback runs — a fiber
;; that has completed abandons its mutexes, and mutex-lock! then returns the
;; "abandoned" error immediately without ever waiting.
(test-assert "a custom-port read! that blocks in mutex-lock! is rejected"
    (let ((m (make-mutex)) (ready (make-channel)) (release (make-channel)))
      (spawn (lambda () (mutex-lock! m) (channel-send ready 'held)
                        (channel-receive release) (mutex-unlock! m)))
      (channel-receive ready)
      (let ((r (msg-has? (lambda () (read-char (port-whose-read! (lambda () (mutex-lock! m)))))
                         "custom port callback blocked")))
        (channel-send release 'go) ; let the holder unlock and retire
        r)))
;; thread-join!'s *fiber* path is the one that drives. Its OS-thread path
;; does not (reapOsThread joins the pthread, or polls with sleepNs), which
;; is why primitives_srfi181-audit.scm's "a read! that joins a short-lived
;; thread is NOT rejected" control keeps passing. The target must already
;; have STARTED: thread-join! on a spawn'd fiber still in .created spins in
;; its own sleepNs poll and never reaches the scheduler at all — unrelated
;; to this guard, and it hangs, so it is not probed here.
(test-assert "a custom-port read! that blocks in thread-join! on a started fiber is rejected"
    (let ((started (make-channel)) (hold (make-channel)))
      (let ((f (spawn (lambda () (channel-send started 'up) (channel-receive hold) 'done))))
        (channel-receive started) ; f has run and is now parked on `hold`
        (let ((r (msg-has? (lambda () (read-char (port-whose-read! (lambda () (thread-join! f)))))
                           "custom port callback blocked")))
          (channel-send hold 'go)
          (thread-join! f) ; retire it rather than leave a parked fiber behind
          r))))
;; SRFI-18 spells a condition-variable wait `(mutex-unlock! mutex cv timeout)`.
;; The timeout keeps this bounded if the guard ever stops firing.
(test-assert "a custom-port read! that blocks in a condition-variable wait is rejected"
    (let ((m (make-mutex)) (cv (make-condition-variable)))
      (mutex-lock! m)
      (msg-has? (lambda () (read-char (port-whose-read! (lambda () (mutex-unlock! m cv 0.05)))))
                "custom port callback blocked")))
;; The TIMED variants are the ones that arm scheduler state (a .waiting
;; status, a waiter_index enrolment, a reactor timer) *before* the wait is
;; entered, so the rejection unwinds through more than the untimed ones do.
;; The round trip after each rejection is the actual assertion: it only
;; completes if the scheduler came out of that unwind healthy.
(test-equal "a rejected timed channel-receive in read! leaves the scheduler usable"
    'still-works
    (let ((ch (make-channel)) (after (make-channel)))
      (msg-has? (lambda () (read-char (port-whose-read!
                                        (lambda () (channel-receive ch 0.05 'timed-out)))))
                "custom port callback blocked")
      (spawn (lambda () (channel-send after 'still-works)))
      (channel-receive after)))
(test-equal "a rejected timed channel-send in read! leaves the scheduler usable"
    'still-works
    (let ((full (make-channel 1)) (after (make-channel)))
      (channel-send full 'fill)
      (msg-has? (lambda () (read-char (port-whose-read!
                                        (lambda () (channel-send full 'v 0.05 'timed-out)))))
                "custom port callback blocked")
      (spawn (lambda () (channel-send after 'still-works)))
      (channel-receive after)))

;;; --- D6: cross-thread sharing model ---
;; CLAUDE.md and docs/dev/thread-value-sharing.md: a channel must be captured
;; LEXICALLY by the thread thunk (deep-copied and re-owned); one reached
;; through a top-level define is shared by pointer and must be refused.
(test-equal "a lexically captured channel crosses an OS-thread boundary"
    'from-child
    (let ((ch (make-channel)))
      (let ((t (make-thread (lambda () (channel-send ch 'from-child)))))
        (thread-start! t)
        (let ((v (channel-receive ch))) (thread-join! t) v))))
(test-equal "a channel payload is deep-copied across an OS-thread boundary, not aliased"
    #f (let ((ch (make-channel)) (obj (list 1 2)))
         (let ((t (make-thread (lambda () (channel-send ch obj)))))
           (thread-start! t)
           (let ((v (channel-receive ch))) (thread-join! t) (eq? v obj)))))
(test-equal "a channel sent as a payload promotes and works from the receiving side"
    '(#t via-inner)
    (let ((ch (make-channel)) (inner (make-channel)))
      (let ((t (make-thread (lambda () (channel-send ch inner) (channel-send inner 'via-inner)))))
        (thread-start! t)
        (let* ((got (channel-receive ch)) (v (channel-receive got)))
          (thread-join! t) (list (channel? got) v)))))
(test-assert "channel-send refuses an uncopyable payload (a port) across threads"
    (let ((ch (make-channel)))
      (let ((t (make-thread (lambda ()
                              (guard (e (#t (and (error-object? e) 'refused)))
                                (channel-send ch (current-output-port)) #f)))))
        (thread-start! t)
        (eq? 'refused (thread-join! t)))))
(test-assert "channel-send refuses a fiber as a cross-thread payload"
    (let ((ch (make-channel)))
      (let ((t (make-thread (lambda ()
                              (guard (e (#t (and (error-object? e) 'refused)))
                                (channel-send ch (spawn (lambda () 1))) #f)))))
        (thread-start! t)
        (eq? 'refused (thread-join! t)))))

;;; --- D6: the globals route is refused for channels (Object.owner check) ---
;; These four use a top-level binding deliberately: a top-level define is
;; shared by pointer across threads, so the owner check must reject it.
(define shared-ch (make-channel))
(define (child-does thunk)
  (let ((t (make-thread (lambda ()
                          (guard (e (#t (list 'refused (and (error-object? e) #t))))
                            (list 'allowed (thunk)))))))
    (thread-start! t)
    (thread-join! t)))
(test-equal "channel-send through a shared global is refused"
    '(refused #t) (child-does (lambda () (channel-send shared-ch 'x))))
(test-equal "channel-receive through a shared global is refused"
    '(refused #t) (child-does (lambda () (channel-receive shared-ch))))
(test-equal "channel-close! through a shared global is refused"
    '(refused #t) (child-does (lambda () (channel-close! shared-ch))))
(test-equal "channel-closed? through a shared global is refused"
    '(refused #t) (child-does (lambda () (channel-closed? shared-ch))))
;; The message has to be read inside the child: thread-join! re-raises a
;; child's error as a fresh "uncaught exception in thread" object.
(test-assert "the foreign-channel refusal explains the thread-thunk route"
    (let ((t (make-thread (lambda ()
                            (guard (e (#t (error-object-message e)))
                              (channel-send shared-ch 'x) "")))))
      (thread-start! t)
      (let* ((s (thread-join! t)) (sub "another thread")
             (n (string-length s)) (m (string-length sub)))
        (let loop ((i 0))
          (cond ((> (+ i m) n) #f)
                ((string=? (substring s i (+ i m)) sub) #t)
                (else (loop (+ i 1))))))))
;; channel? is deliberately a total predicate — it must NOT raise on a
;; foreign channel, so a defensive guard gets #f-and-skip instead.
(test-equal "channel? does not apply the owner check (total predicate)"
    '(allowed #t) (child-does (lambda () (channel? shared-ch))))

;;; --- D6: fiber-join applies the owner check too (#2001) ---
;; Every channel operation above rejects a foreign-heap object, and so does
;; fiber-join: without that check a child thread reached straight into the
;; parent's heap through a top-level fiber binding, and fiber-join *returned*
;; the parent's object uncopied.
(define shared-fiber (spawn (lambda () (list 1 2 3))))
(define parent-view (fiber-join shared-fiber))
(test-equal "CONTROL: the parent's own fiber-join returns the thunk's value"
    '(1 2 3) parent-view)
(test-equal "fiber-join through a shared global is refused, like every channel op"
    '(refused #t) (child-does (lambda () (fiber-join shared-fiber))))
(test-equal "a foreign fiber-join result is not aliased into the parent's heap"
    '(1 2 3)
    (begin (child-does (lambda () (set-car! (fiber-join shared-fiber) 'MUTATED)))
           parent-view))
;; A still-running foreign fiber used to report a deadlock that does not
;; exist — the fiber belongs to another thread's scheduler, and no cycle is
;; involved. It must be refused with the ownership message instead.
(define running-fiber (spawn (lambda () (channel-receive (make-channel)))))
(test-assert "a foreign fiber-join says 'another thread', not 'deadlock'"
    (let ((t (make-thread (lambda ()
                            (msg-has? (lambda () (fiber-join running-fiber))
                                      "another thread")))))
      (thread-start! t)
      (thread-join! t)))
;; fiber? stays a total predicate, exactly like channel? above.
(test-equal "fiber? does not apply the owner check (total predicate)"
    '(allowed #t) (child-does (lambda () (fiber? shared-fiber))))

;;; --- deadlock detection (each leaks a parked fiber; that is inherent) ---
;; joining a fiber blocked on a never-sent channel raises, not hangs
(test-equal "joining a fiber blocked on a never-sent channel raises rather than hanging"
    'deadlock-caught
    (guard (e (#t 'deadlock-caught))
      (let ((ch (make-channel)))
        (fiber-join (spawn (lambda () (channel-receive ch)))))))
;; cyclic join raises, not hangs
(test-equal "a cyclic fiber-join raises rather than hanging"
    'deadlock-caught
    (guard (e (#t 'deadlock-caught))
      (letrec ((fa (spawn (lambda () (fiber-join fb))))
               (fb (spawn (lambda () (fiber-join fa)))))
        (fiber-join fa))))
;; deadlock errors carry a useful message
(test-equal "deadlock errors carry a non-trivial message"
    #t (guard (e (#t (and (error-object? e)
                          (> (string-length (error-object-message e)) 10))))
         (channel-receive (make-channel))
         #f))
(test-assert "the fiber-join deadlock error names fiber-join"
    (msg-has? (lambda ()
                (let ((ch (make-channel)))
                  (fiber-join (spawn (lambda () (channel-receive ch))))))
              "fiber-join"))

;;; --- spawn limit — superseded by the growable fiber table (KEP-0001
;;; Phase 2, kaappi/kaappi#1440): the fixed MAX_FIBERS=64 table this test
;;; used to hit is gone, so 70 concurrently-parked spawns now succeed
;;; outright instead of erroring at the old ceiling.
(test-equal "70 concurrently-parked spawns succeed — the fixed fiber table is gone"
    'no-limit
    (guard (e (#t (list 'limit-hit (error-object? e))))
      (let loop ((i 0))
        (if (= i 70) 'no-limit
            (begin (spawn (lambda () (channel-receive (make-channel))))
                   (loop (+ i 1)))))))
;; sends/receives that need no new slot still work at the limit
(test-equal "a send/receive needing no new fiber slot still works with 70 fibers parked"
    1 (let ((ch (make-channel))) (channel-send ch 1) (channel-receive ch)))
;; With every slot holding a permanently-parked fiber, a top-level (yield)
;; used to raise a bare error whose message was just "error" (#1184): the
;; test macro's guard sits between the yield and the scheduler loop, and
;; with-exception-handler converted the in-flight Yielded unwind into a
;; contentless exception. Yield is advisory and must be a no-op here.
(test-equal "yield stays a no-op with every fiber parked (#1184)"
    'yield-ok (begin (yield) 'yield-ok))

(let ((runner (test-runner-current)))
  (test-end "primitives_fiber audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
