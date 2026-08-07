;; Regression test for #1933: the parent's collector reclaims objects a live
;; child thread still references.
;;
;; Each SRFI-18 OS thread has its own VM and GC. A value reaches a child
;; either deep-copied (thread thunk, channel message, join result) or by
;; POINTER through the shared globals map. A child that reads a parent-heap
;; object from a global holds that object in its registers — and those
;; registers are invisible to the parent's collector (markVMRoots marks only
;; the VM owning the collecting gc), while the child's own collector skips
;; foreign-owner objects (#958). Between them, a parent-heap object referenced
;; ONLY from a live child's registers is unreachable to both markers: if the
;; parent drops its last reference (here, by deleting the hash-table entry
;; that was the sole parent-side root) and then churns the heap, the parent's
;; collection frees the object the child is still using. The child then reads
;; freed memory — a recycled-slot type error, or a hard
;; "GC: marking freed object (use-after-free)" panic under -Dgc-stress.
;;
;; The fix: the parent's collector stops every live child at a dispatch-loop
;; safepoint and marks the child's roots (registers, frames, handlers, winds,
;; exceptions, scheduler fibers) with its own gc, keeping parent-heap objects
;; the child references alive. This test drives the exact issue shape —
;; hash-table entry filled inside a procedure (so no stale base-frame
;; register retains the value), the child pulling the value into a local
;; through a channel handshake, the parent deleting the entry and churning
;; the heap, and only THEN releasing the child — with a second channel
;; handshake so the child reads the value only after the parent's churn has
;; surely recycled the old slot. Without the fix the value is freed and the
;; child's `cadr` reads garbage (wrong answer or a raise); with it the child
;; reads the intact list.

(import (scheme base) (scheme write) (srfi 18) (srfi 125) (srfi 254) (srfi 64))

(test-begin "srfi18-child-registers-1933")

(define h (make-hash-table equal?))
(define seed 100)
;; Filled inside a procedure, so the value is never a stale base-frame
;; register on the parent; and built at runtime (from `seed`), so the
;; compiler's constant-folding cannot retain it in the procedure's constant
;; pool either.
(define (fill!)
  (hash-table-set! h 'key (list seed (+ seed 1) (+ seed 2))))
(fill!)

(let ((got-ch (make-channel))
      (go-ch (make-channel)))
  (define t
    (make-thread
      (lambda ()
        (let ((v (hash-table-ref h 'key)))
          ;; Handshake 1: tell the parent the value is now held in a local.
          (channel-send got-ch 'got)
          ;; Handshake 2: wait until the parent has dropped its reference AND
          ;; churned the heap, so the freed slot is surely recycled — reading
          ;; `v` now is what used to read freed memory.
          (channel-receive go-ch)
          (cadr v)))))
  (thread-start! t)
  (channel-receive got-ch)
  ;; Drop the parent's only reference to the value...
  (hash-table-delete! h 'key)
  ;; ...and churn: enough allocations that several full collections run and
  ;; the freed pair's slot is recycled. Without the fix the child's register
  ;; was invisible to these collections and the pair was swept.
  (let loop ((i 0))
    (when (< i 400000)
      (let ((tmp (list 1 2 3 (make-vector 8 i))))
        (loop (+ i 1)))))
  (channel-send go-ch 'churned)
  (test-equal "a parent-heap object held only in a live child's registers survives the parent's collection"
    101
    (thread-join! t)))

;; Control: the same shape but WITHOUT the child — dropping the entry and
;; churning must actually free the value, proving the churn is strong enough
;; to recycle the slot (i.e. the test above is not passing vacuously because
;; nothing was ever collected). A guardian observes the collection.
(define h2 (make-hash-table equal?))
(define g2 (make-guardian))
(define seed2 200)
(define (fill2!)
  (hash-table-set! h2 'key (list seed2 (+ seed2 1) (+ seed2 2)))
  (g2 (hash-table-ref h2 'key)))
(fill2!)
(hash-table-delete! h2 'key)
(let loop ((i 0))
  (when (< i 400000)
    (let ((tmp (list 1 2 3 (make-vector 8 i))))
      (loop (+ i 1)))))
(test-assert "control: the churn really collects an unreferenced value (the test is not vacuous)"
  (pair? (g2)))

(let ((runner (test-runner-current)))
  (test-end "srfi18-child-registers-1933")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
