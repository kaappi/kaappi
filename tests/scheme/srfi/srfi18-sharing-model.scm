;; Characterisation test for #1937: which values may cross a thread
;; boundary, by which of the two routes.
;;
;; A value reaches another thread either by being deep-copied (the thunk
;; closure at thread-start!, the result at thread-join!, a channel message)
;; or by being reached through the shared globals map, by pointer, with no
;; copy at all. The two routes have separate, unrelated enforcement:
;; gc_deep_copy.zig's fourteen-tag uncopyable list governs the copy route
;; only, and the globals route is checked by individual primitives for
;; exactly two types (channels and thread handles).
;;
;; This file pins BOTH routes for each type, which is the pairing that makes
;; the asymmetry visible -- and it is deliberately a characterisation test,
;; not an endorsement. Rows that docs/dev/thread-value-sharing.md calls
;; "unchecked" are asserted here as they behave today so that changing one
;; fails loudly and the table gets updated with it, rather than the code and
;; the document drifting apart silently. If a fix for #1924 / #1936 changes a
;; row, change it here and in that table together.
;;
;; Deliberately avoids (srfi 170): user-info raises unsupported on Windows,
;; and this suite runs there. The nine types below cover every distinct
;; enforcement shape.

(import (scheme base) (scheme write) (scheme eval) (scheme repl)
        (scheme process-context)
        (srfi 18) (srfi 254) (kaappi fibers) (srfi 64))

(test-begin "srfi18-sharing-model")

;; Runs THUNK on a child thread and returns either its value or
;; (raised . message) -- for whichever of the two raises first, the child
;; itself or the join. Both refusal shapes reduce to the same answer:
;; a captured-value refusal fails at thread-start! and surfaces at the join,
;; while a globals-route refusal fails inside the primitive on the child.
(define (on-child thunk)
  (let ((t (make-thread
            (lambda ()
              (guard (e (#t (cons 'raised (error-object-message e))))
                (thunk))))))
    (guard (e (#t (cons 'raised (error-object-message e))))
      (thread-start! t)
      (thread-join! t))))

(define (refused? r) (and (pair? r) (eq? (car r) 'raised)))

;; ---------------------------------------------------------------------------
;; The copy route: fourteen tags are refused when captured lexically.
;; ---------------------------------------------------------------------------
;; Each `let` binding below is a genuine lexical capture, so the value is
;; part of the closure gc_deep_copy walks at thread-start!.

(define-syntax test-capture-refused
  (syntax-rules ()
    ((_ label expr)
     (test-assert (string-append "capture refused: " label)
       (refused? (let ((v expr)) (on-child (lambda () (if v 'used 'used)))))))))

(test-capture-refused "port" (open-input-string "abc"))
(test-capture-refused "continuation"
                      (call-with-current-continuation (lambda (k) k)))
(test-capture-refused "thread handle" (make-thread (lambda () 1)))
(test-capture-refused "mutex" (make-mutex))
(test-capture-refused "condition variable" (make-condition-variable))
(test-capture-refused "environment" (environment '(scheme base)))
(test-capture-refused "ephemeron" (make-ephemeron 'k 'v))
(test-capture-refused "guardian" (make-guardian))

;; A channel is the exception: its arm promotes and aliases rather than
;; refusing, which is what makes lexical capture the supported way to share
;; one (KEP-0002 §2, "Motivation Path 1").
(test-equal "capture aliased: channel"
  'from-child
  (let ((ch (make-channel)))
    (let ((t (make-thread (lambda () (channel-send ch 'from-child)))))
      (thread-start! t)
      (let ((v (channel-receive ch)))
        (thread-join! t)
        v))))

;; ---------------------------------------------------------------------------
;; The globals route: same values, reached by name instead of by capture.
;; ---------------------------------------------------------------------------
;; Every binding below is top-level, so VM.initForThread's shared globals map
;; hands the child the parent's own object. None of these is copied.

(define g-in-port (open-input-string "abcdef"))
(define g-out-port (open-output-string))
(define g-mutex (make-mutex))
(define g-condvar (make-condition-variable))
(define g-env (environment '(scheme base)))
(define g-ephemeron (make-ephemeron 'k 'v))
(define g-guardian (make-guardian))
(define g-channel (make-channel))
(define g-thread (make-thread (lambda () 'never-started)))

;; Checked on this route -- the only two types that are.
(test-assert "global refused: channel"
  (refused? (on-child (lambda () (channel-send g-channel 'hi)))))
(test-assert "global refused: thread handle"
  (refused? (on-child (lambda () (thread-name g-thread)))))

;; Unchecked on this route. Mutexes and condition variables are not merely
;; tolerated here: a global is the ONLY way to share one, since the line
;; above refuses the capture. That is exactly inverted from the channel.
(test-equal "global works: mutex (the only supported route)"
  'ok
  (on-child (lambda () (mutex-lock! g-mutex) (mutex-unlock! g-mutex) 'ok)))
(test-equal "global works: condition variable (the only supported route)"
  'ok
  (on-child (lambda () (condition-variable-signal! g-condvar) 'ok)))

;; A shared input port has ONE position, advanced by both threads.
(test-equal "global works: input port shares its position"
  '(#\a #\b)
  (on-child (lambda () (list (read-char g-in-port) (read-char g-in-port)))))
(test-equal "global works: parent resumes where the child left off"
  #\c
  (read-char g-in-port))

;; A shared output port interleaves in call order across the boundary.
(write-string "P1;" g-out-port)
(test-equal "global works: output port interleaves"
  'ok
  (on-child (lambda () (write-string "CHILD;" g-out-port) 'ok)))
(write-string "P2;" g-out-port)
(test-equal "global works: interleaved output is in call order"
  "P1;CHILD;P2;"
  (get-output-string g-out-port))

(test-equal "global works: environment (eval succeeds in it)"
  3
  (on-child (lambda () (eval '(+ 1 2) g-env))))
(test-equal "global works: ephemeron"
  'k
  (on-child (lambda () (ephemeron-key g-ephemeron))))
(test-equal "global works: guardian"
  'ok
  (on-child (lambda () (g-guardian (list 1 2)) 'ok)))

;; ---------------------------------------------------------------------------
;; The copy route also governs the two boundaries that are not the thunk.
;; ---------------------------------------------------------------------------

(test-assert "join result refused: port"
  (refused? (on-child (lambda () (open-input-string "abc")))))
(test-assert "channel message refused: port"
  (refused?
   (let ((ch (make-channel)))
     (on-child (lambda () (channel-send ch (open-input-string "abc")) 'sent)))))

(let ((runner (test-runner-current)))
  (test-end "srfi18-sharing-model")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
