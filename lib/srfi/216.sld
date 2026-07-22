;;; SRFI 216 — SICP Prerequisites (Portable)
;;;
;;; The full spec is "four constants, five procedures, and one syntactic
;;; construction" — the small set of non-R7RS bindings SICP-era /
;;; MIT-Scheme-flavored code assumes, so that "(include (srfi sicp))"-style
;;; code from the book runs "without problems (apart from those intended
;;; by the book authors)". Per the SRFI's own words: "None of these
;;; procedures is fit for production use." (SRFI 216 does NOT define
;;; `1+`, `-1+`, `pp`, or `named-lambda` — those identifiers are simply not
;;; part of this spec, despite sometimes being associated with SICP-era
;;; code in other contexts.)
;;;
;;; Built on Kaappi's built-in (srfi 18) and (srfi 27), same as this SRFI's
;;; own reference implementation
;;; (github.com/scheme-requests-for-implementation/srfi-216,
;;; srfi/216/216.scm), with two deliberate deviations from that reference:
;;;
;;;  - (runtime): the reference computes microseconds as
;;;    (round (* (current-jiffy) (jiffies-per-second) 1e6)) — multiplying
;;;    instead of dividing by jiffies-per-second. That looks like a bug
;;;    (jiffies -> seconds is current-jiffy / jiffies-per-second) which the
;;;    reference's own test suite never catches, because it only checks
;;;    that runtime *increases*, which holds either way (any positive
;;;    monotonic scaling of current-jiffy still increases). We implement
;;;    (runtime) as plain (current-jiffy): still "an integer" (the spec's
;;;    only requirement), usable exactly the way SICP exercises use it —
;;;    (- (runtime) t0) to measure an elapsed duration — without
;;;    inheriting the arithmetic bug or inventing a unit conversion the
;;;    spec does not actually require.
;;;
;;;  - parallel-execute: the reference redirects each thread's
;;;    current-output-port to a private string port (so concurrent display
;;;    calls from the classic SICP examples don't interleave into garbled
;;;    text on a real terminal), joins every thread, then replays the
;;;    captured output in thread order — its own comment notes "return
;;;    value is not specified by SICP". Kaappi's SRFI-39 parameter objects
;;;    are ordinary shared heap values with a push/pop-style dynamic-extent
;;;    stack; two threads racing a (parameterize ((current-output-port
;;;    ...)) ...) on that very same shared parameter object is exactly the
;;;    kind of unsynchronized shared mutation this library otherwise avoids
;;;    (see below), so we skip that trick — concurrent output interleaves
;;;    at ordinary write-syscall granularity instead, same as any other
;;;    concurrent Scheme program. parallel-execute still starts every
;;;    thunk and then waits for all of them to finish before returning:
;;;    confirmed against the reference's own test suite, which inspects a
;;;    thunk's side effect immediately after parallel-execute returns with
;;;    no intervening synchronization — a non-blocking parallel-execute
;;;    would make that test (and the tests in this port) flaky.
;;;
;;; Known limitation, specific to Kaappi's threading model: SRFI-18
;;; threads here are real OS threads, each with an independent heap/GC; a
;;; thunk's closure is deep-copied when it crosses into its own thread
;;; (see kaappi/CLAUDE.md, "OS threads (SRFI-18)"). Only *global* top-level
;;; variables are actually shared between threads, because the globals
;;; table itself is shared and never deep-copied — exactly the classic
;;; SICP 3.4.1 example, (define x 10) (parallel-execute (lambda ()
;;; (set! x (* x x))) (lambda () (set! x (+ x 1)))), which this SRFI's
;;; tests exercise. A thunk that instead closes over a *local* (let-bound)
;;; mutable pair/vector does NOT share it with the other thunks passed to
;;; the same parallel-execute call — each thunk's captured environment is
;;; deep-copied independently when its thread starts. test-and-set! is
;;; therefore genuinely atomic for a cell reachable through global state
;;; (this SRFI's tests build a parallel-execute + test-and-set! critical
;;; section and confirm it never loses an update across many threads), but
;;; a from-the-book mutex built by closing over a local cell inside two
;;; parallel-execute'd lambdas will not observe a shared cell here.

(define-library (srfi 216)
  (import (scheme base) (scheme time) (srfi 18) (srfi 27))

  (export
    ;; Constants
    false true nil the-empty-stream
    ;; Time and randomness
    runtime random
    ;; Concurrency
    parallel-execute test-and-set!
    ;; Streams
    cons-stream stream-null?)

  (begin

    ;;; --- Booleans and the empty list ---

    (define false #f)
    (define true #t)
    (define nil '())

    ;;; --- Time ---

    ;; An implementation-defined monotonic integer counter, suitable for
    ;; measuring elapsed durations via (- (runtime) t0) exactly the way
    ;; SICP's exercises use it. See the file header for why this isn't
    ;; converted to a fixed unit like microseconds.
    (define (runtime) (current-jiffy))

    ;;; --- Random numbers ---

    (define (random x)
      (if (exact-integer? x)
          (random-integer x)
          (* x (random-real))))

    ;;; --- Concurrency ---

    ;; Guards every test-and-set! call regardless of which cell — coarser
    ;; than per-cell locking, but sufficient for genuine atomicity, and
    ;; this SRFI is explicitly "not fit for production use".
    (define %test-and-set-mutex (make-mutex))

    (define (test-and-set! cell)
      (mutex-lock! %test-and-set-mutex)
      (let ((prior (if (car cell) #t (begin (set-car! cell #t) #f))))
        (mutex-unlock! %test-and-set-mutex)
        prior))

    ;; Starts every thunk in its own thread, then waits for all of them to
    ;; finish before returning (see file header for why).
    (define (parallel-execute . thunks)
      (let ((threads (map make-thread thunks)))
        (for-each thread-start! threads)
        (for-each thread-join! threads)))

    ;;; --- Streams ---
    ;;; SICP 3.5's "odd" streams (one delay per cons-stream) — distinct
    ;;; from SRFI 41's "even" streams and NOT a drop-in replacement, per
    ;;; this SRFI's own text.

    (define-syntax cons-stream
      (syntax-rules ()
        ((_ a b) (cons a (delay b)))))

    (define the-empty-stream '())

    (define (stream-null? obj) (null? obj))))
