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
;; The two fixed-size arrays under test (src/printer.zig:24-25):
;;
;;   const MAX_SHARED = 1024;            // seen[] / shared[] / labels[]
;;   const MAX_PRINT_DEPTH: u32 = 1024;
;;
;; Every disabled assertion below was reproduced against a fresh ReleaseSafe
;; build with an isolated KAAPPI_HOME, and each is paired with an ENABLED
;; control -- a near-identical input that behaves differently -- so the file
;; keeps proving the neighbouring path still works.
;;
;; NON-TERMINATION WARNING.  Several findings here are HANGS, not wrong
;; values.  Those assertions are commented out rather than marked
;; `test-expect-fail': an expected-fail case that never returns wedges the
;; whole suite.  Do not re-enable one without a fix in hand.
;;
;; NOT TESTABLE FROM SCHEME (documented here so it is not lost): `prettyPrint'
;; (src/printer.zig:904) is reachable only from the interactive REPL under a
;; TTY.  It hangs on ANY cyclic value whose labelled flat form is wider than
;; the terminal, because `ppValue' calls `exactFlatLen' (src/printer.zig:1064)
;; -> the cycle-unaware `printValue'.  Reproduce with a pty driver:
;;   (define c (list 1 2 3)) (set-cdr! (cddr c) c) c
;; at COLUMNS=12 wedges the REPL; at COLUMNS=80 it prints "#0=(1 2 3 . #0#)".
;; This is closed issue kaappi#859 still live: commit a74137c1 added the
;; MAX_PRINT_DEPTH guard to `ppValue', which fixed the unbounded memory growth
;; (RSS now stays flat at ~4.3 MB) but not the hang, which has moved into
;; `exactFlatLen'.

(import (scheme base) (scheme write) (scheme lazy) (scheme eval) (scheme repl)
        (scheme process-context) (srfi 64) (srfi 258))

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

;; A list's cdr spine costs no printer depth (printListWithDepth walks it
;; iteratively), so length is unbounded where nesting is not.  This is the
;; control that makes section B's cliff about DEPTH, not size.
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
;; B. MAX_PRINT_DEPTH -- the nesting cliff (kaappi#1902)
;; ---------------------------------------------------------------------------
;;
;; Both the printer and the reader stop at 1024 levels, so 1023 is the last
;; depth that survives a round trip.  The asymmetry is the point: the READER
;; raises a read error; the PRINTER emits "..." and returns success.

(test-assert "list nested 100 deep round-trips" (round-trips? (nest 100 'leaf)))
(test-assert "list nested 1000 deep round-trips" (round-trips? (nest 1000 'leaf)))
(test-assert "list nested 1023 deep round-trips" (round-trips? (nest 1023 'leaf)))
(test-assert "vector nested 1023 deep round-trips"
             (round-trips? (let loop ((i 0) (a 'leaf))
                             (if (= i 1023) a (loop (+ i 1) (vector a))))))

;; The reader is loud about its own limit -- this is the control proving the
;; printer's silence (below) is a choice, not a shared inevitability.  The
;; shape below is exactly what the printer emits: N opens, an atom, N closes.
;; The reader accepts that to N=1023 and raises at N=1024, i.e. the two limits
;; coincide for plain nesting -- which is why section B2's rational case, where
;; they do NOT coincide, is the only readable-corruption window.
(define (parens n inner)
  (string-append (make-string n #\() inner (make-string n #\))))

(test-assert "reader ACCEPTS 1023 levels of nesting around an atom"
             (guard (e (#t #f))
               (begin (read (open-input-string (parens 1023 "x"))) #t)))
(test-assert "reader REJECTS 1024 levels of nesting around an atom"
             (guard (e (#t #t))
               (read (open-input-string (parens 1024 "x")))
               #f))

;; The printer, by contrast, reports success and truncates.
(test-equal "write of a 1024-deep nest succeeds but is truncated to 2051 chars"
            2051 (string-length (wr (nest 1024 'leaf))))
(test-equal "write output stops growing past the depth cap"
            (string-length (wr (nest 1024 'leaf)))
            (string-length (wr (nest 5000 'leaf))))

;; FAIL: #1902 (write of a >1024-deep nest emits truncated output with no error)
;; (test-assert "list nested 1024 deep round-trips" (round-trips? (nest 1024 'leaf)))
;; FAIL: #1902 (same, well past the cliff)
;; (test-assert "list nested 2000 deep round-trips" (round-trips? (nest 2000 'leaf)))

;; --- B2: the truncation sentinel is itself a legal datum -------------------
;;
;; The plain printer truncates with "...", which READS BACK as the ellipsis
;; symbol; the shared printer truncates with "#<deep>", which the reader
;; rejects.  Where the printer's depth counter outruns the reader's paren
;; nesting, that difference turns silent truncation into silent CORRUPTION.
;;
;; The `.rational' arm (src/printer.zig:826-831) recurses into numerator and
;; denominator with `depth + 1', so at nesting depth 1023 -- still inside what
;; the reader accepts -- an exact rational prints as ".../..." and reads back
;; as a SYMBOL.

(test-assert "write-shared truncates with the unreadable #<deep>"
             (reader-rejects? (nest 1100 'leaf)))

;; Controls: at the SAME depth 1023, every other leaf type round-trips
;; exactly.  Only the two-part numeric prints wrong.
(test-assert "fixnum leaf at depth 1023 round-trips" (round-trips? (nest 1023 42)))
(test-assert "flonum leaf at depth 1023 round-trips" (round-trips? (nest 1023 1.5)))
(test-assert "symbol leaf at depth 1023 round-trips" (round-trips? (nest 1023 'abc)))
(test-assert "string leaf at depth 1023 round-trips" (round-trips? (nest 1023 "s")))
(test-assert "bignum leaf at depth 1023 round-trips"
             (round-trips? (nest 1023 123456789012345678901234567890)))
(test-assert "bytevector leaf at depth 1023 round-trips"
             (round-trips? (nest 1023 (bytevector 1 2))))
;; Control on the OTHER side of the boundary: one level shallower is exact.
(test-assert "rational leaf at depth 1022 round-trips" (round-trips? (nest 1022 1/3)))
;; Control on the far side: at 1024 the reader refuses, i.e. loudly.
(test-assert "rational leaf at depth 1024 is REJECTED by the reader"
             (reader-rejects? (nest 1024 1/3)))

;; FAIL: #1953 (exact rational at nesting depth 1023 prints as "..." "/" "..." and
;; FAIL: #1953  reads back as the symbol |.../...| -- readable, silent, wrong type)
;; (test-assert "rational leaf at depth 1023 round-trips" (round-trips? (nest 1023 1/3)))
;; FAIL: #1953 (same, negative)
;; (test-assert "negative rational leaf at depth 1023 round-trips"
;;             (round-trips? (nest 1023 -7/9)))
;; FAIL: #1953 (the corrupted leaf is accepted by the reader as a symbol)
;; (test-assert "depth-1023 rational does not silently become a symbol"
;;             (not (symbol? (unnest 1023 (round-trip (nest 1023 1/3))))))

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
;; It is registered as `.func = &write' (src/primitives_io.zig:56), so on
;; acyclic input it agrees with write (correct) and on cyclic input it emits
;; labels (a spec violation).  The enabled control is the acyclic half.
(test-equal "write-simple does NOT label acyclic sharing"
            "((1 2 3) (1 2 3))" (out write-simple (make-acyclic-sharing)))
