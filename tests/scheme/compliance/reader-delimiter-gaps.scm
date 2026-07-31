;;; Trailing-delimiter checking in the number reader (audit v2, Phase 1B).
;;;
;;; R7RS 7.1.1, page 61:
;;;
;;;   "Identifiers that do not begin with a vertical line are terminated by a
;;;    <delimiter> or by the end of the input. So are dot, numbers, characters,
;;;    and booleans."
;;;
;;; and page 62:
;;;
;;;   <delimiter> --> <whitespace> | <vertical line> | ( | ) | " | ;
;;;   <whitespace> --> <intraline whitespace> | <line ending>
;;;
;;; So a numeric token must end at one of: space, tab, newline, return,
;;; `|`, `(`, `)`, `"`, `;`, or end of input.  Anything else glued to the end
;;; of a number is a malformed token, not the start of a second datum.
;;; `Reader.isDelimiter` (src/reader.zig:254) implements exactly this set.
;;;
;;; This file is the systematic sweep of  radix prefix x exactness prefix x
;;; trailing character.  The full 19x26 matrix (19 prefix spellings, 26
;;; trailing characters, body "1") splits 382 of 494 cells; all 26
;;; un-prefixed cells are correct.  The representative cells are pinned below.
;;;
;;; ORACLE: `string->number`.  It rejects every string pinned here as a
;;; failure, so each disabled reader assertion is paired with an ENABLED
;;; `string->number` assertion showing the correct answer is already known.
;;; Cross-checked against Chibi 0.12 (the project's own pinned differential
;;; fuzz oracle) and Guile 3: both RAISE on every cell pinned below, and both
;;; accept every cell in the "must keep working" groups that is not a
;;; kaappi-specific extension (SRFI 169 separators, SRFI 270 hex floats).
;;;
;;; Overlap note: `tests/scheme/compliance/reader-exactness-gaps.scm`
;;; (Phase 1A) already pins the canonical decimal spellings `#e1.5abc`,
;;; `#e12abc` and `#d1e19/3` under the same issue.  This file deliberately
;;; uses different spellings for those cells so the two suites do not
;;; duplicate assertions.

(import (scheme base) (scheme complex) (scheme process-context) (srfi 64))

(test-begin "reader-delimiter-gaps")

;;; ---------------------------------------------------------------------
;;; Helpers
;;; ---------------------------------------------------------------------

