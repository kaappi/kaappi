;; SRFI 215 (Central Log Exchange) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi215.scm
;;
;; current-log-callback is a single dynamically-scoped slot (like
;; current-output-port), so every test below installs its own callback
;; via `parameterize` and never calls send-log outside of one -- except
;; the very first block, which deliberately exercises what happens
;; *before* any callback has ever been installed (the default buffers
;; instead of losing messages). Keeping that to the first block (and
;; never sending outside a parameterize afterward) means the shared
;; internal buffer is provably empty for every later test.

(import (scheme base)
        (scheme write)
        (scheme process-context)
        (srfi 215)
        (srfi 64))

(test-begin "srfi-215")

;;; --- severity constants: exact values and ordering per the spec's table ---

(test-equal "EMERGENCY = 0" 0 EMERGENCY)
(test-equal "ALERT = 1" 1 ALERT)
(test-equal "CRITICAL = 2" 2 CRITICAL)
(test-equal "ERROR = 3" 3 ERROR)
(test-equal "WARNING = 4" 4 WARNING)
(test-equal "NOTICE = 5" 5 NOTICE)
(test-equal "INFO = 6" 6 INFO)
(test-equal "DEBUG = 7" 7 DEBUG)
(test-assert "severities are ordered EMERGENCY .. DEBUG, most to least severe"
             (< EMERGENCY ALERT CRITICAL ERROR WARNING NOTICE INFO DEBUG))

;;; --- default callback buffers messages sent before any receiver exists,
;;; --- and flushes them (oldest first) into the first installed callback ---

