;;; SRFI 231 -- Intervals (phase 1a of #1694's SRFI 231 slice).
;;;
;;; SRFI 231 ("Intervals and Generalized Arrays") is 118 bindings total (101
;;; procedures/parameters + 17 storage-class singletons) -- roughly 5-10x
;;; any prior slice in this project, and structurally unrelated to SRFI
;;; 25/164/63 already shipped for #1694: an interval is a genuinely new,
;;; distinct opaque type (two parallel vectors of exact-integer lower/upper
;;; bounds, arbitrary sign, not a vector of (lo . hi) pairs like 25's shape
;;; nor plain zero-based sizes like 63's dims), and array?/array-set!'s
;;; conventions (researched but not yet implemented -- later phases) turn
;;; out to be their own hybrid of 25/164's and 63's rules, not identical to
;;; either. Given the scale, SRFI 231 is being built across several slices:
;;; this one covers only the interval layer (plus (srfi 231 misc)'s
;;; permutation/translation helpers), which has zero dependency on arrays or
;;; storage classes and is independently useful/testable. No bare
;;; `(srfi 231)` library exists yet -- it will be assembled as a thin
;;; re-export hub over these internal sub-libraries once every phase lands,
;;; the same way `(srfi 160 base)` + per-tag files have no bare `(srfi 160)`
;;; until a caller imports a specific typed sub-library.
;;;
;;; Every procedure's calling convention and error behavior below was
;;; confirmed against the primary spec text (srfi.schemers.org/srfi-231)
;;; and its official sample implementation before being written --
;;; including two procedures (translation?, permutation?) whose exact
;;; validation rule the spec states only in prose, not executable
;;; pseudocode, and interval-fold-right's "all f evaluations before any
;;; operator application" requirement, which is easy to implement as an
;;; ordinary reverse fold without noticing that's insufficient (a naive
;;; right-to-left walk interleaving f and operator calls would violate the
;;; letter of the spec even though it 'looks' right for the common case
;;; where f has no side effects).
(define-library (srfi 231 intervals)
  (import (scheme base) (srfi 1) (srfi 231 misc))
  (export interval? make-interval interval-dimension
          interval-lower-bound interval-upper-bound interval-width
          interval-lower-bounds->list interval-upper-bounds->list
          interval-lower-bounds->vector interval-upper-bounds->vector
          interval-widths interval-volume interval-empty?
          interval= interval-subset? interval-contains-multi-index?
          interval-for-each interval-fold-left interval-fold-right
          interval-dilate interval-translate interval-permute interval-scale
          interval-intersect interval-cartesian-product interval-projections
          ;; internal: the functional lexicographic walk sibling files build
          ;; their own accumulating procedures on (see its comment); not
          ;; re-exported by the (srfi 231) hub, same as arrays.sld's %-helpers
          %interval-fold)
  (begin

    (define-record-type <interval>
      (%make-interval lower upper)
      interval?
      (lower interval-lower-vec)
      (upper interval-upper-vec))

    (define (%validate-bounds! lower upper who)
      (unless (= (vector-length lower) (vector-length upper))
        (error (string-append who ": lower/upper bound vectors must have the same length") lower upper))
      (let loop ((i 0))
        (when (< i (vector-length lower))
          (let ((lo (vector-ref lower i)) (hi (vector-ref upper i)))
            (unless (and (integer? lo) (exact? lo) (integer? hi) (exact? hi))
              (error (string-append who ": bounds must be exact integers") lo hi))
            (unless (<= lo hi)
              (error (string-append who ": lower bound must not exceed upper bound on axis") i lo hi)))
          (loop (+ i 1)))))

    ;; Deep-copies -- an interval must not retain a dependence on the
    ;; caller's own (mutable, otherwise-visible) bound vectors, the same
    ;; discipline as SRFI 25's shape (a CodeRabbit-caught bug there).
    (define (%build-interval lower upper who)
      (%validate-bounds! lower upper who)
      (%make-interval (vector-copy lower) (vector-copy upper)))

    (define (make-interval arg1 . rest)
      (cond
       ((null? rest)
        (unless (vector? arg1) (error "make-interval: argument must be a vector" arg1))
        (%build-interval (make-vector (vector-length arg1) 0) arg1 "make-interval"))
       ((null? (cdr rest))
        (%build-interval arg1 (car rest) "make-interval"))
       (else (error "make-interval: too many arguments" arg1 rest))))

    (define (interval-dimension interval) (vector-length (interval-lower-vec interval)))

    (define (%check-axis! interval i who)
      (unless (and (integer? i) (exact? i) (<= 0 i) (< i (interval-dimension interval)))
        (error (string-append who ": axis index out of range") interval i)))

    (define (interval-lower-bound interval i)
      (%check-axis! interval i "interval-lower-bound")
      (vector-ref (interval-lower-vec interval) i))

    (define (interval-upper-bound interval i)
      (%check-axis! interval i "interval-upper-bound")
      (vector-ref (interval-upper-vec interval) i))

    (define (interval-width interval i)
      (%check-axis! interval i "interval-width")
      (- (vector-ref (interval-upper-vec interval) i) (vector-ref (interval-lower-vec interval) i)))

    (define (interval-lower-bounds->list interval) (vector->list (interval-lower-vec interval)))
    (define (interval-upper-bounds->list interval) (vector->list (interval-upper-vec interval)))
    (define (interval-lower-bounds->vector interval) (vector-copy (interval-lower-vec interval)))
    (define (interval-upper-bounds->vector interval) (vector-copy (interval-upper-vec interval)))

    (define (interval-widths interval)
      (vector-map - (interval-upper-vec interval) (interval-lower-vec interval)))

    (define (interval-volume interval)
      (let ((w (interval-widths interval)))
        (let loop ((i 0) (acc 1))
          (if (= i (vector-length w)) acc (loop (+ i 1) (* acc (vector-ref w i)))))))

    (define (interval-empty? interval) (zero? (interval-volume interval)))

    (define (interval= i1 i2)
      (and (equal? (interval-lower-vec i1) (interval-lower-vec i2))
           (equal? (interval-upper-vec i1) (interval-upper-vec i2))))

    ;; Per spec, this "assumes" i1 and i2 have the same dimension -- a
    ;; mismatch is an error, not a normal #f comparison result (#f is
    ;; reserved for same-dimension intervals that fail the bound check).
    (define (interval-subset? i1 i2)
      (unless (= (interval-dimension i1) (interval-dimension i2))
        (error "interval-subset?: intervals must have the same dimension" i1 i2))
      (let loop ((k 0))
        (or (= k (interval-dimension i1))
            (and (<= (interval-lower-bound i2 k) (interval-lower-bound i1 k))
                 (<= (interval-upper-bound i1 k) (interval-upper-bound i2 k))
                 (loop (+ k 1))))))

    ;; Per spec, the multi-index must have exactly the interval's
    ;; dimension -- a mismatch is an error, not a normal #f result (#f is
    ;; reserved for a well-formed multi-index that fails the bound check),
    ;; mirroring interval-subset? above.
    (define (interval-contains-multi-index? interval . multi-index)
      (unless (= (length multi-index) (interval-dimension interval))
        (error "interval-contains-multi-index?: the dimension of the interval does not match the number of indices"
               interval multi-index))
      (let ((lo (interval-lower-vec interval)) (up (interval-upper-vec interval)))
        (let loop ((i 0) (xs multi-index))
          (or (null? xs)
              (begin
                (unless (and (integer? (car xs)) (exact? (car xs)))
                  (error "interval-contains-multi-index?: multi-index entries must be exact integers" (car xs)))
                (and (<= (vector-ref lo i) (car xs)) (< (car xs) (vector-ref up i))
                     (loop (+ i 1) (cdr xs))))))))

    ;; General d-dimensional nested traversal in lexicographic order
    ;; (first axis outermost), and the ONE walk every accumulating
    ;; procedure in this package is built on. proc receives each
    ;; multi-index as a fresh LIST plus the accumulator so far, and its
    ;; result is the accumulator for the next multi-index; public callers
    ;; apply the index list to their own procedure via `apply` so
    ;; f/operator see separate positional index arguments, matching the
    ;; spec's convention everywhere. A zero-dimensional interval (both
    ;; vectors empty) calls proc exactly once with '() -- a thunk call
    ;; once `apply`-ed. Any axis with lo=hi contributes zero iterations,
    ;; so an empty interval calls proc zero times and returns seed, both
    ;; matching spec exactly with no special-casing.
    ;;
    ;; The accumulator is threaded FUNCTIONALLY -- through the axis loops'
    ;; own variables and the recursion's return value, never a set! cell
    ;; -- and that threading is the whole call/cc-safety story for the
    ;; non-! half of SRFI 231. The spec defines "call/cc safe" as written
    ;; "in a way that does not modify the state of any data captured by a
    ;; continuation" and intends every procedure without a trailing ! to
    ;; be that (only array-set!/array-assign! and the five `!` bulk
    ;; variants are exempt). A set! accumulator is exactly such state: a
    ;; continuation captured inside f (or an array's getter) shares the
    ;; cell with every other invocation of that continuation, so a
    ;; re-entry resumes from wherever the LAST run left the cell rather
    ;; than from what its own run had accumulated at capture time. One
    ;; re-entry cannot tell the two apart -- it is the second re-entry,
    ;; or a second continuation, that sees the first re-entry's
    ;; overwrites (kaappi#2539, reported by the SRFI's author). With the
    ;; accumulator held in the continuation's own frames, a re-entry sees
    ;; precisely the accumulation its capture point had: an immutable
    ;; list prefix, a fixnum, a folded value -- and consumers must keep
    ;; it that way (never reverse! or otherwise mutate a list this walk
    ;; built; a re-entry's continuation still holds a pointer into it).
    (define (%interval-fold proc seed interval)
      (let* ((lower (interval-lower-vec interval))
             (upper (interval-upper-vec interval))
             (d (vector-length lower)))
        (define (go axis rev-index acc)
          (if (= axis d)
              (proc (reverse rev-index) acc)
              (let ((lo (vector-ref lower axis)) (hi (vector-ref upper axis)))
                (let loop ((i lo) (acc acc))
                  (if (< i hi)
                      (loop (+ i 1) (go (+ axis 1) (cons i rev-index) acc))
                      acc)))))
        (go 0 '() seed)))

    ;; f's result is discarded, never threaded: interval-for-each is for
    ;; effect, and f may return zero or several values.
    (define (interval-for-each f interval)
      (%interval-fold (lambda (indices acc) (apply f indices) acc) #f interval)
      (if #f #f))

    (define (interval-fold-left f operator identity interval)
      (%interval-fold (lambda (indices acc) (operator acc (apply f indices)))
                      identity interval))

    ;; Per spec, interval-fold-right must complete ALL f evaluations before
    ;; applying operator to any of them -- not just visit indices in
    ;; reverse order interleaved with operator, which looks equivalent only
    ;; when f is pure. Collecting via cons during one lex-order traversal
    ;; yields the results in REVERSE lex order for free; a plain left walk
    ;; over that reversed list, applying (operator elem acc), is then
    ;; algebraically identical to a true right fold over the lex-ordered
    ;; results (verified by hand-expansion against the spec's own
    ;; 0-dimensional formula, which falls out with no special-casing).
    (define (interval-fold-right f operator identity interval)
      (let loop ((xs (%interval-fold (lambda (indices acc) (cons (apply f indices) acc))
                                     '() interval))
                 (acc identity))
        (if (null? xs) acc (loop (cdr xs) (operator (car xs) acc)))))

    ;; vector-map stops at the shortest input on a length mismatch (R7RS,
    ;; matching `map`) rather than erroring, so a diffs/translation/scales/
    ;; permutation vector shorter or longer than the interval's own
    ;; dimension would otherwise silently produce a wrong-rank result
    ;; instead of failing loudly -- validate lengths explicitly everywhere
    ;; below rather than relying on vector-map to notice.
    (define (%check-dimension-match! v interval who)
      (unless (= (vector-length v) (interval-dimension interval))
        (error (string-append who ": vector must match the interval's dimension") interval v)))

    (define (interval-dilate interval lower-diffs upper-diffs)
      (%check-dimension-match! lower-diffs interval "interval-dilate")
      (%check-dimension-match! upper-diffs interval "interval-dilate")
      (%build-interval (vector-map + (interval-lower-vec interval) lower-diffs)
                        (vector-map + (interval-upper-vec interval) upper-diffs)
                        "interval-dilate"))

    (define (interval-translate interval translation)
      (unless (translation? translation)
        (error "interval-translate: not a valid translation" translation))
      (%check-dimension-match! translation interval "interval-translate")
      (%build-interval (vector-map + (interval-lower-vec interval) translation)
                        (vector-map + (interval-upper-vec interval) translation)
                        "interval-translate"))

    ;; If the permutation is (p0,...,pd-1), result axis i has bounds
    ;; [l_{pi},u_{pi}) of the original interval -- per the spec's own
    ;; exact convention statement.
    (define (interval-permute interval permutation)
      (unless (permutation? permutation)
        (error "interval-permute: not a valid permutation" permutation))
      (%check-dimension-match! permutation interval "interval-permute")
      (let* ((lo (interval-lower-vec interval)) (up (interval-upper-vec interval)) (d (vector-length lo))
             (new-lo (make-vector d 0)) (new-up (make-vector d 0)))
        (let loop ((i 0))
          (when (< i d)
            (let ((p (vector-ref permutation i)))
              (vector-set! new-lo i (vector-ref lo p))
              (vector-set! new-up i (vector-ref up p)))
            (loop (+ i 1))))
        (%build-interval new-lo new-up "interval-permute")))

    (define (interval-scale interval scales)
      (%check-dimension-match! scales interval "interval-scale")
      ;; The spec requires "a length-d vector of positive exact integers"; the
      ;; sample implementation rejects bad scales up front. Without this check
      ;; a negative scale on a zero-width axis or a rational scale silently
      ;; produces a plausible-looking interval instead of an error (#2357).
      (let ((d (vector-length scales)))
        (let loop ((i 0))
          (when (< i d)
            (let ((s (vector-ref scales i)))
              (unless (and (exact-integer? s) (positive? s))
                (error "interval-scale: scales must be a vector of positive exact integers" scales)))
            (loop (+ i 1)))))
      (let* ((lo (interval-lower-vec interval)) (up (interval-upper-vec interval)) (d (vector-length lo)))
        (let loop ((i 0))
          (when (< i d)
            (unless (zero? (vector-ref lo i))
              (error "interval-scale: interval must have all-zero lower bounds" interval))
            (loop (+ i 1))))
        (%build-interval (make-vector d 0)
                          (vector-map (lambda (u s) (ceiling (/ u s))) up scales)
                          "interval-scale")))

    ;; Returns #f (not an error) when no valid intersection exists -- an
    ;; explicit, spec-sanctioned result, so this bypasses %build-interval's
    ;; error-raising validation and checks componentwise itself. All
    ;; intervals must share one dimension first, though -- otherwise a
    ;; shorter first interval would silently limit the loop below to its
    ;; own (smaller) axis count, never even looking at a later interval's
    ;; extra axes rather than rejecting the mismatch.
    (define (interval-intersect interval . intervals)
      (let* ((all (cons interval intervals))
             (d (interval-dimension interval)))
        (for-each (lambda (iv)
                    (unless (= (interval-dimension iv) d)
                      (error "interval-intersect: all intervals must have the same dimension" all)))
                  all)
        (let ((new-lo (make-vector d 0)) (new-up (make-vector d 0)))
          (let loop ((i 0))
            (when (< i d)
              (vector-set! new-lo i (apply max (map (lambda (iv) (interval-lower-bound iv i)) all)))
              (vector-set! new-up i (apply min (map (lambda (iv) (interval-upper-bound iv i)) all)))
              (loop (+ i 1))))
          (let check ((i 0))
            (cond
             ((= i d) (%make-interval new-lo new-up))
             ((<= (vector-ref new-lo i) (vector-ref new-up i)) (check (+ i 1)))
             (else #f))))))

    (define (interval-cartesian-product . intervals)
      (%make-interval (list->vector (apply append (map interval-lower-bounds->list intervals)))
                       (list->vector (apply append (map interval-upper-bounds->list intervals)))))

    (define (interval-projections interval right-dimension)
      (let ((d (interval-dimension interval)))
        (unless (and (integer? right-dimension) (exact? right-dimension)
                     (<= 0 right-dimension) (<= right-dimension d))
          (error "interval-projections: right-dimension out of range" interval right-dimension))
        (let* ((left-dimension (- d right-dimension))
               (lowers (interval-lower-bounds->list interval))
               (uppers (interval-upper-bounds->list interval)))
          (values
           (%make-interval (list->vector (take lowers left-dimension)) (list->vector (take uppers left-dimension)))
           (%make-interval (list->vector (drop lowers left-dimension)) (list->vector (drop uppers left-dimension)))))))))
