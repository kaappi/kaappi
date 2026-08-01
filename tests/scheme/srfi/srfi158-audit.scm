;;; Audit: SRFI 158 — Generators and Accumulators
;;; Systematic audit v2, Phase 3.6 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 158 (finalized 2018-05-05), https://srfi.schemers.org/srfi-158/
;;; Quoted spec sentences appear beside the assertions they justify.
;;;
;;; Surface under test: lib/srfi/158.sld + lib/srfi/158-impl.scm, 55 exported
;;; names.  The pre-existing tests/scheme/srfi/srfi158.scm is an 11-check
;;; manual-counter regression file for one continuation bug (%call-generators);
;;; 43 of the 55 exports appeared in no test at all.  Every export is touched
;;; here.
;;;
;;; The three areas ranked highest going in — laziness/effect ordering,
;;; exhaustion stickiness, and infinite generators under bounded consumers —
;;; came back CLEAN, and are pinned below with counter-instrumented sources
;;; rather than left as prose.  The bugs are elsewhere: an inexact `start`
;;; that the sequence does not begin with, an empty sub-list that raises, and
;;; a documented spec example that cannot run at all.
;;;
;;; Portability notes for the emulated CI legs:
;;;   * Never write (list (g) (g)) — R7RS leaves argument evaluation order
;;;     unspecified, and chibi evaluates right-to-left, so the same generator
;;;     yields the reverse sequence.  Every multi-call sequence below uses
;;;     let* so the order is the program's, not the implementation's.
;;;   * An accumulator's return value for a non-eof argument is explicitly
;;;     unspecified; only its eof value is asserted.
;;;   * Every assertion touching an infinite generator is bounded by gtake or
;;;     an early-terminating consumer, so a regression that loses the bound
;;;     shows up as a CI timeout rather than a wrong value.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 158) (srfi 1) (srfi 160 u8) (srfi 69))

(test-begin "srfi158-audit")