(send-log DEBUG "buffered before any callback")
(let ((received '()))
  (parameterize ((current-log-callback (lambda (msg)
                                         (set! received (cons msg received)))))
    (send-log INFO "sent after callback installed")
    (let ((ordered (reverse received)))
      (test-equal "both the flushed and the newly sent message arrive"
                  2
                  (length ordered))
      (test-equal "the flushed (earlier) message arrives first"
                  "buffered before any callback"
                  (cdr (assq 'MESSAGE (car ordered))))
      (test-equal "the newly sent message arrives second"
                  "sent after callback installed"
                  (cdr (assq 'MESSAGE (cadr ordered)))))))

;;; --- registering a receiver: it gets a structured entry with SEVERITY/MESSAGE ---

(let ((received '()))
  (parameterize ((current-log-callback (lambda (msg)
                                         (set! received (cons msg received)))))
    (send-log INFO "hello"))
  (test-equal "receiver was called exactly once" 1 (length received))
  (let ((msg (car received)))
    (test-assert "the entry is a proper association list" (list? msg))
    (test-equal "SEVERITY key carries the severity passed to send-log"
                INFO
                (cdr (assq 'SEVERITY msg)))
    (test-equal "MESSAGE key carries the message passed to send-log"
                "hello"
                (cdr (assq 'MESSAGE msg)))))

;;; --- extra fields passed directly to send-log appear in the entry ---

(let ((received #f))
  (parameterize ((current-log-callback (lambda (msg) (set! received msg))))
    (send-log WARNING "disk low" 'FACILITY 3 'TOPIC "disk"))
  (test-equal "SEVERITY still present alongside extra fields"
              WARNING
              (cdr (assq 'SEVERITY received)))
  (test-equal "MESSAGE still present alongside extra fields"
              "disk low"
              (cdr (assq 'MESSAGE received)))
  (test-equal "explicit FACILITY field" 3 (cdr (assq 'FACILITY received)))
  (test-equal "explicit TOPIC field" "disk" (cdr (assq 'TOPIC received))))

;;; --- current-log-fields is merged in after send-log's own explicit fields ---

(let ((received #f))
  (parameterize ((current-log-fields (list 'APP-NAME "myapp" 'PROCID "123")) (current-log-callback (lambda (msg)
                                                                                                     (set! received
                                                                                                           msg))))
    (send-log ERROR "oops" 'TOPIC "billing"))
  (test-equal "field from current-log-fields is present"
              "myapp"
              (cdr (assq 'APP-NAME received)))
  (test-equal "a second field from current-log-fields is present"
              "123"
              (cdr (assq 'PROCID received)))
  (test-equal "explicit send-log field is still present alongside ambient fields"
              "billing"
              (cdr (assq 'TOPIC received)))
  (test-equal "current-log-fields defaults back to empty outside the parameterize"
              '()
              (current-log-fields)))

;;; --- field value conversion: non-standard types are written to a string ---

(let ((received #f))
  (parameterize ((current-log-callback (lambda (msg) (set! received msg))))
    (send-log DEBUG "typed" 'THING (list 1 2 3) 'SYM 'a-symbol))
  (test-equal "a list value is converted via write"
              "(1 2 3)"
              (cdr (assq 'THING received)))
  (test-equal "a symbol value is converted via write"
              "a-symbol"
              (cdr (assq 'SYM received))))

;;; --- field value conversion: already-safe types pass through unconverted ---

(define %sample-error-object (guard (e (#t e)) (error "boom" 1 2)))

(let ((received #f))
  (parameterize ((current-log-callback (lambda (msg) (set! received msg))))
    (send-log DEBUG
              "typed2"
              'S
              "a string"
              'N
              42
              'B
              (bytevector 1 2 3)
              'E
              %sample-error-object))
  (test-equal "a string value passes through unconverted"
              "a string"
              (cdr (assq 'S received)))
  (test-equal "an exact-integer value passes through unconverted"
              42
              (cdr (assq 'N received)))
  (test-equal "a bytevector value passes through unconverted"
              (bytevector 1 2 3)
              (cdr (assq 'B received)))
  (test-assert "an error-object value passes through unconverted (same object)"
               (eq? %sample-error-object (cdr (assq 'E received)))))

;;; --- error conditions the spec requires send-log to signal ---

(test-error "send-log signals an error for an odd number of trailing arguments"
            (send-log INFO "message" 'ONLY-A-KEY))
(test-error "send-log signals an error when a field key is not a symbol"
            (send-log INFO "message" "not-a-symbol" "value"))

;;; --- receiver filtering by severity is the callback's own responsibility ---
;;; (lower numeric severity = more severe; "only high-severity" means a
;;; small SEVERITY number, i.e. WARNING/ERROR/CRITICAL/ALERT/EMERGENCY)

(let ((accepted '()))
  (define (only-warning-or-worse msg)
    (when (<= (cdr (assq 'SEVERITY msg)) WARNING)
      (set! accepted (cons msg accepted))))
  (parameterize ((current-log-callback only-warning-or-worse))
    (send-log DEBUG "debug noise")
    (send-log INFO "info noise")
    (send-log NOTICE "just fyi")
    (send-log WARNING "a warning")
    (send-log ERROR "an error"))
  (let ((ordered (reverse accepted)))
    (test-equal "the severity-filtering receiver ignored DEBUG/INFO/NOTICE"
                2
                (length ordered))
    (test-equal "it kept the WARNING message"
                "a warning"
                (cdr (assq 'MESSAGE (car ordered))))
    (test-equal "it kept the ERROR message"
                "an error"
                (cdr (assq 'MESSAGE (cadr ordered))))))

;; A minimal, direct version of the same check: a receiver that only
;; wants WARNING-or-worse must not be invoked at all for a single
;; DEBUG-severity call.
(let ((called? #f))
  (parameterize ((current-log-callback (lambda (msg)
                                         (when (<= (cdr (assq 'SEVERITY msg))
                                                   WARNING)
                                           (set! called? #t)))))
    (send-log DEBUG "low severity, should not trigger the filter"))
  (test-assert "a high-severity-only receiver body does not act on a low-severity call"
               (not called?)))

;;; --- multiple receivers: no built-in fan-out, so the callback dispatches itself ---

(let ((log-a '()) (log-b '()))
  (define (receiver-a msg) (set! log-a (cons msg log-a)))
  (define (receiver-b msg)
    (when (<= (cdr (assq 'SEVERITY msg)) NOTICE) (set! log-b (cons msg log-b))))
  (define (fan-out msg) (receiver-a msg) (receiver-b msg))
  (parameterize ((current-log-callback fan-out))
    (send-log ERROR "disk failure")
    (send-log DEBUG "loop iteration 42")
    (send-log INFO "request handled"))
  (test-equal "unfiltered receiver-a saw all three messages" 3 (length log-a))
  (test-equal "receiver-b's own NOTICE-or-worse filter kept only one"
              1
              (length log-b))
  (test-equal "the message receiver-b kept is the ERROR one"
              "disk failure"
              (cdr (assq 'MESSAGE (car log-b)))))

;;; --- "unregistering" a receiver: SRFI 215 has no separate API for this --
;;; --- removal is leaving the dynamic extent that installed it (or a further
;;; --- direct call to current-log-callback); either restores whatever was
;;; --- previously current, so the removed receiver is never called again ---

(let ((receiver-1-log '()) (receiver-2-log '()))
  (parameterize ((current-log-callback (lambda (msg)
                                         (set! receiver-1-log
                                               (cons msg receiver-1-log)))))
    (send-log INFO "while receiver-1 installed"))
  ;; receiver-1's dynamic extent has ended: it is no longer current.
  (parameterize ((current-log-callback (lambda (msg)
                                         (set! receiver-2-log
                                               (cons msg receiver-2-log)))))
    (send-log INFO "while receiver-2 installed"))
  (test-equal "receiver-1 saw only the message sent during its own extent"
              1
              (length receiver-1-log))
  (test-equal "receiver-2 saw only the message sent during its own extent"
              1
              (length receiver-2-log))
  (test-equal "receiver-1's removal means it never saw receiver-2's message"
              "while receiver-1 installed"
              (cdr (assq 'MESSAGE (car receiver-1-log)))))

;;; --- the default callback's buffer is bounded: past some implementation- ---
;;; --- defined cap, the oldest buffered messages are dropped to keep the ---
;;; --- most recent activity rather than growing without limit forever ---

(let ((received '()))
  ;; Send far more than any reasonable cap before installing a callback.
  ;; current-log-callback is still at its module-level default here --
  ;; nothing earlier in this file sends outside of a parameterize, so
  ;; the buffer is provably empty going in.
  (do ((i 0 (+ i 1))) ((= i 1500))
    (send-log INFO (number->string i)))
  (parameterize ((current-log-callback (lambda (msg)
                                         (set! received (cons msg received)))))
    #f)
  (test-assert "far fewer than all 1500 sent messages survive: growth is bounded"
               (< (length received) 1500))
  (test-assert "at least some messages survive"
               (> (length received) 0))
  (test-equal "the most recently sent message survives (oldest, not newest, is dropped)"
              "1499"
              (cdr (assq 'MESSAGE (car received))))
  (test-assert "the very first message sent is among those dropped"
               (not (member "0" (map (lambda (m) (cdr (assq 'MESSAGE m))) received)))))

;;; --- a callback that itself calls send-log while being flushed gets its ---
;;; --- own reentrant message delivered too, rather than stranded in the ---
;;; --- buffer until some later, unrelated callback replacement ---

(let ((received '()))
  (send-log INFO "buffered-before-reentrant-test")
  (parameterize ((current-log-callback
                  (lambda (msg)
                    (set! received (cons msg received))
                    (when (= (length received) 1)
                      (send-log INFO "sent reentrantly during the flush")))))
    #f)
  (let ((ordered (reverse received)))
    (test-equal "both the originally-buffered and the reentrantly-sent message arrive"
                2
                (length ordered))
    (test-equal "the reentrant message is delivered within the same flush, not stranded"
                "sent reentrantly during the flush"
                (cdr (assq 'MESSAGE (cadr ordered))))))

(let ((received-later '()))
  (parameterize ((current-log-callback (lambda (msg)
                                         (set! received-later
                                               (cons msg received-later)))))
    #f)
  (test-equal "nothing was left stranded in the buffer after the reentrant flush"
              0
              (length received-later)))

;;; --- installing a non-procedure is rejected, and doesn't discard ---
;;; --- whatever was already buffered ---

(send-log NOTICE "should survive a rejected install")
(test-error "current-log-callback rejects a non-procedure"
            (current-log-callback 42))
(let ((received '()))
  (parameterize ((current-log-callback (lambda (msg) (set! received (cons msg received)))))
    #f)
  (test-equal "the message buffered before the rejected install still survives"
              1
              (length received))
  (test-equal "its content is intact"
              "should survive a rejected install"
              (cdr (assq 'MESSAGE (car received)))))

;; Direct-call removal: replacing current-log-callback outside of any
;; parameterize also "unregisters" whatever was current before -- here,
;; back to the (still-empty, since every prior send happened inside a
;; parameterize) default buffering callback.
(let ((direct-log '()))
  (current-log-callback (lambda (msg) (set! direct-log (cons msg direct-log))))
  (send-log NOTICE "via direct call")
  (test-equal "a directly-installed callback receives subsequent messages"
              1
              (length direct-log))
  (test-equal "its message content is correct"
              "via direct call"
              (cdr (assq 'MESSAGE (car direct-log)))))

(let ((runner (test-runner-current)))
  (test-end "srfi-215")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
