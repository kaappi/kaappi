;; SRFI-152 (string library reduced) conformance tests
;; Run: zig build run -- tests/scheme/srfi/srfi152.scm

(import (scheme base) (srfi 152) (chibi test))

(test-begin "srfi-152")

;;; --- predicates ---
(test #t (string-null? ""))
(test #f (string-null? "a"))
(test #f (string-null? " "))

(test #t (string-every char-alphabetic? "abc"))
(test #f (string-every char-alphabetic? "a1c"))
(test #t (string-every char-alphabetic? ""))
(test 99 (string-every (lambda (c) (char->integer c)) "abc"))
(test #t (string-every char-numeric? "ab12" 2))

(test #t (string-any char-numeric? "a1c"))
(test #f (string-any char-numeric? "abc"))
(test #f (string-any char-numeric? ""))
(test 98 (string-any (lambda (c) (and (char=? c #\b) (char->integer c))) "abc"))
(test #t (string-any char-numeric? "ab1c" 2 3))

;;; --- constructors ---
(test "aaa" (string-tabulate (lambda (i) #\a) 3))
(test "abc" (string-tabulate (lambda (i) (integer->char (+ 97 i))) 3))
(test "" (string-tabulate (lambda (i) #\a) 0))

;;; --- conversion ---
(test #(#\a #\b #\c) (string->vector "abc"))
(test "abc" (vector->string #(#\a #\b #\c)))
(test "cba" (reverse-list->string '(#\a #\b #\c)))
(test "" (reverse-list->string '()))

;;; --- selection ---
(test "he" (string-take "hello" 2))
(test "" (string-take "hello" 0))
(test "llo" (string-drop "hello" 2))
(test "lo" (string-take-right "hello" 2))
(test "hel" (string-drop-right "hello" 2))

(test "  abc" (string-pad "abc" 5))
(test "bc" (string-pad "abc" 2))
(test "xxabc" (string-pad "abc" 5 #\x))
(test "abc  " (string-pad-right "abc" 5))
(test "ab" (string-pad-right "abc" 2))

(test "ab  " (string-trim "  ab  "))
(test "  ab" (string-trim-right "  ab  "))
(test "ab" (string-trim-both "  ab  "))
(test "" (string-trim "   "))
(test "bc" (string-trim "aabc" (lambda (c) (char=? c #\a))))

;;; --- replacement ---
(test "hXYZo" (string-replace "hello" "XYZ" 1 4))
(test "hello" (string-replace "hllo" "e" 1 1))

;;; --- comparison ---
(test #t (string-ci=? "ABC" "abc"))
(test #f (string-ci=? "ABC" "abd"))
(test #t (string-ci<? "abc" "ABD"))
(test #t (string-ci>? "abd" "ABC"))
(test #t (string-ci<=? "abc" "ABC"))
(test #t (string-ci>=? "abc" "ABC"))

;;; --- prefix/suffix length ---
(test 3 (string-prefix-length "abcdef" "abcxyz"))
(test 0 (string-prefix-length "xyz" "abc"))
(test 0 (string-prefix-length "" "abc"))
(test 3 (string-prefix-length "abc" "abc"))
(test 2 (string-suffix-length "xyzbc" "abc"))
(test 0 (string-suffix-length "xyz" "abc"))
(test 0 (string-suffix-length "" "abc"))

;;; --- searching ---
(test 2 (string-contains "hello" "ll"))
(test #f (string-contains "hello" "xyz"))
(test 0 (string-contains "hello" ""))
(test #t (string-prefix? "he" "hello"))
(test #f (string-prefix? "lo" "hello"))
(test #t (string-prefix? "" "hello"))
(test #t (string-suffix? "lo" "hello"))
(test #f (string-suffix? "he" "hello"))

(test 1 (string-index "hello" (lambda (c) (char=? c #\e))))
(test #f (string-index "hello" (lambda (c) (char=? c #\z))))
(test 3 (string-index "hello" (lambda (c) (char=? c #\l)) 3))
(test 3 (string-index-right "hello" (lambda (c) (char=? c #\l))))
(test 2 (string-skip "  x" char-whitespace?))
(test 1 (string-skip-right "xy  " char-whitespace?))
(test 2 (string-count "hello" (lambda (c) (char=? c #\l))))
(test 0 (string-count "" char-alphabetic?))

(test 3 (string-contains-right "abcabc" "abc"))
(test #f (string-contains-right "hello" "xyz"))
(test 5 (string-contains-right "hello" ""))

;;; --- take-while / drop-while ---
(test "abc" (string-take-while "abc def" char-alphabetic?))
(test "" (string-take-while " abc" char-alphabetic?))
(test "abc" (string-take-while "abc" char-alphabetic?))
(test "ef" (string-take-while-right "abc ef" char-alphabetic?))
(test "" (string-take-while-right "abc " char-alphabetic?))

(test "c def" (string-drop-while "abc def" (lambda (c) (char<=? c #\b))))
(test " abc" (string-drop-while " abc" char-alphabetic?))
(test "" (string-drop-while "abc" char-alphabetic?))
(test "abc " (string-drop-while-right "abc ef" char-alphabetic?))

;;; --- break / span ---
(test-values (values "abc" " def")
  (string-break "abc def" char-whitespace?))
(test-values (values "hello" "")
  (string-break "hello" char-whitespace?))
(test-values (values "" " abc")
  (string-break " abc" char-whitespace?))

(test-values (values "abc" " def")
  (string-span "abc def" char-alphabetic?))
(test-values (values "" " abc")
  (string-span " abc" char-alphabetic?))
(test-values (values "hello" "")
  (string-span "hello" char-alphabetic?))

;;; --- concatenation ---
(test "a,b,c" (string-join '("a" "b" "c") ","))
(test "abc" (string-join '("abc")))
(test "" (string-join '()))
(test "a b" (string-join '("a" "b")))
(test "abcdef" (string-concatenate '("ab" "cd" "ef")))
(test "" (string-concatenate '()))

(test "cba" (string-concatenate-reverse '("a" "b" "c")))
(test "" (string-concatenate-reverse '()))
(test "cbad" (string-concatenate-reverse '("a" "b" "c") "d"))
(test "bade" (string-concatenate-reverse '("a" "b") "def" 2))

;;; --- fold ---
(test '(#\c #\b #\a)
  (string-fold cons '() "abc"))
(test '(#\a #\b #\c)
  (string-fold-right cons '() "abc"))
(test 3 (string-fold (lambda (c n) (+ n 1)) 0 "abc"))
(test '(#\c #\b)
  (string-fold cons '() "abc" 1))
(test '(#\b)
  (string-fold-right cons '() "abc" 1 2))

;;; --- filter / remove ---
(test "aeiou"
  (string-filter char-alphabetic? "a1e2i3o4u5"))
(test "12345"
  (string-remove char-alphabetic? "a1e2i3o4u5"))
(test "" (string-filter char-numeric? "abc"))
(test "" (string-remove char-alphabetic? "abc"))

;;; --- replicate ---
(test "bcab" (string-replicate "abc" 1 5))
(test "abcab" (string-replicate "abc" 0 5))
(test "cab" (string-replicate "abc" -1 2))
(test "cd" (string-replicate "abcde" 1 3 1 4))

;;; --- segment ---
(test '("ab" "cd" "ef") (string-segment "abcdef" 2))
(test '("ab" "cd" "e") (string-segment "abcde" 2))
(test '("abc") (string-segment "abc" 5))
(test '() (string-segment "" 3))

;;; --- splitting ---
(test '("a" "b" "c") (string-split "a,b,c" ","))
(test '("a" "" "b") (string-split "a,,b" ","))
(test '("ab") (string-split "ab" ","))
(test '("a" "b") (string-split "a--b" "--"))
(test '() (string-split "" ","))

;; grammar variants
(test '("a" "b" "c") (string-split "a,b,c" "," 'infix))
(test '("a" "b" "c") (string-split ",a,b,c" "," 'prefix))
(test '("a" "b" "c") (string-split "a,b,c," "," 'suffix))
(test '("" "a" "b" "c") (string-split ",a,b,c" "," 'infix))
(test '("a" "b" "c" "") (string-split "a,b,c," "," 'infix))

;; limit
(test '("a" "b,c") (string-split "a,b,c" "," 'infix 1))
(test '("a" "b" "c") (string-split "a,b,c" "," 'infix 5))

;;; --- start/end ranges ---
(test 1 (string-count "ab1c" char-numeric? 1 3))

;;; --- multibyte safety ---
(test 2 (string-contains "aλb" "b"))
(test "λ" (string-take (string-drop "aλb" 1) 1))

;;; --- I/O re-exports ---
(test "hel" (let ((p (open-input-string "hello")))
              (read-string 3 p)))
(test-assert (let ((p (open-output-string)))
               (write-string "hello" p)
               (string=? "hello" (get-output-string p))))

(test-end "srfi-152")
