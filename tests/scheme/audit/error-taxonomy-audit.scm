;;; Audit: error taxonomy (D2) and diagnostic fidelity (D3 / finding F10)
;;; Systematic audit v2, Phase 2.13 (docs/audit-strategy.md, tracking #1890).
;;;
;;; This is a CROSS-CUTTING unit: the surface is every `primitives_*.zig` file
;;; plus `src/ffi.zig`, not one module. What it pins is the mapping from a
;;; *kind of failure* to a *diagnostic code*, and the information content of
;;; the message that comes with it.
;;;
;;; Oracle — the codebase's own written contract, in two places:
;;;
;;;   docs/dev/adding-features.md:64-68
;;;     | typeError(proc, expected, got) | KP3002 | the value is of the wrong type |
;;;     | indexError(proc, index, len)   | KP3006 | an index outside `0..len`      |
;;;     | argError(proc, fmt, args)      | KP3007 | the type is fine and the
;;;     |                               |        |  procedure rejects it anyway   |
;;;
;;;   src/diagnostics.zig — the text `kaappi explain` prints:
;;;     KP3006 "An index passed to a sequence operation (vector-ref, string-ref,
;;;             list-ref, bytevector-u8-ref, ...) was negative or not less than
;;;             the length of the sequence."
;;;     KP3007 "An argument was of an acceptable type but outside the range or
;;;             shape the procedure allows -- for example a start index greater
;;;             than an end index, or a value a procedure explicitly rejects."
;;;
;;; Note that KP3006's own explanation names `bytevector-u8-ref` as an example,
;;; and KP3007's names a start-index-past-end. Both currently report KP3002.
;;;
;;; Every assertion below checks the *code* (and, where it is the point, the
;;; message text). `raises?`-only assertions pin nothing -- a documented lesson
;;; from #1944, and the central hazard of this unit specifically.
;;;
;;; Related, already filed -- not re-tested here:
;;;   #1899 primitives.safeValueDescription renders heap values opaquely (F10)
;;;   #1914 internal `%` primitives return bare TypeError on range failures
;;;   #1944 / #1972 primitives_io.zig taxonomy
;;;   #1978 SRFI-170 errno / filesystem range errors
;;;   #2002 fibers: make-channel range error claims a type error
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/audit/error-taxonomy-audit.scm

(import (scheme base) (scheme write) (scheme char) (scheme complex) (scheme inexact) (scheme process-context)
        (srfi 1) (srfi 13) (srfi 64) (srfi 69)
        (srfi 133) (srfi 160 s8) (srfi 160 u8))

(test-begin "error taxonomy audit")

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

