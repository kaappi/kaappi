;; SRFI-181 (Custom Ports) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi181.scm
;;
;; Built in (no lib/srfi/181.sld -- see src/primitives_srfi181.zig, gated
;; behind the srfi_181 Lib tag). This pass implements the 5 port
;; constructors (make-custom-binary-input-port, -output-port,
;; make-custom-textual-input-port, -output-port,
;; make-custom-binary-input/output-port) plus make-file-error. Transcoded
;; ports (make-transcoder, codecs, eol-styles, the raise error-handling
;; mode) are a separate follow-up -- see the tracking issue.
;;
;; Custom port callbacks run through vm.callWithArgs, which always
;; executes with dispatched_from_scheduler forced false: a callback that
;; tries to block (another port's I/O, thread-sleep!) is rejected with a
;; catchable error rather than risking a native-stack-overflow recursive
;; scheduler drive -- callbacks must be effectively synchronous,
;; non-blocking code. See the "blocking callback" section below.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 181) (srfi 192) (srfi 64))

(test-begin "srfi-181")

;;; --- binary input port ---

(let* ((src (bytevector 10 20 30 40 50))
       (pos 0)
       (p (make-custom-binary-input-port
            "src"
            (lambda (bv start count)
              (let ((n (min count (- (bytevector-length src) pos))))
                (let loop ((i 0))
                  (when (< i n)
                    (bytevector-u8-set! bv (+ start i) (bytevector-u8-ref src (+ pos i)))
                    (loop (+ i 1))))
                (set! pos (+ pos n))
                n))
            #f #f #f)))
  (test-assert "binary input port: port? and input-port?" (and (port? p) (input-port? p)))
  (test-assert "binary input port: binary-port?, not textual-port?"
    (and (binary-port? p) (not (textual-port? p))))
  (test-equal "binary input port: read-u8 sequence" 10 (read-u8 p))
  (test-equal "binary input port: read-u8 sequence 2" 20 (read-u8 p))
  (test-equal "binary input port: read-bytevector drains the rest"
    (bytevector 30 40 50)
    (read-bytevector 10 p))
  (test-assert "binary input port: EOF after exhaustion" (eof-object? (read-u8 p))))

;;; --- textual input port ---

(let* ((src "hello\nworld")
       (pos 0)
       (p (make-custom-textual-input-port
            "src"
            (lambda (s start count)
              (let ((n (min count (- (string-length src) pos))))
                (let loop ((i 0))
                  (when (< i n)
                    (string-set! s (+ start i) (string-ref src (+ pos i)))
                    (loop (+ i 1))))
                (set! pos (+ pos n))
                n))
            #f #f #f)))
  (test-assert "textual input port: textual-port?, not binary-port?"
    (and (textual-port? p) (not (binary-port? p))))
  (test-equal "textual input port: read-char" #\h (read-char p))
  (test-equal "textual input port: read-line reads to newline" "ello" (read-line p))
  (test-equal "textual input port: read-line again reads the rest" "world" (read-line p))
  (test-assert "textual input port: EOF after exhaustion" (eof-object? (read-char p))))

;; A read! that writes a multi-byte UTF-8 character forces Kaappi's string
;; internals to reallocate the backing buffer in place (differing byte
;; width) -- regression for the use-after-free trap this must avoid
;; (never cache a string's byte slice across the callWithArgs call).
(let* ((src "aéz") ; 1-byte, 2-byte (e-acute), 1-byte
       (pos 0)
       (p (make-custom-textual-input-port
            "utf8"
            (lambda (s start count)
              (if (>= pos (string-length src)) 0
                  (begin (string-set! s start (string-ref src pos))
                         (set! pos (+ pos 1))
                         1)))
            #f #f #f)))
  (test-equal "textual input port: multi-byte character read one at a time"
    "aéz"
    (read-string 10 p)))

;;; --- binary output port ---

(let* ((collected '())
       (p (make-custom-binary-output-port
            "sink"
            (lambda (bv start count)
              (let loop ((i start) (n 0))
                (if (>= n count)
                    n
                    (begin (set! collected (cons (bytevector-u8-ref bv i) collected))
                           (loop (+ i 1) (+ n 1))))))
            #f #f #f)))
  (test-assert "binary output port: port? and output-port?" (and (port? p) (output-port? p)))
  (write-u8 1 p)
  (write-bytevector (bytevector 2 3 4) p)
  (test-equal "binary output port: bytes arrive in order" '(1 2 3 4) (reverse collected)))

;;; --- textual output port ---

(let* ((acc (open-output-string))
       (p (make-custom-textual-output-port
            "sink"
            (lambda (s start count)
              (write-string (substring s start (+ start count)) acc)
              count)
            #f #f #f)))
  (write-string "hello " p)
  (write-char #\w p)
  (write-string "orld" p)
  (test-equal "textual output port: chars arrive in order" "hello world" (get-output-string acc)))

;;; --- partial reads/writes: the callback need not fill/drain in one call ---

(let* ((src (bytevector 1 2 3 4 5))
       (pos 0)
       (p (make-custom-binary-input-port
            "one-at-a-time"
            (lambda (bv start count)
              (if (>= pos (bytevector-length src)) 0
                  (begin (bytevector-u8-set! bv start (bytevector-u8-ref src pos))
                         (set! pos (+ pos 1))
                         1))) ; always exactly 1 byte, forcing readOneByte's caller to loop
            #f #f #f)))
  (test-equal "binary input port: read-bytevector across many 1-byte read! calls"
    (bytevector 1 2 3 4 5)
    (read-bytevector 5 p)))

(let* ((collected '())
       (p (make-custom-binary-output-port
            "one-at-a-time"
            (lambda (bv start count)
              (set! collected (cons (bytevector-u8-ref bv start) collected))
              1) ; always accept exactly 1 byte, forcing the write loop to iterate
            #f #f #f)))
  (write-bytevector (bytevector 9 8 7 6) p)
  (test-equal "binary output port: write-bytevector across many 1-byte write! calls"
    '(9 8 7 6)
    (reverse collected)))

;;; --- bidirectional port ---

(let* ((state '())
       (p (make-custom-binary-input/output-port
            "bidi"
            (lambda (bv start count) 0) ; EOF on read
            (lambda (bv start count)
              (set! state (cons (bytevector-u8-ref bv start) state))
              count)
            #f #f #f)))
  (test-assert "bidirectional port: both input-port? and output-port?"
    (and (input-port? p) (output-port? p)))
  (write-u8 42 p)
  (test-assert "bidirectional port: EOF on read side" (eof-object? (read-u8 p)))
  (test-equal "bidirectional port: write side received the byte" '(42) state))

;;; --- get-position / set-position! (integrates with SRFI 192) ---

(let* ((data (bytevector 100 101 102 103 104))
       (pos 0)
       (p (make-custom-binary-input-port
            "posn"
            (lambda (bv start count)
              (if (>= pos (bytevector-length data)) 0
                  (begin (bytevector-u8-set! bv start (bytevector-u8-ref data pos))
                         (set! pos (+ pos 1))
                         1)))
            (lambda () pos)
            (lambda (new-pos) (set! pos new-pos))
            #f)))
  (test-assert "custom port: port-has-port-position? is true when get-position is supplied"
    (port-has-port-position? p))
  (read-u8 p)
  (test-equal "custom port: port-position reflects get-position" 1 (port-position p))
  (set-port-position! p 3)
  (test-equal "custom port: read after set-port-position! honors the new position" 103 (read-u8 p)))

;; A port with no get-position/set-position! reports it cleanly rather
;; than falling through to fd-based positioning on the fd=-1 sentinel.
(let ((p (make-custom-binary-input-port "no-posn" (lambda (bv s c) 0) #f #f #f)))
  (test-assert "custom port: port-has-port-position? is false without get-position"
    (not (port-has-port-position? p)))
  (test-error "custom port: port-position without get-position signals an error"
    (port-position p)))

;;; --- close semantics ---

(let ((close-count 0))
  (let ((p (make-custom-binary-input-port
             "c" (lambda (bv s c) 0) #f #f
             (lambda () (set! close-count (+ close-count 1))))))
    (close-port p)
    (close-port p) ; a second close must not re-invoke close_proc
    (test-equal "custom port: close_proc invoked exactly once across a double close-port"
      1 close-count)))

;; close is optional (#f) -- close-port must still succeed.
(let ((p (make-custom-binary-input-port "no-close" (lambda (bv s c) 0) #f #f #f)))
  (close-port p)
  (test-assert "custom port: close-port succeeds when close_proc is #f" #t))

;;; --- flush semantics ---

(let ((flush-count 0))
  (let ((p (make-custom-binary-output-port
             "f" (lambda (bv s c) c) #f #f #f
             (lambda () (set! flush-count (+ flush-count 1))))))
    (flush-output-port p)
    (flush-output-port p)
    (test-equal "custom port: flush_proc invoked once per flush-output-port call"
      2 flush-count)))

;; flush is optional (#f) -- flush-output-port must still succeed, and
;; must not attempt to call #f as a procedure.
(let ((p (make-custom-binary-output-port "no-flush" (lambda (bv s c) c) #f #f #f)))
  (flush-output-port p)
  (test-assert "custom port: flush-output-port succeeds when flush_proc is #f" #t))

;;; --- error propagation ---

(test-error "custom port: a read! that raises propagates the error"
  (read-u8 (make-custom-binary-input-port
             "boom" (lambda (bv s c) (error "read! boom")) #f #f #f)))

(test-error "custom port: a write! that raises propagates the error"
  (write-u8 1 (make-custom-binary-output-port
                "boom" (lambda (bv s c) (error "write! boom")) #f #f #f)))

;;; --- misbehaving callbacks are rejected, not trusted blindly ---

(test-error "custom port: read! returning a negative count is rejected"
  (read-u8 (make-custom-binary-input-port "bad" (lambda (bv s c) -1) #f #f #f)))

(test-error "custom port: read! returning a too-large count is rejected"
  (read-u8 (make-custom-binary-input-port "bad" (lambda (bv s c) (+ c 1)) #f #f #f)))

(test-error "custom port: write! returning zero progress on a non-empty write is rejected"
  (write-u8 1 (make-custom-binary-output-port "stuck" (lambda (bv s c) 0) #f #f #f)))

(test-error "custom port: a non-procedure read! argument is rejected at construction"
  (make-custom-binary-input-port "bad" 42 #f #f #f))

(test-error "custom port: a non-#f non-procedure get-position is rejected at construction"
  (make-custom-binary-input-port "bad" (lambda (bv s c) 0) 42 #f #f))

;;; --- blocking callback guard ---
;;; A custom port callback runs with dispatched_from_scheduler forced
;;; false; it must not be able to block on another port's I/O or
;;; thread-sleep! without a clean, catchable rejection.

(let* ((p (make-custom-binary-input-port
            "blocks"
            (lambda (bv s c) (thread-sleep! 0.01) 0)
            #f #f #f))
       (f (spawn (lambda ()
            (guard (e (#t 'caught))
              (read-u8 p)
              'did-not-raise)))))
  (test-equal "blocking callback: thread-sleep! inside read! is rejected, not hung"
    'caught
    (fiber-join f)))

;;; --- make-file-error ---

(test-assert "make-file-error: satisfies file-error?" (file-error? (make-file-error "boom")))
(test-assert "make-file-error: does not satisfy read-error?" (not (read-error? (make-file-error "boom"))))
(test-assert "make-file-error: no arguments still constructs a file-error" (file-error? (make-file-error)))

(let ((runner (test-runner-current)))
  (test-end "srfi-181")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
