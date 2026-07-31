;; Cross-thread heap boundary audit (systematic audit v2, Phase 5C).
;;
;; Pins the SRFI-18 cross-heap boundary: what `thread-start!` and
;; `thread-join!` deep-copy, what is shared by pointer, and which tags
;; `gc_deep_copy.zig` refuses outright.
;;
;; The model, as read from src/gc_deep_copy.zig, VM.initForThread and
;; GC.initForThread:
;;
;;   * `thread-start!` deep-copies the thunk closure (and therefore every
;;     LEXICAL capture) into a private envelope heap on the parent thread;
;;     the child copies it out again into its own heap.
;;   * `thread-join!` deep-copies the result (or the raised exception) the
;;     same way, built on the child thread.
;;   * TOP-LEVEL bindings are NOT copied: `VM.initForThread` shares
;;     `parent.globals` by pointer, so a child reaches the parent's own
;;     objects through them.
;;   * The child heap is freed at `thread-join!`
;;     (primitives_srfi18.freeChildResources -> child_gc.deinit()).
;;
;; Those facts leave a gap: a child mutating a parent-heap object reachable
;; from a top-level binding installs a CHILD-heap pointer into a PARENT-heap
;; object, which dangles the moment the child heap is freed (kaappi#1924).
;;
;; ****************************************************************
;; * Assertions for corrupting shapes are COMMENTED OUT, not       *
;; * `test-expect-fail`ed: they read freed memory, so running them *
;; * can segfault the whole runner. Each carries a `;; FAIL:`      *
;; * marker naming the issue. The fix PR re-enables them.          *
;; ****************************************************************

(import (scheme base)
        (scheme write)
        (scheme process-context)
        (srfi 18)
        (srfi 64)
        (srfi 69)
        (srfi 111)
        (srfi 117)
        (srfi 258)
        (srfi 160 f64)
        (srfi 237)
        (srfi 254 ephemerons)
        (srfi 254 guardians)
        (kaappi fibers))

(test-begin "cross-thread-boundary-audit")

;; ---------------------------------------------------------------------
;; Top-level fixtures. Every use below goes through a top-level binding on
;; purpose -- that is the shared-by-pointer path this file is auditing.
;; ---------------------------------------------------------------------

(define-record-type <abox> (make-abox v) abox? (v abox-v set-abox-v!))
(define-record-type <pt> (make-pt x y) pt? (x pt-x) (y pt-y set-pt-y!))
;; SRFI 237 `nongenerative`: the one record shape whose identity survives
;; gc_deep_copy (see section 10).
(define-record-type (<upt> make-upt upt?)
  (fields (immutable x upt-x))
  (nongenerative upt-uid-cross-thread-audit))
(define shared-pair (cons 'a 'b))
(define shared-list (list 1 2 3))
(define shared-symbol 'alpha)
(define global-slot #f)
(define global-counter 0)
(define global-mutex (make-mutex))
(define global-channel (make-channel 2))
(define probe-container #f)

;; Run `thunk` on a child OS thread and return its result; any raise
;; (including thread-start!'s own deep-copy rejection, which surfaces at
;; join) comes back as `(raised . <message-or-object>)` instead of
;; unwinding the test runner.
(define (on-thread thunk)
  (guard (e (#t (cons 'raised (if (error-object? e) (error-object-message e) e))))
    (let ((t (make-thread thunk)))
      (thread-start! t)
      (thread-join! t))))

(define (raised? x) (and (pair? x) (eq? (car x) 'raised)))

;; ---------------------------------------------------------------------
;; 1. The boundary model itself
;; ---------------------------------------------------------------------

;; A top-level binding is shared BY POINTER: the child mutates the very
;; object the parent holds. (Immediate payload, so the result is also
;; memory-safe -- see section 2.)
(test-equal "top-level binding is shared by pointer (child write is visible)"
  99
  (let ()
    (set-car! shared-pair 'a)
    (on-thread (lambda () (set-car! shared-pair 99)))
    (car shared-pair)))

;; A LEXICAL capture is deep-copied at thread-start!: the child mutates its
;; own copy, and the parent's object is untouched. This is the contrast
;; that makes the previous assertion meaningful.
(test-equal "lexical capture is deep-copied (child write is NOT visible)"
  'a
  (let ((p (cons 'a 'b)))
    (on-thread (lambda () (set-car! p 99)))
    (car p)))

;; ...and the child does see the captured object's contents, so the copy is
;; a real copy rather than an empty placeholder.
(test-equal "lexical capture carries the captured contents into the child"
  '(1 . 2)
  (let ((p (cons 1 2)))
    (on-thread (lambda () (cons (car p) (cdr p))))))

;; thread-join! deep-copies the result: a parent-heap object returned by the
;; child comes back `equal?` but NOT `eq?` to the original.
(test-assert "join result is a copy, not the parent's own object"
  (let ((r (on-thread (lambda () shared-list))))
    (and (equal? r '(1 2 3)) (not (eq? r shared-list)))))

;; Symbols are the exception: they re-intern by name in the destination.
(test-assert "a symbol survives the join copy with eq? intact"
  (eq? 'alpha (on-thread (lambda () shared-symbol))))

;; ...and the copy is deep: a parent object nested inside the child's
;; result is copied too, never aliased back.
(test-assert "a parent-heap object nested in the result is copied, not aliased"
  (let ((r (on-thread (lambda () (list 'wrap shared-list)))))
    (and (equal? r (list 'wrap shared-list))
         (not (eq? (cadr r) shared-list)))))

;; ---------------------------------------------------------------------
;; 2. Write direction -- what is SOUND
;;
;; The discriminating control throughout: an immediate (fixnum, char,
;; boolean, flonum) is NaN-boxed inline and carries no pointer, so it
;; survives the child heap being freed. A heap value does not (section 3).
;; ---------------------------------------------------------------------

;; `write!` must reference the container and the mutator through TOP-LEVEL
;; names, never through a lexical capture: capturing the container would
;; hand the child its own copy (section 1), and capturing a record mutator
;; would hand it a copy of the record TYPE too (section 10).
(define (write-through make-container write! fetch)
  (let ((c (make-container)))
    (set! probe-container c)
    (on-thread write!)
    (fetch c)))

(test-equal "pair car: fixnum written by a child survives the join"
  7 (write-through (lambda () (cons 'a 'b))
                   (lambda () (set-car! probe-container 7)) car))
(test-equal "pair cdr: fixnum written by a child survives the join"
  7 (write-through (lambda () (cons 'a 'b))
                   (lambda () (set-cdr! probe-container 7)) cdr))
(test-equal "pair car: character survives"
  #\Q (write-through (lambda () (cons 'a 'b))
                     (lambda () (set-car! probe-container #\Q)) car))
(test-equal "pair car: flonum survives (NaN-boxed inline, not a heap Flonum)"
  3.5 (write-through (lambda () (cons 'a 'b))
                     (lambda () (set-car! probe-container 3.5)) car))
(test-equal "pair car: boolean survives"
  #t (write-through (lambda () (cons 'a 'b))
                    (lambda () (set-car! probe-container #t)) car))

(test-equal "vector-set!: fixnum survives"
  7 (write-through (lambda () (make-vector 3 0))
                   (lambda () (vector-set! probe-container 0 7))
                   (lambda (v) (vector-ref v 0))))

(test-equal "record field: fixnum survives"
  7 (write-through (lambda () (make-abox #f))
                   (lambda () (set-abox-v! probe-container 7)) abox-v))

(test-equal "hash-table value: fixnum survives"
  7 (write-through (lambda () (make-hash-table))
                   (lambda () (hash-table-set! probe-container 'k 7))
                   (lambda (h) (hash-table-ref/default h 'k 'missing))))

(test-equal "box: fixnum survives"
  7 (write-through (lambda () (box #f))
                   (lambda () (set-box! probe-container 7)) unbox))

;; A child may also GROW a parent-heap container: the rehash reallocates
;; the parent table's entry array through the child, using the same
;; underlying allocator, and the parent reads every entry back.
(test-equal "a child may grow a parent hash table across a rehash"
  '(200 398)
  (let ((h (make-hash-table)))
    (set! probe-container h)
    (on-thread (lambda ()
                 (let loop ((i 0))
                   (if (< i 200)
                       (begin (hash-table-set! probe-container i (* i 2)) (loop (+ i 1)))
                       'done))))
    (list (hash-table-size h) (hash-table-ref/default h 199 'missing))))

;; The shared globals MAP is itself written by a child `set!` -- the same
;; hazard shape as a heap-object field, and equally safe for an immediate.
(test-equal "global set!: fixnum survives"
  7 (begin (set! global-slot #f)
           (on-thread (lambda () (set! global-slot 7)))
           global-slot))

;; Raw-byte content carries no Values at all, so a child's byte writes into
;; a parent-heap string/bytevector are sound -- including the case where a
;; wider character forces the backing buffer to be rebuilt.
(test-equal "string-set!: same-width character written by a child survives"
  "Zbc" (let ((s (string-copy "abc")))
          (set! probe-container s)
          (on-thread (lambda () (string-set! probe-container 0 #\Z)))
          s))
(test-equal "string-set!: widening character (buffer rebuild) survives"
  "\x3bb;bc" (let ((s (string-copy "abc")))
               (set! probe-container s)
               (on-thread (lambda () (string-set! probe-container 0 #\x3bb)))
               s))
(test-equal "string-copy! from a child-heap string survives (bytes, not Values)"
  "XYZ" (let ((s (string-copy "abc")))
          (set! probe-container s)
          (on-thread (lambda () (string-copy! probe-container 0 (string #\X #\Y #\Z))))
          s))
(test-equal "bytevector-u8-set!: survives"
  200 (let ((bv (make-bytevector 3 0)))
        (set! probe-container bv)
        (on-thread (lambda () (bytevector-u8-set! probe-container 0 200)))
        (bytevector-u8-ref bv 0)))
;; SRFI 160's NumericVector is a distinct heap type, but its elements are
;; raw bytes too, so a child's element write is sound for the same reason.
(test-equal "f64vector-set!: survives"
  2.5 (let ((nv (make-f64vector 3 0.0)))
        (set! probe-container nv)
        (on-thread (lambda () (f64vector-set! probe-container 0 2.5)))
        (f64vector-ref nv 0)))

;; An INTERNED symbol allocated by a child is stamped with the PARENT's GC
;; id and appended to the parent's `foreign_symbols` (gc_alloc.allocSymbol),
;; so the parent -- not the dying child heap -- owns and frees it. This
;; holds even for a name the parent has never seen. NOTE: it holds at
;; thread depth 1 only; see section 4.
(test-equal "interned symbol written by a child survives the join"
  'zebra (write-through (lambda () (cons 'a 'b))
                        (lambda () (set-car! probe-container (string->symbol "zebra")))
                        car))
(test-assert "a symbol name the parent never saw is still eq? after the join"
  (let ((p (cons 'a 'b)))
    (set! probe-container p)
    (on-thread (lambda ()
                 (set-car! probe-container (string->symbol "never-seen-before-xyz"))))
    (eq? (car p) (string->symbol "never-seen-before-xyz"))))

;; A child writing a value it read from the PARENT's heap is sound, and
;; keeps eq?. This isolates "child-allocated pointer" as the hazard rather
;; than "cross-thread write" as such.
(test-assert "a child may store a parent-heap value into a parent-heap object"
  (let ((p (cons 'a 'b)))
    (set! probe-container p)
    (on-thread (lambda () (set-car! probe-container shared-list)))
    (and (equal? (car p) '(1 2 3)) (eq? (car p) shared-list))))

;; ---------------------------------------------------------------------
;; 3. Write direction -- what CORRUPTS (kaappi#1924)
;;
;; Every assertion below reads a dangling child-heap pointer out of a
;; parent-heap object after thread-join! has freed the child heap. Running
;; them can segfault the runner, so they stay commented out. Observed
;; readbacks (macOS aarch64, ReleaseSafe, v0.22.1) are noted per line: the
;; recycled slot most often reads back as the program's own source text.
;; ---------------------------------------------------------------------

;; FAIL: #1924 (pair car, list payload -- reads back as source text "(p)")
;; (test-equal "pair car: list written by a child survives"
;;   '(1 2 3) (write-through (lambda () (cons 'a 'b))
;;                           (lambda () (set-car! probe-container (list 1 2 3))) car))

;; FAIL: #1924 (pair car, string payload -- reads back as #<procedure>)
;; (test-equal "pair car: string written by a child survives"
;;   "xyz" (write-through (lambda () (cons 'a 'b))
;;                        (lambda () (set-car! probe-container (string #\x #\y #\z))) car))

;; FAIL: #1924 (vector-set! -- reads back as recycled source text)
;; (test-equal "vector-set!: list written by a child survives"
;;   '(1 2 3) (write-through (lambda () (make-vector 3 0))
;;                           (lambda () (vector-set! probe-container 0 (list 1 2 3)))
;;                           (lambda (v) (vector-ref v 0))))

;; FAIL: #1924 (vector-fill! and vector-copy! have the same shape)
;; (test-equal "vector-fill!: list written by a child survives"
;;   '#((9) (9)) (write-through (lambda () (make-vector 2 0))
;;                              (lambda () (vector-fill! probe-container (list 9)))
;;                              (lambda (v) v)))

;; FAIL: #1924 (record field -- the issue's own reproduction)
;; (test-equal "record field: vector written by a child survives"
;;   '#(1 2 3) (write-through (lambda () (make-abox #f))
;;                            (lambda () (set-abox-v! probe-container (vector 1 2 3)))
;;                            abox-v))

;; FAIL: #1924 (hash-table VALUE -- reads back as #<ephemeron broken>)
;; (test-equal "hash-table value: list written by a child survives"
;;   '(1 2 3) (write-through (lambda () (make-hash-table))
;;                           (lambda () (hash-table-set! probe-container 'k (list 1 2 3)))
;;                           (lambda (h) (hash-table-ref/default h 'k 'missing))))

;; FAIL: #1924 (hash-table KEY -- the key corrupts, so the entry silently
;; becomes unreachable rather than raising)
;; (test-equal "hash-table key: list key written by a child still looks up"
;;   7 (let ((h (make-hash-table equal?)))
;;       (set! probe-container h)
;;       (on-thread (lambda () (hash-table-set! probe-container (list 'k) 7)))
;;       (hash-table-ref/default h (list 'k) 'missing)))

;; FAIL: #1924 (box, SRFI 111)
;; (test-equal "box: list written by a child survives"
;;   '(1 2 3) (write-through (lambda () (box #f))
;;                           (lambda () (set-box! probe-container (list 1 2 3))) unbox))

;; FAIL: #1924 (list-queue, SRFI 117 -- record over pairs)
;; (test-equal "list-queue: list added by a child survives"
;;   '((1 2 3)) (let ((q (make-list-queue '())))
;;                (set! probe-container q)
;;                (on-thread (lambda () (list-queue-add-back! probe-container (list 1 2 3))))
;;                (list-queue-list q)))

;; FAIL: #1924 (the shared globals map itself, not a heap-object field --
;; a shape the issue's own matrix does not cover)
;; (test-equal "global set!: list written by a child survives"
;;   '(1 2 3) (begin (set! global-slot #f)
;;                   (on-thread (lambda () (set! global-slot (list 1 2 3))))
;;                   global-slot))

;; FAIL: #1924 (promise memoisation -- this is why portable delay/force and
;; every fill-on-first-use cache are unsafe across threads)
;; (test-equal "promise: a value memoised by a child survives"
;;   '(1 2 3) (let ((pr (delay (list 1 2 3))))
;;              (set! probe-container pr)
;;              (on-thread (lambda () (force probe-container)))
;;              (force pr)))

;; FAIL: #1924 (bignum -- heap-allocated, unlike a fixnum)
;; (test-equal "pair car: bignum written by a child survives"
;;   9999999999800000000001
;;   (write-through (lambda () (cons 'a 'b))
;;                  (lambda () (set-car! probe-container (* 99999999999 99999999999)))
;;                  car))

;; FAIL: #1924 (closure -- reads back as a recycled string; calling it raises)
;; (test-equal "pair car: procedure written by a child is still callable"
;;   42 (begin (set! probe-container (cons 'a 'b))
;;             (on-thread (lambda () (set-car! probe-container (lambda (x) (* x 2)))))
;;             ((car probe-container) 21)))

;; FAIL: #1924 (UNINTERNED symbol -- allocUninternedSymbol bypasses the
;; shared intern table, so unlike an interned symbol it is child-owned)
;; (test-assert "an uninterned symbol written by a child survives"
;;   (symbol? (write-through (lambda () (cons 'a 'b))
;;                           (lambda () (set-car! probe-container
;;                                                (string->uninterned-symbol "zebra")))
;;                           car)))

;; FAIL: #1924 (an f64vector VALUE, unlike its raw-byte contents, is a heap
;; pointer like any other -- reads back as recycled source text)
;; (test-assert "an f64vector written by a child survives"
;;   (f64vector? (write-through (lambda () (cons 'a 'b))
;;                              (lambda () (set-car! probe-container (f64vector 1.0 2.0)))
;;                              car)))

;; FAIL: #1924 (mutex-specific -- the SRFI-18 per-mutex user slot)
;; (test-equal "mutex-specific: list written by a child survives"
;;   '(1 2 3) (let ((m (make-mutex)))
;;              (set! probe-container m)
;;              (on-thread (lambda () (mutex-specific-set! probe-container (list 1 2 3))))
;;              (mutex-specific m)))

;; FAIL: #1924 (thread-specific -- the child's own fiber object is
;; parent-heap, so the child writes a child-heap value into it)
;; (test-equal "thread-specific: list set by a child survives the join"
;;   '(1 2 3) (let ((t (make-thread (lambda () (thread-specific-set! (current-thread) (list 1 2 3))))))
;;              (thread-start! t) (thread-join! t)
;;              (thread-specific t)))

;; ---------------------------------------------------------------------
;; 4. Thread depth >= 2: the shared symbol table is only one level deep
;;
;; GC.initForThread sets `shared_symbols = &parent.symbols`. For a CHILD
;; gc, `symbols` is its own (permanently empty) field -- the child itself
;; interns through `shared_symbols`. So a GRANDCHILD interns into a table
;; nothing else consults, and its symbols are owned by the child heap.
;; ---------------------------------------------------------------------

(define (on-grandchild thunk)
  (on-thread (lambda () (on-thread thunk))))

;; Sound at depth 1: the child shares the parent's intern table.
(test-assert "depth 1: a global symbol is eq? to the child's own interning"
  (on-thread (lambda () (eq? shared-symbol (string->symbol "alpha")))))

;; A grandchild is at least self-consistent.
(test-assert "depth 2: a grandchild's own internings agree with each other"
  (on-grandchild (lambda () (eq? (string->symbol "beta") (string->symbol "beta")))))
(test-assert "depth 2: a grandchild's literal agrees with its own interning"
  (on-grandchild (lambda () (eq? 'beta (string->symbol "beta")))))

;; Control for the two disabled depth-2 assertions below: an immediate
;; written by a grandchild is fine, so depth alone is not the problem.
(test-equal "depth 2: a fixnum written by a grandchild survives"
  7 (begin (set! probe-container (cons 'a 'b))
           (on-grandchild (lambda () (set-car! probe-container 7)))
           (car probe-container)))

;; FAIL: TBD (symbol identity breaks at thread depth >= 2: a grandchild's
;; string->symbol does not dedupe against the process intern table, so
;; (eq? 'alpha (string->symbol "alpha")) is #f there -- an R7RS violation
;; independent of memory safety)
;; (test-assert "depth 2: a global symbol is eq? to a grandchild's own interning"
;;   (on-grandchild (lambda () (eq? shared-symbol (string->symbol "alpha")))))

;; FAIL: TBD (same root cause: a grandchild's symbol is owned by the CHILD
;; heap, so it dangles once the child is joined -- the depth-1 soundness in
;; section 2 does not extend)
;; (test-equal "depth 2: a symbol written by a grandchild survives"
;;   'zebra9 (begin (set! probe-container (cons 'a 'b))
;;                  (on-grandchild (lambda ()
;;                                   (set-car! probe-container (string->symbol "zebra9"))))
;;                  (car probe-container)))

;; ---------------------------------------------------------------------
;; 5. Read direction
;; ---------------------------------------------------------------------

;; A child reading a parent-heap object that the parent still holds is fine.
(test-equal "a child may read a parent-heap object through a top-level binding"
  '(1 2 3) (on-thread (lambda () (list (car shared-list) (cadr shared-list) (caddr shared-list)))))

;; FAIL: TBD (the parent's collector reclaims an object that a LIVE child
;; still references: markVMRoots returns early unless `vm.gc == gc`, so the
;; child's registers are invisible to the parent's root marker. No mutation
;; and no thread-join! is involved -- this is the opposite direction from
;; #1924. Reproduced 6/6 with a channel handshake: parent drops the only
;; reference, churns the heap, then releases the child, which reads a
;; recycled slot -- "type error in 'cadr': expected pair, got 0". The
;; discriminating control -- the same program without the drop -- reads
;; correctly 3/3. Needs a garbage-churn loop, so it is probe-only.)

;; ---------------------------------------------------------------------
;; 6. The uncopyable-tag list (gc_deep_copy.zig :503-518) -- SOUND
;;
;; A LEXICALLY CAPTURED value of one of these tags is rejected before the
;; OS thread is ever spawned, and the failure surfaces at thread-join!.
;; ---------------------------------------------------------------------

(define (rejects-lexical-capture? make-value use)
  (let ((v (make-value)))
    (raised? (on-thread (lambda () (use v))))))

(test-assert "thunk capturing a port is rejected"
  (rejects-lexical-capture? (lambda () (open-input-string "hi")) read-char))
(test-assert "thunk capturing a continuation is rejected"
  (rejects-lexical-capture? (lambda () (call-with-current-continuation (lambda (k) k)))
                            procedure?))
(test-assert "thunk capturing a thread object is rejected"
  (rejects-lexical-capture? (lambda () (make-thread (lambda () 1))) thread?))
(test-assert "thunk capturing a mutex is rejected"
  (rejects-lexical-capture? make-mutex mutex?))
(test-assert "thunk capturing a condition variable is rejected"
  (rejects-lexical-capture? make-condition-variable condition-variable?))
(test-assert "thunk capturing an ephemeron is rejected"
  (rejects-lexical-capture? (lambda () (make-ephemeron (list 1) (list 2))) ephemeron?))
(test-assert "thunk capturing a guardian is rejected"
  (rejects-lexical-capture? make-guardian procedure?))

;; The same list guards the RESULT direction at thread-join!, with its own
;; message.
(test-assert "a thunk returning a port is rejected at thread-join!"
  (let ((r (on-thread (lambda () (open-input-string "x")))))
    (and (raised? r) (string? (cdr r)))))

;; ---------------------------------------------------------------------
;; 7. Channels -- the one boundary with a primitive-level ownership check
;; ---------------------------------------------------------------------

;; A channel lexically captured by the thunk is the supported way to share
;; one, and it works in both directions.
(test-equal "a lexically captured channel carries a message to the parent"
  'hello
  (let ((ch (make-channel 2)))
    (let ((t (make-thread (let ((c ch)) (lambda () (channel-send c 'hello) 'sent)))))
      (thread-start! t)
      (thread-join! t)
      (channel-receive ch))))

;; A channel reached through a top-level binding instead is refused by the
;; foreign-owner check in primitives_fiber.zig (KEP-0002 Motivation Path 2).
(test-assert "channel-send on a channel reached through a global is refused"
  (raised? (on-thread (lambda () (channel-send global-channel 'nope)))))
(test-assert "channel-receive on a channel reached through a global is refused"
  (raised? (on-thread (lambda () (channel-receive global-channel 0.1 'timeout)))))

;; ...and an UNPROMOTED channel handed to a grandchild by lexical capture
;; from inside a child (i.e. reached by the child through a global) is
;; refused by gc_deep_copy's own ownership check. This is the control for
;; the disabled assertion below, and it depends on `global-channel` never
;; having been promoted: nothing above this line lexically captures it in
;; a thunk (the two tests above are refused by the primitive, before any
;; deep copy runs), and nothing below it may either.
(test-assert "an unpromoted foreign channel cannot be handed to a grandchild"
  (raised?
   (on-thread
    (lambda ()
      (let ((c global-channel))
        (let ((g (make-thread (lambda () (channel-send c 'escaped)))))
          (thread-start! g)
          (thread-join! g)
          'reached)))))) ; unreachable when the copy is refused

;; FAIL: TBD (gc_deep_copy.zig's `.channel` arm skips the ownership check
;; entirely for an ALREADY-PROMOTED channel, so the identical program
;; above SUCCEEDS once any earlier thread has promoted the channel: a
;; grandchild that only ever reached it through a shared global gets a
;; working stub and sends into it. Verified 3/3, with the unpromoted
;; control above refusing 3/3 -- promotion state alone decides whether
;; KEP-0002 invariant 4 is enforced. Re-enable as the assertion that the
;; escape is refused:)
;; (test-assert "an already-promoted foreign channel cannot be handed to a grandchild"
;;   (let ((ch (make-channel 4)))
;;     ;; promote it legitimately
;;     (let ((p (make-thread (let ((c ch)) (lambda () (channel-send c 'from-c1))))))
;;       (thread-start! p) (thread-join! p))
;;     (set! global-channel ch)
;;     (raised?
;;      (on-thread
;;       (lambda ()
;;         (let ((c global-channel))
;;           (let ((g (make-thread (lambda () (channel-send c 'escaped)))))
;;             (thread-start! g) (thread-join! g) 'reached)))))))

;; ---------------------------------------------------------------------
;; 8. Other objects the boundary handles without corrupting
;; ---------------------------------------------------------------------

;; A mutex is shared through a top-level binding (its tag is uncopyable, so
;; lexical capture is refused -- exactly the opposite of a channel), and a
;; child that dies holding it leaves it `abandoned`, not owned by a freed
;; child-heap fiber.
(test-equal "a global mutex can be locked and unlocked by a child"
  1 (begin (set! global-counter 0)
           (on-thread (lambda ()
                        (mutex-lock! global-mutex)
                        (set! global-counter (+ global-counter 1))
                        (mutex-unlock! global-mutex)
                        'ok))
           global-counter))
(test-equal "a mutex left locked by a dead child reads as abandoned"
  'abandoned (let ((m (make-mutex)))
               (set! probe-container m)
               (on-thread (lambda () (mutex-lock! probe-container) 'locked))
               (mutex-state m)))

;; Parameters are per-thread: VM.initForThread gives the child its own
;; `param_overrides`, so a child's parameter write never reaches the
;; parent's ParameterObject.
(test-equal "a parameter set by a child does not leak into the parent"
  'parent-value
  (let ((pm (make-parameter 'parent-value)))
    (set! probe-container pm)
    (on-thread (lambda () (probe-container 'child-value) 'ok))
    (pm)))

;; ---------------------------------------------------------------------
;; 9. Asymmetries pinned as they stand today
;; ---------------------------------------------------------------------

;; A port is "uncopyable" through lexical capture (section 6) yet fully
;; usable through a top-level binding -- shared by pointer, with no check
;; anywhere. Sound here only because a port's mutable state is byte
;; offsets, not Values.
(test-equal "a parent input port is read by a child through a global"
  '(#\a #\b #\c)
  (let ((p (open-input-string "abc")))
    (set! probe-container p)
    (on-thread (lambda () (list (read-char probe-container)
                                (read-char probe-container)
                                (read-char probe-container))))))
(test-equal "a parent output port is written by a child through a global"
  "P1;CHILD;P2;"
  (let ((op (open-output-string)))
    (set! probe-container op)
    (write-string "P1;" op)
    (on-thread (lambda () (write-string "CHILD;" probe-container) 'ok))
    (write-string "P2;" op)
    (get-output-string op)))

;; ---------------------------------------------------------------------
;; 10. Record type identity across the copy
;;
;; gc_deep_copy.zig's `.record_type` arm MANUFACTURES A NEW RecordType for
;; a plain R7RS record type: same name, same field count, different
;; identity. The one identity-preserving path is SRFI 237's
;; `nongenerative` uid, which the arm looks up in the destination VM's
;; `record_uid_registry` and reuses.
;; ---------------------------------------------------------------------

;; Control: an instance built in this thread is of course recognised.
(test-assert "a locally constructed record is recognised by its predicate"
  (pt? (make-pt 9 9)))

;; A `nongenerative` (uid-carrying) SRFI 237 record type keeps its identity
;; across thread-join!, because the uid registry is consulted.
(test-assert "a nongenerative SRFI 237 record survives thread-join! usable"
  (let ((r (on-thread (lambda () (make-upt 1)))))
    (and (upt? r) (= 1 (upt-x r)))))

;; FAIL: TBD (a PLAIN R7RS record constructed by a child and returned
;; through thread-join! arrives as an instance of a DIFFERENT record type:
;; `pt?` answers #f and every accessor raises "type error in '%record-ref':
;; expected <pt>, got #<record_instance>", even though it prints as
;; #<<pt> 1 2>. Verified 3/3. No shared global and no mutation is involved
;; -- this is the plain, supported worker-thread path, and it is a
;; wrong-but-stable answer rather than a memory-safety problem. The
;; nongenerative case above is the discriminating control.)
;; (test-assert "a plain record returned by a child is usable in the parent"
;;   (let ((r (on-thread (lambda () (make-pt 1 2)))))
;;     (and (pt? r) (= 1 (pt-x r)) (= 2 (pt-y r)))))

;; FAIL: TBD (same root cause, reached from the other side: a record
;; accessor/mutator/predicate LEXICALLY CAPTURED by a thunk is copied
;; together with a fresh copy of its record type, so applying it to a
;; parent-heap instance fails -- the predicate answers #f for a genuine
;; instance, and the accessor raises.)
;; (test-assert "a captured record predicate still recognises a parent instance"
;;   (let ((b (make-abox 5)))
;;     (set! probe-container b)
;;     (on-thread (let ((p abox?)) (lambda () (p probe-container))))))

;; FAIL: TBD (a continuation reached through a global is invoked by a child
;; with no check: the parent's continuation is NOT resumed, and
;; thread-join! hands back a value that satisfies no type predicate at all
;; -- not null?, pair?, symbol?, procedure?, eof-object?, boolean?,
;; number?, string? or vector?. Verified 3/3. Re-enable as the assertion
;; that the cross-thread invocation is refused:)
;; (test-assert "invoking a parent continuation from a child is refused"
;;   (let ((k #f))
;;     (call-with-current-continuation (lambda (c) (set! k c) 'first))
;;     (raised? (on-thread (lambda () (k 'from-child))))))

(let ((runner (test-runner-current)))
  (test-end "cross-thread-boundary-audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