;; The diagnostic code a thunk raises, as a symbol, or 'no-error.
(define (code-of thunk)
  (guard (e (#t (if (error-object? e) (error-object-code e) 'non-error-object)))
    (thunk)
    'no-error))

;; The message a thunk raises, or "" when it does not raise.
(define (msg-of thunk)
  (guard (e (#t (if (error-object? e) (error-object-message e) "")))
    (thunk)
    ""))

(define (contains? haystack needle)
  (and (string-contains haystack needle) #t))

;; ===========================================================================
;; PART 0 -- the contract itself
;;
;; The three codes exist, are distinct, and the machinery that produces each
;; one is reachable. If this section ever fails, nothing below means anything.
;; ===========================================================================

(test-equal "contract: a genuine wrong-type argument is KP3002"
            'KP3002 (code-of (lambda () (car 42))))

(test-equal "contract: a genuine out-of-range index is KP3006"
            'KP3006 (code-of (lambda () (vector-ref (vector 1 2) 5))))

(test-equal "contract: a well-typed-but-rejected value is KP3007"
            'KP3007
            (code-of (lambda ()
                       (let ((p (open-input-string "a")))
                         (close-port p)
                         (read-char p)))))

(test-assert "contract: the three codes are pairwise distinct"
             (and (not (eq? 'KP3002 'KP3006))
                  (not (eq? 'KP3006 'KP3007))
                  (not (eq? 'KP3002 'KP3007))))

;; ===========================================================================
;; PART 1 -- bounds failures that ARE reported as KP3006 (the controls)
;;
;; These are the discriminating controls for Part 2. Each is a procedure whose
;; sibling, listed in Part 2, gets the same kind of failure wrong. They are
;; asserted here so that a future change which "fixes" Part 2 by regressing
;; these instead is caught.
;; ===========================================================================

(test-equal "KP3006 control: vector-ref past the end"
            'KP3006 (code-of (lambda () (vector-ref (vector 1 2) 5))))
(test-equal "KP3006 control: vector-ref with a negative index"
            'KP3006 (code-of (lambda () (vector-ref (vector 1 2) -1))))
(test-equal "KP3006 control: vector-set! past the end"
            'KP3006 (code-of (lambda () (vector-set! (vector 1 2) 5 0))))
(test-equal "KP3006 control: string-ref past the end"
            'KP3006 (code-of (lambda () (string-ref "ab" 5))))
(test-equal "KP3006 control: string-set! past the end"
            'KP3006 (code-of (lambda () (string-set! (string-copy "ab") 5 #\x))))
(test-equal "KP3006 control: list-ref past the end"
            'KP3006 (code-of (lambda () (list-ref (list 1 2) 5))))
(test-equal "KP3006 control: list-set! past the end"
            'KP3006 (code-of (lambda () (list-set! (list 1 2) 5 0))))
(test-equal "KP3006 control: substring with end past the length"
            'KP3006 (code-of (lambda () (substring "ab" 0 99))))
(test-equal "KP3006 control: substring with start greater than end"
            'KP3006 (code-of (lambda () (substring "abc" 2 1))))
(test-equal "KP3006 control: s8vector-ref past the end"
            'KP3006 (code-of (lambda () (s8vector-ref (s8vector 1) 9))))

;; The KP3006 message names the index and the length -- that is the whole
;; reason the helper exists rather than a bare return.
(test-assert "KP3006 control: the message names the offending index"
             (contains? (msg-of (lambda () (vector-ref (vector 1 2) 5))) "5"))
(test-assert "KP3006 control: the message names the sequence length"
             (contains? (msg-of (lambda () (vector-ref (vector 1 2) 5))) "2"))
(test-assert "KP3006 control: the message names the procedure"
             (contains? (msg-of (lambda () (vector-ref (vector 1 2) 5))) "vector-ref"))

;; ===========================================================================
;; PART 2 -- bounds failures reported as KP3002        [FAIL: #2020]
;;
;; Root cause: primitives.parseOptionalRange (src/primitives.zig:543) reports
;; an out-of-range [start end] through `typeError`, plus ~15 direct sites in
;; primitives_bytevector / _vector / _srfi1 / _string / _string_ext / _srfi160.
;;
;; The sharpest control is `substring` vs `string-copy`: R7RS defines
;; `(substring s start end)` as `(string-copy s start end)` -- the SAME
;; operation under two names -- and they disagree on the code.
;; ===========================================================================

;; -- What is asserted TODAY (the bug, pinned so the fix flips it) ------------
;; These pin current behaviour so #2020's fix is a visible, deliberate change.
;; Each has a matching disabled assertion below stating the correct answer.

(test-equal "TODAY (#2020): string-copy end-past-length is KP3002, not KP3006"
            'KP3002 (code-of (lambda () (string-copy "ab" 0 99))))
(test-equal "TODAY (#2020): bytevector-u8-ref past the end is KP3002"
            'KP3002 (code-of (lambda () (bytevector-u8-ref (bytevector 1 2) 5))))

;; -- The divergence itself, stated as one assertion -------------------------
;; This is the finding in a single line: two spellings of one operation.
;;
;; FAIL: #2020 (substring and string-copy are the same operation and disagree)
;; (test-equal "substring and string-copy agree on the code for an out-of-range end"
;;             (code-of (lambda () (substring "ab" 0 99)))
;;             (code-of (lambda () (string-copy "ab" 0 99))))

;; -- parseOptionalRange sites: end index past the length --------------------
;; FAIL: #2020 (parseOptionalRange reports an out-of-range bound as KP3002)
;; (test-equal "vector-copy end past length is KP3006"
;;             'KP3006 (code-of (lambda () (vector-copy (vector 1 2) 0 99))))
;; (test-equal "vector->list end past length is KP3006"
;;             'KP3006 (code-of (lambda () (vector->list (vector 1 2) 0 99))))
;; (test-equal "vector-fill! end past length is KP3006"
;;             'KP3006 (code-of (lambda () (vector-fill! (vector 1 2) 0 0 99))))
;; (test-equal "vector->string end past length is KP3006"
;;             'KP3006 (code-of (lambda () (vector->string (vector #\a) 0 99))))
;; (test-equal "string-copy end past length is KP3006"
;;             'KP3006 (code-of (lambda () (string-copy "ab" 0 99))))
;; (test-equal "string->list end past length is KP3006"
;;             'KP3006 (code-of (lambda () (string->list "ab" 0 99))))
;; (test-equal "string->vector end past length is KP3006"
;;             'KP3006 (code-of (lambda () (string->vector "ab" 0 99))))
;; (test-equal "string-fill! end past length is KP3006"
;;             'KP3006 (code-of (lambda () (string-fill! (string-copy "ab") #\x 0 99))))
;; (test-equal "bytevector-copy end past length is KP3006"
;;             'KP3006 (code-of (lambda () (bytevector-copy (bytevector 1 2) 0 99))))
;; (test-equal "utf8->string end past length is KP3006"
;;             'KP3006 (code-of (lambda () (utf8->string (bytevector 97 98) 0 99))))
;; (test-equal "string->utf8 end past length is KP3006"
;;             'KP3006 (code-of (lambda () (string->utf8 "ab" 0 99))))
;; (test-equal "vector-copy! end past length is KP3006"
;;             'KP3006 (code-of (lambda () (vector-copy! (vector 1 2) 0 (vector 1 2 3) 0 99))))
;; (test-equal "string-copy! end past length is KP3006"
;;             'KP3006 (code-of (lambda () (string-copy! (string-copy "ab") 0 "abc" 0 99))))
;; (test-equal "bytevector-copy! end past length is KP3006"
;;             'KP3006 (code-of (lambda () (bytevector-copy! (bytevector 1 2) 0 (bytevector 1 2 3) 0 99))))

;; -- parseOptionalRange: start greater than end -----------------------------
;; KP3007's own `explain` text names this case verbatim: "a start index greater
;; than an end index". `substring` reports KP3006; these report KP3002; nothing
;; reports the KP3007 the documentation promises.
;;
;; FAIL: #2020 (start > end reports KP3002; explain KP3007 names this case)
;; (test-assert "vector-copy start>end is a range code, not KP3002"
;;              (memq (code-of (lambda () (vector-copy (vector 1 2 3) 2 1)))
;;                    '(KP3006 KP3007)))
;; (test-assert "string-copy start>end is a range code, not KP3002"
;;              (memq (code-of (lambda () (string-copy "abc" 2 1)))
;;                    '(KP3006 KP3007)))
;; (test-assert "bytevector-copy start>end is a range code, not KP3002"
;;              (memq (code-of (lambda () (bytevector-copy (bytevector 1 2 3) 2 1)))
;;                    '(KP3006 KP3007)))

;; -- Direct bytevector accessors --------------------------------------------
;; KP3006's own `explain` text names `bytevector-u8-ref` as an example of the
;; code, which makes this the one case the documentation contradicts directly.
;;
;; FAIL: #2020 (KP3006's explain text names bytevector-u8-ref as its example)
;; (test-equal "bytevector-u8-ref past the end is KP3006"
;;             'KP3006 (code-of (lambda () (bytevector-u8-ref (bytevector 1 2) 5))))
;; (test-equal "bytevector-u8-ref with a negative index is KP3006"
;;             'KP3006 (code-of (lambda () (bytevector-u8-ref (bytevector 1 2) -1))))
;; (test-equal "bytevector-u8-set! past the end is KP3006"
;;             'KP3006 (code-of (lambda () (bytevector-u8-set! (bytevector 1 2) 5 0))))

;; -- The SRFI 160 u8 seam: one SRFI, two codes for one operation ------------
;; `u8vector` is a plain bytevector (SRFI 160's own recommendation), so
;; `u8vector-ref` routes to `bytevector-u8-ref` while every other element kind
;; routes to `%numeric-vector-ref`. Unit 2.4 verified the seam's *values* agree
;; across all 12 kinds; the diagnostic codes do not. This is the same finding
;; as the bytevector accessors above, reached from inside a single SRFI.
(test-equal "TODAY (#2020): s8vector-ref out of range is KP3006"
            'KP3006 (code-of (lambda () (s8vector-ref (s8vector 1 2) 9))))
(test-equal "TODAY (#2020): u8vector-ref out of range is KP3002 — same SRFI, other code"
            'KP3002 (code-of (lambda () (u8vector-ref (u8vector 1 2) 9))))
(test-assert "control: a u8vector really is a bytevector, which is why it diverges"
             (bytevector? (u8vector 1 2)))

;; FAIL: #2020 (the SRFI 160 u8 seam returns a different code from every other kind)
;; (test-equal "every SRFI 160 element kind agrees on the out-of-range code"
;;             (code-of (lambda () (s8vector-ref (s8vector 1 2) 9)))
;;             (code-of (lambda () (u8vector-ref (u8vector 1 2) 9))))

;; -- SRFI 133 / SRFI 1 -------------------------------------------------------
;; FAIL: #2020 (SRFI 133 and SRFI 1 range sites report KP3002)
;; (test-equal "vector-swap! out-of-range index is KP3006"
;;             'KP3006 (code-of (lambda () (vector-swap! (vector 1 2) 0 9))))
;; (test-assert "vector-unfold! end<start is a range code, not KP3002"
;;              (memq (code-of (lambda () (vector-unfold! (lambda (i) i) (vector 1 2 3) 2 1)))
;;                    '(KP3006 KP3007)))
;; (test-equal "take-right with k past the length is KP3006"
;;             'KP3006 (code-of (lambda () (take-right (list 1 2) 5))))
;; (test-equal "drop-right with k past the length is KP3006"
;;             'KP3006 (code-of (lambda () (drop-right (list 1 2) 5))))

;; -- list-tail / take / drop: a range failure surfacing as "expected pair" ---
;; `list-ref` reports KP3006 for exactly this input (asserted in Part 1), so
;; the walk-until-not-a-pair spelling is a choice, not a constraint.
(test-equal "TODAY (#2020): list-tail past the end blames the type of ()"
            'KP3002 (code-of (lambda () (list-tail (list 1 2) 5))))
(test-assert "TODAY (#2020): list-tail's message says 'expected pair'"
             (contains? (msg-of (lambda () (list-tail (list 1 2) 5))) "expected pair"))

;; FAIL: #2020 (list-tail/take/drop report a range failure as a type error)
;; (test-equal "list-tail past the end is KP3006, like list-ref"
;;             'KP3006 (code-of (lambda () (list-tail (list 1 2) 5))))
;; (test-equal "take past the end is KP3006"
;;             'KP3006 (code-of (lambda () (take (list 1 2) 5))))
;; (test-equal "drop past the end is KP3006"
;;             'KP3006 (code-of (lambda () (drop (list 1 2) 5))))

;; ===========================================================================
;; PART 3 -- domain failures on a well-typed value      [FAIL: #2021]
;;
;; These are KP3007's own definition: "an argument was of an acceptable type
;; but outside the range or shape the procedure allows". Every one reports
;; KP3002 instead, and in most cases the TYPE branch and the RANGE branch of
;; the same check share one message string, so a caller cannot tell a symbol
;; from a 256.
;; ===========================================================================

;; -- The conflation, demonstrated -------------------------------------------
;; Same procedure, same argument position: one is a real type error, the other
;; is a well-typed value out of range. Identical code, near-identical message.
(test-equal "TODAY (#2021): bytevector with a non-integer is KP3002 (correct)"
            'KP3002 (code-of (lambda () (bytevector 'x))))
(test-equal "TODAY (#2021): bytevector with 256 is ALSO KP3002 (should be KP3007)"
            'KP3002 (code-of (lambda () (bytevector 256))))
(test-assert "TODAY (#2021): both branches emit the same 'expected' text"
             (and (contains? (msg-of (lambda () (bytevector 'x)))
                             "exact integer 0-255")
                  (contains? (msg-of (lambda () (bytevector 256)))
                             "exact integer 0-255")))

;; FAIL: #2021 (the type branch and the range branch share one code)
;; (test-assert "bytevector distinguishes a wrong type from an out-of-range byte"
;;              (not (eq? (code-of (lambda () (bytevector 'x)))
;;                        (code-of (lambda () (bytevector 256))))))

;; -- Byte-range sites --------------------------------------------------------
;; FAIL: #2021 (0-255 range failures report KP3002)
;; (test-equal "bytevector with an out-of-range byte is KP3007"
;;             'KP3007 (code-of (lambda () (bytevector 256))))
;; (test-equal "bytevector-u8-set! with an out-of-range byte is KP3007"
;;             'KP3007 (code-of (lambda () (bytevector-u8-set! (bytevector 1) 0 256))))
;; (test-equal "make-bytevector with an out-of-range fill is KP3007"
;;             'KP3007 (code-of (lambda () (make-bytevector 1 256))))

;; -- Negative lengths --------------------------------------------------------
;; FAIL: #2021 (negative length reports KP3002)
;; (test-equal "make-vector with a negative length is KP3007"
;;             'KP3007 (code-of (lambda () (make-vector -1))))
;; (test-equal "make-string with a negative length is KP3007"
;;             'KP3007 (code-of (lambda () (make-string -1))))
;; (test-equal "make-bytevector with a negative length is KP3007"
;;             'KP3007 (code-of (lambda () (make-bytevector -1))))
;; (test-equal "make-list with a negative length is KP3007"
;;             'KP3007 (code-of (lambda () (make-list -1))))
;; (test-equal "make-s8vector with a negative length is KP3007"
;;             'KP3007 (code-of (lambda () (make-s8vector -1))))

;; -- integer->char: a Unicode domain rule, not a type rule -------------------
;; R7RS 6.6: "It is an error if n is not a Unicode scalar value." The argument
;; is an exact integer in every case below -- exactly what the procedure wants.
(test-equal "TODAY (#2021): integer->char past #x10FFFF is KP3002"
            'KP3002 (code-of (lambda () (integer->char #x110000))))
(test-assert "TODAY (#2021): the message describes a range, not a type"
             (contains? (msg-of (lambda () (integer->char #x110000)))
                        "Unicode scalar value"))

;; FAIL: #2021 (integer->char domain failures report KP3002)
;; (test-equal "integer->char past #x10FFFF is KP3007"
;;             'KP3007 (code-of (lambda () (integer->char #x110000))))
;; (test-equal "integer->char on a surrogate is KP3007"
;;             'KP3007 (code-of (lambda () (integer->char #xD800))))
;; (test-equal "integer->char on a negative value is KP3007"
;;             'KP3007 (code-of (lambda () (integer->char -1))))

;; -- Enumerated-value rejections ---------------------------------------------
;; FAIL: #2021 (a value outside an accepted set reports KP3002)
;; (test-equal "number->string with radix 1 is KP3007"
;;             'KP3007 (code-of (lambda () (number->string 10 1))))
;; (test-equal "number->string with radix 37 is KP3007"
;;             'KP3007 (code-of (lambda () (number->string 10 37))))
;; (test-equal "null-environment with a version other than 5 or 7 is KP3007"
;;             'KP3007 (code-of (lambda () (null-environment 6))))
;; (test-equal "hash with a non-positive bound is KP3007"
;;             'KP3007 (code-of (lambda () (hash 'k 0))))
;; (test-equal "s8vector with an out-of-range element is KP3007"
;;             'KP3007 (code-of (lambda () (s8vector 200))))

;; -- Immutability: a property of the object, not its type --------------------
;; The value IS a pair / string / vector. `read-char` on a closed port already
;; reports this class as KP3007 (asserted in Part 0), so the house style exists.
(test-equal "TODAY (#2021): set-car! on a literal is KP3002"
            'KP3002 (code-of (lambda () (set-car! '(1 2) 9))))
(test-equal "TODAY (#2021): string-set! on a literal is KP3002"
            'KP3002 (code-of (lambda () (string-set! "ab" 0 #\x))))
(test-equal "TODAY (#2021): vector-set! on a literal is KP3002"
            'KP3002 (code-of (lambda () (vector-set! '#(1 2) 0 9))))

;; FAIL: #2021 (immutability rejections report KP3002)
;; (test-equal "set-car! on an immutable pair is KP3007"
;;             'KP3007 (code-of (lambda () (set-car! '(1 2) 9))))
;; (test-equal "string-set! on an immutable string is KP3007"
;;             'KP3007 (code-of (lambda () (string-set! "ab" 0 #\x))))
;; (test-equal "vector-set! on an immutable vector is KP3007"
;;             'KP3007 (code-of (lambda () (vector-set! '#(1 2) 0 9))))

;; -- A lookup miss is not a type error ---------------------------------------
;; SRFI 69: hash-table-ref "signals an error" when the key is absent and no
;; thunk was supplied. The key is a perfectly good key; it is simply not there.
(test-equal "TODAY (#2021): hash-table-ref on a missing key is KP3002"
            'KP3002 (code-of (lambda () (hash-table-ref (make-hash-table) 'nope))))

;; FAIL: #2021 (an absent key is reported as a type error)
;; (test-equal "hash-table-ref on a missing key is not a type error"
;;             'KP3007 (code-of (lambda () (hash-table-ref (make-hash-table) 'nope))))

;; ===========================================================================
;; PART 4 -- the procedure name in the message          [FAIL: #2022]
;;
;; primitives_string_ext.zig's shared `parseStartEnd` helper (:137) passes the
;; literal "string" as the procedure name to parseOptionalRange, so 20 SRFI-13
;; procedures report their range failure as coming from `string` -- a real,
;; unrelated, working (scheme base) procedure.
;; ===========================================================================

;; The control: `string` exists and works, so the name in the message is not a
;; placeholder the reader can recognise as such.
(test-equal "control: `string` is a real working procedure"
            "ab" (string #\a #\b))

;; The control: a sibling in the SAME file that does not route through
;; parseStartEnd names itself correctly.
(test-assert "control: string-take names itself in its message"
             (contains? (msg-of (lambda () (string-take "ab" 9))) "string-take"))

(test-assert "TODAY (#2022): string-index blames 'string'"
             (contains? (msg-of (lambda () (string-index "ab" #\a 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-contains blames 'string'"
             (contains? (msg-of (lambda () (string-contains "ab" "a" 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-count blames 'string'"
             (contains? (msg-of (lambda () (string-count "ab" #\a 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-trim blames 'string'"
             (contains? (msg-of (lambda () (string-trim "ab" #\a 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-prefix? blames 'string'"
             (contains? (msg-of (lambda () (string-prefix? "a" "ab" 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-every blames 'string'"
             (contains? (msg-of (lambda () (string-every char? "ab" 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-filter blames 'string'"
             (contains? (msg-of (lambda () (string-filter char? "ab" 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-reverse blames 'string'"
             (contains? (msg-of (lambda () (string-reverse "ab" 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-titlecase blames 'string'"
             (contains? (msg-of (lambda () (string-titlecase "ab" 0 9))) "'string'"))
(test-assert "TODAY (#2022): string-skip blames 'string'"
             (contains? (msg-of (lambda () (string-skip "ab" char? 0 9))) "'string'"))

;; A second wrong name in the same file: not a procedure at all.
(test-assert "TODAY (#2022): a bad predicate blames 'string operation'"
             (contains? (msg-of (lambda () (string-index "ab" 42))) "string operation"))

;; -- The same root cause in primitives_arithmetic.zig: 'arithmetic' ---------
;; `numberTypeError` (:40) hardcodes "arithmetic" across 20 call sites.
;; Unlike `string`, `arithmetic` is not a bound name -- but `+` is the most
;; called procedure in the language and its type error names nothing the user
;; wrote. The controls are in the same two files.
(test-assert "control: / names itself in its message"
             (contains? (msg-of (lambda () (/ 1 'x))) "'/'"))
(test-assert "control: gcd names itself in its message"
             (contains? (msg-of (lambda () (gcd 1 'x))) "gcd"))
(test-assert "control: numerator names itself in its message"
             (contains? (msg-of (lambda () (numerator 'x))) "numerator"))
(test-assert "control: floor names itself in its message"
             (contains? (msg-of (lambda () (floor 'x))) "floor"))
(test-assert "control: truncate names itself in its message"
             (contains? (msg-of (lambda () (truncate 'x))) "truncate"))

(test-assert "TODAY (#2022): + blames 'arithmetic'"
             (contains? (msg-of (lambda () (+ 1 'x))) "'arithmetic'"))
(test-assert "TODAY (#2022): - blames 'arithmetic'"
             (contains? (msg-of (lambda () (- 1 'x))) "'arithmetic'"))
(test-assert "TODAY (#2022): * blames 'arithmetic'"
             (contains? (msg-of (lambda () (* 1 'x))) "'arithmetic'"))
(test-assert "TODAY (#2022): < blames 'arithmetic'"
             (contains? (msg-of (lambda () (< 1 'x))) "'arithmetic'"))
(test-assert "TODAY (#2022): = blames 'arithmetic'"
             (contains? (msg-of (lambda () (= 1 'x))) "'arithmetic'"))
(test-assert "TODAY (#2022): max blames 'arithmetic'"
             (contains? (msg-of (lambda () (max 1 'x))) "'arithmetic'"))
(test-assert "TODAY (#2022): abs blames 'arithmetic'"
             (contains? (msg-of (lambda () (abs 'x))) "'arithmetic'"))
(test-assert "TODAY (#2022): expt blames 'arithmetic'"
             (contains? (msg-of (lambda () (expt 'x 2))) "'arithmetic'"))

;; The pair that makes it a defect rather than a convention: adjacent entries
;; in one specs table, one names itself and one does not.
;; FAIL: #2022 (+ and / disagree on whether to name themselves)
;; (test-assert "+ names itself, like its neighbour /"
;;              (contains? (msg-of (lambda () (+ 1 'x))) "'+'"))
;; (test-assert "* names itself"
;;              (contains? (msg-of (lambda () (* 1 'x))) "'*'"))
;; (test-assert "max names itself"
;;              (contains? (msg-of (lambda () (max 1 'x))) "max"))
;; (test-assert "abs names itself"
;;              (contains? (msg-of (lambda () (abs 'x))) "abs"))

;; FAIL: #2022 (parseStartEnd hardcodes "string" as the procedure name)
;; (test-assert "string-index names itself in its message"
;;              (contains? (msg-of (lambda () (string-index "ab" #\a 0 9))) "string-index"))
;; (test-assert "string-contains names itself in its message"
;;              (contains? (msg-of (lambda () (string-contains "ab" "a" 0 9))) "string-contains"))
;; (test-assert "string-count names itself in its message"
;;              (contains? (msg-of (lambda () (string-count "ab" #\a 0 9))) "string-count"))
;; (test-assert "string-trim names itself in its message"
;;              (contains? (msg-of (lambda () (string-trim "ab" #\a 0 9))) "string-trim"))
;; (test-assert "string-prefix? names itself in its message"
;;              (contains? (msg-of (lambda () (string-prefix? "a" "ab" 0 9))) "string-prefix?"))

;; ===========================================================================
;; PART 5 -- diagnostic fidelity (F10, extends #1899)
;;
;; safeValueDescription renders the offending value. Which types survive?
;; ===========================================================================

;; -- Values that DO render concretely (the controls) -------------------------
(test-assert "fidelity: a fixnum renders its value"
             (contains? (msg-of (lambda () (car 42))) "42"))
(test-assert "fidelity: a flonum renders its value (fixed by #1916)"
             (contains? (msg-of (lambda () (car 1.5))) "1.5"))
(test-assert "fidelity: an integral flonum keeps its .0 (the #1916 fix)"
             (contains? (msg-of (lambda () (vector-ref (vector 1) 1.0))) "1.0"))
(test-assert "fidelity: #t renders as #t"
             (contains? (msg-of (lambda () (car #t))) "#t"))
(test-assert "fidelity: the empty list renders as ()"
             (contains? (msg-of (lambda () (car '()))) "()"))

;; -- Values that do NOT render (the finding) ---------------------------------
(test-assert "TODAY (#1899): a symbol renders as an opaque #<symbol>"
             (contains? (msg-of (lambda () (vector-ref (vector 1) 'the-key))) "#<symbol>"))
(test-assert "TODAY (#1899): the symbol's name is absent from the message"
             (not (contains? (msg-of (lambda () (vector-ref (vector 1) 'the-key)))
                             "the-key")))
(test-assert "TODAY (#1899): a string renders as an opaque #<string>"
             (contains? (msg-of (lambda () (vector-ref (vector 1) "needle"))) "#<string>"))
(test-assert "TODAY (#1899): a vector renders as an opaque #<vector>"
             (contains? (msg-of (lambda () (vector-ref (vector 1) (vector 9)))) "#<vector>"))
(test-assert "TODAY (#1899): a pair renders as an opaque #<pair>"
             (contains? (msg-of (lambda () (vector-ref (vector 1) (list 9)))) "#<pair>"))
(test-assert "TODAY (#1899): a bytevector renders as an opaque #<bytevector>"
             (contains? (msg-of (lambda () (vector-ref (vector 1) (bytevector 1))))
                        "#<bytevector>"))
(test-assert "TODAY (#1899): a rational renders as an opaque #<rational>"
             (contains? (msg-of (lambda () (vector-ref (vector 1) 3/2))) "#<rational>"))

;; A character is an IMMEDIATE under NaN-boxing -- rendering it needs no heap
;; access at all, so the documented "does not dereference heap payloads"
;; rationale cannot apply. #1899 says this could not be reproduced; it does.
(test-assert "TODAY (#1899): a character renders as #<char> despite being immediate"
             (contains? (msg-of (lambda () (vector-ref (vector 1) #\a))) "#<char>"))
(test-assert "TODAY (#1899): the character's own value is absent"
             (not (contains? (msg-of (lambda () (vector-ref (vector 1) #\a))) "#\\a")))

;; -- The self-contradiction: a bignum IS an exact integer --------------------
;; This is #1916's exact shape ("expected exact integer, got 1", where 1 is an
;; exact integer), still live for bignums and rationals. It is also a Part 2
;; instance: the value satisfies the claimed type and is merely out of range.
(test-assert "TODAY (#1899): a bignum index says 'expected exact integer'"
             (contains? (msg-of (lambda () (vector-ref (vector 1 2) 99999999999999999999)))
                        "expected exact integer"))
(test-assert "TODAY (#1899): ...and reports the value as #<bignum>"
             (contains? (msg-of (lambda () (vector-ref (vector 1 2) 99999999999999999999)))
                        "#<bignum>"))
(test-assert "control: the value really is an exact integer, so the message is self-contradictory"
             (exact-integer? 99999999999999999999))

;; -- The decisive control: the "unsafe" path renders BETTER ------------------
;; `vm_calls.mapNativeError:383` runs the FULL allocating printer
;; (printer.valueToString) when a primitive returns a bare TypeError with no
;; detail set. So the path CI's gate exists to eliminate produces a strictly
;; more informative value than primitives.typeError does -- same error class,
;; same VM state, same file. This is why the documented rationale for the
;; opacity ("deliberately does not dereference heap payloads",
;; docs/dev/adding-features.md:75-77) cannot be the real constraint.
(test-assert "control: sqrt (bare-return path) renders the symbol's name"
             (contains? (msg-of (lambda () (sqrt 'the-key))) "the-key"))
(test-assert "TODAY (#1899): magnitude (typeError path) renders #<symbol> instead"
             (contains? (msg-of (lambda () (magnitude 'the-key))) "#<symbol>"))
(test-assert "TODAY (#1899): ...and loses the name the other path kept"
             (not (contains? (msg-of (lambda () (magnitude 'the-key))) "the-key")))

;; FAIL: #1899 (the helper path is less informative than the fallback path)
;; (test-assert "the typeError path is at least as informative as the fallback"
;;              (contains? (msg-of (lambda () (magnitude 'the-key))) "the-key"))

;; FAIL: #1899 (heap values render opaquely)
;; (test-assert "a symbol's name appears in the message"
;;              (contains? (msg-of (lambda () (vector-ref (vector 1) 'the-key))) "the-key"))
;; (test-assert "a character renders as itself"
;;              (contains? (msg-of (lambda () (vector-ref (vector 1) #\a))) "#\\a"))
;; (test-assert "a bignum renders its value, not #<bignum>"
;;              (contains? (msg-of (lambda () (vector-ref (vector 1 2) 99999999999999999999)))
;;                         "99999999999999999999"))
;; (test-assert "a bignum index is not described as a wrong type"
;;              (not (contains? (msg-of (lambda () (vector-ref (vector 1 2) 99999999999999999999)))
;;                              "expected exact integer")))

;; ===========================================================================
;; PART 6 -- message quality where the code is already right
;;
;; primitives_string_ext.zig returns ~19 BARE PrimitiveError.IndexOutOfBounds.
;; The tag is right, so the code is right, but no detail is set and the message
;; loses the index and the length that the indexError helper would have given.
;; Not filed separately -- recorded here so the contrast is measured.
;; ===========================================================================

(test-equal "bare IndexOutOfBounds still yields the right code"
            'KP3006 (code-of (lambda () (string-take "ab" 99))))
(test-assert "bare IndexOutOfBounds still names the procedure"
             (contains? (msg-of (lambda () (string-take "ab" 99))) "string-take"))
(test-assert "bare IndexOutOfBounds loses the index (helper sites keep it)"
             (not (contains? (msg-of (lambda () (string-take "ab" 99))) "99")))
(test-assert "control: an indexError site keeps the index"
             (contains? (msg-of (lambda () (string-ref "ab" 99))) "99"))

;; ===========================================================================
;; PART 7 -- files whose taxonomy is already exact
;;
;; A clean file is a real result. These are asserted so a regression is caught.
;; ===========================================================================

;; primitives_srfi254.zig -- audited exact by unit 2.10; its range paths use
;; the right helpers. Re-pinned here from the taxonomy angle only.
(test-equal "clean: primitives_srfi160 index accessor uses KP3006"
            'KP3006 (code-of (lambda () (s8vector-ref (s8vector 1 2) 9))))
(test-equal "clean: primitives_srfi160 negative index uses KP3006"
            'KP3006 (code-of (lambda () (s8vector-ref (s8vector 1 2) -1))))

;; primitives_io.zig -- fixed by #1944/#1969; the closed-port class is KP3007.
(test-equal "clean: a closed input port is KP3007 (#1969)"
            'KP3007 (code-of (lambda ()
                               (let ((p (open-input-string "a")))
                                 (close-port p) (read-char p)))))
(test-equal "clean: a closed output port is KP3007 (#1969)"
            'KP3007 (code-of (lambda ()
                               (let ((p (open-output-string)))
                                 (close-port p) (write-char #\a p)))))

;; Arity, division and not-a-procedure are their own codes and stay distinct
;; from the three under audit -- confirming the taxonomy is granular where it
;; was designed to be.
(test-equal "clean: a division by zero is KP3004, not KP3002"
            'KP3004 (code-of (lambda () (expt 0 -1))))
(test-equal "clean: calling a non-procedure is KP3005, not KP3002"
            'KP3005 (code-of (lambda () (42 1))))
(test-equal "clean: an arity mismatch is KP3003, not KP3002"
            'KP3003 (code-of (lambda () ((lambda (a b) a) 1))))
(test-equal "clean: an unbound name is KP3001, not KP3002"
            'KP3001 (code-of (lambda () (eval 'no-such-name-anywhere
                                              (environment '(scheme base))))))

;; Genuine type errors across a spread of files stay KP3002 -- the fixes for
;; #2020/#2021 must not over-reach into these.
(test-equal "clean: car on a non-pair stays KP3002"
            'KP3002 (code-of (lambda () (car 42))))
(test-equal "clean: vector-ref on a non-vector stays KP3002"
            'KP3002 (code-of (lambda () (vector-ref 42 0))))
(test-equal "clean: string-length on a non-string stays KP3002"
            'KP3002 (code-of (lambda () (string-length 42))))
(test-equal "clean: bytevector-u8-ref on a non-bytevector stays KP3002"
            'KP3002 (code-of (lambda () (bytevector-u8-ref 42 0))))
(test-equal "clean: an out-of-range index with a non-integer type stays KP3002"
            'KP3002 (code-of (lambda () (vector-ref (vector 1 2) 'x))))
(test-equal "clean: + on a non-number stays KP3002"
            'KP3002 (code-of (lambda () (+ 1 'x))))
(test-equal "clean: apply with a non-procedure is KP3005, not KP3002"
            'KP3005 (code-of (lambda () (apply 42 '()))))

(let ((runner (test-runner-current)))
  (test-end "error taxonomy audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