;; #t when READ raises on S.  This is the correct behaviour for every
;; malformed numeric token below.
(define (rejects? s)
  (guard (e (#t #t))
    (let ((p (open-input-string s)))
      (read p)
      #f)))

;; #t when READ returns a datum but leaves input behind -- i.e. one token was
;; silently read as two datums.  Uses PEEK-CHAR rather than a second READ so
;; that a tail which is not itself a readable datum (`#b1.`, `#b1#`) still
;; registers as a split rather than as an error.
(define (splits? s)
  (guard (e (#t #f))
    (let* ((p (open-input-string s))
           (d (read p)))
      (and (not (eof-object? d))
           (not (eof-object? (peek-char p)))))))

;; #t when READ consumes S as exactly one datum and then reaches end of input.
;; Unlike SPLITS? this reads the *next* datum, so trailing whitespace and
;; trailing comments -- both legitimate ways for a token to end -- do not
;; count as leftover input.
(define (clean? s)
  (guard (e (#t #f))
    (let* ((p (open-input-string s))
           (d (read p)))
      (and (not (eof-object? d))
           (eof-object? (read p))))))

;; The single datum READ produces for S.
(define (read1 s) (read (open-input-string s)))

;;; ---------------------------------------------------------------------
;;; 1. The delimiter set itself.  Every R7RS <delimiter> must terminate a
;;;    prefixed numeric token cleanly.  These pass today.
;;; ---------------------------------------------------------------------

(test-group "R7RS 7.1.1 delimiters terminate a prefixed number"
  (test-assert "space"   (clean? "#b101 "))
  (test-assert "tab"     (clean? "#x1f\t"))
  (test-assert "newline" (clean? "#o17\n"))
  (test-assert "return"  (clean? "#d42\r"))
  (test-assert "semicolon starts a comment" (clean? "#b101;c"))
  (test-assert "end of input" (clean? "#b101"))

  (test-eqv "space-delimited value"  5 (read1 "#b101 "))
  (test-eqv "tab-delimited value"   31 (read1 "#x1f\t"))
  (test-eqv "comment-delimited value" 5 (read1 "#b101;c"))

  ;; `(`, `)`, `"` and `|` are delimiters too: the number ends, and what
  ;; follows is a separate token rather than part of the number.
  (test-eqv "vertical line delimits" 5 (read1 "#b101|a|"))
  (test-eqv "close paren delimits"   5 (car (read1 "(#b101)")))
  (test-equal "quote delimits" '(5 "s") (read1 "(#b101\"s\")")))

;;; ---------------------------------------------------------------------
;;; 2. Control axis: the UN-prefixed decimal path is guarded correctly.
;;;    This is what makes every failure below a prefix-specific defect
;;;    rather than a general reader gap.  These pass today.
;;; ---------------------------------------------------------------------

(test-group "un-prefixed decimal rejects a glued tail (control)"
  (test-assert "12abc"  (rejects? "12abc"))
  (test-assert "1.5abc" (rejects? "1.5abc"))
  (test-assert "1p4"    (rejects? "1p4"))
  (test-assert "1e3x"   (rejects? "1e3x"))
  (test-assert "1/2z"   (rejects? "1/2z"))
  (test-assert "1a"     (rejects? "1a"))
  (test-assert "99999999999999999999z (bignum)" (rejects? "99999999999999999999z"))
  (test-assert "99999999999999999999/3z (bignum rational)"
    (rejects? "99999999999999999999/3z"))
  ;; The un-prefixed reader keeps the list length honest.
  (test-assert "(1p4) is a read error" (rejects? "(1p4)")))

;;; ---------------------------------------------------------------------
;;; 3. Other token kinds already carry the guard.  These are the
;;;    discriminating controls: same reader, same file, same delimiter
;;;    helper -- only the numeric prefixed paths skip the check.
;;;    These pass today.
;;; ---------------------------------------------------------------------

(test-group "guarded token paths (discriminating controls)"
  (test-assert "#tz"       (rejects? "#tz"))
  (test-assert "#fz"       (rejects? "#fz"))
  (test-assert "#truez"    (rejects? "#truez"))
  (test-assert "#\\x41z"   (rejects? "#\\x41z"))
  (test-assert "#\\az"     (rejects? "#\\az"))
  (test-assert "#\\spacez" (rejects? "#\\spacez"))
  (test-assert "#x+inf.0z" (rejects? "#x+inf.0z"))
  ;; The bignum-rational token IS guarded (`bigRationalToken`,
  ;; src/reader_tokens.zig:83) while the fixnum-rational token beside it is
  ;; not -- the sharpest control in this file: the only difference between
  ;; these two inputs is whether the numerator overflows i64.
  (test-assert "#x<bignum>/3z is rejected"
    (rejects? "#x99999999999999999999/3z"))
  (test-assert "#x1/2z is NOT rejected -- same path, fixnum numerator"
    (not (rejects? "#x1/2z"))))

;;; ---------------------------------------------------------------------
;;; 4. Valid syntax that must keep working.  A fix for the gaps below must
;;;    not regress any of these.  These pass today.
;;; ---------------------------------------------------------------------

(test-group "SRFI 270 hexadecimal floats still read"
  (test-eqv "#x1p4"     16.0 #x1p4)
  (test-eqv "#x1.8"      1.5 #x1.8)
  (test-eqv "#x1.0p1"    2.0 #x1.0p1)
  (test-eqv "#xFE.FF" 254.99609375 #xFE.FF)
  (test-eqv "#x1p-1"     0.5 #x1p-1)
  (test-eqv "#x1."       1.0 #x1.)
  (test-assert "#x1p4 reads clean"  (clean? "#x1p4"))
  (test-assert "#x1.8 reads clean"  (clean? "#x1.8"))
  (test-assert "#e#x1p4 is exact"   (exact? #e#x1p4))
  (test-eqv    "#e#x1p4 value" 16   #e#x1p4)
  (test-eqv    "#i#x1.8 value" 1.5  #i#x1.8)
  ;; A hex float with no exponent digits is still an error, not a split.
  (test-assert "#x1p is rejected"  (rejects? "#x1p"))
  (test-assert "#x1pz is rejected" (rejects? "#x1pz")))

(test-group "SRFI 169 digit separators still read"
  (test-eqv "1_2_3"   123 1_2_3)
  (test-eqv "#x1_f"    31 #x1_f)
  (test-eqv "#b1_0"     2 #b1_0)
  (test-eqv "#o1_7"    15 #o1_7)
  (test-eqv "#e1_2"    12 #e1_2)
  (test-eqv "#d1_000" 1000 #d1_000)
  (test-assert "1_2_3 reads clean" (clean? "1_2_3"))
  (test-assert "#x1_f reads clean" (clean? "#x1_f"))
  ;; Misplaced separators are errors, in every radix -- never splits.
  (test-assert "1__0 rejected"    (rejects? "1__0"))
  (test-assert "1_ rejected"      (rejects? "1_"))
  (test-assert "#x1_ rejected"    (rejects? "#x1_"))
  (test-assert "#x1__f rejected"  (rejects? "#x1__f"))
  (test-assert "#b1_ rejected"    (rejects? "#b1_"))
  ;; `_1` is an identifier, not a number -- `_` is a <special initial>.
  (test-assert "_1 is a symbol" (symbol? (read1 "_1"))))

(test-group "rational and complex tails still read"
  (test-eqv "1/2"      1/2 1/2)
  (test-eqv "#x1/2"    1/2 #x1/2)
  (test-eqv "#b1/10"   1/2 #b1/10)
  (test-eqv "#o1/4"    1/4 #o1/4)
  (test-eqv "#e1/2"    1/2 #e1/2)
  (test-assert "1/2 reads clean"   (clean? "1/2"))
  (test-assert "#x1/2 reads clean" (clean? "#x1/2"))
  (test-assert "1/2+3i reads clean" (clean? "1/2+3i"))
  (test-assert "1/2+3i is complex" (not (real? (read1 "1/2+3i"))))
  (test-assert "1/2+3i real part is numerically 1/2"
    (= 1/2 (real-part (read1 "1/2+3i"))))
  (test-assert "1/2+3i imag part is numerically 3"
    (= 3 (imag-part (read1 "1/2+3i"))))
  (test-assert "3+4i reads clean"  (clean? "3+4i"))
  (test-assert "1.5-2i reads clean" (clean? "1.5-2i")))

(test-group "radix letters are digits, not exponent markers"
  (test-eqv "#x1e5 is a hex integer" 485 #x1e5)
  (test-eqv "#x1d"      29 #x1d)
  (test-eqv "#xabcdef" 11259375 #xabcdef)
  (test-eqv "#x1e"      30 #x1e)
  (test-eqv "#d1e5 is a decimal exponent" 100000.0 #d1e5)
  (test-eqv "1e5"  100000.0 1e5)
  (test-assert "#x1e5 reads clean" (clean? "#x1e5")))

(test-group "signs, bignums and bare prefixes still behave"
  (test-eqv "#x-1f"   -31 #x-1f)
  (test-eqv "#b-101"   -5 #b-101)
  (test-eqv "#o-17"   -15 #o-17)
  (test-eqv "#e-1/2" -1/2 #e-1/2)
  (test-eqv "hex bignum" 725355491768777504823705 #x99999999999999999999)
  (test-assert "hex bignum reads clean" (clean? "#x99999999999999999999"))
  (test-assert "#e+inf.0 reads clean"   (clean? "#e+inf.0"))
  ;; A digit that is out of range for the radix is a read error, not a split
  ;; -- the token has no valid digits at all, so there is nothing to split.
  (test-assert "#b2 rejected" (rejects? "#b2"))
  (test-assert "#o8 rejected" (rejects? "#o8"))
  (test-assert "#o9 rejected" (rejects? "#o9"))
  (test-assert "#xg rejected" (rejects? "#xg"))
  (test-assert "#dg rejected" (rejects? "#dg"))
  (test-assert "bare #b rejected" (rejects? "#b"))
  (test-assert "bare #x rejected" (rejects? "#x"))
  (test-assert "bare #e rejected" (rejects? "#e")))

;;; ---------------------------------------------------------------------
;;; 5. The gaps.  `readNumberPrefixed` (src/reader_tokens.zig:481) calls the
;;;    unguarded `reader_tokens.readNumber` / `reader_tokens.readIntegerWith-
;;;    Radix` directly, bypassing the delimiter-checking wrappers
;;;    `Reader.readNumber` (src/reader.zig:366) and
;;;    `Reader.readIntegerWithRadix` (src/reader.zig:646).  The second wrapper
;;;    has no callers at all -- it is dead code.
;;;
;;;    Every assertion below is paired with an ENABLED `string->number`
;;;    assertion immediately above it, showing the oracle already rejects
;;;    the same string.
;;; ---------------------------------------------------------------------

(test-group "radix prefix: trailing character must terminate the token"
  ;; --- #b: a digit from a higher radix ---
  (test-assert "s->n rejects #b12" (not (string->number "#b12")))
  ;; FAIL: #1929 (#b12 reads as 1 followed by the symbol 2)
  ;; (test-assert "#b12 rejected" (rejects? "#b12"))

  (test-assert "s->n rejects #b19" (not (string->number "#b19")))
  ;; FAIL: #1929 (#b19 reads as 1 followed by the symbol 9)
  ;; (test-assert "#b19 rejected" (rejects? "#b19"))

  (test-assert "s->n rejects #o18" (not (string->number "#o18")))
  ;; FAIL: #1929 (#o18 reads as 1 followed by the symbol 8)
  ;; (test-assert "#o18 rejected" (rejects? "#o18"))

  (test-assert "s->n rejects #d1a" (not (string->number "#d1a")))
  ;; FAIL: #1929 (#d1a reads as 1 followed by the symbol a)
  ;; (test-assert "#d1a rejected" (rejects? "#d1a"))

  (test-assert "s->n rejects #x1g" (not (string->number "#x1g")))
  ;; FAIL: #1929 (#x1g reads as 1 followed by the symbol g)
  ;; (test-assert "#x1g rejected" (rejects? "#x1g"))

  ;; --- exponent-marker-shaped letters ---
  (test-assert "s->n rejects #b1p4" (not (string->number "#b1p4")))
  ;; FAIL: #1929 (#b1p4 reads as 1 followed by the symbol p4)
  ;; (test-assert "#b1p4 rejected" (rejects? "#b1p4"))

  (test-assert "s->n rejects #o1e3" (not (string->number "#o1e3")))
  ;; FAIL: #1929 (#o1e3 reads as 1 followed by the symbol e3)
  ;; (test-assert "#o1e3 rejected" (rejects? "#o1e3"))

  (test-assert "s->n rejects #d1p" (not (string->number "#d1p")))
  ;; FAIL: #1929 (#d1p reads as 1 followed by the symbol p)
  ;; (test-assert "#d1p rejected" (rejects? "#d1p"))

  (test-assert "s->n rejects #x1s" (not (string->number "#x1s")))
  ;; FAIL: #1929 (#x1s reads as 1 followed by the symbol s)
  ;; (test-assert "#x1s rejected" (rejects? "#x1s"))

  (test-assert "s->n rejects #x1l" (not (string->number "#x1l")))
  ;; FAIL: #1929 (#x1l reads as 1 followed by the symbol l)
  ;; (test-assert "#x1l rejected" (rejects? "#x1l"))

  ;; --- punctuation ---
  (test-assert "s->n rejects #b1/" (not (string->number "#b1/")))
  ;; FAIL: #1929 (#b1/ reads as 1 followed by the symbol /)
  ;; (test-assert "#b1/ rejected" (rejects? "#b1/"))

  (test-assert "s->n rejects #b1." (not (string->number "#b1.")))
  ;; FAIL: #1929 (#b1. reads as 1 followed by a stray dot token)
  ;; (test-assert "#b1. rejected" (rejects? "#b1."))

  (test-assert "s->n rejects #o1+" (not (string->number "#o1+")))
  ;; FAIL: #1929 (#o1+ reads as 1 followed by the symbol +)
  ;; (test-assert "#o1+ rejected" (rejects? "#o1+"))

  (test-assert "s->n rejects #x1-" (not (string->number "#x1-")))
  ;; FAIL: #1929 (#x1- reads as 1 followed by the symbol -)
  ;; (test-assert "#x1- rejected" (rejects? "#x1-"))

  (test-assert "s->n rejects #b1#" (not (string->number "#b1#")))
  ;; FAIL: #1929 (#b1# reads as 1 followed by a stray # token)
  ;; (test-assert "#b1# rejected" (rejects? "#b1#"))

  (test-assert "s->n rejects #x1'" (not (string->number "#x1'")))
  ;; FAIL: #1929 (#x1' reads as 1 followed by a dangling quote)
  ;; (test-assert "#x1' rejected" (rejects? "#x1'"))

  ;; --- ordinary identifier characters ---
  (test-assert "s->n rejects #x1z"  (not (string->number "#x1z")))
  ;; FAIL: #1929 (#x1z reads as 1 followed by the symbol z)
  ;; (test-assert "#x1z rejected" (rejects? "#x1z"))

  (test-assert "s->n rejects #b1!"  (not (string->number "#b1!")))
  ;; FAIL: #1929 (#b1! reads as 1 followed by the symbol !)
  ;; (test-assert "#b1! rejected" (rejects? "#b1!"))

  (test-assert "s->n rejects #o1~"  (not (string->number "#o1~")))
  ;; FAIL: #1929 (#o1~ reads as 1 followed by the symbol ~)
  ;; (test-assert "#o1~ rejected" (rejects? "#o1~"))

  (test-assert "s->n rejects #d1:"  (not (string->number "#d1:")))
  ;; FAIL: #1929 (#d1: reads as 1 followed by the symbol :)
  ;; (test-assert "#d1: rejected" (rejects? "#d1:"))

  (test-assert "s->n rejects #x1@"  (not (string->number "#x1@")))
  ;; FAIL: #1929 (#x1@ reads as 1 followed by the symbol @)
  ;; (test-assert "#x1@ rejected" (rejects? "#x1@"))

  ;; --- multi-character tails ---
  (test-assert "s->n rejects #b101foo" (not (string->number "#b101foo")))
  ;; FAIL: #1929 (#b101foo reads as 5 followed by the symbol foo)
  ;; (test-assert "#b101foo rejected" (rejects? "#b101foo"))

  (test-assert "s->n rejects #x1zzz" (not (string->number "#x1zzz")))
  ;; FAIL: #1929 (#x1zzz reads as 1 followed by the symbol zzz)
  ;; (test-assert "#x1zzz rejected" (rejects? "#x1zzz"))
  )

(test-group "exactness-only prefix: the same gap on the DECIMAL path"
  ;; No radix at all -- a bare `#e`/`#i` is enough to disable the check,
  ;; because `readNumberPrefixed` routes radix 10 through the unguarded
  ;; `reader_tokens.readNumber`.  (Phase 1A pins `#e1.5abc`, `#e12abc` and
  ;; `#d1e19/3`; these are different spellings of the same gap.)
  (test-assert "s->n rejects #e34zz" (not (string->number "#e34zz")))
  ;; FAIL: #1929 (#e34zz reads as 34 followed by the symbol zz)
  ;; (test-assert "#e34zz rejected" (rejects? "#e34zz"))

  (test-assert "s->n rejects #e1.25xyz" (not (string->number "#e1.25xyz")))
  ;; FAIL: #1929 (#e1.25xyz reads as 5/4 followed by the symbol xyz)
  ;; (test-assert "#e1.25xyz rejected" (rejects? "#e1.25xyz"))

  (test-assert "s->n rejects #i7q" (not (string->number "#i7q")))
  ;; FAIL: #1929 (#i7q reads as 7.0 followed by the symbol q)
  ;; (test-assert "#i7q rejected" (rejects? "#i7q"))

  (test-assert "s->n rejects #i1.5abc" (not (string->number "#i1.5abc")))
  ;; FAIL: #1929 (#i1.5abc reads as 1.5 followed by the symbol abc)
  ;; (test-assert "#i1.5abc rejected" (rejects? "#i1.5abc"))

  (test-assert "s->n rejects #d2e19/7" (not (string->number "#d2e19/7")))
  ;; FAIL: #1929 (#d2e19/7 reads as 2e19 and silently drops the /7)
  ;; (test-assert "#d2e19/7 rejected" (rejects? "#d2e19/7"))

  (test-assert "s->n rejects #e1e3x" (not (string->number "#e1e3x")))
  ;; FAIL: #1929 (#e1e3x reads as 1000 followed by the symbol x)
  ;; (test-assert "#e1e3x rejected" (rejects? "#e1e3x"))
  )

(test-group "two-prefix combinations, in both orders"
  (test-assert "s->n rejects #e#b12" (not (string->number "#e#b12")))
  ;; FAIL: #1929 (#e#b12 reads as 1 followed by the symbol 2)
  ;; (test-assert "#e#b12 rejected" (rejects? "#e#b12"))

  (test-assert "s->n rejects #b#e12" (not (string->number "#b#e12")))
  ;; FAIL: #1929 (#b#e12 reads as 1 followed by the symbol 2)
  ;; (test-assert "#b#e12 rejected" (rejects? "#b#e12"))

  (test-assert "s->n rejects #i#b1z" (not (string->number "#i#b1z")))
  ;; FAIL: #1929 (#i#b1z reads as 1.0 followed by the symbol z)
  ;; (test-assert "#i#b1z rejected" (rejects? "#i#b1z"))

  (test-assert "s->n rejects #b#i1z" (not (string->number "#b#i1z")))
  ;; FAIL: #1929 (#b#i1z reads as 1.0 followed by the symbol z)
  ;; (test-assert "#b#i1z rejected" (rejects? "#b#i1z"))

  (test-assert "s->n rejects #e#o19" (not (string->number "#e#o19")))
  ;; FAIL: #1929 (#e#o19 reads as 1 followed by the symbol 9)
  ;; (test-assert "#e#o19 rejected" (rejects? "#e#o19"))

  (test-assert "s->n rejects #o#e19" (not (string->number "#o#e19")))
  ;; FAIL: #1929 (#o#e19 reads as 1 followed by the symbol 9)
  ;; (test-assert "#o#e19 rejected" (rejects? "#o#e19"))

  (test-assert "s->n rejects #e#x1g" (not (string->number "#e#x1g")))
  ;; FAIL: #1929 (#e#x1g reads as 1 followed by the symbol g)
  ;; (test-assert "#e#x1g rejected" (rejects? "#e#x1g"))

  (test-assert "s->n rejects #x#e1g" (not (string->number "#x#e1g")))
  ;; FAIL: #1929 (#x#e1g reads as 1 followed by the symbol g)
  ;; (test-assert "#x#e1g rejected" (rejects? "#x#e1g"))

  (test-assert "s->n rejects #e#d1a" (not (string->number "#e#d1a")))
  ;; FAIL: #1929 (#e#d1a reads as 1 followed by the symbol a)
  ;; (test-assert "#e#d1a rejected" (rejects? "#e#d1a"))

  (test-assert "s->n rejects #d#e1a" (not (string->number "#d#e1a")))
  ;; FAIL: #1929 (#d#e1a reads as 1 followed by the symbol a)
  ;; (test-assert "#d#e1a rejected" (rejects? "#d#e1a"))
  )

(test-group "SRFI 270 hex-float suffix path is unguarded too"
  ;; A third unguarded return, in `readHexFloatSuffix`
  ;; (src/reader_tokens.zig:829) -- beyond the fixnum and rational returns
  ;; named in #1892.
  (test-assert "s->n rejects #x1p4z" (not (string->number "#x1p4z")))
  ;; FAIL: #1929 (#x1p4z reads as 16.0 followed by the symbol z)
  ;; (test-assert "#x1p4z rejected" (rejects? "#x1p4z"))

  (test-assert "s->n rejects #x1.8z" (not (string->number "#x1.8z")))
  ;; FAIL: #1929 (#x1.8z reads as 1.5 followed by the symbol z)
  ;; (test-assert "#x1.8z rejected" (rejects? "#x1.8z"))

  (test-assert "s->n rejects #x1.g" (not (string->number "#x1.g")))
  ;; FAIL: #1929 (#x1.g reads as 1.0 followed by the symbol g)
  ;; (test-assert "#x1.g rejected" (rejects? "#x1.g"))

  (test-assert "s->n rejects #x1p4/3" (not (string->number "#x1p4/3")))
  ;; FAIL: #1929 (#x1p4/3 reads as 16.0 followed by the symbol /3)
  ;; (test-assert "#x1p4/3 rejected" (rejects? "#x1p4/3"))
  )

(test-group "bignum and rational token paths are unguarded too"
  ;; `.bignum_str` (i64 overflow) -- the guarded `.big_rational` sibling in
  ;; the same function is the control in group 3 above.
  (test-assert "s->n rejects #x<bignum>z"
    (not (string->number "#x99999999999999999999z")))
  ;; FAIL: #1929 (#x99999999999999999999z reads as a bignum plus the symbol z)
  ;; (test-assert "#x<bignum>z rejected" (rejects? "#x99999999999999999999z"))

  (test-assert "s->n rejects #d<bignum>z"
    (not (string->number "#d99999999999999999999z")))
  ;; FAIL: #1929 (#d99999999999999999999z reads as a bignum plus the symbol z)
  ;; (test-assert "#d<bignum>z rejected" (rejects? "#d99999999999999999999z"))

  (test-assert "s->n rejects #e<bignum>z"
    (not (string->number "#e99999999999999999999z")))
  ;; FAIL: #1929 (#e99999999999999999999z reads as a bignum plus the symbol z)
  ;; (test-assert "#e<bignum>z rejected" (rejects? "#e99999999999999999999z"))

  ;; A binary literal one digit too wide for i64, with a `2` glued on.
  (test-assert "s->n rejects the wide binary literal"
    (not (string->number
          "#b1111111111111111111111111111111111111111111111111111111111111111112")))
  ;; FAIL: #1929 (wide binary literal reads as a bignum plus the symbol 2)
  ;; (test-assert "wide binary literal rejected"
  ;;   (rejects?
  ;;    "#b1111111111111111111111111111111111111111111111111111111111111111112"))

  ;; Fixnum rational.
  (test-assert "s->n rejects #x1/2z" (not (string->number "#x1/2z")))
  ;; FAIL: #1929 (#x1/2z reads as 1/2 followed by the symbol z)
  ;; (test-assert "#x1/2z rejected" (rejects? "#x1/2z"))

  (test-assert "s->n rejects #e1/2z" (not (string->number "#e1/2z")))
  ;; FAIL: #1929 (#e1/2z reads as 1/2 followed by the symbol z)
  ;; (test-assert "#e1/2z rejected" (rejects? "#e1/2z"))

  (test-assert "s->n rejects #b1/1z" (not (string->number "#b1/1z")))
  ;; FAIL: #1929 (#b1/1z reads as 1 followed by the symbol z)
  ;; (test-assert "#b1/1z rejected" (rejects? "#b1/1z"))

  ;; A radix rational followed by a complex tail: the decimal path accepts
  ;; `1/2+3i`, the radix path silently splits it instead of rejecting it.
  (test-assert "s->n rejects #x1/2+3i" (not (string->number "#x1/2+3i")))
  ;; FAIL: #1929 (#x1/2+3i reads as 1/2 followed by the symbol +3i)
  ;; (test-assert "#x1/2+3i rejected or read whole" (not (splits? "#x1/2+3i")))
  )

;;; ---------------------------------------------------------------------
;;; 6. Datum-count damage.  The reason this matters: a split changes the
;;;    LENGTH of a list, so a program's structure changes silently.
;;; ---------------------------------------------------------------------

(test-group "a split changes the datum count of an enclosing list"
  (test-eqv "(#b101) has one element (control)" 1 (length (read1 "(#b101)")))
  (test-eqv "(#x1p4) has one element (control)" 1 (length (read1 "(#x1p4)")))

  ;; FAIL: #1929 ('(#b1p4) reads as the two-element list (1 p4))
  ;; (test-eqv "(#b1p4) is not two datums" 1 (length (read1 "(#b1p4)")))
  ;; FAIL: #1929 ('(#o1e3) reads as the two-element list (1 e3))
  ;; (test-eqv "(#o1e3) is not two datums" 1 (length (read1 "(#o1e3)")))
  ;; FAIL: #1929 ('(#e12abc) reads as the two-element list (12 abc))
  ;; (test-eqv "(#e12abc) is not two datums" 1 (length (read1 "(#e12abc)")))
  ;; FAIL: #1929 ('(#x1p4z) reads as the two-element list (16.0 z))
  ;; (test-eqv "(#x1p4z) is not two datums" 1 (length (read1 "(#x1p4z)")))
  )

;;; ---------------------------------------------------------------------
;;; 7. Not a delimiter failure: an exactness/value divergence found by the
;;;    same reader-vs-string->number comparison.  Adjacent to #1891
;;;    (Phase 1A's `#e` over the i64 boundary), filed neither there nor in
;;;    #1892 as of this writing.
;;; ---------------------------------------------------------------------

(test-group "reader vs string->number, non-delimiter divergences"
  ;; `#e+inf.0` reads as the inexact +inf.0 while `string->number` rejects
  ;; the same string.  Chibi 0.12 also reads it as +inf.0, so the reader
  ;; side matches the project's own differential oracle and the divergence
  ;; is on the `string->number` side.
  (test-assert "reader accepts #e+inf.0" (clean? "#e+inf.0"))
  ;; FAIL: TBD (string->number "#e+inf.0" returns #f where READ yields +inf.0)
  ;; (test-assert "s->n agrees with read on #e+inf.0"
  ;;   (string->number "#e+inf.0"))

  ;; The same shape again: the READER accepts `1/2+3i`, which R7RS 7.1.1's
  ;; <complex R> --> <real R> + <ureal R> i production allows (and Chibi
  ;; accepts), but `string->number` rejects it.  The reader is right here.
  (test-assert "reader accepts 1/2+3i" (clean? "1/2+3i"))
  ;; FAIL: TBD (string->number "1/2+3i" returns #f for a valid R7RS complex)
  ;; (test-assert "s->n accepts 1/2+3i" (string->number "1/2+3i"))

  ;; Same literal, a third divergence: it PRINTS as `1/2+3i` (exact real
  ;; part) but `real-part` hands back the inexact 0.5, so `write` does not
  ;; round-trip its exactness.  Not a delimiter defect; noted here because
  ;; the same reader-vs-oracle sweep surfaced it.
  (test-assert "1/2+3i writes with an exact-looking real part"
    (equal? "1/2+3i"
            (let ((p (open-output-string)))
              (write (read1 "1/2+3i") p)
              (get-output-string p))))
  ;; FAIL: TBD (real-part of the exact complex 1/2+3i is the inexact 0.5)
  ;; (test-assert "1/2+3i real part is exact" (exact? (real-part (read1 "1/2+3i"))))
  )

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "reader-delimiter-gaps")
(if (> %test-fail-count 0) (exit 1))