(test-assert "write-simple agrees with write on acyclic input"
             (equal? (wr (make-acyclic-sharing))
                     (out write-simple (make-acyclic-sharing))))

;; FAIL: #1955 (write-simple is registered as &write, so it emits datum labels on a
;; FAIL: #1955  circular structure; R7RS 6.13.3 says it never may)
;; (test-assert "write-simple emits NO datum label on a cycle"
;;             (not (has-label? (out write-simple (make-cycle)))))

;; ---------------------------------------------------------------------------
;; D. Sharing detection -- three independent failure modes, one constant
;; ---------------------------------------------------------------------------
;;
;; kaappi#1902 reports "write-shared loses labels".  There are three distinct
;; mechanisms behind that, all bounded by MAX_SHARED = 1024, and each has its
;; own cliff.  Separating them matters: a fix for one leaves the other two.

;; --- D1: markShared recurses down the cdr spine, incrementing `depth' ------
;; A pair shared between position 0 and position L-1 of a list is detected
;; only while L <= 1023, because the tail is past MAX_PRINT_DEPTH.
(define (d1 L)
  (let* ((x (list 'X))
         (mid (let loop ((i 0) (a (list x)))
                (if (= i (- L 2)) a (loop (+ i 1) (cons i a))))))
    (cons x mid)))

(test-assert "D1 control: sharing across a 1000-long list is labelled"
             (has-label? (wsh (d1 1000))))
(test-assert "D1 control: sharing across a 1023-long list is labelled"
             (has-label? (wsh (d1 1023))))

;; FAIL: #1902 (markShared's cdr-spine recursion hits MAX_PRINT_DEPTH: sharing
;; FAIL: #1902  across a list of 1024+ is silently unlabelled)
;; (test-assert "D1: sharing across a 1024-long list is labelled"
;;             (has-label? (wsh (d1 1024))))

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

;; FAIL: #1902 (seen[] is full at MAX_SHARED, so a pair first met at index 1023
;; FAIL: #1902  is never recorded and its repeat is never detected)
;; (test-assert "D2: first occurrence at index 1023 is labelled"
;;             (has-label? (wsh (d2 1100 1023))))

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

;; FAIL: #1902 (shared[] holds at most MAX_SHARED entries, so only 1023 of 1200
;; FAIL: #1902  repeated objects are labelled; the other 177 print twice, silently)
;; (test-equal "D3: 1200 shared objects get 1200 labels" 1200 (label-count (wsh (d3 1200))))

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

;; FAIL: #1902 (markCycles returns at MAX_PRINT_DEPTH, so a car-nested cycle at
;; FAIL: #1902  1024+ is never recorded and prints unlabelled and truncated)
;; (test-assert "D4: a 1024-deep chain cycle keeps its label"
;;             (has-label? (wr (chain-cycle 1024))))

;; ---------------------------------------------------------------------------
;; E. Cycles reachable only through a container the pre-pass does not walk
;; ---------------------------------------------------------------------------
;;
;; NON-TERMINATING -- every assertion in this section HANGS.  Do not enable.
;;
;; `markCycles'/`markShared' descend into `.pair', `.vector' and
;; `.record_instance' only (src/printer.zig:223-229, 76-114).  An error
;; object's message/irritants, and a mutex's or condition variable's name, are
;; printed recursively by `printValueWithDepth' but are never visited by the
;; cycle pre-pass.  `printListWithDepth' then walks the cdr spine with no depth
;; increment and no cycle guard (src/printer.zig:889-900), so the loop never
;; ends.  All four output procedures are affected, including `display', whose
;; spec text says it "must not loop forever on self-referencing pairs".

