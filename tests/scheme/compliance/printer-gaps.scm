;; Audit v2, Phase 1D -- `src/printer.zig`: structural round-trip, the four
;; `write`-family contracts, and the fixed-array limits.
;;
;; The oracle throughout is ROUND-TRIP: (equal? x (read (open-input-string
;; <written x>))).  Phase 1A already swept numbers and characters
;; (tests/scheme/compliance/reader-exactness-gaps.scm); this file's axis is
;; STRUCTURE -- nesting depth, sharing, cycles, and their interaction.
;;
;; Oracles (quoted, not remembered) -- R7RS 6.13.3, pp. 58-59:
;;
;;   `write' -- "If obj contains cycles which would cause an infinite loop
;;   using the normal written representation, then at least the objects that
;;   form part of the cycle must be represented using datum labels as
;;   described in section 2.4.  Datum labels must not be used if there are no
;;   cycles."
;;
;;   `write-shared' -- "The write-shared procedure is the same as write,
;;   except that shared structure must be represented using datum labels for
;;   all pairs and vectors that appear more than once in the output."
;;
;;   `write-simple' -- "The write-simple procedure is the same as write,
;;   except that shared structure is never represented using datum labels.
;;   This can cause write-simple not to terminate if obj contains circular
;;   structure."
;;
;;   `display' -- "The display representation of other objects is
;;   unspecified.  However, display must not loop forever on self-referencing
;;   pairs, vectors, or records.  Thus if the normal write representation is
;;   used, datum labels are needed to represent cycles as in write."
;;
;; HISTORY.  This file originally pinned the printer's fixed 1024-entry
;; arrays (MAX_SHARED seen[]/shared[]/labels[] and MAX_PRINT_DEPTH), whose
;; silent truncation was kaappi#1902 (closed, decomposed into #1953/#1954/
;; #1955) and whose native-stack recursion was the wasm32 module abort of
;; kaappi#2107.  The printer is now a single iterative engine over
;; heap-allocated work stacks with hashmap-based cycle/sharing detection:
;;
;;   - `write'/`display'/`write-shared' output is EXACT at any depth and for
;;     any number of labels -- no truncation sentinel exists on this path.
;;   - Cycle/sharing detection covers every container the printer recurses
;;     into (pairs, vectors, records, error objects, multiple-values, mutex
;;     and condition-variable names), so printing always terminates.
;;   - `write-simple' never emits labels; on cyclic input it raises a
;;     catchable error instead of the non-termination R7RS anticipates.
;;   - The READER's own nesting limit (Reader.MAX_NESTING_DEPTH = 1024)
;;     remains, and remains LOUD: output deeper than 1023 nesting levels is
;;     exact but fails at read time with a read error.  Section B pins that
;;     boundary from both sides.
;;
;; The formerly-disabled assertions below (each marked with the issue that
;; kept it off) are all enabled; each keeps its ENABLED control -- a
;; near-identical input that always worked -- so the file still proves the
;; neighbouring path as well.
;;
;; The prettyPrint REPL hang once noted here (kaappi#859's tail: exactFlatLen
;; fed a cyclic value to a printer with no spine bound) is fixed by the same
;; rework and pinned by a Zig unit test ("prettyPrint terminates on a cyclic
;; value at narrow width", src/printer_pretty.zig) -- prettyPrint is only
;; reachable from a TTY REPL, so it stays untestable from this file.

(import (scheme base) (scheme write) (scheme lazy) (scheme eval) (scheme repl)
        (scheme process-context) (srfi 18) (srfi 64) (srfi 258))

(test-begin "printer-gaps")

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

(define (out proc v)
  (let ((p (open-output-string))) (proc v p) (get-output-string p)))

(define (wr v) (out write v))
(define (dsp v) (out display v))
(define (wsh v) (out write-shared v))

;; Round-trip oracle.  Returns 'read-rejected when the reader refuses the
;; printer's own output -- which for the `#<...>' types is the CORRECT answer.
(define (round-trip v)
  (let ((txt (wr v)))
    (guard (e (#t 'read-rejected)) (read (open-input-string txt)))))

(define (round-trips? v)
  (let ((rd (round-trip v)))
    (and (not (eq? rd 'read-rejected)) (equal? v rd))))

(define (reader-rejects? v) (eq? (round-trip v) 'read-rejected))

;; n nested one-element lists around v:  n=3, v=x  =>  (((x)))
(define (nest n v)
  (let loop ((i 0) (a v)) (if (= i n) a (loop (+ i 1) (list a)))))

(define (unnest n x)
  (let loop ((i 0) (a x)) (if (= i n) a (loop (+ i 1) (car a)))))

;; A flat proper list (0 1 ... n-1) built without deep recursion.
(define (flat n)
  (let loop ((i n) (a '())) (if (= i 0) a (loop (- i 1) (cons (- i 1) a)))))

;; Count "#<digits>=" label DEFINITIONS in s (back-references "#N#" excluded).
(define (label-count s)
  (let ((len (string-length s)))
    (let loop ((i 0) (n 0))
      (cond
       ((>= i (- len 2)) n)
       ((and (char=? (string-ref s i) #\#)
             (char-numeric? (string-ref s (+ i 1)))
             (let scan ((j (+ i 1)))
               (cond ((>= j len) #f)
                     ((char-numeric? (string-ref s j)) (scan (+ j 1)))
                     ((char=? (string-ref s j) #\=) #t)
                     (else #f))))
        (loop (+ i 1) (+ n 1)))
       (else (loop (+ i 1) n))))))

(define (has-label? s) (> (label-count s) 0))

;; ---------------------------------------------------------------------------
;; A. Round-trip by structure -- the shapes that DO work
;; ---------------------------------------------------------------------------

(test-assert "flat proper list round-trips" (round-trips? (flat 20)))
(test-assert "dotted pair round-trips" (round-trips? (cons 1 2)))
(test-assert "improper list round-trips" (round-trips? (cons 1 (cons 2 3))))
(test-assert "empty list round-trips" (round-trips? '()))
(test-assert "vector round-trips" (round-trips? (vector 1 "s" #\a 'sym '())))
(test-assert "nested vector round-trips" (round-trips? (vector (vector 1) (vector 2))))
(test-assert "bytevector round-trips" (round-trips? (bytevector 0 1 255)))
(test-assert "mixed nesting round-trips"
             (round-trips? (list 1 (vector 2 (list 3 (cons 4 5))) (bytevector 6))))
(test-assert "string with every escape round-trips"
             (round-trips? "a\"b\\c\nd\te\x7;f\x1;g"))
(test-assert "vector of strings round-trips"
             (round-trips? (vector "" "\"" "\\" "\n")))

;; A list's cdr spine never overflowed even under the old printer (it was
;; walked iteratively), so length was always unbounded where nesting was not.
;; These controls keep section B about DEPTH, not size.
(test-assert "flat list of 5000 round-trips" (round-trips? (flat 5000)))
(test-assert "flat list of 50000 round-trips" (round-trips? (flat 50000)))
(test-assert "vector of 20000 round-trips"
             (round-trips? (make-vector 20000 7)))

;; Symbols: the printer's `symbolNeedsBars' must bar anything that would
;; otherwise read back as something else.
(test-assert "symbol with space round-trips" (round-trips? (string->symbol "has space")))
(test-assert "empty symbol round-trips" (round-trips? (string->symbol "")))
(test-assert "lone-dot symbol round-trips" (round-trips? (string->symbol ".")))
(test-assert "digit-led symbol round-trips" (round-trips? (string->symbol "1abc")))
(test-assert "hash-bearing symbol round-trips" (round-trips? (string->symbol "a#b")))
(test-assert "bar-bearing symbol round-trips" (round-trips? (string->symbol "a|b")))
(test-assert "number-lookalike symbol round-trips" (round-trips? (string->symbol "+inf.0")))
(test-assert "-i symbol round-trips" (round-trips? (string->symbol "-i")))
(test-assert "unicode symbol round-trips" (round-trips? (string->symbol "\x3bb;x")))
(test-assert "bare + round-trips" (round-trips? (string->symbol "+")))
(test-assert "ellipsis symbol round-trips" (round-trips? (string->symbol "...")))
(test-assert "newline-bearing symbol round-trips" (round-trips? (string->symbol "a\nb")))

;; ---------------------------------------------------------------------------
;; B. Nesting depth -- the printer is exact; the reader's limit stays loud
;; ---------------------------------------------------------------------------
;;
;; The printer no longer has a depth limit (kaappi#1902): output is exact at
;; any nesting.  The READER keeps MAX_NESTING_DEPTH = 1024 and raises a read
;; error past it, so 1023 remains the last depth that survives a round trip
;; -- but the failure past it is now LOUD, at read time, instead of the
;; printer silently emitting truncated output with unbalanced parens.

(test-assert "list nested 100 deep round-trips" (round-trips? (nest 100 'leaf)))
(test-assert "list nested 1000 deep round-trips" (round-trips? (nest 1000 'leaf)))
(test-assert "list nested 1023 deep round-trips" (round-trips? (nest 1023 'leaf)))
(test-assert "vector nested 1023 deep round-trips"
             (round-trips? (let loop ((i 0) (a 'leaf))
                             (if (= i 1023) a (loop (+ i 1) (vector a))))))

;; The reader's limit, pinned from both sides.  The shape below is exactly
;; what the printer emits: N opens, an atom, N closes.
(define (parens n inner)
  (string-append (make-string n #\() inner (make-string n #\))))

(test-assert "reader ACCEPTS 1023 levels of nesting around an atom"
             (guard (e (#t #f))
               (begin (read (open-input-string (parens 1023 "x"))) #t)))
(test-assert "reader REJECTS 1024 levels of nesting around an atom"
             (guard (e (#t #t))
               (read (open-input-string (parens 1024 "x")))
               #f))

;; The printer is exact past the reader's limit: N opens + the leaf + N
;; closes, at every depth (#1902 -- it used to saturate at 2051 chars with
;; unbalanced parens and report success).
(test-equal "write of a 1024-deep nest is exact"
            (+ (* 2 1024) 4) (string-length (wr (nest 1024 'leaf))))
(test-equal "write of a 5000-deep nest is exact"
            (+ (* 2 5000) 4) (string-length (wr (nest 5000 'leaf))))
(test-equal "write of a 2000-deep nest is its own parens shape"
            (parens 2000 "leaf") (wr (nest 2000 'leaf)))
;; ...so past the reader's limit the round trip fails LOUDLY at read time.
(test-assert "a 1024-deep nest fails loudly at READ time, not silently at write"
             (reader-rejects? (nest 1024 'leaf)))

;; --- B2: two-part numeric leaves near the boundary (kaappi#1953) -----------
;;
;; The old `.rational' arm recursed into numerator and denominator with
;; `depth + 1', so at nesting depth 1023 -- still inside what the reader
;; accepts -- an exact rational printed as ".../..." and read back as a
;; SYMBOL: the one depth where truncation was silent AND legal.  Rationals
;; now render atomically (both parts are always exact integers), so no depth
;; seam can split them.

;; Controls: at the same depth 1023, every leaf type round-trips exactly.
(test-assert "fixnum leaf at depth 1023 round-trips" (round-trips? (nest 1023 42)))
(test-assert "flonum leaf at depth 1023 round-trips" (round-trips? (nest 1023 1.5)))
(test-assert "symbol leaf at depth 1023 round-trips" (round-trips? (nest 1023 'abc)))
(test-assert "string leaf at depth 1023 round-trips" (round-trips? (nest 1023 "s")))
(test-assert "bignum leaf at depth 1023 round-trips"
             (round-trips? (nest 1023 123456789012345678901234567890)))
(test-assert "bytevector leaf at depth 1023 round-trips"
             (round-trips? (nest 1023 (bytevector 1 2))))
(test-assert "rational leaf at depth 1022 round-trips" (round-trips? (nest 1022 1/3)))
;; At 1024 the READER refuses (its own nesting limit), i.e. loudly.
(test-assert "rational leaf at depth 1024 is REJECTED by the reader"
             (reader-rejects? (nest 1024 1/3)))

;; Re-enabled: #1953.
(test-assert "rational leaf at depth 1023 round-trips" (round-trips? (nest 1023 1/3)))
(test-assert "negative rational leaf at depth 1023 round-trips"
             (round-trips? (nest 1023 -7/9)))
(test-assert "depth-1023 rational does not silently become a symbol"
             (not (symbol? (unnest 1023 (round-trip (nest 1023 1/3))))))

;; ---------------------------------------------------------------------------
;; C. write / display / write-shared / write-simple -- four different contracts
;; ---------------------------------------------------------------------------

(define (make-cycle) (let ((c (list 1 2 3))) (set-cdr! (cddr c) c) c))
(define (make-acyclic-sharing) (let ((d (list 1 2 3))) (list d d)))

;; write: labels cycles, never labels acyclic sharing.
(test-equal "write labels a cycle" "#0=(1 2 3 . #0#)" (wr (make-cycle)))
(test-equal "write does NOT label acyclic sharing"
            "((1 2 3) (1 2 3))" (wr (make-acyclic-sharing)))
(test-assert "write terminates on a cyclic vector"
             (string? (wr (let ((v (vector 0))) (vector-set! v 0 v) v))))

;; display: same obligation on cycles.
(test-equal "display labels a cycle" "#0=(1 2 3 . #0#)" (dsp (make-cycle)))
(test-equal "display does NOT label acyclic sharing"
            "((1 2 3) (1 2 3))" (dsp (make-acyclic-sharing)))

;; write-shared: labels ALL repeated pairs and vectors.
(test-equal "write-shared labels acyclic sharing"
            "(#0=(1 2 3) #0#)" (wsh (make-acyclic-sharing)))
(test-equal "write-shared labels a repeated vector"
            "(#0=#(1 2) #0#)" (wsh (let ((v (vector 1 2))) (list v v))))
(test-equal "write-shared labels a cycle" "#0=(1 2 3 . #0#)" (wsh (make-cycle)))

;; write-simple: "shared structure is NEVER represented using datum labels."
;; It was registered as `.func = &write' (kaappi#1955), making the two
;; procedures indistinguishable.  It now has its own implementation: acyclic
;; input renders exactly like write (which never labels acyclic sharing), and
;; cyclic input -- for which R7RS anticipates non-termination -- raises a
;; catchable error rather than either hanging or (the old bug) labelling.
(test-equal "write-simple does NOT label acyclic sharing"
            "((1 2 3) (1 2 3))" (out write-simple (make-acyclic-sharing)))
(test-assert "write-simple agrees with write on acyclic input"
             (equal? (wr (make-acyclic-sharing))
                     (out write-simple (make-acyclic-sharing))))

;; Re-enabled: #1955.  A cycle never produces a label: the call raises (a
;; catchable error object) instead of emitting anything.
(test-assert "write-simple never emits a datum label on a cycle -- it raises"
             (guard (e (#t (error-object? e)))
               (out write-simple (make-cycle))
               #f))
(test-assert "write-simple leaves the port untouched when it raises"
             (let ((p (open-output-string)))
               (guard (e (#t #t)) (write-simple (make-cycle) p))
               (string=? "" (get-output-string p))))

;; ---------------------------------------------------------------------------
;; D. Sharing detection -- the three old cliffs (kaappi#1902), all removed
;; ---------------------------------------------------------------------------
;;
;; The old fixed MAX_SHARED = 1024 arrays had three distinct failure modes,
;; each with its own cliff.  Detection is hashmap-based now; each subsection
;; keeps its just-below-the-cliff control and its re-enabled beyond-the-cliff
;; assertion, so a regression to any bounded mechanism shows up here.

;; --- D1: the old markShared recursed down the cdr spine, ticking `depth' ---
;; A pair shared between position 0 and position L-1 of a list was detected
;; only while L <= 1023, the tail beyond that being past the old depth cap.
(define (d1 L)
  (let* ((x (list 'X))
         (mid (let loop ((i 0) (a (list x)))
                (if (= i (- L 2)) a (loop (+ i 1) (cons i a))))))
    (cons x mid)))

(test-assert "D1 control: sharing across a 1000-long list is labelled"
             (has-label? (wsh (d1 1000))))
(test-assert "D1 control: sharing across a 1023-long list is labelled"
             (has-label? (wsh (d1 1023))))

;; Re-enabled: #1902 D1 (the cdr-spine depth tick in the old markShared).
(test-assert "D1: sharing across a 1024-long list is labelled"
             (has-label? (wsh (d1 1024))))
(test-assert "D1: sharing across a 5000-long list is labelled"
             (has-label? (wsh (d1 5000))))

;; --- D2: the seen[] array fills, so LATE-FIRST-SEEN objects are invisible --
;; Vector elements all sit at the same depth, so D1's mechanism is excluded.
;; What decides the answer is how many DISTINCT objects were recorded before
;; the shared one is first met: a positional bug, not a structural one.
(define (d2 size first)
  (let ((v (make-vector size #f)) (x (list 'X)))
    (let loop ((i 0)) (when (< i size) (vector-set! v i (list i)) (loop (+ i 1))))
    (vector-set! v first x)
    (vector-set! v (- size 1) x)
    v))

(test-assert "D2 control: first occurrence at index 10 is labelled"
             (has-label? (wsh (d2 1100 10))))
(test-assert "D2 control: first occurrence at index 1022 is labelled"
             (has-label? (wsh (d2 1100 1022))))

;; Re-enabled: #1902 D2 (the positional seen[] capacity).
(test-assert "D2: first occurrence at index 1023 is labelled"
             (has-label? (wsh (d2 1100 1023))))
(test-assert "D2: first occurrence at index 1090 is labelled"
             (has-label? (wsh (d2 1100 1090))))

;; --- D3: the shared[] array caps the NUMBER of labels ---------------------
(define (d3 n)
  (let ((v (make-vector (* 2 n) #f)))
    (let loop ((i 0))
      (when (< i n)
        (let ((x (list i)))
          (vector-set! v (* 2 i) x)
          (vector-set! v (+ (* 2 i) 1) x))
        (loop (+ i 1))))
    v))

(test-equal "D3 control: 400 shared objects get 400 labels" 400 (label-count (wsh (d3 400))))
(test-equal "D3 control: 600 shared objects get 600 labels" 600 (label-count (wsh (d3 600))))

;; Re-enabled: #1902 D3 (the shared[] label capacity).
(test-equal "D3: 1200 shared objects get 1200 labels" 1200 (label-count (wsh (d3 1200))))

;; --- D4: a cycle whose back-edge is deeper than MAX_PRINT_DEPTH -----------
;; A car-nested cycle loses its label entirely past 1024.  A FLAT cdr-cycle of
;; any length is fine (markCycles walks the spine iteratively) -- that is the
;; control, and the distinction matters.
(define (chain-cycle depth)
  (let ((nodes (let loop ((i 0) (a '()))
                 (if (= i depth) a (loop (+ i 1) (cons (make-vector 1 'leaf) a))))))
    (let loop ((v nodes))
      (when (pair? (cdr v)) (vector-set! (car v) 0 (cadr v)) (loop (cdr v))))
    (vector-set! (car (reverse nodes)) 0 (car nodes))
    (car nodes)))

(test-assert "D4 control: a 1023-deep chain cycle keeps its label"
             (has-label? (wr (chain-cycle 1023))))
(test-assert "D4 control: a FLAT cdr-cycle of 5000 keeps its label"
             (has-label? (wr (let ((c (flat 5000))) (set-cdr! (list-tail c 4999) c) c))))

;; Re-enabled: #1902 D4 (the depth guard on the old markCycles recursion).
(test-assert "D4: a 1024-deep chain cycle keeps its label"
             (has-label? (wr (chain-cycle 1024))))
(test-assert "D4: a 2000-deep chain cycle keeps its label"
             (has-label? (wr (chain-cycle 2000))))

;; ---------------------------------------------------------------------------
;; E. Cycles reached only through error objects / mutex / condvar names
;; ---------------------------------------------------------------------------
;;
;; Formerly the NON-TERMINATING section (kaappi#1954): the old cycle pre-pass
;; descended into `.pair', `.vector' and `.record_instance' only, while the
;; printer also recursed into error-object message/irritants and mutex /
;; condition-variable names -- so a cycle reached only through one of those
;; hung all four output procedures, `display' included, whose spec text says
;; it "must not loop forever on self-referencing pairs".  Detection and the
;; print engine now enumerate children through one shared `childAt', so the
;; two cannot disagree again (the per-tag self-cycle lock lives in
;; src/tests_printer.zig).

(define (cyclic-list) (let ((c (list 1 2 3))) (set-cdr! (cddr c) c) c))
(define (err-with irritant) (guard (x (#t x)) (error "boom" irritant)))

;; Control 1 -- the SAME cycle, reached the ordinary way, terminates and is
;; labelled.  This is what isolates the bug to the container, not the cycle.
(test-equal "E control: the same cycle outside an error object is labelled"
            "(#<error \"boom\" plain> #0=(1 2 3 . #0#))"
            (wr (list (err-with 'plain) (cyclic-list))))

;; Control 2 -- a cyclic VECTOR irritant.  Under the old printer this
;; terminated only by depth-cap truncation; it now gets a real datum label.
(test-assert "E control: a cyclic VECTOR irritant terminates, labelled"
             (let ((s (wr (err-with (let ((v (vector 1 2 3)))
                                      (vector-set! v 0 v) v)))))
               (and (string? s) (has-label? s))))

;; Control 3 -- an acyclic irritant prints normally.
(test-equal "E control: an acyclic list irritant prints normally"
            "#<error \"boom\" (1 2 3)>" (wr (err-with (list 1 2 3))))

;; Re-enabled: #1954 -- all four output procedures, plus the two SRFI-18
;; containers.  Exact output is asserted where the rendering is pinned by the
;; Zig unit tests too, so a hang OR a formatting regression both show here.
(test-equal "E: write of a cyclic-irritant error object terminates"
            "#<error \"boom\" #0=(1 2 3 . #0#)>" (wr (err-with (cyclic-list))))
(test-equal "E: display of a cyclic-irritant error object terminates"
            "#<error boom #0=(1 2 3 . #0#)>" (dsp (err-with (cyclic-list))))
(test-equal "E: write-shared of a cyclic-irritant error object terminates"
            "#<error \"boom\" #0=(1 2 3 . #0#)>" (wsh (err-with (cyclic-list))))
(test-equal "E: write of a mutex named by a cyclic list terminates"
            "#<mutex #0=(1 2 3 . #0#)>" (wr (make-mutex (cyclic-list))))
(test-equal "E: write of a condition variable named by a cyclic list terminates"
            "#<condition-variable #0=(1 2 3 . #0#)>"
            (wr (make-condition-variable (cyclic-list))))
;; A cyclic irritants SPINE, not merely a cyclic irritant: the live list
;; error-object-irritants returns is the error object's own, so tying it
;; into a cycle makes the printer's irritants walk itself cyclic.  The
;; labelled head restarts as a dotted datum.
(test-equal "E: a cyclic irritants SPINE terminates"
            "#<error \"boom\" . #0=(1 2 3 . #0#)>"
            (let* ((e (guard (x (#t x)) (error "boom" 1 2 3)))
                   (irr (error-object-irritants e)))
              (set-cdr! (cddr irr) irr)
              (wr e)))
;;
;; The complete set of print arms that recurse into contained Values is:
;; .pair, .vector, .record_instance, .error_object, .multiple_values,
;; .mutex, .condition_variable.  Detection walks the same seven via the
;; shared `childAt`.  `.rational' renders atomically (its parts are always
;; integers), and `.multiple_values' stays latent from portable Scheme -- a
;; MultipleValues object is consumed by call-with-values before it can reach
;; the printer -- but is covered by a self-cycle unit test anyway.

;; ---------------------------------------------------------------------------
;; F. write-shared must be linear regardless of traversal order
;; ---------------------------------------------------------------------------
;;
;; A binary DAG of depth d has d+1 distinct pairs but 2^d leaves when written
;; unshared.  `write' is REQUIRED to unfold it ("Datum labels must not be used
;; if there are no cycles"), so `(write dag)' is astronomical BY SPEC and is
;; not a bug.  `write-shared' is required to label it, and must therefore stay
;; linear.  Under the old fixed seen[] the SAME two objects in a two-element
;; vector printed instantly one way round and never terminated the other
;; (kaappi#1902): once the filler exhausted the array, the DAG's nodes could
;; no longer be recorded as shared.

(define (dag d) (if (= d 0) 'leaf (let ((x (dag (- d 1)))) (cons x x))))
(define (filler n)
  (let ((v (make-vector n #f)))
    (let loop ((i 0)) (when (< i n) (vector-set! v i (list i)) (loop (+ i 1))))
    v))

(test-assert "F control: write-shared of a bare depth-40 DAG is linear"
             (< (string-length (wsh (dag 40))) 2000))
(test-assert "F control: DAG BEFORE the filler stays linear"
             (< (string-length (wsh (vector (dag 40) (filler 1200)))) 20000))

;; Re-enabled: #1902 (order-dependence of the old positional seen[] cap).
(test-assert "F: DAG AFTER the filler stays linear"
             (< (string-length (wsh (vector (filler 1200) (dag 40)))) 20000))

;; ---------------------------------------------------------------------------
;; G. Types with no external representation -- deliberately unreadable
;; ---------------------------------------------------------------------------
;;
;; R7RS 6.13.3: "Implementations may support extended syntax to represent
;; record types or other types that do not have datum representations."
;; Kaappi writes them all as `#<...>', and the reader rejects `#<'.  That
;; printer/reader pair is COHERENT: the failure is loud, at read time, rather
;; than a silently different value.  These assertions lock that in -- they are
;; the regression net for anyone tempted to make one of these forms readable
;; without teaching the reader about it.

(define-record-type <pt> (mk-pt x y) pt? (x pt-x) (y pt-y))

(test-assert "record instance is rejected by the reader" (reader-rejects? (mk-pt 1 2)))
(test-assert "promise is rejected by the reader" (reader-rejects? (delay (+ 1 2))))
(test-assert "parameter is rejected by the reader" (reader-rejects? (make-parameter 1)))
(test-assert "continuation is rejected by the reader"
             (reader-rejects? (call-with-current-continuation (lambda (k) k))))
(test-assert "port is rejected by the reader" (reader-rejects? (open-input-string "x")))
(test-assert "environment is rejected by the reader"
             (reader-rejects? (environment '(scheme base))))
(test-assert "builtin procedure is rejected by the reader" (reader-rejects? car))
(test-assert "closure is rejected by the reader" (reader-rejects? (lambda (x) x)))
(test-assert "eof object is rejected by the reader" (reader-rejects? (eof-object)))

;; SRFI 258: an uninterned symbol has no readable representation BY DESIGN
;; (src/printer.zig:516-522).  Confirm the printer/reader pair is coherent --
;; `write' emits the unreadable form and the reader refuses it -- rather than
;; round-tripping into a DIFFERENT (interned) symbol.  `display' still shows
;; the bare name, which is display's own contract, not a round-trip promise.
(define uninterned (string->uninterned-symbol "abc"))
(test-equal "uninterned symbol writes unreadably"
            "#<uninterned-symbol abc>" (wr uninterned))
(test-assert "uninterned symbol is rejected by the reader" (reader-rejects? uninterned))
(test-equal "uninterned symbol displays as its bare name" "abc" (dsp uninterned))
(test-assert "the interned symbol of the same name is NOT the uninterned one"
             (not (eq? uninterned (string->symbol "abc"))))
(test-assert "an interned symbol of the same name DOES round-trip"
             (round-trips? (string->symbol "abc")))

(let ((runner (test-runner-current)))
  (test-end "printer-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
