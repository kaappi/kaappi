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
;;; #2020/#2021/#2022 are FIXED: bounds failures now report KP3006, rejections
;;; of well-typed values report KP3007, and shared helpers thread the real
;;; procedure name. The assertions that used to be disabled `;; FAIL:` pins of
;;; the bugs are now live; the `TODAY:` pins of the old behaviour are gone.
;;; Each fixed group keeps its "clean:" guards so a future change cannot
;;; quietly regress the type branches that were always correct.
;;;
;;; Every assertion below checks the *code* (and, where it is the point, the
;;; message text). `raises?`-only assertions pin nothing -- a documented lesson
;;; from #1944, and the central hazard of this unit specifically.
;;;
;;; Related, already filed -- not re-tested here:
;;;   #1899 primitives.safeValueDescription renders heap values opaquely (F10)
;;;        (fixed; its assertions remain live in PART 5)
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
;; sibling, listed in Part 2, used to get the same kind of failure wrong. They
;; are asserted here so that a future change which "fixes" Part 2 by
;; regressing these instead is caught.
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
;; PART 2 -- bounds failures reported as KP3002                 [FIXED: #2020]
;;
;; Root cause was primitives.parseOptionalRange (src/primitives.zig) reporting
;; an out-of-range [start end] through `typeError`, plus direct sites in
;; primitives_bytevector / _vector / _srfi1 / _string / _string_ext / _srfi160
;; and the list-walk family (list-tail / take / drop / take-right /
;; drop-right). All now report KP3006; `start > end` reports KP3007, the case
;; `kaappi explain KP3007` names verbatim.
;; ===========================================================================

;; The sharpest control, now in agreement: R7RS defines
;; `(substring s start end)` as `(string-copy s start end)` -- the SAME
;; operation under two names, and now the same code.
(test-equal "substring and string-copy agree on the code for an out-of-range end"
            (code-of (lambda () (substring "ab" 0 99)))
            (code-of (lambda () (string-copy "ab" 0 99))))

;; -- parseOptionalRange sites: end index past the length --------------------
(test-equal "vector-copy end past length is KP3006"
            'KP3006 (code-of (lambda () (vector-copy (vector 1 2) 0 99))))
(test-equal "vector->list end past length is KP3006"
            'KP3006 (code-of (lambda () (vector->list (vector 1 2) 0 99))))
(test-equal "vector-fill! end past length is KP3006"
            'KP3006 (code-of (lambda () (vector-fill! (vector 1 2) 0 0 99))))
(test-equal "vector->string end past length is KP3006"
            'KP3006 (code-of (lambda () (vector->string (vector #\a) 0 99))))
(test-equal "string-copy end past length is KP3006"
            'KP3006 (code-of (lambda () (string-copy "ab" 0 99))))
(test-equal "string->list end past length is KP3006"
            'KP3006 (code-of (lambda () (string->list "ab" 0 99))))
(test-equal "string->vector end past length is KP3006"
            'KP3006 (code-of (lambda () (string->vector "ab" 0 99))))
(test-equal "string-fill! end past length is KP3006"
            'KP3006 (code-of (lambda () (string-fill! (string-copy "ab") #\x 0 99))))
(test-equal "bytevector-copy end past length is KP3006"
            'KP3006 (code-of (lambda () (bytevector-copy (bytevector 1 2) 0 99))))
(test-equal "utf8->string end past length is KP3006"
            'KP3006 (code-of (lambda () (utf8->string (bytevector 97 98) 0 99))))
(test-equal "string->utf8 end past length is KP3006"
            'KP3006 (code-of (lambda () (string->utf8 "ab" 0 99))))
(test-equal "vector-copy! end past length is KP3006"
            'KP3006 (code-of (lambda () (vector-copy! (vector 1 2) 0 (vector 1 2 3) 0 99))))
(test-equal "string-copy! end past length is KP3006"
            'KP3006 (code-of (lambda () (string-copy! (string-copy "ab") 0 "abc" 0 99))))
(test-equal "bytevector-copy! end past length is KP3006"
            'KP3006 (code-of (lambda () (bytevector-copy! (bytevector 1 2) 0 (bytevector 1 2 3) 0 99))))

;; The message keeps the indexError shape: procedure, index, length.
(test-assert "string-copy's message names the index"
             (contains? (msg-of (lambda () (string-copy "ab" 0 99))) "99"))
(test-assert "string-copy's message names the length"
             (contains? (msg-of (lambda () (string-copy "ab" 0 99))) "2"))

;; -- parseOptionalRange: start greater than end -----------------------------
;; KP3007's own `explain` text names this case verbatim: "a start index greater
;; than an end index". parseOptionalRange now routes it through argError.
(test-assert "vector-copy start>end is a range code, not KP3002"
             (memq (code-of (lambda () (vector-copy (vector 1 2 3) 2 1)))
                   '(KP3006 KP3007)))
(test-assert "string-copy start>end is a range code, not KP3002"
             (memq (code-of (lambda () (string-copy "abc" 2 1)))
                   '(KP3006 KP3007)))
(test-assert "bytevector-copy start>end is a range code, not KP3002"
             (memq (code-of (lambda () (bytevector-copy (bytevector 1 2 3) 2 1)))
                   '(KP3006 KP3007)))
(test-equal "string-copy start>end is exactly KP3007"
            'KP3007 (code-of (lambda () (string-copy "abc" 2 1))))
(test-assert "string-copy's start>end message names both bounds"
             (contains? (msg-of (lambda () (string-copy "abc" 2 1))) "greater than end"))

;; -- Direct bytevector accessors --------------------------------------------
;; KP3006's own `explain` text names `bytevector-u8-ref` as an example of the
;; code; it now actually produces it.
(test-equal "bytevector-u8-ref past the end is KP3006"
            'KP3006 (code-of (lambda () (bytevector-u8-ref (bytevector 1 2) 5))))
(test-equal "bytevector-u8-ref with a negative index is KP3006"
            'KP3006 (code-of (lambda () (bytevector-u8-ref (bytevector 1 2) -1))))
(test-equal "bytevector-u8-set! past the end is KP3006"
            'KP3006 (code-of (lambda () (bytevector-u8-set! (bytevector 1 2) 5 0))))

;; -- The SRFI 160 u8 seam: one SRFI, one code for one operation -------------
;; `u8vector` is a plain bytevector (SRFI 160's own recommendation), so
;; `u8vector-ref` routes to `bytevector-u8-ref` while every other element kind
;; routes to `%numeric-vector-ref`. The codes now agree across the seam.
(test-equal "s8vector-ref out of range is KP3006"
            'KP3006 (code-of (lambda () (s8vector-ref (s8vector 1 2) 9))))
(test-equal "u8vector-ref out of range is KP3006 — same SRFI, same code"
            'KP3006 (code-of (lambda () (u8vector-ref (u8vector 1 2) 9))))
(test-assert "control: a u8vector really is a bytevector, which is why it diverges"
             (bytevector? (u8vector 1 2)))
(test-equal "every SRFI 160 element kind agrees on the out-of-range code"
            (code-of (lambda () (s8vector-ref (s8vector 1 2) 9)))
            (code-of (lambda () (u8vector-ref (u8vector 1 2) 9))))

;; -- SRFI 133 / SRFI 1 -------------------------------------------------------
(test-equal "vector-swap! out-of-range index is KP3006"
            'KP3006 (code-of (lambda () (vector-swap! (vector 1 2) 0 9))))
(test-assert "vector-unfold! end<start is a range code, not KP3002"
             (memq (code-of (lambda () (vector-unfold! (lambda (i) i) (vector 1 2 3) 2 1)))
                   '(KP3006 KP3007)))
(test-equal "take-right with k past the length is KP3006"
            'KP3006 (code-of (lambda () (take-right (list 1 2) 5))))
(test-equal "drop-right with k past the length is KP3006"
            'KP3006 (code-of (lambda () (drop-right (list 1 2) 5))))

;; -- list-tail / take / drop: the walk spelling now matches list-ref ---------
;; Walking off the end of a proper list reports the range failure (KP3006,
;; with the walk length); a non-pair element is still a type failure.
(test-equal "list-tail past the end is KP3006, like list-ref"
            'KP3006 (code-of (lambda () (list-tail (list 1 2) 5))))
(test-equal "take past the end is KP3006"
            'KP3006 (code-of (lambda () (take (list 1 2) 5))))
(test-equal "drop past the end is KP3006"
            'KP3006 (code-of (lambda () (drop (list 1 2) 5))))
(test-equal "list-tail on a non-list stays KP3002"
            'KP3002 (code-of (lambda () (list-tail 42 1))))

;; ===========================================================================
;; PART 3 -- domain failures on a well-typed value               [FIXED: #2021]
;;
;; KP3007's own definition: "an argument was of an acceptable type but outside
;; the range or shape the procedure allows". The type branch and the range
;; branch of each check no longer share one message and one code.
;; ===========================================================================

;; -- The conflation, resolved ------------------------------------------------
;; Same procedure, same argument position: a symbol is KP3002, an
;; out-of-range byte is KP3007. Different codes, different prose.
(test-equal "bytevector with a non-integer is KP3002 (the type branch)"
            'KP3002 (code-of (lambda () (bytevector 'x))))
(test-equal "bytevector with 256 is KP3007 (the range branch)"
            'KP3007 (code-of (lambda () (bytevector 256))))
(test-assert "bytevector distinguishes a wrong type from an out-of-range byte"
             (not (eq? (code-of (lambda () (bytevector 'x)))
                       (code-of (lambda () (bytevector 256))))))
(test-assert "the range branch no longer claims a type"
             (not (contains? (msg-of (lambda () (bytevector 256)))
                             "type error")))

;; -- Byte-range sites --------------------------------------------------------
(test-equal "bytevector with an out-of-range byte is KP3007"
            'KP3007 (code-of (lambda () (bytevector 256))))
(test-equal "bytevector-u8-set! with an out-of-range byte is KP3007"
            'KP3007 (code-of (lambda () (bytevector-u8-set! (bytevector 1) 0 256))))
(test-equal "make-bytevector with an out-of-range fill is KP3007"
            'KP3007 (code-of (lambda () (make-bytevector 1 256))))
(test-equal "write-u8 with an out-of-range byte is KP3007"
            'KP3007 (code-of (lambda () (write-u8 256))))

;; -- Negative lengths --------------------------------------------------------
(test-equal "make-vector with a negative length is KP3007"
            'KP3007 (code-of (lambda () (make-vector -1))))
(test-equal "make-string with a negative length is KP3007"
            'KP3007 (code-of (lambda () (make-string -1))))
(test-equal "make-bytevector with a negative length is KP3007"
            'KP3007 (code-of (lambda () (make-bytevector -1))))
(test-equal "make-list with a negative length is KP3007"
            'KP3007 (code-of (lambda () (make-list -1))))
(test-equal "make-s8vector with a negative length is KP3007"
            'KP3007 (code-of (lambda () (make-s8vector -1))))

;; -- integer->char: a Unicode domain rule, not a type rule -------------------
;; R7RS 6.6: "It is an error if n is not a Unicode scalar value." The argument
;; is an exact integer in every case below -- exactly what the procedure wants.
(test-equal "integer->char past #x10FFFF is KP3007"
            'KP3007 (code-of (lambda () (integer->char #x110000))))
(test-equal "integer->char on a surrogate is KP3007"
            'KP3007 (code-of (lambda () (integer->char #xD800))))
(test-equal "integer->char on a negative value is KP3007"
            'KP3007 (code-of (lambda () (integer->char -1))))
(test-assert "integer->char's message describes the range"
             (contains? (msg-of (lambda () (integer->char #x110000)))
                        "Unicode scalar value"))
(test-equal "integer->char on a non-integer stays KP3002"
            'KP3002 (code-of (lambda () (integer->char 'x))))

;; -- Enumerated-value rejections ---------------------------------------------
(test-equal "number->string with radix 1 is KP3007"
            'KP3007 (code-of (lambda () (number->string 10 1))))
(test-equal "number->string with radix 37 is KP3007"
            'KP3007 (code-of (lambda () (number->string 10 37))))
(test-equal "null-environment with a version other than 5 or 7 is KP3007"
            'KP3007 (code-of (lambda () (null-environment 6))))
(test-equal "hash with a non-positive bound is KP3007"
            'KP3007 (code-of (lambda () (hash 'k 0))))
(test-equal "s8vector with an out-of-range element is KP3007"
            'KP3007 (code-of (lambda () (s8vector 200))))
(test-equal "exact on +inf.0 is KP3007 (no exact representation)"
            'KP3007 (code-of (lambda () (exact +inf.0))))

;; -- Immutability: a property of the object, not its type --------------------
;; The value IS a pair / string / vector. `read-char` on a closed port already
;; reported this class as KP3007 (Part 0), so the house style existed.
(test-equal "set-car! on an immutable pair is KP3007"
            'KP3007 (code-of (lambda () (set-car! '(1 2) 9))))
(test-equal "string-set! on an immutable string is KP3007"
            'KP3007 (code-of (lambda () (string-set! "ab" 0 #\x))))
(test-equal "vector-set! on an immutable vector is KP3007"
            'KP3007 (code-of (lambda () (vector-set! '#(1 2) 0 9))))

;; -- A lookup miss is not a type error ---------------------------------------
;; SRFI 69: hash-table-ref "signals an error" when the key is absent and no
;; thunk was supplied. The key is a perfectly good key; it is simply not there.
(test-equal "hash-table-ref on a missing key is not a type error"
            'KP3007 (code-of (lambda () (hash-table-ref (make-hash-table) 'nope))))

;; ===========================================================================
;; PART 4 -- the procedure name in the message                  [FIXED: #2022]
;;
;; primitives_string_ext.zig's shared `parseStartEnd` helper used to pass the
;; literal "string" as the procedure name to parseOptionalRange, so 20 SRFI-13
;; procedures reported their range failure as coming from `string` -- a real,
;; unrelated, working (scheme base) procedure. The helper (and
;; callPredOrCharset's "string operation" site, and arithmetic's
;; numberTypeError "arithmetic") now thread the real name from every call
;; site.
;; ===========================================================================

;; The control: `string` exists and works, so a message naming it is not a
;; placeholder the reader can recognise as such.
(test-equal "control: `string` is a real working procedure"
            "ab" (string #\a #\b))

;; The control: a sibling in the SAME file that does not route through
;; parseStartEnd names itself correctly.
(test-assert "control: string-take names itself in its message"
             (contains? (msg-of (lambda () (string-take "ab" 9))) "string-take"))

;; -- Every parseStartEnd caller names itself in its own message --------------
;; This is the cheap guard against recurrence: a shared helper that hardcodes
;; a placeholder breaks one of these 20 lines by name.
(test-assert "string-index names itself in its message"
             (contains? (msg-of (lambda () (string-index "ab" #\a 0 9))) "string-index"))
(test-assert "string-index-right names itself in its message"
             (contains? (msg-of (lambda () (string-index-right "ab" #\a 0 9))) "string-index-right"))
(test-assert "string-contains names itself in its message"
             (contains? (msg-of (lambda () (string-contains "ab" "a" 0 9))) "string-contains"))
(test-assert "string-count names itself in its message"
             (contains? (msg-of (lambda () (string-count "ab" #\a 0 9))) "string-count"))
(test-assert "string-trim names itself in its message"
             (contains? (msg-of (lambda () (string-trim "ab" #\a 0 9))) "string-trim"))
(test-assert "string-trim-right names itself in its message"
             (contains? (msg-of (lambda () (string-trim-right "ab" #\a 0 9))) "string-trim-right"))
(test-assert "string-trim-both names itself in its message"
             (contains? (msg-of (lambda () (string-trim-both "ab" #\a 0 9))) "string-trim-both"))
(test-assert "string-prefix? names itself in its message"
             (contains? (msg-of (lambda () (string-prefix? "a" "ab" 0 9))) "string-prefix?"))
(test-assert "string-suffix? names itself in its message"
             (contains? (msg-of (lambda () (string-suffix? "a" "ab" 0 9))) "string-suffix?"))
(test-assert "string-every names itself in its message"
             (contains? (msg-of (lambda () (string-every char? "ab" 0 9))) "string-every"))
(test-assert "string-any names itself in its message"
             (contains? (msg-of (lambda () (string-any char? "ab" 0 9))) "string-any"))
(test-assert "string-filter names itself in its message"
             (contains? (msg-of (lambda () (string-filter char? "ab" 0 9))) "string-filter"))
(test-assert "string-delete names itself in its message"
             (contains? (msg-of (lambda () (string-delete char? "ab" 0 9))) "string-delete"))
(test-assert "string-reverse names itself in its message"
             (contains? (msg-of (lambda () (string-reverse "ab" 0 9))) "string-reverse"))
(test-assert "string-titlecase names itself in its message"
             (contains? (msg-of (lambda () (string-titlecase "ab" 0 9))) "string-titlecase"))
(test-assert "string-skip names itself in its message"
             (contains? (msg-of (lambda () (string-skip "ab" char? 0 9))) "string-skip"))
(test-assert "string-skip-right names itself in its message"
             (contains? (msg-of (lambda () (string-skip-right "ab" char? 0 9))) "string-skip-right"))
(test-assert "string-pad names itself in its message"
             (contains? (msg-of (lambda () (string-pad "ab" 3 #\space 0 9))) "string-pad"))
(test-assert "string-pad-right names itself in its message"
             (contains? (msg-of (lambda () (string-pad-right "ab" 3 #\space 0 9))) "string-pad-right"))
(test-assert "string-replace names itself in its message"
             (contains? (msg-of (lambda () (string-replace "abc" "xy" 0 1 0 9))) "string-replace"))

;; None of them blame the real, unrelated procedure `string` any more.
(test-assert "string-index no longer blames 'string'"
             (not (contains? (msg-of (lambda () (string-index "ab" #\a 0 9))) "'string'")))
(test-assert "a bad predicate no longer blames 'string operation'"
             (contains? (msg-of (lambda () (string-index "ab" 42))) "string-index"))

;; -- arithmetic: numberTypeError threads the real name -----------------------
;; `numberTypeError` used to hardcode "arithmetic" across its call sites (and
;; `ratPartsVal` "arithmetic" for rationals, `toF64Ext` for the flonum path).
;; The controls are in the same two files.
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

;; The pair that made it a defect rather than a convention: adjacent entries
;; in one specs table, both now name themselves.
(test-assert "+ names itself, like its neighbour /"
             (contains? (msg-of (lambda () (+ 1 'x))) "'+'"))
(test-assert "- names itself"
             (contains? (msg-of (lambda () (- 1 'x))) "'-'"))
(test-assert "* names itself"
             (contains? (msg-of (lambda () (* 1 'x))) "'*'"))
(test-assert "< names itself"
             (contains? (msg-of (lambda () (< 1 'x))) "'<'"))
(test-assert "= names itself"
             (contains? (msg-of (lambda () (= 1 'x))) "'='"))
(test-assert "max names itself"
             (contains? (msg-of (lambda () (max 1 'x))) "max"))
(test-assert "min names itself"
             (contains? (msg-of (lambda () (min 1 'x))) "min"))
(test-assert "abs names itself"
             (contains? (msg-of (lambda () (abs 'x))) "abs"))
(test-assert "expt names itself"
             (contains? (msg-of (lambda () (expt 'x 2))) "expt"))
;; The flonum path goes through toF64Ext, which also used to say 'arithmetic'.
(test-assert "+ names itself on the flonum path too"
             (contains? (msg-of (lambda () (+ 1.0 'x))) "'+'"))
(test-assert "no arithmetic site still blames 'arithmetic'"
             (not (contains? (msg-of (lambda () (+ 1 'x))) "'arithmetic'")))

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

;; -- Values that now render their identity (#1899 fixed) ---------------------
;; safeValueDescription renders identifying content for heap types while
;; staying no-allocation, bounded, and cycle-safe (a compound value gets a
;; one-level summary, never a recursive print).
(test-assert "#1899 FIXED: a symbol renders its name"
             (contains? (msg-of (lambda () (vector-ref (vector 1) 'the-key))) "the-key"))
(test-assert "#1899 FIXED: the opaque #<symbol> tag is gone"
             (not (contains? (msg-of (lambda () (vector-ref (vector 1) 'the-key)))
                             "#<symbol>")))
(test-assert "#1899 FIXED: a string renders a quoted prefix"
             (contains? (msg-of (lambda () (vector-ref (vector 1) "needle"))) "\"needle\""))
;; Compound types get a one-level length summary -- cheap, and cycle-safe by
;; construction (no recursion into the contents).
(test-assert "#1899 FIXED: a vector renders its length, not #<vector>"
             (contains? (msg-of (lambda () (vector-ref (vector 1) (vector 9))))
                        "#<vector length 1>"))
(test-assert "#1899 FIXED: a bytevector renders its length"
             (contains? (msg-of (lambda () (vector-ref (vector 1) (bytevector 1 2 3))))
                        "#<bytevector length 3>"))
(test-assert "#1899 FIXED: a rational renders as num/den"
             (contains? (msg-of (lambda () (vector-ref (vector 1) 3/2))) "3/2"))
;; A pair stays a summary (rendering its spine would need cycle detection).
(test-assert "a pair still renders conservatively as #<pair>"
             (contains? (msg-of (lambda () (vector-ref (vector 1) (list 9)))) "#<pair>"))

;; A character is an IMMEDIATE under NaN-boxing -- #1899 noted an unverified
;; report that it rendered as #<char>; that was real, and it now renders in its
;; #\ external form.
(test-assert "#1899 FIXED: a character renders in its #\\ form"
             (contains? (msg-of (lambda () (vector-ref (vector 1) #\a))) "#\\a"))
(test-assert "#1899 FIXED: the opaque #<char> tag is gone"
             (not (contains? (msg-of (lambda () (vector-ref (vector 1) #\a))) "#<char>")))

;; -- A bignum in u128 range now renders its exact value ----------------------
;; #1916's shape ("expected exact integer, got <the integer>") no longer argues
;; against itself for bignums that fit a u128; the value is shown in full.
(test-assert "#1899 FIXED: a bignum index says 'expected exact integer'"
             (contains? (msg-of (lambda () (vector-ref (vector 1 2) 99999999999999999999)))
                        "expected exact integer"))
(test-assert "#1899 FIXED: ...and reports the bignum's value"
             (contains? (msg-of (lambda () (vector-ref (vector 1 2) 99999999999999999999)))
                        "99999999999999999999"))
(test-assert "control: the value really is an exact integer"
             (exact-integer? 99999999999999999999))
;; A magnitude beyond u128 needs heap scratch to stringify, which the error
;; path must not allocate, so it falls back to a bounded #<bignum>.
(test-assert "a bignum past u128 falls back conservatively to #<bignum>"
             (contains? (msg-of (lambda () (vector-ref (vector 1 2)
                                                       999999999999999999999999999999999999999999)))
                        "#<bignum>"))

;; -- Parity with the "unsafe" bare-return path -------------------------------
;; `vm_calls.mapNativeError` runs the full allocating printer for a primitive
;; that returns a bare TypeError with no detail. The typeError path used to
;; render strictly worse than that; now both name the value.
(test-assert "control: sqrt (bare-return path) renders the symbol's name"
             (contains? (msg-of (lambda () (sqrt 'the-key))) "the-key"))
(test-assert "#1899 FIXED: magnitude (typeError path) also renders the name"
             (contains? (msg-of (lambda () (magnitude 'the-key))) "the-key"))

;; ===========================================================================
;; PART 6 -- primitives_string_ext.zig bounds sites            [FIXED with #2020]
;;
;; This file used to return ~19 BARE PrimitiveError.IndexOutOfBounds -- the
;; code was right but no detail was set, so the message lost the index and the
;; length that the indexError helper gives. Fixed alongside #2020 (the CI
;; bare-error gate's baseline dropped accordingly); asserted here so the
;; contrast stays measured.
;; ===========================================================================

(test-equal "string-take bounds failure yields KP3006"
            'KP3006 (code-of (lambda () (string-take "ab" 99))))
(test-assert "string-take names the procedure"
             (contains? (msg-of (lambda () (string-take "ab" 99))) "string-take"))
(test-assert "string-take now keeps the index in the message"
             (contains? (msg-of (lambda () (string-take "ab" 99))) "99"))
(test-assert "string-take now keeps the length in the message"
             (contains? (msg-of (lambda () (string-take "ab" 99))) "2"))
(test-assert "control: an indexError site keeps the index"
             (contains? (msg-of (lambda () (string-ref "ab" 99))) "99"))
(test-assert "string-drop names the procedure and the index"
             (and (contains? (msg-of (lambda () (string-drop "ab" 99))) "string-drop")
                  (contains? (msg-of (lambda () (string-drop "ab" 99))) "99")))
(test-assert "string-replace start>end is KP3007 with both bounds"
             (and (eq? (code-of (lambda () (string-replace "abc" "xy" 2 1 0 1))) 'KP3007)
                  (contains? (msg-of (lambda () (string-replace "abc" "xy" 2 1 0 1)))
                             "greater than end")))

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
;; #2020/#2021/#2022 must not over-reach into these.
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