(define (raises? thunk) (guard (e (#t #t)) (thunk) #f))
(define eof (eof-object))

;; A source generator that counts how many times it was called.  Effect
;; ordering is the one property a generator library cannot be checked for
;; from return values alone.
(define (make-counter)
  (let ((n 0)) (lambda args (if (null? args) n (set! n (+ n 1))))))
(define (counted ctr lst)
  (lambda ()
    (ctr 'bump)
    (if (null? lst) eof (let ((v (car lst))) (set! lst (cdr lst)) v))))
(define (calls-for build consume)
  ;; Returns the number of source-generator calls `consume` provoked.
  (let* ((ctr (make-counter))
         (g (build (counted ctr '(1 2 3 4 5 6 7 8 9 10)))))
    (consume g)
    (ctr)))

;; Drain a generator, then call it three more times.  Returns
;; (items post1 post2 post3) with eof normalised to the symbol eof.
(define (drain-then-poke g)
  (let loop ((acc '()) (n 0))
    (if (> n 300)
        (list (reverse acc) 'RUNAWAY 'RUNAWAY 'RUNAWAY)
        (let ((v (g)))
          (if (eof-object? v)
              (let* ((a (g)) (b (g)) (c (g)))
                (list (reverse acc)
                      (if (eof-object? a) 'eof a)
                      (if (eof-object? b) 'eof b)
                      (if (eof-object? c) 'eof c)))
              (loop (cons v acc) (+ n 1)))))))
(define (sticky? g) (equal? '(eof eof eof) (cdr (drain-then-poke g))))
(define (items-of g) (car (drain-then-poke g)))

;; An infinite generator, three ways.
(define (inf) (make-range-generator 0))
(define (circ) (circular-generator 1 2 3))

;; ---------------------------------------------------------------------------
;; 1. The spec's own documented examples, verbatim.
;; ---------------------------------------------------------------------------

(test-equal "spec example: (generator 1 2 3)"
            '(1 2 3) (generator->list (generator 1 2 3)))
(test-equal "spec example: make-iota-generator 3 8"
            '(8 9 10) (generator->list (make-iota-generator 3 8)))
(test-equal "spec example: make-iota-generator 3 8 2"
            '(8 10 12) (generator->list (make-iota-generator 3 8 2)))
(test-equal "spec example: (generator->list (make-range-generator 3) 4)"
            '(3 4 5 6) (generator->list (make-range-generator 3) 4))
(test-equal "spec example: make-range-generator 3 8"
            '(3 4 5 6 7) (generator->list (make-range-generator 3 8)))
(test-equal "spec example: make-range-generator 3 8 2"
            '(3 5 7) (generator->list (make-range-generator 3 8 2)))
(test-equal "spec example: make-coroutine-generator loop 0..2"
            '(0 1 2)
            (generator->list
             (make-coroutine-generator
              (lambda (yield) (let loop ((i 0)) (when (< i 3) (yield i) (loop (+ i 1))))))))
(test-equal "spec example: list->generator '(1 2 3 4 5)"
            '(1 2 3 4 5) (generator->list (list->generator '(1 2 3 4 5))))
(test-equal "spec example: vector->generator #(1 2 3 4 5)"
            '(1 2 3 4 5) (generator->list (vector->generator '#(1 2 3 4 5))))
(test-equal "spec example: vector->generator #(a b c d e) 2"
            '(c d e) (generator->list (vector->generator '#(a b c d e) 2)))
(test-equal "spec example: vector->generator #(a b c d e) 2 4"
            '(c d) (generator->list (vector->generator '#(a b c d e) 2 4)))
(test-equal "spec example: reverse-vector->generator #(a b c d e)"
            '(e d c b a) (generator->list (reverse-vector->generator '#(a b c d e))))
(test-equal "spec example: reverse-vector->generator #(a b c d e) 2"
            '(e d c) (generator->list (reverse-vector->generator '#(a b c d e) 2)))
(test-equal "spec example: reverse-vector->generator #(a b c d e) 2 4"
            '(d c) (generator->list (reverse-vector->generator '#(a b c d e) 2 4)))
(test-equal "spec example: reverse-vector->generator #(a b c d e) 0 2"
            '(b a) (generator->list (reverse-vector->generator '#(a b c d e) 0 2)))
(test-equal "spec example: string->generator \"abcde\""
            '(#\a #\b #\c #\d #\e) (generator->list (string->generator "abcde")))
(test-equal "spec example: make-unfold-generator doubling 0..5"
            '(0 2 4 6 8 10)
            (generator->list (make-unfold-generator (lambda (s) (> s 5))
                                                    (lambda (s) (* s 2))
                                                    (lambda (s) (+ s 1)) 0)))
(test-equal "spec example: gcons* 'a 'b over range 0 2"
            '(a b 0 1) (generator->list (gcons* 'a 'b (make-range-generator 0 2))))
(test-equal "spec example: gappend of two ranges"
            '(0 1 2 0 1)
            (generator->list (gappend (make-range-generator 0 3) (make-range-generator 0 2))))
(test-equal "spec example: (generator->list (gappend)) is the empty list"
            '() (generator->list (gappend)))
(test-equal "spec example: gmap - over range 0 3"
            '(0 -1 -2) (generator->list (gmap - (make-range-generator 0 3))))
(test-equal "spec example: gmap cons over uneven generators"
            '((1 . 4) (2 . 5))
            (generator->list (gmap cons (generator 1 2 3) (generator 4 5))))
(test-equal "spec example: gdelete 3 from (1 2 3 4 5 3 6 7)"
            '(1 2 4 5 6 7) (generator->list (gdelete 3 (generator 1 2 3 4 5 3 6 7))))
(test-equal "spec example: gdelete-neighbor-dups (a a b c a a a d c)"
            '(a b c a d c)
            (generator->list (gdelete-neighbor-dups (list->generator '(a a b c a a a d c)))))
(test-equal "spec example: gindex (a b c d e f) by (0 2 4)"
            '(a c e)
            (generator->list (gindex (list->generator '(a b c d e f))
                                     (list->generator '(0 2 4)))))
(test-equal "spec example: gselect (a b c d e f) by (#t #f #f #t #t #f)"
            '(a d e)
            (generator->list (gselect (list->generator '(a b c d e f))
                                      (list->generator '(#t #f #f #t #t #f)))))

;; The 27th documented example.  It does not run — see #2060 below.

;; ---------------------------------------------------------------------------
;; 2. Laziness: construction must not consume.
;;    Every combinator is a "generator operation", which the spec introduces
;;    with: "These procedures return new generators without consuming source
;;    values."  Instrumented, not inferred: the assertion is on the number of
;;    calls the source generator received, which no return value exposes.
;; ---------------------------------------------------------------------------

(define (built-only build) (calls-for build (lambda (g) 'discard)))

(test-equal "lazy: gmap construction consumes nothing"
            0 (built-only (lambda (s) (gmap - s))))
(test-equal "lazy: gfilter construction consumes nothing"
            0 (built-only (lambda (s) (gfilter odd? s))))
(test-equal "lazy: gremove construction consumes nothing"
            0 (built-only (lambda (s) (gremove odd? s))))
(test-equal "lazy: gtake construction consumes nothing"
            0 (built-only (lambda (s) (gtake s 2))))
(test-equal "lazy: gdrop construction consumes nothing"
            0 (built-only (lambda (s) (gdrop s 2))))
(test-equal "lazy: gtake-while construction consumes nothing"
            0 (built-only (lambda (s) (gtake-while odd? s))))
(test-equal "lazy: gdrop-while construction consumes nothing"
            0 (built-only (lambda (s) (gdrop-while odd? s))))
(test-equal "lazy: gdelete construction consumes nothing"
            0 (built-only (lambda (s) (gdelete 1 s))))
(test-equal "lazy: gdelete-neighbor-dups construction consumes nothing"
            0 (built-only (lambda (s) (gdelete-neighbor-dups s))))
(test-equal "lazy: gflatten construction consumes nothing"
            0 (built-only (lambda (s) (gflatten s))))
(test-equal "lazy: ggroup construction consumes nothing"
            0 (built-only (lambda (s) (ggroup s 2))))
(test-equal "lazy: ggroup with padding construction consumes nothing"
            0 (built-only (lambda (s) (ggroup s 2 'pad))))
(test-equal "lazy: gappend construction consumes nothing"
            0 (built-only (lambda (s) (gappend s))))
(test-equal "lazy: gcons* construction consumes nothing"
            0 (built-only (lambda (s) (gcons* 'a s))))
(test-equal "lazy: gstate-filter construction consumes nothing"
            0 (built-only (lambda (s) (gstate-filter (lambda (i st) (values #t st)) 0 s))))
(test-equal "lazy: gcombine construction consumes nothing"
            0 (built-only (lambda (s) (gcombine (lambda (x st) (values x st)) 0 s))))
(test-equal "lazy: gindex construction consumes nothing"
            0 (built-only (lambda (s) (gindex s (list->generator '(0))))))
(test-equal "lazy: gselect construction consumes nothing"
            0 (built-only (lambda (s) (gselect s (list->generator '(#t))))))
(test-equal "lazy: gmerge with a single generator consumes nothing"
            0 (built-only (lambda (s) (gmerge < s))))

;; gmerge is the documented exception, and it is the reference implementation's
;; design, not a Kaappi deviation (chibi-scheme agrees exactly): the two-argument
;; case primes both inputs at construction time.  Pinned rather than reported,
;; because the spec constrains only the merge order, never when the inputs may
;; be read, and because a lazy rewrite would change no observable result.
(test-equal "lazy: gmerge primes its left input at construction time (documented)"
            1 (built-only (lambda (s) (gmerge < s (list->generator '(4 5))))))
(test-equal "lazy: gmerge primes its right input at construction time (documented)"
            1 (built-only (lambda (s) (gmerge < (list->generator '(4 5)) s))))
(test-equal "lazy: a 4-way gmerge primes each leaf exactly once"
            2 (built-only (lambda (s) (gmerge < s (list->generator '(3))
                                              (list->generator '(4)) (list->generator '(5))))))

;; ---------------------------------------------------------------------------
;; 3. Effect ordering: demanding one item must consume the minimum.
;; ---------------------------------------------------------------------------

(define (one-item build) (calls-for build (lambda (g) (g))))

(test-equal "effects: gmap yields item 1 after exactly 1 source call"
            1 (one-item (lambda (s) (gmap - s))))
(test-equal "effects: gfilter yields item 1 after exactly 1 source call"
            1 (one-item (lambda (s) (gfilter odd? s))))
(test-equal "effects: gtake yields item 1 after exactly 1 source call"
            1 (one-item (lambda (s) (gtake s 3))))
(test-equal "effects: gcons* yields its own item without touching the source"
            0 (one-item (lambda (s) (gcons* 'a s))))
(test-equal "effects: gappend yields item 1 after exactly 1 source call"
            1 (one-item (lambda (s) (gappend s))))
(test-equal "effects: ggroup k=2 yields group 1 after exactly 2 source calls"
            2 (one-item (lambda (s) (ggroup s 2))))
(test-equal "effects: gdelete-neighbor-dups yields item 1 after 1 source call"
            1 (one-item (lambda (s) (gdelete-neighbor-dups s))))
(test-equal "effects: gstate-filter yields item 1 after exactly 1 source call"
            1 (one-item (lambda (s) (gstate-filter (lambda (i st) (values #t st)) 0 s))))
(test-equal "effects: gindex yields item 1 after exactly 1 source call"
            1 (one-item (lambda (s) (gindex s (list->generator '(0 2))))))
(test-equal "effects: gselect yields item 1 after exactly 1 source call"
            1 (one-item (lambda (s) (gselect s (list->generator '(#t #f))))))
(test-equal "effects: gdrop k=3 pays its skip on the first demand, not before"
            0 (built-only (lambda (s) (gdrop s 3))))
(test-equal "effects: gdrop k=3 consumes 4 to yield item 1"
            4 (one-item (lambda (s) (gdrop s 3))))
(test-equal "effects: gtake yields nothing and consumes nothing when k=0"
            0 (one-item (lambda (s) (gtake s 0))))

;; Early-terminating consumers: "without consuming the rest of gen".
(test-equal "effects: generator-find stops at the first match (1 call)"
            1 (calls-for (lambda (s) s) (lambda (g) (generator-find odd? g))))
(test-equal "effects: generator-any stops at the first true (1 call)"
            1 (calls-for (lambda (s) s) (lambda (g) (generator-any odd? g))))
(test-equal "effects: generator-every stops at the first false (2 calls)"
            2 (calls-for (lambda (s) s) (lambda (g) (generator-every odd? g))))
(test-equal "effects: generator->list with k reads exactly k items"
            3 (calls-for (lambda (s) s) (lambda (g) (generator->list g 3))))
(test-equal "effects: generator->reverse-list with k reads exactly k items"
            3 (calls-for (lambda (s) s) (lambda (g) (generator->reverse-list g 3))))
(test-equal "effects: generator->vector with k reads exactly k items"
            3 (calls-for (lambda (s) s) (lambda (g) (generator->vector g 3))))
(test-equal "effects: generator-fold over a 10-item source reads 11 (10 + the eof)"
            11 (calls-for (lambda (s) s) (lambda (g) (generator-fold + 0 g))))
(test-equal "effects: generator-count reads the whole source plus its eof"
            11 (calls-for (lambda (s) s) (lambda (g) (generator-count odd? g))))

;; generator->vector! reads one item past the point at which the vector fills.
;; The spec says "until vector is full or generator is exhausted" but never
;; describes the source's state afterwards, and chibi-scheme reads the same
;; extra item, so this is pinned as behaviour rather than filed.
(test-equal "effects: generator->vector! reads one item past a full vector (documented)"
            4 (calls-for (lambda (s) s)
                         (lambda (g) (generator->vector! (make-vector 3 'x) 0 g))))
(test-equal "effects: generator->vector! on an already-full vector still reads one (documented)"
            1 (calls-for (lambda (s) s)
                         (lambda (g) (generator->vector! (make-vector 3 'x) 3 g))))

;; ---------------------------------------------------------------------------
;; 4. Exhaustion.  "After a finite generator has generated all its values, it
;;    will return an end-of-file object for all subsequent calls."
;;    Checked for every constructor and every combinator, by draining and then
;;    calling three more times.
;; ---------------------------------------------------------------------------

(test-assert "exhaustion sticks: generator" (sticky? (generator 1 2)))
(test-assert "exhaustion sticks: generator with no arguments" (sticky? (generator)))
(test-assert "exhaustion sticks: list->generator" (sticky? (list->generator '(1 2))))
(test-assert "exhaustion sticks: list->generator of the empty list"
             (sticky? (list->generator '())))
(test-assert "exhaustion sticks: vector->generator" (sticky? (vector->generator #(1 2))))
(test-assert "exhaustion sticks: vector->generator of the empty vector"
             (sticky? (vector->generator #())))
(test-assert "exhaustion sticks: reverse-vector->generator"
             (sticky? (reverse-vector->generator #(1 2))))
(test-assert "exhaustion sticks: string->generator" (sticky? (string->generator "ab")))
(test-assert "exhaustion sticks: string->generator of the empty string"
             (sticky? (string->generator "")))
(test-assert "exhaustion sticks: bytevector->generator"
             (sticky? (bytevector->generator #u8(1 2))))
(test-assert "exhaustion sticks: make-iota-generator" (sticky? (make-iota-generator 2)))
(test-assert "exhaustion sticks: make-iota-generator with count 0"
             (sticky? (make-iota-generator 0)))
(test-assert "exhaustion sticks: make-range-generator" (sticky? (make-range-generator 0 2)))
(test-assert "exhaustion sticks: an empty make-range-generator"
             (sticky? (make-range-generator 2 2)))
(test-assert "exhaustion sticks: make-coroutine-generator"
             (sticky? (make-coroutine-generator (lambda (y) (y 1) (y 2)))))
(test-assert "exhaustion sticks: a coroutine generator that never yields"
             (sticky? (make-coroutine-generator (lambda (y) (if #f #f)))))
(test-assert "exhaustion sticks: make-for-each-generator over a vector"
             (sticky? (make-for-each-generator vector-for-each #(1 2))))
(test-assert "exhaustion sticks: make-for-each-generator over a string"
             (sticky? (make-for-each-generator string-for-each "ab")))
(test-assert "exhaustion sticks: make-for-each-generator over a list"
             (sticky? (make-for-each-generator for-each '(1 2))))
(test-assert "exhaustion sticks: make-unfold-generator"
             (sticky? (make-unfold-generator (lambda (s) (> s 1)) (lambda (s) s)
                                             (lambda (s) (+ s 1)) 0)))
(test-assert "exhaustion sticks: a make-unfold-generator that stops immediately"
             (sticky? (make-unfold-generator (lambda (s) #t) (lambda (s) s)
                                             (lambda (s) s) 0)))
(test-assert "exhaustion sticks: gcons*" (sticky? (gcons* 'a (generator 1))))
(test-assert "exhaustion sticks: gappend" (sticky? (gappend (generator 1) (generator 2))))
(test-assert "exhaustion sticks: gappend of empty generators"
             (sticky? (gappend (generator) (generator))))
(test-assert "exhaustion sticks: gflatten" (sticky? (gflatten (generator '(1 2) '(3)))))
(test-assert "exhaustion sticks: ggroup" (sticky? (ggroup (generator 1 2 3) 2)))
(test-assert "exhaustion sticks: ggroup with padding"
             (sticky? (ggroup (generator 1 2 3) 2 'z)))
(test-assert "exhaustion sticks: gmerge" (sticky? (gmerge < (generator 1 3) (generator 2 4))))
(test-assert "exhaustion sticks: gmap" (sticky? (gmap - (generator 1 2))))
(test-assert "exhaustion sticks: gmap over two generators"
             (sticky? (gmap + (generator 1 2) (generator 10 20))))
(test-assert "exhaustion sticks: gcombine"
             (sticky? (gcombine (lambda (x s) (values x s)) 0 (generator 1 2))))
(test-assert "exhaustion sticks: gfilter" (sticky? (gfilter odd? (generator 1 2 3))))
(test-assert "exhaustion sticks: gremove" (sticky? (gremove odd? (generator 1 2 3))))
(test-assert "exhaustion sticks: gstate-filter"
             (sticky? (gstate-filter (lambda (i s) (values #t s)) 0 (generator 1 2))))
(test-assert "exhaustion sticks: gtake" (sticky? (gtake (generator 1 2 3) 2)))
(test-assert "exhaustion sticks: gtake past the end of a short source"
             (sticky? (gtake (generator 1) 3)))
(test-assert "exhaustion sticks: gtake with padding"
             (sticky? (gtake (generator 1) 3 'z)))
(test-assert "exhaustion sticks: gtake with k=0" (sticky? (gtake (generator 1 2) 0)))
(test-assert "exhaustion sticks: gdrop" (sticky? (gdrop (generator 1 2 3) 2)))
(test-assert "exhaustion sticks: gdrop past the end" (sticky? (gdrop (generator 1 2) 5)))
(test-assert "exhaustion sticks: gdrop with k=0" (sticky? (gdrop (generator 1 2) 0)))
(test-assert "exhaustion sticks: gtake-while" (sticky? (gtake-while odd? (generator 1 3 2 5))))
(test-assert "exhaustion sticks: gtake-while that matches nothing"
             (sticky? (gtake-while even? (generator 1 3))))
(test-assert "exhaustion sticks: gdrop-while" (sticky? (gdrop-while odd? (generator 1 3 2 5))))
(test-assert "exhaustion sticks: gdrop-while that drops everything"
             (sticky? (gdrop-while odd? (generator 1 3))))
(test-assert "exhaustion sticks: gdelete" (sticky? (gdelete 1 (generator 1 2 1))))
(test-assert "exhaustion sticks: gdelete-neighbor-dups"
             (sticky? (gdelete-neighbor-dups (generator 1 1 2))))
(test-assert "exhaustion sticks: gindex" (sticky? (gindex (generator 'a 'b 'c) (generator 0 2))))
(test-assert "exhaustion sticks: gselect" (sticky? (gselect (generator 'a 'b) (generator #t #f))))

;; The same drains, checked for value as well as stickiness.
(test-equal "exhausted mid-operation: gmap stops when its shortest input does"
            '(11 22) (items-of (gmap + (generator 1 2) (generator 10 20 30))))
(test-equal "exhausted mid-operation: gcombine stops when its input does"
            '(1 2) (items-of (gcombine (lambda (x s) (values x s)) 0 (generator 1 2))))
(test-equal "exhausted mid-operation: gindex stops when the index generator does"
            '(a c) (items-of (gindex (generator 'a 'b 'c 'd) (generator 0 2))))
(test-equal "exhausted mid-operation: gindex stops when the value generator does"
            '(a) (items-of (gindex (generator 'a) (generator 0 2))))
(test-equal "exhausted mid-operation: gselect stops when the truth generator does"
            '(a) (items-of (gselect (generator 'a 'b 'c) (generator #t #f))))
(test-equal "exhausted mid-operation: gmerge drains both sides"
            '(1 2 3 4) (items-of (gmerge < (generator 1 3) (generator 2 4))))
(test-equal "exhausted mid-operation: gmerge with one side already empty"
            '(1 3) (items-of (gmerge < (generator 1 3) (generator))))
(test-equal "exhausted mid-operation: gmerge with both sides empty"
            '() (items-of (gmerge < (generator) (generator))))
(test-equal "exhausted mid-operation: ggroup returns the short final group"
            '((1 2) (3)) (items-of (ggroup (generator 1 2 3) 2)))
(test-equal "exhausted mid-operation: ggroup pads the short final group"
            '((1 2) (3 z)) (items-of (ggroup (generator 1 2 3) 2 'z)))
(test-equal "exhausted mid-operation: ggroup with an exact multiple emits no short group"
            '((1 2) (3 4)) (items-of (ggroup (generator 1 2 3 4) 2)))
(test-equal "exhausted mid-operation: ggroup k=1"
            '((1) (2) (3)) (items-of (ggroup (generator 1 2 3) 1)))
(test-equal "exhausted mid-operation: gtake short of k terminates rather than padding"
            '(1) (items-of (gtake (generator 1) 3)))
(test-equal "exhausted mid-operation: gtake with padding yields exactly k"
            '(1 z z) (items-of (gtake (generator 1) 3 'z)))
(test-equal "exhausted mid-operation: gtake with padding on an empty source"
            '(z z) (items-of (gtake (generator) 2 'z)))

;; ---------------------------------------------------------------------------
;; 5. Infinite generators under bounded consumers.  Every one of these must
;;    terminate; a regression shows up as a CI timeout.
;; ---------------------------------------------------------------------------

(test-equal "infinite: gtake bounds make-range-generator with no end"
            '(0 1 2 3 4) (generator->list (gtake (inf) 5)))
(test-equal "infinite: gtake bounds circular-generator"
            '(1 2 3 1 2 3 1) (generator->list (gtake (circ) 7)))
(test-equal "infinite: circular-generator with one argument repeats it"
            '(9 9 9) (generator->list (gtake (circular-generator 9) 3)))
(test-equal "infinite: generator->list with k bounds an endless source"
            '(0 1 2 3 4) (generator->list (inf) 5))
(test-equal "infinite: generator->reverse-list with k bounds an endless source"
            '(4 3 2 1 0) (generator->reverse-list (inf) 5))
(test-equal "infinite: generator->vector with k bounds an endless source"
            #(0 1 2 3 4) (generator->vector (inf) 5))
(test-equal "infinite: generator->vector! is bounded by the vector"
            4 (generator->vector! (make-vector 4 'x) 0 (inf)))
(test-equal "infinite: generator->string with k bounds an endless source"
            "abc" (generator->string (gmap integer->char (make-range-generator 97)) 3))
(test-equal "infinite: generator-find terminates on the first match"
            4 (generator-find (lambda (x) (> x 3)) (inf)))
(test-equal "infinite: generator-any terminates on the first true"
            4 (generator-any (lambda (x) (and (> x 3) x)) (inf)))
(test-equal "infinite: generator-every terminates on the first false"
            #f (generator-every (lambda (x) (< x 3)) (inf)))
(test-equal "infinite: gindex terminates when the index generator does"
            '(0 2 4) (generator->list (gindex (inf) (generator 0 2 4))))
(test-equal "infinite: gselect terminates when the truth generator does"
            '(0 2) (generator->list (gselect (inf) (generator #t #f #t))))
(test-equal "infinite: gtake over gmap of an endless source"
            '(0 -1 -2 -3) (generator->list (gtake (gmap - (inf)) 4)))
(test-equal "infinite: gtake over gfilter of an endless source"
            '(1 3 5 7) (generator->list (gtake (gfilter odd? (inf)) 4)))
(test-equal "infinite: gtake over gremove of an endless source"
            '(0 2 4 6) (generator->list (gtake (gremove odd? (inf)) 4)))
(test-equal "infinite: gtake over gdrop of an endless source"
            '(10 11 12) (generator->list (gtake (gdrop (inf) 10) 3)))
(test-equal "infinite: gtake-while alone bounds an endless source"
            '(0 1 2 3) (generator->list (gtake-while (lambda (x) (< x 4)) (inf))))
(test-equal "infinite: gtake over gdrop-while of an endless source"
            '(5 6 7) (generator->list (gtake (gdrop-while (lambda (x) (< x 5)) (inf)) 3)))
(test-equal "infinite: gtake over ggroup of an endless source"
            '((0 1 2) (3 4 5)) (generator->list (gtake (ggroup (inf) 3) 2)))
(test-equal "infinite: gtake over gmerge of two endless sources"
            '(0 0 1 1 2) (generator->list (gtake (gmerge < (inf) (inf)) 5)))
(test-equal "infinite: gtake over gappend with an endless tail"
            '(a 0 1 2) (generator->list (gtake (gappend (generator 'a) (inf)) 4)))
(test-equal "infinite: gtake over gcons* with an endless tail"
            '(a b 0 1) (generator->list (gtake (gcons* 'a 'b (inf)) 4)))
(test-equal "infinite: gtake over gdelete of an endless source"
            '(0 1 3 4) (generator->list (gtake (gdelete 2 (inf)) 4)))
(test-equal "infinite: gtake over gdelete-neighbor-dups of a circular source"
            '(1 2 3 1) (generator->list (gtake (gdelete-neighbor-dups (circ)) 4)))
(test-equal "infinite: gtake over gstate-filter of an endless source"
            '(0 2 4)
            (generator->list (gtake (gstate-filter (lambda (i s) (values (even? i) s)) 0 (inf)) 3)))
(test-equal "infinite: gtake over gcombine of an endless source"
            '(0 2 4)
            (generator->list (gtake (gcombine (lambda (x s) (values (+ x s) (+ s 1))) 0 (inf)) 3)))
(test-equal "infinite: gtake over gflatten of an endless source"
            '(0 1 2 3) (generator->list (gtake (gflatten (gmap list (inf))) 4)))
(test-equal "infinite: gtake nested inside a larger gtake"
            '(0 1 2) (generator->list (gtake (gtake (inf) 100) 3)))
(test-equal "infinite: generator-count over a bounded slice of an endless source"
            5 (generator-count odd? (gtake (inf) 10)))
(test-equal "infinite: generator-fold over a bounded slice of an endless source"
            45 (generator-fold + 0 (gtake (inf) 10)))
(test-equal "infinite: generator-fold stops when its shortest input does"
            '((2 1) (1 0)) (generator-fold (lambda (a b acc) (cons (list a b) acc)) '()
                                           (generator 1 2) (inf)))
(test-equal "infinite: generator-for-each stops when its shortest input does"
            3 (let ((n 0))
                (generator-for-each (lambda (a b) (set! n (+ n 1))) (generator 1 2 3) (inf))
                n))
(test-equal "infinite: generator-map->list stops when its shortest input does"
            '(1 3) (generator-map->list + (generator 1 2) (inf)))
(test-equal "infinite: gmap stops when its shortest input does"
            '(10 21) (generator->list (gmap + (inf) (generator 10 20))))
(test-equal "infinite: gtake over an unbounded make-for-each-generator"
            '(0 1 2 3 4)
            (generator->list
             (gtake (make-for-each-generator
                     (lambda (proc obj) (let l ((i 0)) (proc i) (l (+ i 1)))) 'ignored)
                    5)))
(test-equal "infinite: make-unfold-generator that never stops, bounded by gtake"
            '(0 1 2)
            (generator->list
             (gtake (make-unfold-generator (lambda (s) #f) (lambda (s) s) (lambda (s) (+ s 1)) 0) 3)))

;; ---------------------------------------------------------------------------
;; 6. make-range-generator: exactness and the first element.
;;    "The sequence begins with start, increases by step (default 1) ...
;;     If both start and step are exact, it generates exact numbers;
;;     otherwise it generates inexact numbers."
;;    The impl coerces start with (- (+ start step) step), which achieves the
;;    exactness contagion but does not leave an already-inexact start alone.
;; ---------------------------------------------------------------------------

(test-equal "range: exact start and step stay exact"
            '(3 5 7) (generator->list (make-range-generator 3 8 2)))
(test-assert "range: exact start and step generate exact numbers"
             (exact? (car (generator->list (make-range-generator 0 5 1)))))
(test-assert "range: an inexact step makes the results inexact"
             (not (exact? (car (generator->list (make-range-generator 0 5 0.5))))))
(test-assert "range: an inexact start makes the results inexact"
             (not (exact? (car (generator->list (make-range-generator 0.5 5 1))))))
(test-equal "range: exact rational start and step stay exact and unperturbed"
            '(1/3 10/21 13/21 16/21 19/21) (generator->list (make-range-generator 1/3 1 1/7)))
(test-equal "range: the one-argument (endless) form begins with start exactly"
            0.1 (car (generator->list (gtake (make-range-generator 0.1) 1))))
(test-equal "range: a negative step yields nothing when start is not below end"
            '() (generator->list (make-range-generator 5 0 -1)))
(test-equal "range: a zero step repeats start forever"
            '(0 0 0) (generator->list (gtake (make-range-generator 0 5 0) 3)))

;; CONTROL: make-iota-generator carries the identical "begins with start"
;; wording and yields start untouched at every one of these inputs.
;; Expected values are computed, not written as decimal literals: a long
;; literal like 0.30000000000000004 asserts the reader's decimal->binary
;; rounding as well as the generator's arithmetic, on legs that run under
;; emulation.
(test-equal "CONTROL iota: begins with an inexact start exactly"
            (list 0.1 (+ 0.1 0.2) (+ (+ 0.1 0.2) 0.2))
            (generator->list (make-iota-generator 3 0.1 0.2)))
(test-equal "CONTROL iota: begins with a tiny inexact start exactly"
            1e-20 (car (generator->list (make-iota-generator 1 1e-20 1.0))))
(test-equal "CONTROL iota: begins with an exact rational start exactly"
            '(1/3 4/3 7/3) (generator->list (make-iota-generator 3 1/3 1)))
(test-equal "CONTROL iota: count 0 yields nothing" '() (generator->list (make-iota-generator 0)))
(test-equal "CONTROL iota: a negative count yields nothing"
            '() (generator->list (make-iota-generator -3)))
(test-equal "CONTROL iota: default start and step" '(0 1 2) (generator->list (make-iota-generator 3)))

;; FAIL: #2055 (make-range-generator does not begin the sequence with an inexact start)
;; (test-equal "range: begins with an inexact start exactly (default step)"
;;             0.1 (car (generator->list (make-range-generator 0.1 3))))
;; FAIL: #2055 (make-range-generator does not begin the sequence with an inexact start)
;; (test-equal "range: begins with an inexact start exactly (inexact step)"
;;             0.1 (car (generator->list (make-range-generator 0.1 0.5 0.2))))
;; FAIL: #2055 (a large step annihilates start entirely: 1e-20 becomes 0.0)
;; (test-equal "range: a tiny start survives a step of 1.0"
;;             1e-20 (car (generator->list (gtake (make-range-generator 1e-20 1.0 1.0) 1))))
;; FAIL: #2055 (a large step annihilates start entirely: 5.0 becomes 0.0)
;; (test-equal "range: start survives a step 16 orders of magnitude larger"
;;             5.0 (car (generator->list (gtake (make-range-generator 5.0 1e30 1e17) 1))))

;; ---------------------------------------------------------------------------
;; 7. gflatten.  "Returns a generator that yields the elements of the lists
;;    produced by the given generator."  A list with no elements contributes
;;    none; it must not be an error.
;; ---------------------------------------------------------------------------

(test-equal "gflatten: concatenates non-empty lists"
            '(1 2) (generator->list (gflatten (generator '(1) '(2)))))
(test-equal "gflatten: flattens a single multi-element list"
            '(1 2 3) (generator->list (gflatten (generator '(1 2 3)))))
(test-equal "gflatten: an empty source generator yields nothing"
            '() (generator->list (gflatten (generator))))
(test-assert "gflatten: an empty sub-list anywhere raises (see #2057)"
             (raises? (lambda () (generator->list (gflatten (generator '(1) '() '(2)))))))
(test-assert "gflatten: an empty sub-list first raises (see #2057)"
             (raises? (lambda () (generator->list (gflatten (generator '() '(1)))))))
(test-assert "gflatten: an empty sub-list last raises (see #2057)"
             (raises? (lambda () (generator->list (gflatten (generator '(1) '()))))))

;; FAIL: #2057 (gflatten raises on an empty list from its source)
;; (test-equal "gflatten: skips an empty sub-list in the middle"
;;             '(1 2) (generator->list (gflatten (generator '(1) '() '(2)))))
;; FAIL: #2057 (gflatten raises on an empty list from its source)
;; (test-equal "gflatten: skips a leading empty sub-list"
;;             '(1) (generator->list (gflatten (generator '() '(1)))))
;; FAIL: #2057 (gflatten raises on an empty list from its source)
;; (test-equal "gflatten: skips a trailing empty sub-list"
;;             '(1) (generator->list (gflatten (generator '(1) '()))))
;; FAIL: #2057 (gflatten raises on an empty list from its source)
;; (test-equal "gflatten: a filtering gmap that yields '() is a natural source"
;;             '(0 2)
;;             (generator->list (gflatten (gmap (lambda (x) (if (even? x) (list x) '()))
;;                                              (make-range-generator 0 4)))))

;; ---------------------------------------------------------------------------
;; 8. Predicate argument order, which the errata specifically clarified.
;; ---------------------------------------------------------------------------

;; gdelete: "the first is item and the second is an element generated by gen".
(test-equal "gdelete: = receives (item, generated) in that order"
            '(1 2) (generator->list (gdelete 2 (generator 1 2 3) (lambda (a b) (< a b)))))
(test-equal "gdelete: the default = is equal?, so lists compare structurally"
            '((2)) (generator->list (gdelete '(1) (generator '(1) '(2) '(1)))))
;; gdelete-neighbor-dups: "the first was generated by gen before the second".
(test-equal "gdelete-neighbor-dups: = receives (earlier, later) in that order"
            '(1) (generator->list (gdelete-neighbor-dups (generator 1 2 3 4) (lambda (a b) (< a b)))))
(test-equal "gdelete-neighbor-dups: the default = is equal?"
            '((1) (2) (1)) (generator->list (gdelete-neighbor-dups (generator '(1) '(1) '(2) '(1)))))
;; gmerge: "If the items are equal, the leftmost item is used first."
(test-equal "gmerge: equal items take the leftmost first"
            '(a1 b1 a2 b2)
            (map car (generator->list (gmerge (lambda (x y) (< (cdr x) (cdr y)))
                                              (generator '(a1 . 1) '(a2 . 2))
                                              (generator '(b1 . 1) '(b2 . 2))))))
(test-assert "gmerge: a single generator is returned unchanged (spec: 'it is returned')"
             (let ((g (generator 1))) (eq? g (gmerge < g))))
(test-equal "gmerge: three generators merge in order"
            '(1 2 3 4 5 6)
            (generator->list (gmerge < (generator 1 4) (generator 2 5) (generator 3 6))))
(test-equal "gmerge: four generators merge in order"
            '(1 2 3 4) (generator->list (gmerge < (generator 1) (generator 2)
                                                (generator 3) (generator 4))))
(test-assert "gmerge: with no generator at all it is an error"
             (raises? (lambda () (gmerge <))))
(test-assert "gmap: with no generator at all it is an error"
             (raises? (lambda () (gmap -))))

;; ---------------------------------------------------------------------------
;; 9. Consumers.
;; ---------------------------------------------------------------------------

(test-equal "generator->list: drains to the end" '(1 2 3) (generator->list (generator 1 2 3)))
(test-equal "generator->list: k=0 yields the empty list" '() (generator->list (generator 1 2) 0))
(test-equal "generator->list: k larger than the source stops at the source"
            '(1 2) (generator->list (generator 1 2) 9))
(test-equal "generator->reverse-list: drains to the end"
            '(3 2 1) (generator->reverse-list (generator 1 2 3)))
(test-equal "generator->reverse-list: k=0 yields the empty list"
            '() (generator->reverse-list (generator 1 2) 0))
(test-equal "generator->vector: drains to the end" #(1 2 3) (generator->vector (generator 1 2 3)))
(test-equal "generator->vector: k=0 yields the empty vector"
            #() (generator->vector (generator 1 2) 0))
(test-equal "generator->vector!: returns the number of elements written"
            2 (generator->vector! (make-vector 4 'x) 1 (generator 'a 'b)))
(test-equal "generator->vector!: writes at the given offset"
            #(x a b x) (let ((v (make-vector 4 'x))) (generator->vector! v 1 (generator 'a 'b)) v))
(test-equal "generator->vector!: an exhausted source writes nothing"
            0 (generator->vector! (make-vector 2 'x) 0 (generator)))
(test-equal "generator->string: drains to the end"
            "kaappi" (generator->string (generator #\k #\a #\a #\p #\p #\i)))
(test-equal "generator->string: k bounds the result"
            "kaa" (generator->string (generator #\k #\a #\a #\p) 3))
(test-equal "generator->string: k=0 yields the empty string"
            "" (generator->string (generator #\a) 0))
(test-assert "generator->string: a non-character item is an error"
             (raises? (lambda () (generator->string (generator 1 2)))))
(test-equal "generator-fold: one generator folds like SRFI 1 fold"
            '(3 2 1) (generator-fold cons '() (generator 1 2 3)))
(test-equal "generator-fold: the seed is returned for an empty generator"
            'z (generator-fold cons 'z (generator)))
(test-equal "generator-fold: two generators pass both values then the seed"
            '(33 22 11)
            (generator-fold (lambda (a b acc) (cons (+ a b) acc)) '()
                            (generator 1 2 3) (generator 10 20 30)))
(test-equal "generator-map->list: maps and preserves order"
            '(5 7 9) (generator-map->list + (generator 1 2 3) (generator 4 5 6)))
(test-equal "generator-map->list: an empty generator yields the empty list"
            '() (generator-map->list - (generator)))
(test-equal "generator-for-each: visits every item in order"
            '(1 2 3) (let ((acc '()))
                       (generator-for-each (lambda (v) (set! acc (cons v acc))) (generator 1 2 3))
                       (reverse acc)))
(test-equal "generator-for-each: two generators are visited pairwise"
            '(11 22) (let ((acc '()))
                       (generator-for-each (lambda (a b) (set! acc (cons (+ a b) acc)))
                                           (generator 1 2) (generator 10 20))
                       (reverse acc)))
(test-equal "generator-find: returns the matching item"
            2 (generator-find even? (generator 1 2 3)))
(test-equal "generator-find: returns #f when the generator is exhausted"
            #f (generator-find even? (generator 1 3)))
(test-equal "generator-find: returns #f on an empty generator"
            #f (generator-find even? (generator)))
(test-equal "generator-count: counts matching items" 2 (generator-count odd? (generator 1 2 3)))
(test-equal "generator-count: an empty generator counts 0" 0 (generator-count odd? (generator)))
(test-equal "generator-any: returns pred's value, not #t"
            'found (generator-any (lambda (x) (and (even? x) 'found)) (generator 1 2 3)))
(test-equal "generator-any: returns #f when nothing matches"
            #f (generator-any even? (generator 1 3)))
(test-equal "generator-any: an empty generator returns #f" #f (generator-any even? (generator)))
(test-equal "generator-every: returns the last value pred returned"
            'last (generator-every (lambda (x) 'last) (generator 1 2 3)))
(test-equal "generator-every: returns #f at the first false"
            #f (generator-every even? (generator 2 3 4)))
(test-equal "generator-every: an empty generator returns #t (pred never called)"
            #t (generator-every even? (generator)))
(test-equal "generator-unfold: over a plain generator"
            '(1 2 3) (generator-unfold (list->generator '(1 2 3)) unfold))
(test-equal "generator-unfold: over an empty generator"
            '() (generator-unfold (generator) unfold))
(test-equal "generator-unfold: extra arguments reach unfold's tail-gen slot"
            '(1 2 end) (generator-unfold (generator 1 2) unfold (lambda (x) '(end))))

;; ---------------------------------------------------------------------------
;; 10. make-for-each-generator and make-unfold-generator.
;; ---------------------------------------------------------------------------

(test-equal "make-for-each-generator: over a list" '(1 2 3)
            (generator->list (make-for-each-generator for-each '(1 2 3))))
(test-equal "make-for-each-generator: over a vector" '(1 2 3)
            (generator->list (make-for-each-generator vector-for-each #(1 2 3))))
(test-equal "make-for-each-generator: over a string" '(#\a #\b #\c)
            (generator->list (make-for-each-generator string-for-each "abc")))
(test-equal "make-for-each-generator: over an empty list" '()
            (generator->list (make-for-each-generator for-each '())))
(test-equal "make-for-each-generator: over an empty vector" '()
            (generator->list (make-for-each-generator vector-for-each #())))
(test-equal "make-for-each-generator: a caller-supplied tree walker"
            '(1 2 3 4 5)
            (generator->list
             (make-for-each-generator
              (lambda (proc tree)
                (let walk ((t tree))
                  (cond ((null? t) 'x) ((pair? t) (walk (car t)) (walk (cdr t))) (else (proc t)))))
              '((1 2) (3 (4 5))))))
(test-equal "make-unfold-generator: stop? is consulted before the first item"
            '() (generator->list (make-unfold-generator (lambda (s) #t) (lambda (s) s)
                                                        (lambda (s) (+ s 1)) 0)))
(test-equal "make-unfold-generator: mapper transforms each seed"
            '(0 10 20) (generator->list (make-unfold-generator (lambda (s) (> s 2))
                                                               (lambda (s) (* s 10))
                                                               (lambda (s) (+ s 1)) 0)))

;; ---------------------------------------------------------------------------
;; 11. Accumulators.  "if an end-of-file object is passed, the accumulator
;;     returns the result of tail-calling the procedure finalizer on the
;;     state ... end-of-file objects may be passed repeatedly, and always
;;     produce the same result."
;;     The value returned for a NON-eof argument is unspecified and is
;;     deliberately not asserted anywhere below.
;; ---------------------------------------------------------------------------

(define (accumulate acc items) (for-each acc items) (acc eof))
(define (accumulate-twice acc items)
  (for-each acc items)
  (let* ((a (acc eof)) (b (acc eof))) (equal? a b)))

(test-equal "count-accumulator: counts what it was given"
            3 (accumulate (count-accumulator) '(a b c)))
(test-equal "count-accumulator: counts 0 when given nothing"
            0 (accumulate (count-accumulator) '()))
(test-equal "list-accumulator: preserves accumulation order"
            '(1 2 3) (accumulate (list-accumulator) '(1 2 3)))
(test-equal "list-accumulator: yields the empty list when given nothing"
            '() (accumulate (list-accumulator) '()))
(test-equal "reverse-list-accumulator: reverses accumulation order"
            '(3 2 1) (accumulate (reverse-list-accumulator) '(1 2 3)))
(test-equal "reverse-list-accumulator: yields the empty list when given nothing"
            '() (accumulate (reverse-list-accumulator) '()))
(test-equal "vector-accumulator: preserves accumulation order"
            #(1 2 3) (accumulate (vector-accumulator) '(1 2 3)))
(test-equal "vector-accumulator: yields the empty vector when given nothing"
            #() (accumulate (vector-accumulator) '()))
(test-equal "reverse-vector-accumulator: reverses accumulation order"
            #(3 2 1) (accumulate (reverse-vector-accumulator) '(1 2 3)))
(test-equal "string-accumulator: preserves accumulation order"
            "abc" (accumulate (string-accumulator) (list #\a #\b #\c)))
(test-equal "string-accumulator: yields the empty string when given nothing"
            "" (accumulate (string-accumulator) '()))
(test-equal "bytevector-accumulator: preserves accumulation order"
            #u8(1 2 3) (accumulate (bytevector-accumulator) '(1 2 3)))
(test-equal "bytevector-accumulator: yields the empty bytevector when given nothing"
            #u8() (accumulate (bytevector-accumulator) '()))
(test-equal "sum-accumulator: sums what it was given" 6 (accumulate (sum-accumulator) '(1 2 3)))
(test-equal "sum-accumulator: the identity for an empty sum is 0"
            0 (accumulate (sum-accumulator) '()))
(test-equal "product-accumulator: multiplies what it was given"
            24 (accumulate (product-accumulator) '(2 3 4)))
(test-equal "product-accumulator: the identity for an empty product is 1"
            1 (accumulate (product-accumulator) '()))
(test-equal "vector-accumulator!: returns the vector it was given"
            #(x a b x) (accumulate (vector-accumulator! (make-vector 4 'x) 1) '(a b)))
(test-assert "vector-accumulator!: writes into the caller's own vector"
             (let ((v (make-vector 4 'x))) (accumulate (vector-accumulator! v 1) '(a b))
                  (equal? v #(x a b x))))
(test-equal "bytevector-accumulator!: returns the bytevector it was given"
            #u8(0 7 8 0) (accumulate (bytevector-accumulator! (make-bytevector 4 0) 1) '(7 8)))
(test-equal "make-accumulator: kons is called as (kons obj state), fold order"
            '(3 2 1) (accumulate (make-accumulator cons '() (lambda (x) x)) '(1 2 3)))
(test-equal "make-accumulator: the finalizer transforms the final state"
            3 (accumulate (make-accumulator cons '() length) '(1 2 3)))
(test-equal "make-accumulator: knil is the state when nothing is accumulated"
            'seed (accumulate (make-accumulator cons 'seed (lambda (x) x)) '()))

(test-assert "repeated eof: count-accumulator gives the same answer twice"
             (accumulate-twice (count-accumulator) '(a b c)))
(test-assert "repeated eof: list-accumulator gives the same answer twice"
             (accumulate-twice (list-accumulator) '(1 2 3)))
(test-assert "repeated eof: reverse-list-accumulator gives the same answer twice"
             (accumulate-twice (reverse-list-accumulator) '(1 2 3)))
(test-assert "repeated eof: vector-accumulator gives the same answer twice"
             (accumulate-twice (vector-accumulator) '(1 2 3)))
(test-assert "repeated eof: reverse-vector-accumulator gives the same answer twice"
             (accumulate-twice (reverse-vector-accumulator) '(1 2 3)))
(test-assert "repeated eof: string-accumulator gives the same answer twice"
             (accumulate-twice (string-accumulator) (list #\a #\b)))
(test-assert "repeated eof: bytevector-accumulator gives the same answer twice"
             (accumulate-twice (bytevector-accumulator) '(1 2 3)))
(test-assert "repeated eof: sum-accumulator gives the same answer twice"
             (accumulate-twice (sum-accumulator) '(1 2 3)))
(test-assert "repeated eof: product-accumulator gives the same answer twice"
             (accumulate-twice (product-accumulator) '(2 3 4)))
(test-assert "repeated eof: vector-accumulator! gives the same answer twice"
             (accumulate-twice (vector-accumulator! (make-vector 4 'x) 1) '(a b)))
(test-assert "repeated eof: bytevector-accumulator! gives the same answer twice"
             (accumulate-twice (bytevector-accumulator! (make-bytevector 4 0) 1) '(7 8)))
(test-assert "repeated eof: make-accumulator gives the same answer twice"
             (accumulate-twice (make-accumulator cons '() reverse) '(1 2 3)))

;; The mutating accumulators inherit their element rules from the underlying
;; bytevector, so an out-of-range byte is rejected at the write, not silently
;; truncated.
(test-assert "bytevector-accumulator: rejects a byte above 255"
             (raises? (lambda () (accumulate (bytevector-accumulator) '(256)))))
(test-assert "bytevector-accumulator: rejects a negative byte"
             (raises? (lambda () (accumulate (bytevector-accumulator) '(-1)))))
(test-assert "bytevector-accumulator!: rejects a byte above 255"
             (raises? (lambda () (accumulate (bytevector-accumulator! (make-bytevector 2 0) 0) '(256)))))
(test-assert "vector-accumulator!: overflowing the vector is an error"
             (raises? (lambda () (accumulate (vector-accumulator! (make-vector 2 'x) 0) '(1 2 3)))))
(test-assert "bytevector-accumulator!: overflowing the bytevector is an error"
             (raises? (lambda () (accumulate (bytevector-accumulator! (make-bytevector 2 0) 0) '(1 2 3)))))

;; Generator and accumulator are inverses; the round trip is the cheapest
;; end-to-end check of both halves at once.
(test-equal "round trip: list->generator through list-accumulator"
            '(1 2 3)
            (let ((a (list-accumulator))) (generator-for-each a (list->generator '(1 2 3))) (a eof)))
(test-equal "round trip: vector->generator through vector-accumulator"
            #(1 2 3)
            (let ((a (vector-accumulator))) (generator-for-each a (vector->generator #(1 2 3))) (a eof)))
(test-equal "round trip: string->generator through string-accumulator"
            "abc"
            (let ((a (string-accumulator))) (generator-for-each a (string->generator "abc")) (a eof)))
(test-equal "round trip: bytevector->generator through bytevector-accumulator"
            #u8(1 2 3)
            (let ((a (bytevector-accumulator)))
              (generator-for-each a (bytevector->generator #u8(1 2 3))) (a eof)))
(test-equal "round trip: reverse-vector->generator through reverse-vector-accumulator"
            #(1 2 3)
            (let ((a (reverse-vector-accumulator)))
              (generator-for-each a (reverse-vector->generator #(1 2 3))) (a eof)))
(test-equal "round trip: an endless source bounded by gtake into count-accumulator"
            7 (let ((a (count-accumulator))) (generator-for-each a (gtake (inf) 7)) (a eof)))

;; ---------------------------------------------------------------------------
;; 12. Bounded slices of the remaining constructors, and index bounds.
;; ---------------------------------------------------------------------------

(test-equal "bytevector->generator: default bounds" '(1 2 3)
            (generator->list (bytevector->generator #u8(1 2 3))))
(test-equal "bytevector->generator: start only" '(2 3)
            (generator->list (bytevector->generator #u8(1 2 3) 1)))
(test-equal "bytevector->generator: start and end" '(2)
            (generator->list (bytevector->generator #u8(1 2 3) 1 2)))
(test-equal "string->generator: start only" '(#\c #\d)
            (generator->list (string->generator "abcd" 2)))
(test-equal "string->generator: start and end" '(#\c)
            (generator->list (string->generator "abcd" 2 3)))
(test-equal "vector->generator: start equal to end yields nothing" '()
            (generator->list (vector->generator #(a b c) 1 1)))
(test-equal "string->generator: start equal to end yields nothing" '()
            (generator->list (string->generator "abc" 1 1)))
(test-equal "reverse-vector->generator: start equal to end yields nothing" '()
            (generator->list (reverse-vector->generator #(a b c) 1 1)))
(test-equal "generator: with no arguments is empty" '() (generator->list (generator)))
(test-equal "circular-generator: cycles a two-element list"
            '(a b a b a) (generator->list (gtake (circular-generator 'a 'b) 5)))

;; ---------------------------------------------------------------------------
;; 13. Composition depth, and sources that raise or escape.
;; ---------------------------------------------------------------------------

(test-equal "depth: 20 nested gmap layers"
            '(20 21 22 23 24)
            (let loop ((i 0) (g (make-range-generator 0 5)))
              (if (= i 20) (generator->list g) (loop (+ i 1) (gmap (lambda (x) (+ x 1)) g)))))
(test-equal "depth: 20 nested gtake layers (each a coroutine generator)"
            '(0 1 2 3 4)
            (let loop ((i 0) (g (make-range-generator 0 100)))
              (if (= i 20) (generator->list g) (loop (+ i 1) (gtake g 5)))))
(test-equal "depth: 20 nested gfilter layers"
            '(0 1 2 3 4)
            (let loop ((i 0) (g (make-range-generator 0 5)))
              (if (= i 20) (generator->list g) (loop (+ i 1) (gfilter (lambda (x) #t) g)))))
(test-equal "depth: 20 nested gdrop layers"
            '(20 21 22 23 24)
            (let loop ((i 0) (g (make-range-generator 0 25)))
              (if (= i 20) (generator->list g) (loop (+ i 1) (gdrop g 1)))))
;; Flat top-level helpers rather than nested internal lambdas: a deeply nested
;; first draft of this form mis-balanced its closing parens, which the reader
;; reports 800 lines away from the mistake.
(define (relay-body inner)
  (lambda (yield)
    (let l ()
      (let ((v (inner)))
        (unless (eof-object? v) (yield v) (l))))))
(define (relay inner) (make-coroutine-generator (relay-body inner)))
(test-equal "depth: 20 nested make-coroutine-generator layers"
            '(0 1 2 3 4)
            (let loop ((i 0) (g (make-range-generator 0 5)))
              (if (= i 20) (generator->list g) (loop (+ i 1) (relay g)))))
(test-equal "depth: a 20-layer chain mixing gmap, gfilter, gtake and gcons*"
            '(0 1 2 3 4 5 6 7 8 9)
            (let loop ((i 0) (g (make-range-generator 0 10)))
              (if (= i 20) (generator->list g)
                  (loop (+ i 1)
                        (case (modulo i 3)
                          ((0) (gmap (lambda (x) x) g))
                          ((1) (gfilter (lambda (x) #t) g))
                          (else (gtake g 30)))))))

(test-assert "raising source: gmap propagates the source's error"
             (raises? (lambda ()
                        (let ((n 0))
                          (generator->list
                           (gmap - (lambda () (set! n (+ n 1))
                                           (if (> n 2) (error "boom") n))))))))
(test-assert "raising source: gtake propagates the source's error"
             (raises? (lambda ()
                        (let ((n 0))
                          (generator->list
                           (gtake (lambda () (set! n (+ n 1))
                                          (if (> n 2) (error "boom") n)) 5))))))
(test-assert "raising source: a coroutine body's error reaches the caller"
             (raises? (lambda ()
                        (generator->list
                         (make-coroutine-generator (lambda (yield) (yield 1) (error "boom")))))))
(test-equal "raising source: guard at the FIRST call of a coroutine generator catches"
            'caught
            (let* ((n 0)
                   (src (lambda () (set! n (+ n 1)) (if (= n 1) (error "boom") n)))
                   (g (gtake src 4)))
              (guard (e (#t 'caught)) (g))))
(test-equal "raising source: guard around a non-coroutine gmap catches at any call"
            '(-1 caught -3)
            (let* ((n 0)
                   (src (lambda () (set! n (+ n 1)) (if (= n 2) (error "boom") n)))
                   (g (gmap - src))
                   (a (g))
                   (b (guard (e (#t 'caught)) (g)))
                   (c (guard (e (#t 'caught2)) (g))))
              (list a b c)))
;; A resumed coroutine re-enters the dynamic environment captured at its yield
;; point, which is the FIRST caller's, so a guard installed around a LATER call
;; is not in scope for an error raised inside the body.  This follows from
;; R7RS 4.2.7 rather than from anything SRFI 158 says; it is pinned so a change
;; in either direction is visible.
(test-assert "raising source: a guard around a LATER coroutine call does not see the error"
             (raises? (lambda ()
                        (let* ((n 0)
                               (src (lambda () (set! n (+ n 1)) (if (= n 2) (error "boom") n)))
                               (g (gtake src 4))
                               (a (g)))
                          (guard (e (#t 'caught)) (g))))))
(test-equal "escaping source: call/cc out of a generator->list drive"
            'escaped
            (call/cc (lambda (k)
                       (generator->list
                        (gmap (lambda (x) (if (= x 3) (k 'escaped) x)) (make-range-generator 0 10))))))
(test-equal "escaping source: call/cc out of a gtake coroutine"
            'escaped
            (call/cc (lambda (k) (generator->list (gtake (lambda () (k 'escaped)) 3)))))
(test-equal "coroutine generators interleave without interfering"
            '(a1 b1 a2 b2 a3 b3)
            (let* ((ga (make-coroutine-generator (lambda (y) (y 'a1) (y 'a2) (y 'a3))))
                   (gb (make-coroutine-generator (lambda (y) (y 'b1) (y 'b2) (y 'b3))))
                   (v1 (ga)) (v2 (gb)) (v3 (ga)) (v4 (gb)) (v5 (ga)) (v6 (gb)))
              (list v1 v2 v3 v4 v5 v6)))
(test-equal "dynamic-wind inside a coroutine runs once per suspension"
            '(in out in out in out)
            (let* ((log '())
                   (g (make-coroutine-generator
                       (lambda (yield)
                         (dynamic-wind (lambda () (set! log (cons 'in log)))
                                       (lambda () (yield 1) (yield 2))
                                       (lambda () (set! log (cons 'out log)))))))
                   (v1 (g)) (v2 (g)) (v3 (g)))
              (reverse log)))

;; ---------------------------------------------------------------------------
;; 14. Cross-library seams.
;; ---------------------------------------------------------------------------

;; SRFI 160.  "Returns a SRFI 121 generator that generates all the values of
;; @vector in order.  Note that the generator is finite." — one argument only,
;; so rejecting start/end is correct, not a gap.
(test-equal "seam: make-u8vector-generator feeds SRFI 158 consumers"
            '(1 2 3) (generator->list (make-u8vector-generator (u8vector 1 2 3))))
(test-equal "seam: make-u8vector-generator is finite and its exhaustion sticks"
            '(eof eof eof) (cdr (drain-then-poke (make-u8vector-generator (u8vector 1 2)))))
(test-equal "seam: gtake bounds a SRFI 160 generator"
            '(1 2) (generator->list (gtake (make-u8vector-generator (u8vector 1 2 3)) 2)))
(test-equal "seam: a SRFI 160 generator round-trips through bytevector-accumulator"
            #u8(1 2 3)
            (let ((a (bytevector-accumulator)))
              (generator-for-each a (make-u8vector-generator (u8vector 1 2 3))) (a eof)))
(test-assert "seam: make-u8vector-generator takes exactly one argument (SRFI 160)"
             (raises? (lambda () (make-u8vector-generator (u8vector 1 2 3) 1 3))))
;; Any for-each-shaped procedure is a generator source in principle, which is
;; how the hash-table seam would be reached without either library knowing about
;; SRFI 158.  It does not work here — see the driver section below.
(test-equal "seam: SRFI 1 iota feeds list->generator"
            '(0 1 2 3) (generator->list (list->generator (iota 4))))
(test-equal "seam: generator->list output feeds SRFI 1 fold"
            6 (fold + 0 (generator->list (gtake (inf) 4))))

;; ---------------------------------------------------------------------------
;; 15. Native drivers.  SRFI 158's own 27th documented example is
;;
;;       (generator-unfold (make-for-each-generator string-for-each "abc") unfold)
;;                                                              => (#\a #\b #\c)
;;
;;     and it does not run: SRFI 1's `unfold` is a native driver, and every
;;     coroutine-backed generator — make-coroutine-generator,
;;     make-for-each-generator, make-unfold-generator, and gtake — resumes a
;;     continuation captured under it.  See #2060.
;;     The controls below isolate the mechanism to the driver, not the SRFI.
;; ---------------------------------------------------------------------------

(define (portable-unfold stop? mapper successor seed . rest)
  (let loop ((s seed)) (if (stop? s) '() (cons (mapper s) (loop (successor s))))))
(define (fresh-coroutine) (make-coroutine-generator (lambda (y) (y 1) (y 2) (y 3))))
(define (hash-walk proc t) (hash-table-walk t (lambda (k v) (proc v))))
(define (fold-walk proc lst) (fold (lambda (x acc) (proc x) acc) '() lst))
(define (one-entry-table) (let ((h (make-hash-table equal?))) (hash-table-set! h 'a 1) h))

(test-equal "CONTROL driver: a coroutine generator + a portable unfold works"
            '(#\a #\b #\c)
            (generator-unfold (make-for-each-generator string-for-each "abc") portable-unfold))
(test-equal "CONTROL driver: a plain generator + SRFI 1's native unfold works"
            '(#\a #\b #\c) (generator-unfold (string->generator "abc") unfold))
(test-equal "CONTROL driver: a plain generator + a portable unfold works"
            '(#\a #\b #\c) (generator-unfold (string->generator "abc") portable-unfold))
(test-equal "CONTROL driver: map is bytecode-driven, so it can resume a coroutine"
            '(1 2 3) (let ((g (fresh-coroutine))) (map (lambda (i) (g)) '(a b c))))
(test-equal "CONTROL driver: vector-map is bytecode-driven"
            #(1 2) (let ((g (fresh-coroutine))) (vector-map (lambda (i) (g)) #(a b))))
(test-equal "CONTROL driver: for-each is bytecode-driven"
            '(1 2 3) (let ((g (fresh-coroutine)) (acc '()))
                       (for-each (lambda (i) (set! acc (cons (g) acc))) '(a b c))
                       (reverse acc)))
(test-equal "CONTROL driver: string-for-each is bytecode-driven"
            '(1 2) (let ((g (fresh-coroutine)) (acc '()))
                     (string-for-each (lambda (c) (set! acc (cons (g) acc))) "ab")
                     (reverse acc)))
(test-equal "CONTROL driver: a plain let* sequence resumes a coroutine freely"
            '(1 2 3) (let* ((g (fresh-coroutine)) (a (g)) (b (g)) (c (g))) (list a b c)))

(test-assert "driver: SRFI 158's own generator-unfold example raises (see #2060)"
             (raises? (lambda ()
                        (generator-unfold (make-for-each-generator string-for-each "abc") unfold))))
(test-assert "driver: gtake under SRFI 1 unfold raises (see #2060)"
             (raises? (lambda () (generator-unfold (gtake (string->generator "abcdef") 3) unfold))))
(test-assert "driver: make-unfold-generator under SRFI 1 unfold raises (see #2060)"
             (raises? (lambda ()
                        (generator-unfold
                         (make-unfold-generator (lambda (s) (> s 2)) (lambda (s) s)
                                                (lambda (s) (+ s 1)) 0)
                         unfold))))
(test-assert "driver: a coroutine generator under SRFI 1 fold raises (see #2060)"
             (raises? (lambda () (let ((g (fresh-coroutine)))
                                   (fold (lambda (i acc) (cons (g) acc)) '() '(a b c))))))
(test-assert "driver: a coroutine generator under SRFI 1 filter raises (see #2060)"
             (raises? (lambda () (let ((g (fresh-coroutine))) (filter (lambda (i) (g)) '(a b c))))))
(test-assert "driver: a coroutine generator under SRFI 1 any raises (see #2060)"
             (raises? (lambda () (let ((g (fresh-coroutine)))
                                   (any (lambda (i) (eq? 99 (g))) '(a b c))))))
(test-assert "driver: a coroutine generator under SRFI 1 every raises (see #2060)"
             (raises? (lambda () (let ((g (fresh-coroutine))) (every (lambda (i) (g)) '(a b c))))))
(test-assert "driver: a coroutine generator under hash-table-walk raises (see #2060)"
             (raises? (lambda ()
                        (let ((g (fresh-coroutine)) (h (make-hash-table equal?)) (acc '()))
                          (hash-table-set! h 'a 1) (hash-table-set! h 'b 2) (hash-table-set! h 'c 3)
                          (hash-table-walk h (lambda (k v) (set! acc (cons (g) acc))))
                          acc))))
(test-assert "driver: a gtake generator under SRFI 1 fold raises (see #2060)"
             (raises? (lambda ()
                        (let ((g (gtake (make-range-generator 0 100) 5)))
                          (fold (lambda (i acc) (cons (g) acc)) '() '(a b c))))))
(test-equal "CONTROL driver: the same gtake generator under map succeeds"
            '(0 1 2) (let ((g (gtake (make-range-generator 0 100) 5)))
                       (map (lambda (i) (g)) '(a b c))))
(test-equal "CONTROL driver: a fresh gtake per fold callback is fine — only resumption breaks"
            '((0 1) (0 1))
            (fold (lambda (i acc)
                    (cons (generator->list (gtake (make-range-generator 0 100) 2)) acc))
                  '() '(a b)))

;; make-for-each-generator's stated job is to convert ANY collection: "converts
;; any collection obj to a generator that returns its elements using a for-each
;; procedure appropriate for obj".  It works only when that for-each is one of
;; the eight bytecode-driven primitives; a hash table or any SRFI 1-shaped
;; walker cannot be converted at all.  Its very first item does come back — the
;; failure is on resumption — so the damage is not visible until the second call.
(test-equal "driver: make-for-each-generator over hash-table-walk yields item 1"
            1 ((make-for-each-generator hash-walk (one-entry-table))))
(test-assert "driver: ... but its second call raises (see #2060)"
             (raises? (lambda ()
                        (let* ((g (make-for-each-generator hash-walk (one-entry-table))) (a (g)))
                          (g)))))
(test-assert "driver: make-for-each-generator over hash-table-walk cannot be drained (see #2060)"
             (raises? (lambda ()
                        (generator->list (make-for-each-generator hash-walk (one-entry-table))))))
(test-assert "driver: make-for-each-generator over an SRFI 1 walker cannot be drained (see #2060)"
             (raises? (lambda () (generator->list (make-for-each-generator fold-walk '(1 2 3))))))
(test-assert "driver: gtake over a hash-table-backed generator raises (see #2060)"
             (raises? (lambda ()
                        (generator->list
                         (gtake (make-for-each-generator hash-walk (one-entry-table)) 2)))))
(test-equal "CONTROL driver: the same walker shape over a bytecode-driven for-each works"
            '(1 2 3) (generator->list (make-for-each-generator for-each '(1 2 3))))

;; FAIL: #2060 (SRFI 1's native unfold cannot resume a coroutine generator)
;; (test-equal "spec example: generator-unfold over make-for-each-generator"
;;             '(#\a #\b #\c)
;;             (generator-unfold (make-for-each-generator string-for-each "abc") unfold))
;; FAIL: #2060 (SRFI 1's native fold cannot resume a coroutine generator)
;; (test-equal "driver: a coroutine generator drives SRFI 1 fold"
;;             '(3 2 1) (let ((g (fresh-coroutine)))
;;                        (fold (lambda (i acc) (cons (g) acc)) '() '(a b c))))
;; FAIL: #2060 (SRFI 1's native fold cannot resume a gtake generator)
;; (test-equal "driver: a gtake generator drives SRFI 1 fold"
;;             '(2 1 0) (let ((g (gtake (make-range-generator 0 100) 5)))
;;                        (fold (lambda (i acc) (cons (g) acc)) '() '(a b c))))
;; FAIL: #2060 (hash-table-walk is a native driver, so its yield cannot resume)
;; (test-equal "seam: a hash table becomes a generator through make-for-each-generator"
;;             '(1) (generator->list (make-for-each-generator hash-walk (one-entry-table))))
;; FAIL: #2060 (SRFI 1 fold is a native driver, so its yield cannot resume)
;; (test-equal "driver: an SRFI 1-shaped walker becomes a generator"
;;             '(1 2 3) (generator->list (make-for-each-generator fold-walk '(1 2 3))))

(let ((runner (test-runner-current)))
  (test-end "srfi158-audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
