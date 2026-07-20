(import (scheme base) (scheme write) (srfi 115))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;; Predicates
(check-true "regexp?" (regexp? (regexp "hello")))
(check-false "regexp? str" (regexp? "hello"))

;; Literals
(check-true "lit match" (regexp-matches? "hello" "hello"))
(check-false "lit no" (regexp-matches? "hello" "world"))
(check-false "lit partial" (regexp-matches? "hello" "hello world"))

;; Sequence
(check-true "seq" (regexp-matches? '(: "hello" " " "world") "hello world"))

;; Alternation
(check-true "or 1" (regexp-matches? '(or "cat" "dog") "cat"))
(check-true "or 2" (regexp-matches? '(or "cat" "dog") "dog"))
(check-false "or no" (regexp-matches? '(or "cat" "dog") "bird"))

;; Character classes
(check-true "any" (regexp-matches? 'any "x"))
(check-false "any empty" (regexp-matches? 'any ""))
(check-true "alpha" (regexp-matches? 'alphabetic "a"))
(check-false "alpha digit" (regexp-matches? 'alphabetic "1"))
(check-true "num" (regexp-matches? 'numeric "5"))
(check-true "space" (regexp-matches? 'whitespace " "))
(check-true "lower" (regexp-matches? 'lower-case "a"))
(check-true "upper" (regexp-matches? 'upper-case "A"))

;; Quantifiers
(check-true "* 0" (regexp-matches? '(* "a") ""))
(check-true "* many" (regexp-matches? '(* "a") "aaaa"))
(check-true "+ 1" (regexp-matches? '(+ "a") "a"))
(check-true "+ many" (regexp-matches? '(+ "a") "aaa"))
(check-false "+ 0" (regexp-matches? '(+ "a") ""))
(check-true "? 0" (regexp-matches? '(? "a") ""))
(check-true "? 1" (regexp-matches? '(? "a") "a"))
(check-true "= 3" (regexp-matches? '(= 3 "a") "aaa"))
(check-false "= 2" (regexp-matches? '(= 3 "a") "aa"))
(check-true ">= 2" (regexp-matches? '(>= 2 "a") "aaaa"))
(check-false ">= short" (regexp-matches? '(>= 2 "a") "a"))
(check-true "** 2-4" (regexp-matches? '(** 2 4 "a") "aaa"))
(check-false "** short" (regexp-matches? '(** 2 4 "a") "a"))

;; Search
(let ((m (regexp-search "world" "hello world")))
  (check-true "search found" (regexp-match? m))
  (check "search sub" (regexp-match-submatch m 0) "world")
  (check "search start" (regexp-match-submatch-start m 0) 6)
  (check "search end" (regexp-match-submatch-end m 0) 11))
(check-false "search miss" (regexp-search "xyz" "hello"))

;; Submatches
(let ((m (regexp-matches '(: ($ (+ alphabetic)) " " ($ (+ numeric))) "hello 42")))
  (check-true "sub match" (regexp-match? m))
  (check "sub 0" (regexp-match-submatch m 0) "hello 42")
  (check "sub 1" (regexp-match-submatch m 1) "hello")
  (check "sub 2" (regexp-match-submatch m 2) "42")
  (check "count" (regexp-match-count m) 2)
  (check "->list" (regexp-match->list m) '("hello 42" "hello" "42")))

;; Case insensitive
(check-true "nocase" (regexp-matches? '(w/nocase "hello") "HELLO"))
(check-true "nocase mixed" (regexp-matches? '(w/nocase "hello") "HeLLo"))
(check-false "case" (regexp-matches? "hello" "HELLO"))

;; Boundaries
(check-true "bos" (regexp-matches? '(: bos "hello") "hello"))
(check-true "eos" (regexp-matches? '(: "hello" eos) "hello"))
(let ((m (regexp-search '(: bow ($ (+ alphabetic)) eow) "hello world")))
  (check "bow/eow" (regexp-match-submatch m 1) "hello"))

;; nwb — a position that is not a word boundary
(check-true "nwb" (and (regexp-search '(: nwb "foo" nwb) "xfoox") #t))
(check-false "nwb at boundary" (and (regexp-search '(: nwb "foo" nwb) " foo ") #t))

;; Extract
(check "extract" (regexp-extract '(+ alphabetic) "hello 42 world") '("hello" "world"))

;; Split
(check "split" (regexp-split " " "hello world foo") '("hello" "world" "foo"))
(check "split comma" (regexp-split ", " "a, b, c") '("a" "b" "c"))

;; Partition — no trailing "" when the string ends with a match (chibi's
;; reference behaviour; Kaappi used to append one).
(let ((p (regexp-partition '(+ numeric) "abc123def456")))
  (check "partition" p '("abc" "123" "def" "456")))
(check "partition trailing text"
  (regexp-partition '(+ numeric) "abc123def") '("abc" "123" "def"))

;; A regexp that can match the empty string must not split at every position:
;; empty matches are skipped, and the index handed to the fold is where the
;; previous match ended, not where the search resumed.
(check "split nullable"
  (regexp-split '(* numeric) "abc123def456ghi789") '("abc" "def" "ghi" ""))
(check "partition nullable"
  (regexp-partition '(* numeric) "abc123def456ghi") '("abc" "123" "def" "456" "ghi"))
(check "partition nullable empty string" (regexp-partition '(* numeric) "") '(""))
(check "extract nullable"
  (regexp-extract '(* numeric) "abc123def456ghi789") '("123" "456" "789"))

;; A list whose head is a string is the char set of its characters
(check "split char-set list" (regexp-split '(",;") "a,,b") '("a" "" "b"))
(check "split char-set list trailing" (regexp-split '(",;") "a,,b,") '("a" "" "b" ""))

;; Replace
(check "replace" (regexp-replace "world" "hello world" "there") "hello there")
(check "replace-all" (regexp-replace-all "o" "foo boo" "0") "f00 b00")

;; Char ranges
(check-true "range az" (regexp-matches? '(+ (/ "az")) "hello"))
(check-false "range az fail" (regexp-matches? '(+ (/ "az")) "HELLO"))
(check-true "range AZaz" (regexp-matches? '(+ (/ "azAZ")) "helloWORLD"))
;; (/ ...) also takes characters — these used to be dropped, leaving an
;; empty range that matched nothing.
(check-true "range chars" (regexp-matches? '(+ (/ #\a #\z)) "hello"))
(check-false "range chars fail" (regexp-matches? '(+ (/ #\a #\z)) "HELLO"))
(check-true "range mixed" (regexp-matches? '(+ (/ "az" #\0 #\9)) "h3ll0"))

;; Case folding reaches named classes, not just literal characters
(check-true "nocase class" (regexp-matches? '(w/nocase (* lower)) "abcD"))
(check-false "case class" (regexp-matches? '(* lower) "abcD"))
(check-true "nocase range" (regexp-matches? '(w/nocase (+ (/ "af"))) "BeeF"))

;; Repetition must backtrack: a greedy operator has to give characters back
;; when what follows cannot match otherwise.
(check-true "backtrack star" (regexp-matches? '(: (* any) "b") "ab"))
(check "backtrack submatch"
  (regexp-match->list (regexp-matches '(: "<" ($ (* any)) ">" (* any))
                                      "<em>Hello World</em>"))
  '("<em>Hello World</em>" "em>Hello World</em"))
(check "backtrack two groups"
  (regexp-match->list
    (regexp-matches '(: (* any) ($ "foo" (* any)) ($ "bar" (* any))) "fooxbarfbar"))
  '("fooxbarfbar" "fooxbarf" "bar"))

;; Non-greedy repetition prefers the shortest match
(check "non-greedy star"
  (regexp-match->list (regexp-matches '(: "<" ($ (*? any)) ">" (* any))
                                      "<em>Hello World</em>"))
  '("<em>Hello World</em>" "em"))
(check "non-greedy optional"
  (regexp-match->list (regexp-matches '(: ($ (?? "a")) (* any)) "aaa"))
  '("aaa" ""))
(check "non-greedy repeated"
  (regexp-match->list (regexp-matches '(: ($ (**? 1 3 "a")) (* any)) "aaa"))
  '("aaa" "a"))
;; An open-ended upper bound is spelled #f, and used to raise a type error
(check-true "open-ended repeat" (regexp-matches? '(** 1 #f "a") "aaa"))

;; Complement — of the *union* of its arguments, not of their sequence
(check-true "compl" (regexp-matches? '(+ (~ numeric)) "hello"))
(check-false "compl union" (regexp-matches? '(~ #\a #\b) "b"))
(check-true "compl union other" (regexp-matches? '(~ #\a #\b) "c"))

;; Char set intersection and difference (#1681)
(check-true "difference" (regexp-matches? '(* (- (/ "az") ("aeiou"))) "xyzzy"))
(check-false "difference vowel" (regexp-matches? '(* (- (/ "az") ("aeiou"))) "vowels"))
(check-true "intersection" (regexp-matches? '(* (& (/ "az") (~ ("aeiou")))) "xyzzy"))
(check-false "intersection vowel" (regexp-matches? '(* (& (/ "az") (~ ("aeiou")))) "vowels"))
(check-true "difference long name"
  (regexp-matches? '(* (difference alphabetic ("aeiou"))) "xyzzy"))
(check-true "intersection long name"
  (regexp-matches? '(* (and alphabetic (~ ("aeiou")))) "xyzzy"))
;; With no arguments intersection is the set of all characters.
(check-true "intersection empty" (regexp-matches? '(& ) "x"))

;; Look-ahead and look-behind (#1681)
(check-true "look" (regexp-matches? '(: (look-ahead "ab") "ab" "c") "abc"))
(check-false "neglook" (regexp-matches? '(: (neg-look-ahead "ab") "ab") "ab"))
(check "look-behind"
  (regexp-match->list
    (regexp-matches '(: ($ word) (* whitespace) (look-behind "regular ") "expression")
                    "regular expression"))
  '("regular expression" "regular"))
(check-false "look-behind mismatch"
  (regexp-matches '(: ($ word) (* whitespace) (look-behind "regular") "expression")
                  "regular expression"))
(check-false "neg-look-behind"
  (regexp-matches '(: ($ word) (* whitespace) (neg-look-behind "regular ") "expression")
                  "regular expression"))
(check "neg-look-behind mismatch"
  (regexp-match->list
    (regexp-matches '(: ($ word) (* whitespace) (neg-look-behind "regular") "expression")
                    "regular expression"))
  '("regular expression" "regular"))
;; Look-behind cannot see text before the search start.
(check-false "look-behind stops at start"
  (regexp-search '(: (look-behind "ab") "c") "abc" 2))

;; A bare `word' is a whole word, not one word-constituent character (#1681)
(check "bare word" (regexp-match-submatch (regexp-search 'word "**foo**") 0) "foo")
(check "word+ restricted"
  (regexp-match-submatch (regexp-search '(word+ (/ "az")) "**foo**") 0) "foo")
(check-false "word+ excludes" (regexp-search '(word+ (/ "09")) "**foo**"))
(check "word wrapper" (regexp-match-submatch
                       (regexp-search '(word (+ alphabetic)) "**foo**") 0) "foo")

;; title-case and symbol char sets (#1681).  U+01C5 is a titlecase ligature.
(check-true "title" (regexp-matches? '(* title) "\x01C5;"))
(check-false "title on upper" (regexp-matches? '(* title) "A"))
(check-true "title-case alias" (regexp-matches? 'title-case "\x01C5;"))
(check-true "nocase lower reaches title" (regexp-matches? '(w/nocase (* lower)) "\x01C5;"))
(check-true "symbol ascii" (regexp-matches? '(* symbol) "$+<=>^`|~"))
(check-true "symbol unicode" (regexp-matches? 'symbol "\x00A9;"))
(check-false "symbol letter" (regexp-matches? 'symbol "a"))

;; w/ascii restricts the named char sets it wraps; w/unicode widens them (#1681)
(check-true "unicode alpha" (regexp-matches? '(* alphabetic) "\x043A;\x0438;"))
(check-false "w/ascii alpha" (regexp-matches? '(w/ascii (* alphabetic)) "\x043A;\x0438;"))
(check-true "w/ascii alpha ascii" (regexp-matches? '(w/ascii (* alphabetic)) "English"))
(check-true "w/unicode inside w/ascii"
  (regexp-matches? '(w/ascii (w/unicode (* alphabetic))) "\x043A;\x0438;"))
(check-false "w/ascii any" (regexp-matches? '(w/ascii any) "\x043A;"))
(check-false "w/ascii title" (regexp-matches? '(w/ascii title) "\x01C5;"))
;; (~ x) is (- any x), so an ASCII complement is still ASCII.
(check-false "w/ascii complement" (regexp-matches? '(w/ascii (~ numeric)) "\x043A;"))

;; Named submatches can be looked up by symbol (#1681)
(let ((m (regexp-matches '(: (-> user (+ alphabetic)) "@" (-> host (+ alphabetic)))
                         "ann@example")))
  (check "named submatch user" (regexp-match-submatch m 'user) "ann")
  (check "named submatch host" (regexp-match-submatch m 'host) "example")
  (check "named submatch start" (regexp-match-submatch-start m 'host) 4)
  (check "named submatch end" (regexp-match-submatch-end m 'host) 11)
  (check "named submatch by number" (regexp-match-submatch m 1) "ann"))
;; With a repeated name, the first group that actually matched wins.
(check "repeated name first"
  (regexp-match-submatch (regexp-matches '(or (-> x "ab") (-> x "cd")) "ab") 'x) "ab")
(check "repeated name second"
  (regexp-match-submatch (regexp-matches '(or (-> x "ab") (-> x "cd")) "cd") 'x) "cd")
;; A named group that did not match is #f; an unknown name is an error.
(check-false "unmatched name"
  (regexp-match-submatch (regexp-matches '(: (? (-> x "a")) "b") "b") 'x))
(check-true "unknown name raises"
  (guard (e (#t #t)) (regexp-match-submatch (regexp-matches "a" "a") 'nope) #f))

;; w/nocapture suppresses submatches without changing what is matched
(check "nocapture"
  (regexp-match->list
    (regexp-search '(: ($ (+ numeric)) "-" (w/nocapture ($ (+ numeric)))
                       "-" ($ (+ numeric)))
                   "555-867-5309"))
  '("555-867-5309" "555" "5309"))

;; Grapheme clusters (#1681)
(check "grapheme ascii" (regexp-extract 'grapheme "abc") '("a" "b" "c"))
(check "grapheme crlf" (regexp-extract 'grapheme "a\nb\r\nc") '("a" "\n" "b" "\r\n" "c"))
(check "grapheme combining"
  (regexp-extract 'grapheme "a\x0300;b\x0301;\x0302;")
  '("a\x0300;" "b\x0301;\x0302;"))
;; Conjoining jamo (L V T) form one cluster per syllable.
(check "grapheme hangul jamo"
  (map (lambda (g) (map char->integer (string->list g)))
       (regexp-extract 'grapheme "\x1112;\x1161;\x11AB;\x1100;\x1173;\x11AF;"))
  '((#x1112 #x1161 #x11AB) (#x1100 #x1173 #x11AF)))
;; A pair of regional indicators is one cluster; a third starts a new one.
(check "grapheme regional indicators"
  (length (regexp-extract 'grapheme "\x1F1E6;\x1F1E7;\x1F1E8;")) 2)
(check-true "grapheme matches one cluster"
  (regexp-matches? 'grapheme "a\x0300;"))
;; bog/eog assert cluster boundaries.
(check-true "bog/eog" (regexp-matches? '(: bog grapheme eog) "\xD55C;"))
(check-false "bog mid-cluster"
  (regexp-matches? '(: "\x1112;" bog grapheme eog "\x11AB;") "\x1112;\x1161;\x11AB;"))
;; In an ASCII context bog/eog always hold and grapheme is any.
(check-true "w/ascii grapheme" (regexp-matches? '(w/ascii (: bog grapheme eog)) "a"))

;; Complex
(let ((m (regexp-search '(: ($ (+ numeric)) "-" ($ (+ numeric))) "call 555-1234 now")))
  (check "phone 1" (regexp-match-submatch m 1) "555")
  (check "phone 2" (regexp-match-submatch m 2) "1234"))

;; Fold
(check "fold count"
  (regexp-fold '(+ numeric) (lambda (i m s acc) (+ acc 1)) 0 "a1b22c333"
               (lambda (i m s acc) acc))
  3)

;; valid-sre?
(check-true "valid?" (valid-sre? '(+ "a")))
(check-true "valid? str" (valid-sre? "hello"))

;; Unknown named char class must raise, not silently match nothing
;; (regression: (+ digit) returned #f from regexp-search instead of
;; erroring — 'digit is not a SRFI-115 class, 'numeric/'num is)
(check-true "unknown class raises"
  (guard (e (#t #t)) (regexp-search '(+ digit) "age: 25") #f))
(check-true "unknown class raises in regexp"
  (guard (e (#t #t)) (regexp 'digits) #f))
(check-false "valid-sre? unknown class" (valid-sre? '(+ digit)))
(check-true "known class aliases still valid"
  (and (valid-sre? '(+ num)) (valid-sre? '(+ alpha)) (valid-sre? '(* space))))

;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 115 tests failed" fail))
