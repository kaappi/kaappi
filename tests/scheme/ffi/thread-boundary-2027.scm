;; Regression test for kaappi#2027 — an FFI handle that crosses an SRFI-18
;; thread boundary is COPIED into the receiving heap, not aliased into the
;; sender's.
;;
;; gc_deep_copy.zig used to return the source Value unchanged for
;; .ffi_library/.ffi_function, on the reasoning that a dlopen handle cannot be
;; duplicated per-heap. True of the handle, but the WRAPPER is an ordinary heap
;; object owned by one GC — and gc_collect skips foreign-owner objects while
;; marking, so the alias was a cross-heap reference neither collector could
;; see. The sender's own collector reclaimed it (no need for the child to have
;; exited), and the parent read the recycled slot back as `(0.0 . 0.0)`: an
;; ordinary pair that passes `write` and every non-FFI type check.
;;
;; The discriminating axis is which heap OWNS the handle, so all four cells of
;; the issue's matrix are below. A/A'/B aliased a parent-heap object and worked
;; by accident of lifetime; only C — child-allocated, returned — was the bug,
;; and a fix that simply refused FFI handles would have broken B.

(import (scheme base) (scheme write) (srfi 18) (srfi 120))

(define pass 0)
(define fail 0)

(define (check name ok?)
  (if ok?
      (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name) (newline))))

;; Same library and symbol basic.scm uses: libm on POSIX, the CRT on Windows,
;; and `sqrt` rather than a name the platform might inline away (OpenBSD's
;; libm exports no `fabs`).
(define libm-name (cond-expand (windows "ucrtbase") (else "libm")))

(define (open-sqrt) (ffi-fn (ffi-open libm-name) "sqrt" '(double) 'double))

;; Probe once, the way tests/scheme/audit/srfi18-deepcopy-matrix-audit.scm
;; does: a platform with no loadable libm has nothing to say about deep copy,
;; and must not fail this file. basic.scm is the unconditional canary that FFI
;; works at all on each leg, so this skip cannot hide a broken FFI.
(define parent-fn (guard (e (#t #f)) (open-sqrt)))

(define (join-thunk thunk)
  (let ((t (make-thread thunk)))
    (thread-start! t)
    (thread-join! t)))

(if (not parent-fn)
    (begin
      (display "SKIP: no loadable ")
      (display libm-name)
      (display " with a `sqrt` symbol on this platform")
      (newline))
    (begin

      (check "control: the parent's own handle works before any thread"
             (= (parent-fn 9.0) 3.0))

      ;; A — parent-owned handle, called by the child through lexical capture.
      (check "A: parent-owned handle is callable in the child"
             (= (join-thunk (lambda () (parent-fn 16.0))) 4.0))

      ;; A' — and the parent's own handle is undisturbed by the copy.
      (check "A': parent's handle still works after the join"
             (= (parent-fn 25.0) 5.0))

      ;; B — parent-owned handle captured AND returned. Must keep working:
      ;; this is the cell a blanket refusal would have broken.
      (let ((r (join-thunk (lambda () parent-fn))))
        (check "B: a parent-owned handle returned by the child is a procedure"
               (procedure? r))
        (check "B: ...and is callable" (and (procedure? r) (= (r 36.0) 6.0))))

      ;; C — THE BUG. Child-allocated handle returned through thread-join!.
      (let ((r (join-thunk (lambda () (open-sqrt)))))
        (check "C: a child-created ffi-fn arrives as a procedure" (procedure? r))
        (check "C: ...and is callable" (and (procedure? r) (= (r 49.0) 7.0))))

      ;; C, one level down: the ffi-library wrapper itself must cross too,
      ;; since the ffi-function's `library` field is what `callFfi` reads the
      ;; handle from.
      (let ((lib (join-thunk (lambda () (ffi-open libm-name)))))
        (check "C: a child-created ffi-library yields a working ffi-fn"
               (guard (e (#t #f))
                 (= ((ffi-fn lib "sqrt" '(double) 'double) 64.0) 8.0))))

      ;; The channel boundary, where the child is still RUNNING when the parent
      ;; receives and calls the handle — so this cannot be explained away as
      ;; "the child heap was freed at join".
      ;;
      ;; A second channel enforces that rather than a `thread-sleep!`, which
      ;; guarantees nothing: on a loaded runner the child could exit first and
      ;; the cell would silently degrade into cell C above.
      ;;
      ;; Neither side can deadlock. The child's send is unconditional — a
      ;; `guard` turns any failure into a sentinel it still sends — and the
      ;; parent's `go` is sent after a total `guard`, so no assertion can
      ;; escape before it and leave the child parked on `done`.
      (let ((ch (make-channel))
            (done (make-channel)))
        (let ((t (make-thread (lambda ()
                                (channel-send ch (guard (e (#t 'child-raised))
                                                   (open-sqrt)))
                                (channel-receive done)
                                'sent))))
          (thread-start! t)
          (let* ((got (channel-receive ch))
                 (callable (guard (e (#t #f))
                             (and (procedure? got) (= (got 81.0) 9.0)))))
            (channel-send done 'go)
            (check "channel: a child-created handle arrives as a procedure"
                   (procedure? got))
            (check "channel: ...and is callable while the child still runs"
                   callable)
            (thread-join! t)
            (if #f #f))))

      ;; ffi-callback stays REFUSED: it wraps a live Scheme closure, not a
      ;; process-global address, so there is nothing safe to copy.
      (let ((cb (guard (e (#t #f))
                  (ffi-callback (lambda (a b) 0) '(pointer pointer) 'int))))
        (when cb
          (check "ffi-callback is still refused at the join"
                 (guard (e (#t #t))
                   (join-thunk (lambda ()
                                 (ffi-callback (lambda (a b) 0)
                                               '(pointer pointer) 'int)))
                   #f))))))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0)
  (error "kaappi#2027 FFI thread-boundary tests failed"))
