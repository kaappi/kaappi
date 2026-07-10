;; SRFI-152 (string library reduced) conformance tests
;; Run: zig build run -- tests/scheme/srfi/srfi152.scm

(import (scheme base) (srfi 152) (scheme process-context) (srfi 64))

(test-begin "srfi-152")

;;; --- predicates ---
(test-equal #t (string-null? ""))
(test-equal #f (string-null? "a"))
(test-equal #f (string-null? " "))

(test-equal #t (string-every char-alphabetic? "abc"))
(test-equal #f (string-every char-alphabetic? "a1c"))
(test-equal #t (string-every char-alphabetic? ""))
(test-equal 99 (string-every (lambda (c) (char->integer c)) "abc"))
(test-equal #t (string-every char-numeric? "ab12" 2))

(test-equal #t (string-any char-numeric? "a1c"))
(test-equal #f (string-any char-numeric? "abc"))
(test-equal #f (string-any char-numeric? ""))
(test-equal 98 (string-any (lambda (c) (and (char=? c #\b) (char->integer c))) "abc"))
(test-equal #t (string-any char-numeric? "ab1c" 2 3))

;;; --- constructors ---
(test-equal "aaa" (string-tabulate (lambda (i) #\a) 3))
(test-equal "abc" (string-tabulate (lambda (i) (integer->char (+ 97 i))) 3))
(test-equal "" (string-tabulate (lambda (i) #\a) 0))

;;; --- conversion ---
(test-equal #(#\a #\b #\c) (string->vector "abc"))
(test-equal "abc" (vector->string #(#\a #\b #\c)))
(test-equal "cba" (reverse-list->string '(#\a #\b #\c)))
(test-equal "" (reverse-list->string '()))

;;; --- selection ---
(test-equal "he" (string-take "hello" 2))
(test-equal "" (string-take "hello" 0))
(test-equal "llo" (string-drop "hello" 2))
(test-equal "lo" (string-take-right "hello" 2))
(test-equal "hel" (string-drop-right "hello" 2))

(test-equal "  abc" (string-pad "abc" 5))
(test-equal "bc" (string-pad "abc" 2))
(test-equal "xxabc" (string-pad "abc" 5 #\x))
(test-equal "abc  " (string-pad-right "abc" 5))
(test-equal "ab" (string-pad-right "abc" 2))

(test-equal "ab  " (string-trim "  ab  "))
(test-equal "  ab" (string-trim-right "  ab  "))
(test-equal "ab" (string-trim-both "  ab  "))
(test-equal "" (string-trim "   "))
(test-equal "bc" (string-trim "aabc" (lambda (c) (char=? c #\a))))

;;; --- replacement ---
(test-equal "hXYZo" (string-replace "hello" "XYZ" 1 4))
(test-equal "hello" (string-replace "hllo" "e" 1 1))

;;; --- comparison ---
(test-equal #t (string-ci=? "ABC" "abc"))
(test-equal #f (string-ci=? "ABC" "abd"))
(test-equal #t (string-ci<? "abc" "ABD"))
(test-equal #t (string-ci>? "abd" "ABC"))
(test-equal #t (string-ci<=? "abc" "ABC"))
(test-equal #t (string-ci>=? "abc" "ABC"))

;;; --- prefix/suffix length ---
(test-equal 3 (string-prefix-length "abcdef" "abcxyz"))
(test-equal 0 (string-prefix-length "xyz" "abc"))
(test-equal 0 (string-prefix-length "" "abc"))
(test-equal 3 (string-prefix-length "abc" "abc"))
(test-equal 3 (string-prefix-length "xxabcdef" "abcxyz" 2 5 0 3))
(test-equal 2 (string-suffix-length "xyzbc" "abc"))
(test-equal 0 (string-suffix-length "xyz" "abc"))
(test-equal 0 (string-suffix-length "" "abc"))
(test-equal 3 (string-suffix-length "xxabc" "yyabc" 2 5 2 5))

;;; --- searching ---
(test-equal 2 (string-contains "hello" "ll"))
(test-equal #f (string-contains "hello" "xyz"))
(test-equal 0 (string-contains "hello" ""))
(test-equal #t (string-prefix? "he" "hello"))
(test-equal #f (string-prefix? "lo" "hello"))
(test-equal #t (string-prefix? "" "hello"))
(test-equal #t (string-suffix? "lo" "hello"))
(test-equal #f (string-suffix? "he" "hello"))

(test-equal 1 (string-index "hello" (lambda (c) (char=? c #\e))))
(test-equal #f (string-index "hello" (lambda (c) (char=? c #\z))))
(test-equal 3 (string-index "hello" (lambda (c) (char=? c #\l)) 3))
(test-equal 3 (string-index-right "hello" (lambda (c) (char=? c #\l))))
(test-equal 2 (string-skip "  x" char-whitespace?))
(test-equal 1 (string-skip-right "xy  " char-whitespace?))
(test-equal 2 (string-count "hello" (lambda (c) (char=? c #\l))))
(test-equal 0 (string-count "" char-alphabetic?))

(test-equal 3 (string-contains-right "abcabc" "abc"))
(test-equal #f (string-contains-right "hello" "xyz"))
(test-equal 5 (string-contains-right "hello" ""))
(test-equal 5 (string-contains-right "xxabcabcyy" "abc" 2 8))

;;; --- take-while / drop-while ---
(test-equal "abc" (string-take-while "abc def" char-alphabetic?))
(test-equal "" (string-take-while " abc" char-alphabetic?))
(test-equal "abc" (string-take-while "abc" char-alphabetic?))
(test-equal "bc" (string-take-while "abc def" char-alphabetic? 1 5))
(test-equal "ef" (string-take-while-right "abc ef" char-alphabetic?))
(test-equal "" (string-take-while-right "abc " char-alphabetic?))

(test-equal "c def" (string-drop-while "abc def" (lambda (c) (char<=? c #\b))))
(test-equal " abc" (string-drop-while " abc" char-alphabetic?))
(test-equal "" (string-drop-while "abc" char-alphabetic?))
(test-equal " d" (string-drop-while "abc def" char-alphabetic? 2 5))
(test-equal "abc " (string-drop-while-right "abc ef" char-alphabetic?))

;;; --- break / span ---
(test-equal (list "abc" " def")
  (call-with-values (lambda () (string-break "abc def" char-whitespace?)) list))
(test-equal (list "hello" "")
  (call-with-values (lambda () (string-break "hello" char-whitespace?)) list))
(test-equal (list "" " abc")
  (call-with-values (lambda () (string-break " abc" char-whitespace?)) list))

(test-equal (list "abc" " def")
  (call-with-values (lambda () (string-span "abc def" char-alphabetic?)) list))
(test-equal (list "" " abc")
  (call-with-values (lambda () (string-span " abc" char-alphabetic?)) list))
(test-equal (list "hello" "")
  (call-with-values (lambda () (string-span "hello" char-alphabetic?)) list))

;; break/span with start/end
(test-equal (list "bc" " d")
  (call-with-values (lambda () (string-span "abc def" char-alphabetic? 1 5)) list))

;;; --- concatenation ---
(test-equal "a,b,c" (string-join '("a" "b" "c") ","))
(test-equal "abc" (string-join '("abc")))
(test-equal "" (string-join '()))
(test-equal "a b" (string-join '("a" "b")))
(test-equal "abcdef" (string-concatenate '("ab" "cd" "ef")))
(test-equal "" (string-concatenate '()))

(test-equal "cba" (string-concatenate-reverse '("a" "b" "c")))
(test-equal "" (string-concatenate-reverse '()))
(test-equal "cbad" (string-concatenate-reverse '("a" "b" "c") "d"))
(test-equal "bade" (string-concatenate-reverse '("a" "b") "def" 2))

;;; --- fold ---
(test-equal '(#\c #\b #\a)
  (string-fold cons '() "abc"))
(test-equal '(#\a #\b #\c)
  (string-fold-right cons '() "abc"))
(test-equal 3 (string-fold (lambda (c n) (+ n 1)) 0 "abc"))
(test-equal '(#\c #\b)
  (string-fold cons '() "abc" 1))
(test-equal '(#\b)
  (string-fold-right cons '() "abc" 1 2))

;;; --- filter / remove ---
(test-equal "aeiou"
  (string-filter char-alphabetic? "a1e2i3o4u5"))
(test-equal "12345"
  (string-remove char-alphabetic? "a1e2i3o4u5"))
(test-equal "" (string-filter char-numeric? "abc"))
(test-equal "" (string-remove char-alphabetic? "abc"))

;;; --- replicate ---
(test-equal "bcab" (string-replicate "abc" 1 5))
(test-equal "abcab" (string-replicate "abc" 0 5))
(test-equal "cab" (string-replicate "abc" -1 2))
(test-equal "cd" (string-replicate "abcde" 1 3 1 4))

;;; --- segment ---
(test-equal '("ab" "cd" "ef") (string-segment "abcdef" 2))
(test-equal '("ab" "cd" "e") (string-segment "abcde" 2))
(test-equal '("abc") (string-segment "abc" 5))
(test-equal '() (string-segment "" 3))

;;; --- splitting ---
(test-equal '("a" "b" "c") (string-split "a,b,c" ","))
(test-equal '("a" "" "b") (string-split "a,,b" ","))
(test-equal '("ab") (string-split "ab" ","))
(test-equal '("a" "b") (string-split "a--b" "--"))
(test-equal '() (string-split "" ","))

;; grammar variants
(test-equal '("a" "b" "c") (string-split "a,b,c" "," 'infix))
(test-equal '("a" "b" "c") (string-split ",a,b,c" "," 'prefix))
(test-equal '("a" "b" "c") (string-split "a,b,c," "," 'suffix))
(test-equal '("" "a" "b" "c") (string-split ",a,b,c" "," 'infix))
(test-equal '("a" "b" "c" "") (string-split "a,b,c," "," 'infix))

;; limit
(test-equal '("a" "b,c") (string-split "a,b,c" "," 'infix 1))
(test-equal '("a" "b" "c") (string-split "a,b,c" "," 'infix 5))

;;; --- start/end ranges ---
(test-equal 1 (string-count "ab1c" char-numeric? 1 3))

;;; --- multibyte safety ---
(test-equal 2 (string-contains "aλb" "b"))
(test-equal "λ" (string-take (string-drop "aλb" 1) 1))

;;; --- I/O re-exports ---
(test-equal "hel" (let ((p (open-input-string "hello")))
                    (read-string 3 p)))
(test-assert (let ((p (open-output-string)))
               (write-string "hello" p)
               (string=? "hello" (get-output-string p))))

(let ((runner (test-runner-current)))
  (test-end "srfi-152")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
