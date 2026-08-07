;; Regression test for #1924: a child thread mutating a shared heap object
;; installs a child-heap pointer that dangles after thread-join!.
;;
;; Each SRFI-18 OS thread has its own GC heap. Top-level bindings are shared
;; BY POINTER (VM.initForThread shares the root's globals map), so a child
;; reaching a top-level record/vector/pair/promise through the globals route
;; gets the parent's own object. A child that then stores one of ITS OWN heap
;; objects into that shared container leaves a pointer the parent's collector
;; cannot trace and the child's collector cannot see a reference to: the value
;; is freed by the child's GC (or when the child's heap is reclaimed at
;; thread-join!) while the parent's container still holds it. Reading it back
;; yields recycled garbage — `(box-v b)` printing the program's own source
;; text, or worse, a freed slot read as a callable procedure.
;;
;; The fix rejects the store BEFORE it happens: a thread may not install a
;; pointer into a heap object it does not own unless the pointer names an
;; object of that same owning heap. This pins every general mutation site —
;; record field set!, vector-set!, set-car!/set-cdr!, hash-table-set!, global
;; set!/define, and %promise-complete! (the R7RS delay/force memoisation
;; hazard) — plus the two controls that must keep working: a child storing an
;; IMMEDIATE into a shared object, and a child storing a shared parent-heap
;; object into its OWN local structure (the ordinary "copy a global into a
;; local" pattern). The sanctioned cross-heap store — a child locking a
;; parent-heap mutex, which records its own fiber as owner — is asserted to
;; keep working in srfi18-sharing-model.scm / srfi18-cross-heap-abandoned-
;; mutex.scm and is deliberately exempt.

(import (scheme base) (scheme write) (scheme lazy) (srfi 13) (srfi 18) (srfi 125) (srfi 64))

(test-begin "srfi18-cross-heap-mutation-1924")

;; Runs THUNK on a child thread and returns either its value or
;; (raised . message) — for whichever of the two raises first, the child
;; itself or the join.
(define (on-child thunk)
  (let ((t (make-thread
            (lambda ()
              (guard (e (#t (cons 'raised (error-object-message e))))
                (thunk))))))
    (guard (e (#t (cons 'raised (error-object-message e))))
      (thread-start! t)
      (thread-join! t))))

(define (raised? r) (and (pair? r) (eq? (car r) 'raised)))

(define (refused? r)
  (and (raised? r)
       (let ((msg (cdr r)))
         ;; The message names the hazard, not just any error.
         (and (string? msg)
              (not (not (string-contains msg "cannot store an object created on this thread")))))))

;; ---------------------------------------------------------------------------
;; Rejected: a child stores its own heap's object into a shared parent-heap
;; container. Each of these was a deterministic use-after-free before the fix.
;; ---------------------------------------------------------------------------

(define-record-type <box> (make-box v) box? (v box-v set-box-v!))
(define g-box (make-box #f))
(test-assert "record field set! from a child is rejected"
  (refused? (on-child (lambda () (set-box-v! g-box (list 1 2 3)) 'no-error))))
(test-equal "the shared record was not corrupted by the rejected store"
  #f (box-v g-box))

(define g-vec (make-vector 3 #f))
(test-assert "vector-set! from a child is rejected"
  (refused? (on-child (lambda () (vector-set! g-vec 0 (list 1 2 3)) 'no-error))))
(test-equal "the shared vector was not corrupted"
  #f (vector-ref g-vec 0))

(define g-pair (cons 1 2))
(test-assert "set-car! from a child is rejected"
  (refused? (on-child (lambda () (set-car! g-pair (list 9 9 9)) 'no-error))))
(test-equal "the shared pair was not corrupted"
  '(1 . 2) g-pair)

(define g-ht (make-hash-table equal?))
(test-assert "hash-table-set! from a child is rejected"
  (refused? (on-child (lambda () (hash-table-set! g-ht 'k (list 1 2 3)) 'no-error))))
(test-assert "the shared hash table was not corrupted"
  (not (hash-table-contains? g-ht 'k)))

;; The R7RS memoisation hazard: a top-level (define p (delay ...)) shared by
;; pointer, forced by a child, would memoise a child-heap value into the
;; parent-heap promise.
(define g-promise (delay (list 'slow 1 2)))
(test-assert "force on a shared promise from a child is rejected"
  (refused? (on-child (lambda () (force g-promise)))))

;; Global set!/define of a child-heap object into the shared map: the
;; (define cache #f) + fill-on-first-use idiom from a child.
(define g-counter 0)
(test-assert "set! of a heap object on a shared global from a child is rejected"
  (refused? (on-child (lambda () (set! g-counter (list 1 2 3)) 'no-error))))
(test-equal "the shared global was not corrupted"
  0 g-counter)

;; ---------------------------------------------------------------------------
;; Controls: what must keep working.
;; ---------------------------------------------------------------------------

;; An immediate (fixnum) has no lifetime — writing one into a shared object
;; is always safe.
(test-equal "set! of an immediate on a shared global from a child works"
  'ok
  (on-child (lambda () (set! g-counter (+ g-counter 1)) 'ok)))
(test-equal "the fixnum global was updated"
  1 g-counter)

;; Direction B: a child storing a shared parent-heap object into its OWN
;; local structure is the ordinary "copy a global into a local" pattern and
;; must stay legal (its safety is kaappi#1933's parent-marks-child-roots
;; invariant, not a store rejection).
(define g-shared-box (make-box 'hello))
(test-equal "a child may store a shared parent-heap object into its own vector"
  #t
  (on-child (lambda ()
              (let ((v (make-vector 2)))
                (vector-set! v 0 g-shared-box)
                (vector-set! v 1 'ok)
                (eq? (vector-ref v 0) g-shared-box)))))

;; A child mutating its OWN heap objects (created inside the thunk) is
;; entirely local and untouched by the rule.
(test-equal "a child may mutate its own heap objects"
  'ok
  (on-child (lambda ()
              (let ((box (make-box 0)))
                (set-box-v! box (list 1 2 3))
                (if (= (length (box-v box)) 3) 'ok 'bad)))))

(let ((runner (test-runner-current)))
  (test-end "srfi18-cross-heap-mutation-1924")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