(define (cyclic-list) (let ((c (list 1 2 3))) (set-cdr! (cddr c) c) c))
(define (err-with irritant) (guard (x (#t x)) (error "boom" irritant)))

;; Control 1 -- the SAME cycle, reached the ordinary way, terminates and is
;; labelled.  This is what isolates the bug to the container, not the cycle.
(test-equal "E control: the same cycle outside an error object is labelled"
            "(#<error \"boom\" plain> #0=(1 2 3 . #0#))"
            (wr (list (err-with 'plain) (cyclic-list))))

;; Control 2 -- a cyclic VECTOR irritant does terminate, because the vector arm
;; recurses with `depth + 1' and so is caught by MAX_PRINT_DEPTH.  This
;; isolates the hang to the depth-free cdr-spine walk specifically.
(test-assert "E control: a cyclic VECTOR irritant terminates (truncated)"
             (string? (wr (err-with (let ((v (vector 1 2 3)))
                                      (vector-set! v 0 v) v)))))

;; Control 3 -- an acyclic irritant prints normally.
(test-equal "E control: an acyclic list irritant prints normally"
            "#<error \"boom\" (1 2 3)>" (wr (err-with (list 1 2 3))))

;; FAIL: #1954 (write of an error object whose irritant is a cdr-cyclic list never
;; FAIL: #1954  returns -- markCycles does not traverse .error_object)
;; (test-assert "E: write of a cyclic-irritant error object terminates"
;;             (string? (wr (err-with (cyclic-list)))))
;; FAIL: #1954 (display, same hang -- R7RS: "display must not loop forever on
;; FAIL: #1954  self-referencing pairs, vectors, or records")
;; (test-assert "E: display of a cyclic-irritant error object terminates"
;;             (string? (dsp (err-with (cyclic-list)))))
;; FAIL: #1954 (write-shared, same hang -- markShared has the same blind spot)
;; (test-assert "E: write-shared of a cyclic-irritant error object terminates"
;;             (string? (wsh (err-with (cyclic-list)))))
;; FAIL: #1954 (a mutex NAMED by a cyclic list hangs identically; needs (srfi 18))
;; (test-assert "E: write of a mutex named by a cyclic list terminates"
;;             (string? (wr (make-mutex (cyclic-list)))))
;; FAIL: #1954 (a condition variable named by a cyclic list, same; needs (srfi 18).
;; FAIL: #1954  Its acyclic control prints "#<condition-variable (1 2 3)>" fine.)
;; (test-assert "E: write of a condition variable named by a cyclic list terminates"
;;             (string? (wr (make-condition-variable (cyclic-list)))))
;;
;; The complete set of `printValueWithDepth' arms that recurse into contained
;; Values is: .pair, .vector, .record_instance, .error_object,
;; .multiple_values, .mutex, .condition_variable, .rational.  The cycle
;; pre-pass covers only the first three.  Of the rest, .error_object, .mutex
;; and .condition_variable are reachable from portable Scheme and all three
;; hang (above); .rational cannot cycle (its parts are always integers); and
;; .multiple_values is latent -- a MultipleValues object is consumed by
;; call-with-values before it can reach the printer, so it is unreachable
;; today but would hang the same way if it ever became printable.
;;
;; kaappi#1713 fixed exactly this shape for ONE container: it added
;; .record_instance to `vectorLikeChildren' so a cyclic record gets a datum
;; label.  The other four arms were not brought along.

;; ---------------------------------------------------------------------------
;; F. write-shared must be linear -- the seen[] cap makes it exponential
;; ---------------------------------------------------------------------------
;;
;; A binary DAG of depth d has d+1 distinct pairs but 2^d leaves when written
;; unshared.  `write' is REQUIRED to unfold it ("Datum labels must not be used
;; if there are no cycles"), so `(write dag)' is astronomical BY SPEC and is
;; not a bug.  `write-shared' is required to label it, and must therefore stay
;; linear -- but only does so while the DAG's nodes fit in seen[].
;;
;; The discriminating control is order: the same two objects in a two-element
;; vector print instantly one way round and never terminate the other.

(define (dag d) (if (= d 0) 'leaf (let ((x (dag (- d 1)))) (cons x x))))
(define (filler n)
  (let ((v (make-vector n #f)))
    (let loop ((i 0)) (when (< i n) (vector-set! v i (list i)) (loop (+ i 1))))
    v))

(test-assert "F control: write-shared of a bare depth-40 DAG is linear"
             (< (string-length (wsh (dag 40))) 2000))
(test-assert "F control: DAG BEFORE the filler stays linear"
             (< (string-length (wsh (vector (dag 40) (filler 1200)))) 20000))

;; FAIL: #1902 (seen[] is full after the 1200-element filler, so the DAG's nodes are
;; FAIL: #1902  never recorded as shared and write-shared unfolds 2^40 leaves -- the
;; FAIL: #1902  SAME two objects, only swapped)
;; (test-assert "F: DAG AFTER the filler stays linear"
;;             (< (string-length (wsh (vector (filler 1200) (dag 40)))) 20000))

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
