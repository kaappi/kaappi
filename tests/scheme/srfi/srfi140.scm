;; SRFI-140 (Immutable Strings) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi140.scm

(import (scheme base) (scheme process-context) (srfi 140) (srfi 64))

(test-begin "srfi-140")

;;; --- predicates ---
(test-assert "string?: basic" (string? "abc"))
(test-assert "istring?: never overclaims" (not (istring? "abc")))
(test-assert "string-null?: empty" (string-null? ""))
(test-assert "string-null?: non-empty" (not (string-null? "a")))
(test-equal "string-every: all match" #t (string-every char-alphabetic? "abc"))
(test-equal "string-any: one matches" #t (string-any char-numeric? "a1b"))

;;; --- conversions ---
(test-equal "reverse-list->string" "cBa" (reverse-list->string '(#\a #\B #\c)))
(test-equal "list->string: with start/end" "bc" (list->string '(#\a #\b #\c #\d) 1 3))
(test-equal "list->string: no bounds" "abc" (list->string '(#\a #\b #\c)))
(test-equal "string->list roundtrip" '(#\a #\b) (string->list "ab"))

(let* ((bv (string->utf8 "hi")) (s (utf8->string bv)))
  (test-equal "utf8 roundtrip" "hi" s))

(let* ((bv (string->utf16 "AB")) (s (utf16->string bv)))
  (test-equal "utf16 roundtrip (BOM)" "AB" s))
(let* ((bv (string->utf16be "AB")) (s (utf16be->string bv)))
  (test-equal "utf16be roundtrip" "AB" s))
(let* ((bv (string->utf16le "AB")) (s (utf16le->string bv)))
  (test-equal "utf16le roundtrip" "AB" s))
(let* ((bv (string->utf16be "\x1F600;")) (s (utf16be->string bv)))
  (test-equal "utf16be roundtrip: surrogate pair" "\x1F600;" s))

;;; --- selection ---
(test-equal "string-take" "Pete S" (string-take "Pete Szilagyi" 6))
(test-equal "string-drop" "zilagyi" (string-drop "Pete Szilagyi" 6))
(test-equal "string-take-right" "rules" (string-take-right "Beta rules" 5))
(test-equal "string-drop-right" "Beta " (string-drop-right "Beta rules" 5))
(test-equal "string-pad" "  325" (string-pad "325" 5))
(test-equal "string-pad: truncate" "71325" (string-pad "8871325" 5))
(test-equal "string-trim-both"
  "The outlook wasn't brilliant,"
  (string-trim-both "  The outlook wasn't brilliant,  \n\r"))

;;; --- replacement ---
(test-equal "string-replace: basic"
  "The miserable perl programmer endured daily ridicule."
  (string-replace "The TCL programmer endured daily ridicule."
                   "another miserable perl drone" 4 7 8 22))
(test-equal "string-replace: insert"
  "It's really easy to code it up in Scheme."
  (string-replace "It's easy to code it up in Scheme." "really " 5 5))

;;; --- prefixes & suffixes ---
(test-equal "string-prefix-length" 2 (string-prefix-length "abcde" "abzzz"))
(test-equal "string-suffix-length" 3 (string-suffix-length "abcde" "zzcde"))
(test-assert "string-prefix?" (string-prefix? "ab" "abcde"))
(test-assert "string-suffix?" (string-suffix? "de" "abcde"))

;;; --- searching ---
(test-equal "string-contains" 15 (string-contains "eek -- what a geek." "ee" 12 18))
(test-equal "string-contains-right: start=end returns end1"
  18 (string-contains-right "eek -- what a geek." "ee" 0 18 0 0))

;;; --- case conversion ---
(test-equal "string-upcase" "ABC" (string-upcase "abc"))
(test-equal "string-titlecase" "Hello World" (string-titlecase "hello world"))

;;; --- concatenation ---
(test-equal "string-concatenate" "abc" (string-concatenate '("a" "b" "c")))
(test-equal "string-concatenate-reverse"
  "Hello, I must be going."
  (string-concatenate-reverse '(" must be" "Hello, I") " going.XXXX" 7))
(test-equal "string-join: default" "foo bar baz" (string-join '("foo" "bar" "baz")))
(test-equal "string-join: suffix" "foo:bar:baz:" (string-join '("foo" "bar" "baz") ":" 'suffix))

;;; --- fold & map ---
(test-equal "string-fold-right: to list" '(#\a #\b #\c) (string-fold-right cons '() "abc"))
(test-equal "string-map: extension returns strings"
  "HeLLo"
  (string-map (lambda (c) (if (char-lower-case? c) (string c) (string-append "" (string c))))
              "HeLLo"))
(test-equal "string-map: char result (base case)" "AB" (string-map char-upcase "ab"))
(test-equal "string-map: multi-string (stops at shorter)"
  "ab" (string-map (lambda (a b) a) "abc" "ac"))

(let ((v '()))
  (string-for-each-index (lambda (i) (set! v (cons i v))) "abc")
  (test-equal "string-for-each-index" '(2 1 0) v))

(test-equal "string-map-index"
  "0-1-2-"
  (string-map-index (lambda (i) (string-append (number->string i) "-")) "abc"))

(test-equal "string-count" 2 (string-count "abcba" (lambda (c) (char=? c #\a))))
(test-equal "string-filter" "abc" (string-filter char-alphabetic? "a1b2c3"))
(test-equal "string-remove" "123" (string-remove char-alphabetic? "a1b2c3"))

;;; --- replication & splitting ---
(test-equal "xsubstring: rotate left" "cdefab" (xsubstring "abcdef" 2 8))
(test-equal "xsubstring: rotate right" "efabcd" (xsubstring "abcdef" -2 4))
(test-equal "xsubstring: replicate" "abcabca" (xsubstring "abc" 0 7))
(test-equal "string-repeat" "ababab" (string-repeat "ab" 3))
(test-equal "string-repeat: char" "aaa" (string-repeat #\a 3))
(test-equal "string-split: basic" '("foo" "bar" "baz") (string-split "foo:bar:baz" ":"))

;;; --- mutation still works (native) ---
(let ((s (string-copy "abc")))
  (string-set! s 0 #\X)
  (test-equal "string-set! via srfi 140 import" "Xbc" s))

(let ((runner (test-runner-current)))
  (test-end "srfi-140")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
