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
  ;; The bignum-rational token was the one guarded (`bigRationalToken`,
  ;; src/reader_tokens.zig:83) while the fixnum-rational token beside it was
  ;; not -- the sharpest control in this file pre-#1929: the only difference
  ;; between these two inputs is whether the numerator overflows i64.  The
  ;; #1929 fix (one delimiter check in `readNumberPrefixed`) now guards both.
  (test-assert "#x<bignum>/3z is rejected"
    (rejects? "#x99999999999999999999/3z"))
  (test-assert "#x1/2z is rejected -- same path, fixnum numerator"
    (rejects? "#x1/2z")))

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
  ;; #e+inf.0 is a read error since #1911: no exact representation exists,
  ;; and string->number already rejected it (#419).  #i+inf.0 stays valid.
  (test-assert "#e+inf.0 rejected"      (rejects? "#e+inf.0"))
  (test-assert "#i+inf.0 reads clean"   (clean? "#i+inf.0"))
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
;;; 5. The gaps, closed by #1929.  `readNumberPrefixed`
;;;    (src/reader_tokens.zig:481) used to call the file-local unguarded
;;;    `reader_tokens.readNumber` / `reader_tokens.readIntegerWithRadix`
;;;    directly, bypassing the delimiter check; the one wrapper that did
;;;    check, `Reader.readIntegerWithRadix` (src/reader.zig), had no callers
;;;    at all -- dead code, since deleted.  A single delimiter check after
;;;    the body read in `readNumberPrefixed` now guards every prefixed
;;;    spelling.
;;;
;;;    Every assertion below is paired with an ENABLED `string->number`
;;;    assertion immediately above it, showing the oracle already rejects
;;;    the same string.
;;; ---------------------------------------------------------------------

(test-group "radix prefix: trailing character must terminate the token"
  ;; --- #b: a digit from a higher radix ---
  (test-assert "s->n rejects #b12" (not (string->number "#b12")))
  (test-assert "#b12 rejected" (rejects? "#b12"))

  (test-assert "s->n rejects #b19" (not (string->number "#b19")))
  (test-assert "#b19 rejected" (rejects? "#b19"))

  (test-assert "s->n rejects #o18" (not (string->number "#o18")))
  (test-assert "#o18 rejected" (rejects? "#o18"))

  (test-assert "s->n rejects #d1a" (not (string->number "#d1a")))
  (test-assert "#d1a rejected" (rejects? "#d1a"))

  (test-assert "s->n rejects #x1g" (not (string->number "#x1g")))
  (test-assert "#x1g rejected" (rejects? "#x1g"))

  ;; --- exponent-marker-shaped letters ---
  (test-assert "s->n rejects #b1p4" (not (string->number "#b1p4")))
  (test-assert "#b1p4 rejected" (rejects? "#b1p4"))

  (test-assert "s->n rejects #o1e3" (not (string->number "#o1e3")))
  (test-assert "#o1e3 rejected" (rejects? "#o1e3"))

  (test-assert "s->n rejects #d1p" (not (string->number "#d1p")))
  (test-assert "#d1p rejected" (rejects? "#d1p"))

  (test-assert "s->n rejects #x1s" (not (string->number "#x1s")))
  (test-assert "#x1s rejected" (rejects? "#x1s"))

  (test-assert "s->n rejects #x1l" (not (string->number "#x1l")))
  (test-assert "#x1l rejected" (rejects? "#x1l"))

  ;; --- punctuation ---
  (test-assert "s->n rejects #b1/" (not (string->number "#b1/")))
  (test-assert "#b1/ rejected" (rejects? "#b1/"))

  (test-assert "s->n rejects #b1." (not (string->number "#b1.")))
  (test-assert "#b1. rejected" (rejects? "#b1."))

  (test-assert "s->n rejects #o1+" (not (string->number "#o1+")))
  (test-assert "#o1+ rejected" (rejects? "#o1+"))

  (test-assert "s->n rejects #x1-" (not (string->number "#x1-")))
  (test-assert "#x1- rejected" (rejects? "#x1-"))

  (test-assert "s->n rejects #b1#" (not (string->number "#b1#")))
  (test-assert "#b1# rejected" (rejects? "#b1#"))

  (test-assert "s->n rejects #x1'" (not (string->number "#x1'")))
  (test-assert "#x1' rejected" (rejects? "#x1'"))

  ;; --- ordinary identifier characters ---
  (test-assert "s->n rejects #x1z"  (not (string->number "#x1z")))
  (test-assert "#x1z rejected" (rejects? "#x1z"))

  (test-assert "s->n rejects #b1!"  (not (string->number "#b1!")))
  (test-assert "#b1! rejected" (rejects? "#b1!"))

  (test-assert "s->n rejects #o1~"  (not (string->number "#o1~")))
  (test-assert "#o1~ rejected" (rejects? "#o1~"))

  (test-assert "s->n rejects #d1:"  (not (string->number "#d1:")))
  (test-assert "#d1: rejected" (rejects? "#d1:"))

  (test-assert "s->n rejects #x1@"  (not (string->number "#x1@")))
  (test-assert "#x1@ rejected" (rejects? "#x1@"))

  ;; --- multi-character tails ---
  (test-assert "s->n rejects #b101foo" (not (string->number "#b101foo")))
  (test-assert "#b101foo rejected" (rejects? "#b101foo"))

  (test-assert "s->n rejects #x1zzz" (not (string->number "#x1zzz")))
  (test-assert "#x1zzz rejected" (rejects? "#x1zzz"))
  )

(test-group "exactness-only prefix: the same gap on the DECIMAL path"
  ;; No radix at all -- a bare `#e`/`#i` is enough to disable the check,
  ;; because `readNumberPrefixed` routes radix 10 through the unguarded
  ;; `reader_tokens.readNumber`.  (Phase 1A pins `#e1.5abc`, `#e12abc` and
  ;; `#d1e19/3`; these are different spellings of the same gap.)
  (test-assert "s->n rejects #e34zz" (not (string->number "#e34zz")))
  (test-assert "#e34zz rejected" (rejects? "#e34zz"))

  (test-assert "s->n rejects #e1.25xyz" (not (string->number "#e1.25xyz")))
  (test-assert "#e1.25xyz rejected" (rejects? "#e1.25xyz"))

  (test-assert "s->n rejects #i7q" (not (string->number "#i7q")))
  (test-assert "#i7q rejected" (rejects? "#i7q"))

  (test-assert "s->n rejects #i1.5abc" (not (string->number "#i1.5abc")))
  (test-assert "#i1.5abc rejected" (rejects? "#i1.5abc"))

  (test-assert "s->n rejects #d2e19/7" (not (string->number "#d2e19/7")))
  (test-assert "#d2e19/7 rejected" (rejects? "#d2e19/7"))

  (test-assert "s->n rejects #e1e3x" (not (string->number "#e1e3x")))
  (test-assert "#e1e3x rejected" (rejects? "#e1e3x"))
  )

(test-group "two-prefix combinations, in both orders"
  (test-assert "s->n rejects #e#b12" (not (string->number "#e#b12")))
  (test-assert "#e#b12 rejected" (rejects? "#e#b12"))

  (test-assert "s->n rejects #b#e12" (not (string->number "#b#e12")))
  (test-assert "#b#e12 rejected" (rejects? "#b#e12"))

  (test-assert "s->n rejects #i#b1z" (not (string->number "#i#b1z")))
  (test-assert "#i#b1z rejected" (rejects? "#i#b1z"))

  (test-assert "s->n rejects #b#i1z" (not (string->number "#b#i1z")))
  (test-assert "#b#i1z rejected" (rejects? "#b#i1z"))

  (test-assert "s->n rejects #e#o19" (not (string->number "#e#o19")))
  (test-assert "#e#o19 rejected" (rejects? "#e#o19"))

  (test-assert "s->n rejects #o#e19" (not (string->number "#o#e19")))
  (test-assert "#o#e19 rejected" (rejects? "#o#e19"))

  (test-assert "s->n rejects #e#x1g" (not (string->number "#e#x1g")))
  (test-assert "#e#x1g rejected" (rejects? "#e#x1g"))

  (test-assert "s->n rejects #x#e1g" (not (string->number "#x#e1g")))
  (test-assert "#x#e1g rejected" (rejects? "#x#e1g"))

  (test-assert "s->n rejects #e#d1a" (not (string->number "#e#d1a")))
  (test-assert "#e#d1a rejected" (rejects? "#e#d1a"))

  (test-assert "s->n rejects #d#e1a" (not (string->number "#d#e1a")))
  (test-assert "#d#e1a rejected" (rejects? "#d#e1a"))
  )

(test-group "SRFI 270 hex-float suffix path is unguarded too"
  ;; A third unguarded return, in `readHexFloatSuffix`
  ;; (src/reader_tokens.zig:829) -- beyond the fixnum and rational returns
  ;; named in #1892.
  (test-assert "s->n rejects #x1p4z" (not (string->number "#x1p4z")))
  (test-assert "#x1p4z rejected" (rejects? "#x1p4z"))

  (test-assert "s->n rejects #x1.8z" (not (string->number "#x1.8z")))
  (test-assert "#x1.8z rejected" (rejects? "#x1.8z"))

  (test-assert "s->n rejects #x1.g" (not (string->number "#x1.g")))
  (test-assert "#x1.g rejected" (rejects? "#x1.g"))

  (test-assert "s->n rejects #x1p4/3" (not (string->number "#x1p4/3")))
  (test-assert "#x1p4/3 rejected" (rejects? "#x1p4/3"))
  )

(test-group "bignum and rational token paths are unguarded too"
  ;; `.bignum_str` (i64 overflow) -- the guarded `.big_rational` sibling in
  ;; the same function is the control in group 3 above.
  (test-assert "s->n rejects #x<bignum>z"
    (not (string->number "#x99999999999999999999z")))
  (test-assert "#x<bignum>z rejected" (rejects? "#x99999999999999999999z"))

  (test-assert "s->n rejects #d<bignum>z"
    (not (string->number "#d99999999999999999999z")))
  (test-assert "#d<bignum>z rejected" (rejects? "#d99999999999999999999z"))

  (test-assert "s->n rejects #e<bignum>z"
    (not (string->number "#e99999999999999999999z")))
  (test-assert "#e<bignum>z rejected" (rejects? "#e99999999999999999999z"))

  ;; A binary literal one digit too wide for i64, with a `2` glued on.
  (test-assert "s->n rejects the wide binary literal"
    (not (string->number
          "#b1111111111111111111111111111111111111111111111111111111111111111112")))
  (test-assert "wide binary literal rejected"
    (rejects?
     "#b1111111111111111111111111111111111111111111111111111111111111111112"))

  ;; Fixnum rational.
  (test-assert "s->n rejects #x1/2z" (not (string->number "#x1/2z")))
  (test-assert "#x1/2z rejected" (rejects? "#x1/2z"))

  (test-assert "s->n rejects #e1/2z" (not (string->number "#e1/2z")))
  (test-assert "#e1/2z rejected" (rejects? "#e1/2z"))

  (test-assert "s->n rejects #b1/1z" (not (string->number "#b1/1z")))
  (test-assert "#b1/1z rejected" (rejects? "#b1/1z"))

  ;; A radix rational followed by a complex tail: `#x1/2+3i` is a valid
  ;; R7RS 7.1.1 <complex R> (real 1/2 + imag 3, both in radix 16) and now
  ;; reads whole in both parsers (#2243).  It used to silently split into
  ;; `1/2` + `+3i` before #1929 closed the gap, then read-error until
  ;; #2243 accepted the grammar.  The glued-tail siblings still reject in
  ;; both parsers.
  (test-assert "s->n accepts #x1/2+3i" (string->number "#x1/2+3i"))
  (test-assert "#x1/2+3i reads whole" (clean? "#x1/2+3i"))
  (test-assert "s->n rejects #x1/2+3z" (not (string->number "#x1/2+3z")))
  (test-assert "#x1/2+3z rejected" (rejects? "#x1/2+3z"))
  (test-assert "s->n rejects #x1/2+3iz" (not (string->number "#x1/2+3iz")))
  (test-assert "#x1/2+3iz rejected" (rejects? "#x1/2+3iz"))
  )

;;; ---------------------------------------------------------------------
;;; 6. Datum-count damage.  The reason this matters: a split changes the
;;;    LENGTH of a list, so a program's structure changes silently.
;;; ---------------------------------------------------------------------

(test-group "a split changes the datum count of an enclosing list"
  (test-eqv "(#b101) has one element (control)" 1 (length (read1 "(#b101)")))
  (test-eqv "(#x1p4) has one element (control)" 1 (length (read1 "(#x1p4)")))

  ;; A malformed prefixed token inside a list used to read as two datums,
  ;; silently changing the list's length: '(#b1p4) became (1 p4).  Now the
  ;; whole list is a read error -- never a longer list.
  (test-assert "(#b1p4) is a read error, not two datums"
    (rejects? "(#b1p4)"))
  (test-assert "(#o1e3) is a read error, not two datums"
    (rejects? "(#o1e3)"))
  (test-assert "(#e12abc) is a read error, not two datums"
    (rejects? "(#e12abc)"))
  (test-assert "(#x1p4z) is a read error, not two datums"
    (rejects? "(#x1p4z)")))

;;; ---------------------------------------------------------------------
;;; 7. Not a delimiter failure: an exactness/value divergence found by the
;;;    same reader-vs-string->number comparison.  Adjacent to #1891
;;;    (Phase 1A's `#e` over the i64 boundary), filed neither there nor in
;;;    #1892 as of this writing.
;;; ---------------------------------------------------------------------

(test-group "reader vs string->number, non-delimiter divergences"
  ;; `#e+inf.0`: the reader used to yield the inexact +inf.0 while
  ;; string->number rejected the same string.  R7RS 6.2.3 permits either
  ;; treatment of an unrepresentable exact constant (Chibi reads it as
  ;; +inf.0, Racket errors), but 6.2.7 requires the two parsers to agree;
  ;; #1911 settled the divergence on the #419 side, so both now reject.
  (test-assert "reader rejects #e+inf.0" (rejects? "#e+inf.0"))
  (test-assert "s->n agrees with read on #e+inf.0"
    (not (string->number "#e+inf.0")))

  ;; The same shape again: the READER accepts `1/2+3i`, which R7RS 7.1.1's
  ;; <complex R> --> <real R> + <ureal R> i production allows (and Chibi
  ;; accepts), but `string->number` used to reject it.  The reader was
  ;; right; #2243 closed the divergence on the acceptance side by teaching
  ;; string->number the rational-component complex grammar, in every
  ;; radix.
  (test-assert "reader accepts 1/2+3i" (clean? "1/2+3i"))
  (test-assert "s->n accepts 1/2+3i" (string->number "1/2+3i"))
  (test-assert "s->n accepts #d1/2+3i" (string->number "#d1/2+3i"))
  (test-assert "s->n accepts #x1/2+3i" (string->number "#x1/2+3i"))

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

;;; ---------------------------------------------------------------------
;;; 8. Radix-prefixed complex numbers (#2243).  R7RS 7.1.1's
;;;    <complex R> --> <real R> + <ureal R> i | <real R> - <ureal R> i |
;;;    <real R> + i | <real R> - i productions are valid in every radix,
;;;    and `read` and `string->number` now agree on them (R7RS 6.2.7).
;;;    Radix-valid digits only: a digit that is not valid in the radix
;;;    (or any glued tail) still fails the #1929 delimiter check.
;;; ---------------------------------------------------------------------

(test-group "radix-prefixed complex numbers read per R7RS <complex R>"
  (test-assert "#x1/2+3i reads clean" (clean? "#x1/2+3i"))
  (test-assert "#x1/2+3i is complex" (not (real? (read1 "#x1/2+3i"))))
  (test-assert "#x1/2+3i real part is 1/2" (= 1/2 (real-part (read1 "#x1/2+3i"))))
  (test-assert "#x1/2+3i imag part is 3" (= 3 (imag-part (read1 "#x1/2+3i"))))
  (test-assert "#x1+2i reads clean" (clean? "#x1+2i"))
  (test-assert "#x1+i reads clean" (clean? "#x1+i"))
  (test-assert "#x1-i reads clean" (clean? "#x1-i"))
  (test-assert "#x+i reads clean" (clean? "#x+i"))
  (test-assert "#x-i reads clean" (clean? "#x-i"))
  (test-assert "#b+i reads clean" (clean? "#b+i"))
  (test-assert "#x+3i reads clean (signed magnitude)" (clean? "#x+3i"))
  (test-assert "#x+3i is 0+3i" (= 3 (imag-part (read1 "#x+3i"))))
  (test-assert "#x+1i reads clean" (clean? "#x+1i"))
  (test-assert "#x-3i reads clean" (clean? "#x-3i"))
  (test-assert "#x+3/4i reads clean (rational magnitude)" (clean? "#x+3/4i"))
  (test-assert "#x-3/4i reads clean" (clean? "#x-3/4i"))
  (test-assert "+3/4i reads clean (radix 10)" (clean? "+3/4i"))
  ;; the imaginary marker is case-insensitive in both parsers
  (test-assert "#x1+2I reads clean" (clean? "#x1+2I"))
  (test-assert "s->n #x1+2I agrees" (complex? (string->number "#x1+2I")))
  (test-assert "#x1+2i reads clean" (clean? "#x1+2i"))
  (test-assert "#x1+1/2i reads clean" (clean? "#x1+1/2i"))
  (test-assert "#x1/2+3/4i reads clean" (clean? "#x1/2+3/4i"))
  (test-assert "#b1+1i reads clean" (clean? "#b1+1i"))
  (test-assert "#o1+2i reads clean" (clean? "#o1+2i"))
  (test-assert "#x-1+2i reads clean" (clean? "#x-1+2i"))
  (test-assert "#e#x1/2+3i is exact" (exact? (read1 "#e#x1/2+3i")))
  (test-assert "#i#x1/2+3i is inexact" (inexact? (read1 "#i#x1/2+3i")))
  ;; string->number agrees (6.2.7) on the new acceptance.
  (test-assert "s->n #x1/2+3i" (complex? (string->number "#x1/2+3i")))
  (test-assert "s->n #x1+2i" (complex? (string->number "#x1+2i")))
  (test-assert "s->n #b1+1i" (complex? (string->number "#b1+1i")))
  ;; Radix-valid digits only.
  (test-assert "#b1+2i rejected (2 not binary)" (rejects? "#b1+2i"))
  (test-assert "s->n #b1+2i" (not (string->number "#b1+2i")))
  (test-assert "#o1+8i rejected (8 not octal)" (rejects? "#o1+8i"))
  (test-assert "#x1+2 rejected (no i)" (rejects? "#x1+2"))
  (test-assert "s->n #x1+2" (not (string->number "#x1+2")))
  (test-assert "#x1+2iz rejected (glued tail)" (rejects? "#x1+2iz"))
  (test-assert "#x1/2+3z rejected (glued tail)" (rejects? "#x1/2+3z"))
  (test-assert "#x3i rejected (signless radix imaginary)"
    (rejects? "#x3i"))
  (test-assert "#xi rejected (signless radix imaginary)"
    (rejects? "#xi"))
  (test-assert "s->n #xi" (not (string->number "#xi")))
  (test-assert "#x3/4i rejected (signless rational imaginary)"
    (rejects? "#x3/4i"))
  ;; Bignum components have no honest f64 token value: loud rejection,
  ;; matching the radix-10 grammar's i64 bound (kaappi#2182 stance).
  (test-assert "#x99999999999999999999+2i rejected"
    (rejects? "#x99999999999999999999+2i"))
  (test-assert "#x1+99999999999999999999i rejected"
    (rejects? "#x1+99999999999999999999i"))
  ;; A component in (2^53, 2^63] that does not round-trip through f64 is
  ;; rejected loudly too -- an exact-flagged token must never silently
  ;; carry a rounded value (kaappi#2182/#2243).
  (test-assert "#x20000000000001+2i rejected (2^53+1)"
    (rejects? "#x20000000000001+2i"))
  (test-assert "#x1+20000000000001i rejected"
    (rejects? "#x1+20000000000001i"))
  (test-assert "s->n #x20000000000001+2i"
    (not (string->number "#x20000000000001+2i")))
  (test-assert "9007199254740993+2i rejected (radix 10, 2^53+1)"
    (rejects? "9007199254740993+2i"))
  (test-assert "s->n 9007199254740993+2i"
    (not (string->number "9007199254740993+2i")))
  ;; A rational component beyond the printer's recovery granularity is
  ;; rejected too (its f64 would print as a wrong mantissa/2^k fraction).
  (test-assert "1/20000000000001+3i rejected (den > 1e6)"
    (rejects? "1/20000000000001+3i"))
  (test-assert "s->n 1/20000000000001+3i"
    (not (string->number "1/20000000000001+3i")))
  ;; A radix complex inside a list is one datum, never two.
  (test-eqv "(#x1+2i) has one element" 1 (length (read1 "(#x1+2i)")))
  (test-assert "(#x1+2iz) is a read error, not two datums"
    (rejects? "(#x1+2iz)"))
  )

;;; ---------------------------------------------------------------------
;;; 9. string->number with an explicit radix argument: `i` is an ordinary
;;;    digit (value 18) from radix 19 up, so the imaginary-marker
;;;    interpretation only exists at radix <= 18 (#2243 review).
;;; ---------------------------------------------------------------------

(test-group "radix >= 19 treats i as a digit, not the imaginary marker"
  ;; i = 18 at radix 19, so the denominator 2i is 2*19+18 = 56.
  (test-equal "s->n 1/2i radix 19" 1/56 (string->number "1/2i" 19))
  (test-equal "s->n 1/2i radix 36" 1/90 (string->number "1/2i" 36))
  (test-assert "s->n 1/2i radix 18 (i not a digit) is not a number"
    (not (string->number "1/2i" 18)))
  (test-equal "s->n 1/2 radix 19 unchanged" 1/2 (string->number "1/2" 19))
  )

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "reader-delimiter-gaps")
(if (> %test-fail-count 0) (exit 1))
