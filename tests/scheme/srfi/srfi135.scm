;;; SRFI 135 (Immutable Texts) conformance tests.

(import (scheme base)
        (scheme char)
        (scheme process-context)
        (srfi 64)
        (srfi 135))

(test-begin "srfi-135")

;;;=========================================================================
;;; Predicates
;;;=========================================================================

(test-assert "text? on text" (text? (text #\a #\b #\c)))
(test-assert "text? on string is #f" (not (text? "abc")))
(test-assert "text? on empty text" (text? (text)))

(test-assert "textual? on text" (textual? (text #\a)))
(test-assert "textual? on string" (textual? "abc"))
(test-assert "textual? on number is #f" (not (textual? 42)))

(test-assert "textual-null? on empty text" (textual-null? (text)))
(test-assert "textual-null? on empty string" (textual-null? ""))
(test-assert "textual-null? on non-empty" (not (textual-null? (text #\a))))

(test-assert "textual-every char-alphabetic?"
  (textual-every char-alphabetic? (text #\a #\b #\c)))
(test-assert "textual-every fails"
  (not (textual-every char-alphabetic? (text #\a #\1 #\c))))
(test-assert "textual-every on empty"
  (textual-every char-alphabetic? (text)))

(test-assert "textual-any char-numeric?"
  (textual-any char-numeric? (text #\a #\1 #\c)))
(test-assert "textual-any fails"
  (not (textual-any char-numeric? (text #\a #\b #\c))))

;;;=========================================================================
;;; Constructors
;;;=========================================================================

(test-equal "text constructor"
  "abc"
  (textual->string (text #\a #\b #\c)))

(test-equal "make-text"
  "aaa"
  (textual->string (make-text 3 #\a)))

(test-equal "text-tabulate"
  "abcde"
  (textual->string
   (text-tabulate (lambda (i) (integer->char (+ i 97))) 5)))

(test-equal "text-unfold"
  "12345"
  (textual->string
   (text-unfold (lambda (s) (> s 5))
                (lambda (s) (integer->char (+ s 48)))
                (lambda (s) (+ s 1))
                1)))

(test-equal "text-unfold-right"
  "54321"
  (textual->string
   (text-unfold-right (lambda (s) (> s 5))
                      (lambda (s) (integer->char (+ s 48)))
                      (lambda (s) (+ s 1))
                      1)))

;;;=========================================================================
;;; Conversion
;;;=========================================================================

(test-equal "textual->string"
  "hello"
  (textual->string (text #\h #\e #\l #\l #\o)))

(test-equal "textual->string from string"
  "hello"
  (textual->string "hello"))

(test-equal "textual->string with start"
  "llo"
  (textual->string (text #\h #\e #\l #\l #\o) 2))

(test-equal "textual->string with start and end"
  "ll"
  (textual->string (text #\h #\e #\l #\l #\o) 2 4))

(test-equal "string->text round-trip"
  "hello"
  (textual->string (string->text "hello")))

(test-equal "string->text with start end"
  "ell"
  (textual->string (string->text "hello" 1 4)))

(test-equal "list->text"
  "abc"
  (textual->string (list->text '(#\a #\b #\c))))

(test-equal "textual->list"
  '(#\a #\b #\c)
  (textual->list (text #\a #\b #\c)))

(test-equal "vector->text"
  "abc"
  (textual->string (vector->text #(#\a #\b #\c))))

(test-equal "textual->vector"
  #(#\a #\b #\c)
  (textual->vector (text #\a #\b #\c)))

(test-equal "reverse-list->text"
  "cba"
  (textual->string (reverse-list->text '(#\a #\b #\c))))

(test-assert "textual->text from string"
  (text? (textual->text "hello")))
(test-assert "textual->text from text"
  (text? (textual->text (text #\a))))

(test-equal "textual->utf8"
  (string->utf8 "hello")
  (textual->utf8 (text #\h #\e #\l #\l #\o)))

(test-equal "utf8->text"
  "hello"
  (textual->string (utf8->text (string->utf8 "hello"))))

;;;=========================================================================
;;; Selection
;;;=========================================================================

(test-equal "text-length"
  5
  (text-length (text #\h #\e #\l #\l #\o)))

(test-equal "textual-length on text"
  5
  (textual-length (text #\h #\e #\l #\l #\o)))

(test-equal "textual-length on string"
  5
  (textual-length "hello"))

(test-equal "text-ref"
  #\l
  (text-ref (text #\h #\e #\l #\l #\o) 2))

(test-equal "textual-ref on text"
  #\e
  (textual-ref (text #\h #\e #\l #\l #\o) 1))

(test-equal "textual-ref on string"
  #\e
  (textual-ref "hello" 1))

(test-equal "subtext"
  "ell"
  (textual->string (subtext (text #\h #\e #\l #\l #\o) 1 4)))

(test-equal "subtextual"
  "ell"
  (textual->string (subtextual "hello" 1 4)))

(test-equal "textual-copy"
  "hello"
  (textual->string (textual-copy (text #\h #\e #\l #\l #\o))))

(test-equal "textual-copy with start end"
  "ell"
  (textual->string (textual-copy (text #\h #\e #\l #\l #\o) 1 4)))

(test-equal "textual-take"
  "hel"
  (textual->string (textual-take (text #\h #\e #\l #\l #\o) 3)))

(test-equal "textual-drop"
  "lo"
  (textual->string (textual-drop (text #\h #\e #\l #\l #\o) 3)))

(test-equal "textual-take-right"
  "llo"
  (textual->string (textual-take-right (text #\h #\e #\l #\l #\o) 3)))

(test-equal "textual-drop-right"
  "he"
  (textual->string (textual-drop-right (text #\h #\e #\l #\l #\o) 3)))

(test-equal "textual-pad shorter"
  "  abc"
  (textual->string (textual-pad (text #\a #\b #\c) 5)))

(test-equal "textual-pad longer"
  "bc"
  (textual->string (textual-pad (text #\a #\b #\c) 2)))

(test-equal "textual-pad-right shorter"
  "abc  "
  (textual->string (textual-pad-right (text #\a #\b #\c) 5)))

(test-equal "textual-pad-right longer"
  "ab"
  (textual->string (textual-pad-right (text #\a #\b #\c) 2)))

(test-equal "textual-trim"
  "hello  "
  (textual->string (textual-trim (text #\space #\space #\h #\e #\l #\l #\o #\space #\space))))

(test-equal "textual-trim-right"
  "  hello"
  (textual->string (textual-trim-right (text #\space #\space #\h #\e #\l #\l #\o #\space #\space))))

(test-equal "textual-trim-both"
  "hello"
  (textual->string (textual-trim-both (text #\space #\space #\h #\e #\l #\l #\o #\space #\space))))

;;;=========================================================================
;;; Replacement
;;;=========================================================================

(test-equal "textual-replace"
  "abXYZfg"
  (textual->string
   (textual-replace (text #\a #\b #\c #\d #\e #\f #\g)
                    (text #\X #\Y #\Z)
                    2 5)))

;;;=========================================================================
;;; Comparison
;;;=========================================================================

(test-assert "textual=?" (textual=? (text #\a #\b #\c) (text #\a #\b #\c)))
(test-assert "textual=? fail" (not (textual=? (text #\a #\b #\c) (text #\a #\B #\c))))
(test-assert "textual=? with strings" (textual=? "abc" (text #\a #\b #\c)))

(test-assert "textual<?" (textual<? (text #\a #\b #\c) (text #\a #\b #\d)))
(test-assert "textual<? fail" (not (textual<? (text #\a #\b #\c) (text #\a #\b #\c))))

(test-assert "textual>?" (textual>? (text #\a #\b #\d) (text #\a #\b #\c)))
(test-assert "textual<=?" (textual<=? (text #\a #\b #\c) (text #\a #\b #\c)))
(test-assert "textual>=?" (textual>=? (text #\a #\b #\c) (text #\a #\b #\c)))

(test-assert "textual-ci=?" (textual-ci=? (text #\A #\B #\C) (text #\a #\b #\c)))
(test-assert "textual-ci<?" (textual-ci<? (text #\a #\b #\c) (text #\A #\B #\D)))

;;;=========================================================================
;;; Prefixes & suffixes
;;;=========================================================================

(test-equal "textual-prefix-length"
  3
  (textual-prefix-length (text #\a #\b #\c #\d) (text #\a #\b #\c #\x)))

(test-equal "textual-suffix-length"
  2
  (textual-suffix-length (text #\x #\b #\c) (text #\a #\b #\c)))

(test-assert "textual-prefix?"
  (textual-prefix? (text #\a #\b) (text #\a #\b #\c #\d)))
(test-assert "textual-prefix? fail"
  (not (textual-prefix? (text #\a #\x) (text #\a #\b #\c #\d))))

(test-assert "textual-suffix?"
  (textual-suffix? (text #\c #\d) (text #\a #\b #\c #\d)))
(test-assert "textual-suffix? fail"
  (not (textual-suffix? (text #\c #\x) (text #\a #\b #\c #\d))))

;;;=========================================================================
;;; Searching
;;;=========================================================================

(test-equal "textual-index"
  2
  (textual-index (text #\a #\b #\1 #\c) char-numeric?))

(test-equal "textual-index not found"
  #f
  (textual-index (text #\a #\b #\c) char-numeric?))

(test-equal "textual-index-right"
  3
  (textual-index-right (text #\a #\1 #\b #\2) char-numeric?))

(test-equal "textual-skip"
  2
  (textual-skip (text #\a #\b #\1 #\c) char-alphabetic?))

(test-equal "textual-skip-right"
  3
  (textual-skip-right (text #\a #\b #\1 #\2) char-alphabetic?))

(test-equal "textual-contains"
  2
  (textual-contains (text #\a #\b #\c #\d #\e) (text #\c #\d)))

(test-equal "textual-contains not found"
  #f
  (textual-contains (text #\a #\b #\c) (text #\x #\y)))

(test-equal "textual-contains empty pattern"
  0
  (textual-contains (text #\a #\b #\c) (text)))

(test-equal "textual-contains-right"
  3
  (textual-contains-right (text #\a #\b #\c #\a #\b) (text #\a #\b)))

;;;=========================================================================
;;; Case conversion
;;;=========================================================================

(test-equal "textual-upcase"
  "HELLO"
  (textual->string (textual-upcase (text #\h #\e #\l #\l #\o))))

(test-equal "textual-downcase"
  "hello"
  (textual->string (textual-downcase (text #\H #\E #\L #\L #\O))))

(test-equal "textual-foldcase"
  "hello"
  (textual->string (textual-foldcase (text #\H #\e #\L #\l #\O))))

(test-equal "textual-titlecase"
  "Hello World"
  (textual->string (textual-titlecase (text #\h #\e #\l #\l #\o #\space #\w #\o #\r #\l #\d))))

;;;=========================================================================
;;; Concatenation
;;;=========================================================================

(test-equal "textual-append"
  "abcdef"
  (textual->string (textual-append (text #\a #\b #\c) (text #\d #\e #\f))))

(test-equal "textual-append with strings"
  "abcdef"
  (textual->string (textual-append "abc" (text #\d #\e #\f))))

(test-equal "textual-concatenate"
  "abcdef"
  (textual->string
   (textual-concatenate (list (text #\a #\b) (text #\c #\d) (text #\e #\f)))))

(test-equal "textual-concatenate-reverse"
  "cdefab"
  (textual->string
   (textual-concatenate-reverse (list (text #\a #\b) (text #\c #\d #\e #\f)))))

(test-equal "textual-join infix"
  "a-b-c"
  (textual->string
   (textual-join (list (text #\a) (text #\b) (text #\c))
                 (text #\-))))

(test-equal "textual-join prefix"
  "-a-b-c"
  (textual->string
   (textual-join (list (text #\a) (text #\b) (text #\c))
                 (text #\-)
                 'prefix)))

(test-equal "textual-join suffix"
  "a-b-c-"
  (textual->string
   (textual-join (list (text #\a) (text #\b) (text #\c))
                 (text #\-)
                 'suffix)))

;;;=========================================================================
;;; Fold & map
;;;=========================================================================

(test-equal "textual-fold"
  '(#\c #\b #\a)
  (textual-fold cons '() (text #\a #\b #\c)))

(test-equal "textual-fold-right"
  '(#\a #\b #\c)
  (textual-fold-right cons '() (text #\a #\b #\c)))

(test-equal "textual-map"
  "ABC"
  (textual->string (textual-map char-upcase (text #\a #\b #\c))))

(let ((result '()))
  (textual-for-each (lambda (c) (set! result (cons c result)))
                    (text #\a #\b #\c))
  (test-equal "textual-for-each"
    '(#\c #\b #\a)
    result))

(test-equal "textual-map-index"
  "012"
  (textual->string
   (textual-map-index (lambda (i) (integer->char (+ i 48)))
                      (text #\a #\b #\c))))

(test-equal "textual-count"
  2
  (textual-count (text #\a #\1 #\b #\2) char-numeric?))

(test-equal "textual-filter"
  "abc"
  (textual->string (textual-filter char-alphabetic? (text #\a #\1 #\b #\2 #\c))))

(test-equal "textual-remove"
  "12"
  (textual->string (textual-remove char-alphabetic? (text #\a #\1 #\b #\2 #\c))))

;;;=========================================================================
;;; Replication & splitting
;;;=========================================================================

(test-equal "textual-replicate"
  "cdeab"
  (textual->string (textual-replicate (text #\a #\b #\c #\d #\e) 2 7)))

(let ((result (textual-split (text #\a #\space #\b #\space #\c)
                             (text #\space))))
  (test-equal "textual-split count" 3 (length result))
  (test-equal "textual-split 0" "a" (textual->string (car result)))
  (test-equal "textual-split 1" "b" (textual->string (cadr result)))
  (test-equal "textual-split 2" "c" (textual->string (caddr result))))

(test-equal "textual-split empty delimiter"
  3
  (length (textual-split (text #\a #\b #\c) (text))))

;;;=========================================================================
;;; End
;;;=========================================================================

(let ((runner (test-runner-current)))
  (test-end "srfi-135")
  (when (> (test-runner-fail-count runner) 0)
    (exit 1)))
