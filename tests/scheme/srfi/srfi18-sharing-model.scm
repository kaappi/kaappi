;; Characterisation test for #1937: which values may cross a thread
;; boundary, by which of the two routes.
;;
;; A value reaches another thread either by being deep-copied (the thunk
;; closure at thread-start!, the result at thread-join!, a channel message)
;; or by being reached through the shared globals map, by pointer, with no
;; copy at all. The two routes have separate, unrelated enforcement:
;; gc_deep_copy.zig's fourteen-tag uncopyable list governs the copy route
;; only, and the globals route is checked by individual primitives for
;; exactly four types (channels, thread handles, fibers and guardians —
;; the last two added by #2001 and #2008), plus — since #1924 — a general
;; rejection of any store of a child-heap object into a shared parent-heap
;; container (the rows below, and srfi18-cross-heap-mutation-1924.scm).
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

(import (scheme base) (scheme write) (scheme eval) (scheme repl) (scheme lazy)
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
(define g-fiber (spawn (lambda () (list 1 2 3))))
(define-record-type <box> (make-box v) box? (v box-v set-box-v!))
(define g-box (make-box 0))
(define g-vector (make-vector 2 #f))
(define g-pair (cons 1 2))
(define g-promise (delay (list 'slow 1 2)))

;; Checked on this route -- the only four types that are. A fiber and a
;; guardian joined the list with #2001 and #2008: fiber-join was handing the
;; child the parent's own heap object as its documented result value, and
;; invokeGuardian was growing the parent's raw ArrayList from the child.
(test-assert "global refused: channel"
  (refused? (on-child (lambda () (channel-send g-channel 'hi)))))
(test-assert "global refused: thread handle"
  (refused? (on-child (lambda () (thread-name g-thread)))))
(test-assert "global refused: fiber"
  (refused? (on-child (lambda () (fiber-join g-fiber)))))
(test-assert "global refused: guardian"
  (refused? (on-child (lambda () (g-guardian (list 1 2))))))

;; #1924: a child MUTATING a shared parent-heap object is rejected too --
;; the general case of which the four per-type checks above are the
;; specialised instances. A store of a child-heap pointer into a shared
;; container leaves a value neither collector can keep alive (the parent's
;; collector skips it as foreign, the child's collector cannot see the
;; container), so the container comes to hold a dangling pointer the moment
;; the child's heap is freed or the child's GC sweeps. Rejected before the
;; store, at every general mutation site (record field, vector, pair,
;; hash-table, promise, global set!/define) -- see
;; srfi18-cross-heap-mutation-1924.scm for the full matrix. The mutex
;; owner/owner_thread store is the deliberate exception (the only supported
;; way to share a mutex is a global, and locking one from a child must
;; record the child's own fiber as owner).
(test-assert "global mutation refused: record field set!"
  (refused? (on-child (lambda () (set-box-v! g-box (list 1 2 3)) 'no-error))))
(test-assert "global mutation refused: vector-set!"
  (refused? (on-child (lambda () (vector-set! g-vector 0 (list 1 2 3)) 'no-error))))
(test-assert "global mutation refused: set-car!"
  (refused? (on-child (lambda () (set-car! g-pair (list 9 9 9)) 'no-error))))
(test-assert "global mutation refused: force on a shared promise"
  (refused? (on-child (lambda () (force g-promise)))))

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
;; An ephemeron is still unchecked: it is bound to one GC's collection cycle
;; the same way a guardian is, but nothing mutates a raw Zig container through
;; it, so it stays a characterisation row rather than a fix.
(test-equal "global works: ephemeron"
  'k
  (on-child (lambda () (ephemeron-key g-ephemeron))))

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
