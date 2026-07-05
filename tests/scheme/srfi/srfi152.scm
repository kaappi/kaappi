;; SRFI-152 (string library reduced) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi152.scm

(import (scheme base) (srfi 152) (chibi test))

(test-begin "srfi-152")

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

;;; --- modification ---
(test "hXYZo" (string-replace "hello" "XYZ" 1 4))
(test "hello" (string-replace "hllo" "e" 1 1))

;;; --- splitting and joining ---
(test '("a" "b" "c") (string-split "a,b,c" ","))
(test '("a" "" "b") (string-split "a,,b" ","))
(test '("ab") (string-split "ab" ","))
(test '("a" "b") (string-split "a--b" "--"))
(test "a,b,c" (string-join '("a" "b" "c") ","))
(test "abc" (string-join '("abc")))
(test "" (string-join '()))
(test "a b" (string-join '("a" "b")))
(test "abcdef" (string-concatenate '("ab" "cd" "ef")))
(test "" (string-concatenate '()))

;;; --- tabulate / every / any ---
(test "aaa" (string-tabulate (lambda (i) #\a) 3))
(test "abc" (string-tabulate (lambda (i) (integer->char (+ 97 i))) 3))
(test "" (string-tabulate (lambda (i) #\a) 0))

(test #t (string-every char-alphabetic? "abc"))
(test #f (string-every char-alphabetic? "a1c"))
(test #t (string-every char-alphabetic? ""))
(test #t (string-any char-numeric? "a1c"))
(test #f (string-any char-numeric? "abc"))
(test #f (string-any char-numeric? ""))
;; SRFI-152: string-any returns the actual predicate value
(test 98 (string-any (lambda (c) (and (char=? c #\b) (char->integer c))) "abc"))
;; SRFI-152: string-every returns the LAST predicate value when all true
;; FAIL: #1234 (string-every collapses the final predicate value to #t)
;; (test 99 (string-every (lambda (c) (char->integer c)) "abc"))

;;; --- start/end ranges ---
(test #t (string-every char-numeric? "ab12" 2))
(test #t (string-any char-numeric? "ab1c" 2 3))
(test 1 (string-count "ab1c" char-numeric? 1 3))

;;; --- multibyte safety ---
(test 2 (string-contains "aλb" "b"))
(test "λ" (string-take (string-drop "aλb" 1) 1))

;;; --- string-split infix grammar: empty string gives the empty list ---
;; FAIL: #1234 (string-split "" returns ("") instead of ())
;; (test '() (string-split "" ","))

;;; --- missing exports ---
;; FAIL: #1234 (string-null?, string-fold, string-fold-right,
;;   string-unfold, string-unfold-right, reverse-list->string,
;;   string-prefix-length, string-suffix-length, string-contains-right,
;;   string-take-while (+right), string-drop-while (+right), string-break,
;;   string-span, string-concatenate-reverse, string-remove, string-filter,
;;   string-replicate, string-segment, string-ci comparisons, read-string,
;;   write-string, string->vector, vector->string not exported;
;;   string-split lacks grammar/limit arguments)
;; (test #t (string-null? ""))
;; (test '("ab" "cd") (string-segment "abcd" 2))
;; (test "cba" (string-fold string-append-char-reversed "" "abc"))

(test-end "srfi-152")
