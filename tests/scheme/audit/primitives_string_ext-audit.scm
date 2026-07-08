;; Audit tests for src/primitives_string_ext.zig — SRFI-13 string library.
;; Audit campaign Phase 2.2 (#1137). Complements tests/scheme/srfi/srfi13-*.scm.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme char) (scheme write) (srfi 13))
(import (chibi test))

(test-begin "primitives_string_ext audit")

;;; --- string-contains ---
(test 3 (string-contains "eek la bonza" " la"))
(test #f (string-contains "abc" "xyz"))
(test 2 (string-contains "abc" "" 2))      ; empty needle => start1
(test 0 (string-contains "" ""))
(test 3 (string-contains "ab\x3BB;\x3BB;x" "\x3BB;x")) ; codepoint index, not byte
(test 1 (string-contains "abc" "xbcx" 0 3 1 3))

;;; --- string-prefix? / string-suffix? (full 6-arg forms work) ---
(test #t (string-prefix? "ab" "abcd"))
(test #f (string-prefix? "b" "abcd"))
(test #t (string-suffix? "cd" "abcd"))
(test #t (string-prefix? "bc" "abcd" 0 2 1 4))
(test #t (string-prefix? "" "anything"))

;;; --- string-trim family ---
(test "x  " (string-trim "  x  " #\space))  ; string-trim is LEFT-only
(test "x  " (string-trim "  x  "))
(test "  x" (string-trim-right "  x  "))
(test "x" (string-trim-both "  x  "))
(test "a" (string-trim-both "xxaxx" #\x))
(test "" (string-trim-both "   "))
(test "x" (string-trim-both "\x0B;\x0C;x\x0B;\x0C;")) ; VT/FF in default set (#826 fix)
;; FAIL: #826 (default criterion misses Unicode whitespace; byte-based)
;; (test "x" (string-trim-both "\x00A0;x\x00A0;"))

;;; --- string-index / -right / skip / count ---
(test 1 (string-index "abc" #\b))
(test #f (string-index "abc" #\z))
(test 4 (string-index-right "abcabc" #\b))
(test 2 (string-skip "  ab" #\space))
(test 3 (string-count "banana" #\a))
(test 1 (string-index "a\x3BB;c" #\x3BB))   ; codepoint criterion + index
(test 2 (string-index "ab1de" char-numeric? 1 4)) ; range-restricted search
(test 0 (string-count "" #\a))

;;; --- string-split / join / concatenate ---
(test '("a" "b" "" "c") (string-split "a,b,,c" ","))
(test '("") (string-split "" ","))
(test "x y" (string-join '("x" "y")))       ; default delimiter is one space
(test "a:b" (string-join '("a" "b") ":"))
(test "" (string-join '()))
(test "abcd" (string-concatenate '("ab" "cd")))
(test "" (string-concatenate '()))
(test "a:b:" (string-join '("a" "b") ":" 'suffix))
(test ":a:b" (string-join '("a" "b") ":" 'prefix))
(test #t (guard (e (#t #t)) (string-join '() ":" 'strict-infix) #f))

;;; --- take / drop (+ right variants), bounds ---
(test "ab" (string-take "abcd" 2))
(test "cd" (string-drop "abcd" 2))
(test "cd" (string-take-right "abcd" 2))
(test "ab" (string-drop-right "abcd" 2))
(test "\x3B1;\x3B2;" (string-take "\x3B1;\x3B2;\x3B3;\x3B4;" 2)) ; codepoints
(test "" (string-take "abc" 0))
(test "abc" (string-take "abc" 3))
(test #t (guard (e (#t #t)) (string-take "ab" 5)))
(test #t (guard (e (#t #t)) (string-drop "ab" 5)))
(test #t (guard (e (#t #t)) (string-take "ab" -1)))

;;; --- pad / pad-right ---
(test "  x" (string-pad "x" 3))
(test "x  " (string-pad-right "x" 3))
(test "345" (string-pad "12345" 3))          ; truncates from the LEFT
(test "123" (string-pad-right "12345" 3))    ; truncates from the right
(test "**x" (string-pad "x" 3 #\*))
(test "\x3BB;\x3BB;x" (string-pad "x" 3 #\x3BB)) ; multibyte pad char
(test "" (string-pad "abc" 0))
;; FAIL: #1159 (non-char pad argument silently ignored)
;; (test #t (guard (e (#t #t)) (string-pad "x" 5 "*") #f))

;;; --- reverse / filter / delete / replace / titlecase ---
(test "cba" (string-reverse "abc"))
(test "b\x3BB;a" (string-reverse "a\x3BB;b")) ; codepoint-wise reversal
(test "" (string-reverse ""))
(test "ab" (string-filter char-alphabetic? "a1b2"))  ; criterion FIRST
(test "12" (string-delete char-alphabetic? "a1b2"))
(test "heo" (string-delete #\l "hello"))
(test "aXYd" (string-replace "abcd" "XY" 1 3))
(test "abcd" (string-replace "abcd" "" 2 2))
(test "Hello World" (string-titlecase "hello wORLD"))
(test "aYd" (string-replace "abcd" "XYZ" 1 3 1 2))

;;; --- every / any (return values per SRFI-13) ---
(test #t (string-every char-alphabetic? "abc"))
(test #f (string-every char-alphabetic? "ab1"))
(test #t (string-every char-alphabetic? ""))     ; vacuous truth
(test 3 (string-every (lambda (c) (digit-value c)) "123")) ; last value
(test 3 (string-any (lambda (c) (and (char-numeric? c) (digit-value c))) "ab3c"))
(test #f (string-any char-numeric? "abc"))
(test #f (string-any char-numeric? ""))
(test #t (string-every #\a "aaa"))               ; char criterion
(test #t (string-any #\b "abc"))

;;; --- tabulate / unfold / unfold-right ---
(test "abc" (string-tabulate (lambda (i) (integer->char (+ 97 i))) 3))
(test "" (string-tabulate (lambda (i) #\x) 0))
(test #t (guard (e (#t #t)) (string-tabulate (lambda (i) 42) 1))) ; non-char result
(test "abc" (string-unfold (lambda (s) (> s 2))
                           (lambda (s) (integer->char (+ 97 s)))
                           (lambda (s) (+ s 1)) 0))
(test "B:abc:F" (string-unfold (lambda (s) (> s 2))
                               (lambda (s) (integer->char (+ 97 s)))
                               (lambda (s) (+ s 1)) 0
                               "B:" (lambda (s) ":F")))
;; unfold-right: make-final is the LEFT prefix, base is the RIGHT suffix
(test ":FcbaB:" (string-unfold-right (lambda (s) (> s 2))
                                     (lambda (s) (integer->char (+ 97 s)))
                                     (lambda (s) (+ s 1)) 0
                                     "B:" (lambda (s) ":F")))
;; error propagation from callbacks
(test 'caught (guard (e (#t 'caught))
  (string-unfold (lambda (s) (error "stop")) (lambda (s) #\a) (lambda (s) s) 0)))
(test 'caught (guard (e (#t 'caught))
  (string-tabulate (lambda (i) (error "cb")) 2)))
(test 'caught (guard (e (#t 'caught))
  (string-every (lambda (c) (error "cb")) "abc")))
;; FAIL: #1159 (non-string base silently ignored)
;; (test #t (guard (e (#t #t))
;;   (string-unfold (lambda (s) (> s 2)) (lambda (s) #\a) (lambda (s) (+ s 1)) 0 #\Z)
;;   #f))

;;; --- type errors are catchable, not crashes ---
(test #t (guard (e (#t #t)) (string-contains 42 "x")))
(test #t (guard (e (#t #t)) (string-take 42 1)))
(test #t (guard (e (#t #t)) (string-join '("a" 5))))
(test #t (guard (e (#t #t)) (string-join 42)))
(test #t (guard (e (#t #t)) (string-concatenate '(42))))
(test #t (guard (e (#t #t)) (string-split 42 ",")))
(test #t (guard (e (#t #t)) (string-reverse 42)))
(test #t (guard (e (#t #t)) (string-pad "x" "y")))

(test-end "primitives_string_ext audit")
