;; Audit tests for src/primitives_string_ext.zig — SRFI-13 string library.
;; Audit campaign Phase 2.2 (#1137). Complements tests/scheme/srfi/srfi13-*.scm.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme char) (scheme write) (srfi 13))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_string_ext audit")

;;; --- string-contains ---
(test-equal 3 (string-contains "eek la bonza" " la"))
(test-equal #f (string-contains "abc" "xyz"))
(test-equal 2 (string-contains "abc" "" 2))      ; empty needle => start1
(test-equal 0 (string-contains "" ""))
(test-equal 3 (string-contains "ab\x3BB;\x3BB;x" "\x3BB;x")) ; codepoint index, not byte
(test-equal 1 (string-contains "abc" "xbcx" 0 3 1 3))

;;; --- string-prefix? / string-suffix? (full 6-arg forms work) ---
(test-equal #t (string-prefix? "ab" "abcd"))
(test-equal #f (string-prefix? "b" "abcd"))
(test-equal #t (string-suffix? "cd" "abcd"))
(test-equal #t (string-prefix? "bc" "abcd" 0 2 1 4))
(test-equal #t (string-prefix? "" "anything"))

;;; --- string-trim family ---
(test-equal "x  " (string-trim "  x  " #\space))  ; string-trim is LEFT-only
(test-equal "x  " (string-trim "  x  "))
(test-equal "  x" (string-trim-right "  x  "))
(test-equal "x" (string-trim-both "  x  "))
(test-equal "a" (string-trim-both "xxaxx" #\x))
(test-equal "" (string-trim-both "   "))
(test-equal "x" (string-trim-both "\x0B;\x0C;x\x0B;\x0C;")) ; VT/FF in default set (#826 fix)
(test-equal "x" (string-trim-both "\x00A0;x\x00A0;")) ; Unicode whitespace (#826 fix)

;;; --- string-index / -right / skip / count ---
(test-equal 1 (string-index "abc" #\b))
(test-equal #f (string-index "abc" #\z))
(test-equal 4 (string-index-right "abcabc" #\b))
(test-equal 2 (string-skip "  ab" #\space))
(test-equal 3 (string-count "banana" #\a))
(test-equal 1 (string-index "a\x3BB;c" #\x3BB))   ; codepoint criterion + index
(test-equal 2 (string-index "ab1de" char-numeric? 1 4)) ; range-restricted search
(test-equal 0 (string-count "" #\a))

;;; --- string-split / join / concatenate ---
(test-equal '("a" "b" "" "c") (string-split "a,b,,c" ","))
(test-equal '("") (string-split "" ","))
(test-equal "x y" (string-join '("x" "y")))       ; default delimiter is one space
(test-equal "a:b" (string-join '("a" "b") ":"))
(test-equal "" (string-join '()))
(test-equal "abcd" (string-concatenate '("ab" "cd")))
(test-equal "" (string-concatenate '()))
(test-equal "a:b:" (string-join '("a" "b") ":" 'suffix))
(test-equal ":a:b" (string-join '("a" "b") ":" 'prefix))
(test-equal #t (guard (e (#t #t)) (string-join '() ":" 'strict-infix) #f))

;;; --- take / drop (+ right variants), bounds ---
(test-equal "ab" (string-take "abcd" 2))
(test-equal "cd" (string-drop "abcd" 2))
(test-equal "cd" (string-take-right "abcd" 2))
(test-equal "ab" (string-drop-right "abcd" 2))
(test-equal "\x3B1;\x3B2;" (string-take "\x3B1;\x3B2;\x3B3;\x3B4;" 2)) ; codepoints
(test-equal "" (string-take "abc" 0))
(test-equal "abc" (string-take "abc" 3))
(test-equal #t (guard (e (#t #t)) (string-take "ab" 5)))
(test-equal #t (guard (e (#t #t)) (string-drop "ab" 5)))
(test-equal #t (guard (e (#t #t)) (string-take "ab" -1)))

;;; --- pad / pad-right ---
(test-equal "  x" (string-pad "x" 3))
(test-equal "x  " (string-pad-right "x" 3))
(test-equal "345" (string-pad "12345" 3))          ; truncates from the LEFT
(test-equal "123" (string-pad-right "12345" 3))    ; truncates from the right
(test-equal "**x" (string-pad "x" 3 #\*))
(test-equal "\x3BB;\x3BB;x" (string-pad "x" 3 #\x3BB)) ; multibyte pad char
(test-equal "" (string-pad "abc" 0))
(test-equal #t (guard (e (#t #t)) (string-pad "x" 5 "*") #f))
(test-equal #t (guard (e (#t #t)) (string-pad-right "x" 5 "*") #f))

;;; --- reverse / filter / delete / replace / titlecase ---
(test-equal "cba" (string-reverse "abc"))
(test-equal "b\x3BB;a" (string-reverse "a\x3BB;b")) ; codepoint-wise reversal
(test-equal "" (string-reverse ""))
(test-equal "ab" (string-filter char-alphabetic? "a1b2"))  ; criterion FIRST
(test-equal "12" (string-delete char-alphabetic? "a1b2"))
(test-equal "heo" (string-delete #\l "hello"))
(test-equal "aXYd" (string-replace "abcd" "XY" 1 3))
(test-equal "abcd" (string-replace "abcd" "" 2 2))
(test-equal "Hello World" (string-titlecase "hello wORLD"))
(test-equal "aYd" (string-replace "abcd" "XYZ" 1 3 1 2))

;;; --- every / any (return values per SRFI-13) ---
(test-equal #t (string-every char-alphabetic? "abc"))
(test-equal #f (string-every char-alphabetic? "ab1"))
(test-equal #t (string-every char-alphabetic? ""))     ; vacuous truth
(test-equal 3 (string-every (lambda (c) (digit-value c)) "123")) ; last value
(test-equal 3 (string-any (lambda (c) (and (char-numeric? c) (digit-value c))) "ab3c"))
(test-equal #f (string-any char-numeric? "abc"))
(test-equal #f (string-any char-numeric? ""))
(test-equal #t (string-every #\a "aaa"))               ; char criterion
(test-equal #t (string-any #\b "abc"))

;;; --- tabulate / unfold / unfold-right ---
(test-equal "abc" (string-tabulate (lambda (i) (integer->char (+ 97 i))) 3))
(test-equal "" (string-tabulate (lambda (i) #\x) 0))
(test-equal #t (guard (e (#t #t)) (string-tabulate (lambda (i) 42) 1))) ; non-char result
(test-equal "abc" (string-unfold (lambda (s) (> s 2))
                                 (lambda (s) (integer->char (+ 97 s)))
                                 (lambda (s) (+ s 1)) 0))
(test-equal "B:abc:F" (string-unfold (lambda (s) (> s 2))
                                     (lambda (s) (integer->char (+ 97 s)))
                                     (lambda (s) (+ s 1)) 0
                                     "B:" (lambda (s) ":F")))
;; unfold-right: make-final is the LEFT prefix, base is the RIGHT suffix
(test-equal ":FcbaB:" (string-unfold-right (lambda (s) (> s 2))
                                           (lambda (s) (integer->char (+ 97 s)))
                                           (lambda (s) (+ s 1)) 0
                                           "B:" (lambda (s) ":F")))
;; error propagation from callbacks
(test-equal 'caught (guard (e (#t 'caught))
  (string-unfold (lambda (s) (error "stop")) (lambda (s) #\a) (lambda (s) s) 0)))
(test-equal 'caught (guard (e (#t 'caught))
  (string-tabulate (lambda (i) (error "cb")) 2)))
(test-equal 'caught (guard (e (#t 'caught))
  (string-every (lambda (c) (error "cb")) "abc")))
(test-equal #t (guard (e (#t #t))
  (string-unfold (lambda (s) (> s 2)) (lambda (s) #\a) (lambda (s) (+ s 1)) 0 #\Z)
  #f))
(test-equal #t (guard (e (#t #t))
  (string-unfold-right (lambda (s) (> s 2)) (lambda (s) #\a) (lambda (s) (+ s 1)) 0 #\Z)
  #f))
(test-equal #t (guard (e (#t #t))
  (string-unfold (lambda (s) #t) (lambda (s) #\a) (lambda (s) s) 0
                 "" (lambda (s) 42))
  #f))
(test-equal #t (guard (e (#t #t))
  (string-unfold-right (lambda (s) #t) (lambda (s) #\a) (lambda (s) s) 0
                       "" (lambda (s) 42))
  #f))

;;; --- type errors are catchable, not crashes ---
(test-equal #t (guard (e (#t #t)) (string-contains 42 "x")))
(test-equal #t (guard (e (#t #t)) (string-take 42 1)))
(test-equal #t (guard (e (#t #t)) (string-join '("a" 5))))
(test-equal #t (guard (e (#t #t)) (string-join 42)))
(test-equal #t (guard (e (#t #t)) (string-concatenate '(42))))
(test-equal #t (guard (e (#t #t)) (string-split 42 ",")))
(test-equal #t (guard (e (#t #t)) (string-reverse 42)))
(test-equal #t (guard (e (#t #t)) (string-pad "x" "y")))

(let ((runner (test-runner-current)))
  (test-end "primitives_string_ext audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
