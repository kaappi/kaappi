;; SRFI-257 rx sublibrary (regexp match patterns over SRFI 115 regexps and
;; SRFI 264 SSRE strings) conformance tests, ported verbatim from the
;; reference test suite by Sergei Egorov, whose second half is in turn
;; adapted from Alex Shinn's chibi regexp tests.
;;
;; This is the FULL port (about 1½ minutes of macro expansion on an M-class
;; laptop, over run-all.sh's 60s per-file budget), kept out of run-all.sh's
;; non-recursive srfi/*.scm glob; CI runs the lean
;; tests/scheme/srfi/srfi257-rx.scm smoke instead.
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/slow/srfi257-rx-full.scm

;;;; SPDX-FileCopyrightText: Sergei Egorov
;;;; SPDX-License-Identifier: BSD-3-Clause

(import (scheme base) (srfi 64))
(import (srfi 257) (srfi 257 rx) (srfi 264))

; SRFI 257 RX Tests (some of them borrowed)

(test-begin "srfi-257-rx")

(test-equal #f
  (match 42 ((~/ "[0-9]+" a) a) (_ #f)))

(test-equal "42"
  (match "42" ((~/ "[0-9]+" a) a) (_ #f)))

(test-equal #f
  (match 42 ((~/ (rx (+ (/ "09"))) a) a) (_ #f)))

(test-equal "42"
  (match "42" ((~/ (rx (+ (/ "09"))) a) a) (_ #f)))

(define phs "home: 301-123-4567; cell: 240-890-1234; fax: 301-567-8901")

(test-equal '("home" "301" "123" "4567")
  (match phs ((~/sub "({a}*): ({d}*)-({d}*)-({d}*)" _ t a b c) (list t a b c)) (_ #f)))

(test-equal '("home" "301" "123" "4567")
  (match phs ((~/any "({a}*): ({d}*)-({d}*)-({d}*)" _ t a b c) (list t a b c)) (_ #f)))

(test-equal #f
  (match phs ((~/sub "({a}*): ({d}*)-({d}*)-({d}*)" _ t "240" b c) (list t "240" b c)) (_ #f)))

(test-equal '("cell" "240" "890" "1234")
  (match phs ((~/any "({a}*): ({d}*)-({d}*)-({d}*)" _ t "240" b c) (list t "240" b c)) (_ #f)))

(test-equal '("cell" "240" "890" "1234")
  (match phs ((~/any "({a}*): ({d}*)-({d}*)-({d}*)" _ t (~and a (~not "301")) b c) (list t a b c)) (_ #f)))

(test-equal #f
  (match phs ((~/any "({a}*): ({d}*)-({d}*)-({d}*)" _ t "412" b c) (list t "412" b c)) (_ #f)))

(test-equal #f
  (match phs ((~/all "({a}*): ({d}*)-({d}*)-({d}*)" _ t "412" b c) (list t "412" b c)) (_ #f)))

(test-equal '(("home" "cell" "fax") ("301" "240" "301"))
  (match phs ((~/all "({a}*): ({d}*)-({d}*)-({d}*)" _ t a) (list t a)) (_ #f)))

(test-equal #f
  (match phs ((~/etc "({a}*): ({d}*)-({d}*)-({d}*)" _ t (~and a (~not "240"))) (list t a)) (_ #f)))

(test-equal '(("home" "fax") ("301" "301"))
  (match phs ((~/etcse "({a}*): ({d}*)-({d}*)-({d}*)" _ t (~and a (~not "240"))) (list t a)) (_ #f)))

(test-equal '(() ())
  (match phs ((~/etcse "({a}*): ({d}*)-({d}*)-({d}*)" _ t (~and a "412")) (list t a)) (_ #f)))


;;;; SPDX-SnippetBegin
;;;; SPDX-SnippetName: Incorporated SRE Ref. Imp. Tests
;;;; SPDX-SnippetFromFileName: lib/chibi/regexp-test.sld
;;;; SPDX-SnippetLicenseConcluded: BSD-3-Clause
;;;; SPDX-SnippetCopyrightText: 2015 - 2019 Alex Shinn

;;;; tests below adapted from the SRE ref. imp. tests by Alex Shinn
;;;; https://github.com/ashinn/chibi-scheme/blob/master/lib/chibi/regexp-test.sld
;;;; by selectively converting regexes to SSRE strings

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx ($ (* "ab")) "c") a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "((?:ab)*)c" a b) (list a b)) (_ #f)))

(test-equal '("y")
  (match "xy" ((~/any (rx "y") a) (list a)) (_ #f)))
(test-equal '("y")
  (match "xy" ((~/any "y" a) (list a)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "xababc" ((~/any (rx ($ (* "ab")) "c") a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "xababc" ((~/any "((?:ab)*)c" a b) (list a b)) (_ #f)))

(test-equal #f
  (match "fooxbafba" ((~/ (rx (* any) ($ "foo" (* any)) ($ "bar" (* any)))) (list)) (_ #f)))
(test-equal #f
  (match "fooxbafba" ((~/ "{_}*(foo{_}*)(bar{_}*)") (list)) (_ #f)))

(test-equal '("fooxbarfbar" "fooxbarf" "bar")
  (match "fooxbarfbar" ((~/ (rx (* any) ($ "foo" (* any)) ($ "bar" (* any))) a b c) (list a b c)) (_ #f)))
(test-equal '("fooxbarfbar" "fooxbarf" "bar")
  (match "fooxbarfbar" ((~/ "{_}*(foo{_}*)(bar{_}*)" a b c) (list a b c)) (_ #f)))

(test-equal '("abcd" "abcd")
  (match "abcd" ((~/ (rx ($ (* (or "ab" "cd")))) a b) (list a b)) (_ #f)))
(test-equal '("abcd" "abcd")
  (match "abcd" ((~/ "((?:ab|cd)*)" a b) (list a b)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx bos ($ (* "ab")) "c") a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "^((?:ab)*)c" a b) (list a b)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx ($ (* "ab")) "c" eos) a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "((?:ab)*)c$" a b) (list a b)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx bos ($ (* "ab")) "c" eos) a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "^((?:ab)*)c$" a b) (list a b)) (_ #f)))

(test-equal #f
  (match "ababc" ((~/ (rx bos ($ (* "ab")) eos "c")) (list)) (_ #f)))
(test-equal #f
  (match "ababc" ((~/ "^((?:ab)*)$c") (list)) (_ #f)))

(test-equal #f
  (match "ababc" ((~/ (rx ($ (* "ab")) bos "c" eos)) (list)) (_ #f)))
(test-equal #f
  (match "ababc" ((~/ "((?:ab)*)^c$") (list)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx bol ($ (* "ab")) "c") a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "{<l}((?:ab)*)c" a b) (list a b)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx ($ (* "ab")) "c" eol) a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "((?:ab)*)c{l>}" a b) (list a b)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx bol ($ (* "ab")) "c" eol) a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "{<l}((?:ab)*)c{l>}" a b) (list a b)) (_ #f)))

(test-equal #f
  (match "ababc" ((~/ (rx bol ($ (* "ab")) eol "c")) (list)) (_ #f)))
(test-equal #f
  (match "ababc" ((~/ "{<l}((?:ab)*){l>}c") (list)) (_ #f)))

(test-equal #f
  (match "ababc" ((~/ (rx ($ (* "ab")) bol "c" eol)) (list)) (_ #f)))
(test-equal #f
  (match "ababc" ((~/ "((?:ab)*){<l}c{l>}") (list)) (_ #f)))

(test-equal '("\nabc\n" "abc")
  (match "\nabc\n" ((~/ (rx (* #\newline) bol ($ (* alpha)) eol (* #\newline)) a b) (list a b)) (_ #f)))
(test-equal '("\nabc\n" "abc")
  (match "\nabc\n" ((~/ "\n*{<l}({a}*){l>}\n*" a b) (list a b)) (_ #f)))

(test-equal #f
  (match "\n'abc\n" ((~/ (rx (* #\newline) bol ($ (* alpha)) eol (* #\newline))) (list)) (_ #f)))
(test-equal #f
  (match "\n'abc\n" ((~/ "\n*{<l}({a}*){l>}\n*") (list)) (_ #f)))

(test-equal #f
  (match "\nabc.\n" ((~/ (rx (* #\newline) bol ($ (* alpha)) eol (* #\newline))) (list)) (_ #f)))
(test-equal #f
  (match "\nabc.\n" ((~/ "\n*{<l}({a}*){l>}\n*") (list)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx bow ($ (* "ab")) "c") a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "\\<((?:ab)*)c" a b) (list a b)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx ($ (* "ab")) "c" eow) a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "((?:ab)*)c\\>" a b) (list a b)) (_ #f)))

(test-equal '("ababc" "abab")
  (match "ababc" ((~/ (rx bow ($ (* "ab")) "c" eow) a b) (list a b)) (_ #f)))
(test-equal '("ababc" "abab")
  (match "ababc" ((~/ "\\<((?:ab)*)c\\>" a b) (list a b)) (_ #f)))

(test-equal #f
  (match "ababc" ((~/ (rx bow ($ (* "ab")) eow "c")) (list)) (_ #f)))
(test-equal #f
  (match "ababc" ((~/ "\\<((?:ab)*)\\>c") (list)) (_ #f)))

(test-equal #f
  (match "ababc" ((~/ (rx ($ (* "ab")) bow "c" eow)) (list)) (_ #f)))
(test-equal #f
  (match "ababc" ((~/ "((?:ab)*)\\<c\\>") (list)) (_ #f)))

(test-equal '("  abc  " "abc")
  (match "  abc  " ((~/ (rx (* space) bow ($ (* alpha)) eow (* space)) a b) (list a b)) (_ #f)))
(test-equal '("  abc  " "abc")
  (match "  abc  " ((~/ "\\s*\\<({a}*)\\>\\s*" a b) (list a b)) (_ #f)))

(test-equal #f
  (match " 'abc  " ((~/ (rx (* space) bow ($ (* alpha)) eow (* space))) (list)) (_ #f)))
(test-equal #f
  (match " 'abc  " ((~/ "\\s*\\<({a}*)\\>\\s*") (list)) (_ #f)))

(test-equal #f
  (match " abc.  " ((~/ (rx (* space) bow ($ (* alpha)) eow (* space))) (list)) (_ #f)))
(test-equal #f
  (match " abc.  " ((~/ "\\s*\\<({a}*)\\>\\s*") (list)) (_ #f)))

(test-equal '("abc  " "abc")
  (match "abc  " ((~/ (rx ($ (* alpha)) (* any)) a b) (list a b)) (_ #f)))
(test-equal '("abc  " "abc")
  (match "abc  " ((~/ "({a}*){_}*" a b) (list a b)) (_ #f)))

(test-equal '("abc  " "")
  (match "abc  " ((~/ (rx ($ (*? alpha)) (* any)) a b) (list a b)) (_ #f)))
(test-equal '("abc  " "")
  (match "abc  " ((~/ "({a}*?){_}*" a b) (list a b)) (_ #f)))

(test-equal '("<em>Hello World</em>" "em>Hello World</em")
  (match "<em>Hello World</em>" ((~/ (rx "<" ($ (* any)) ">" (* any)) a b) (list a b)) (_ #f)))
(test-equal '("<em>Hello World</em>" "em>Hello World</em")
  (match "<em>Hello World</em>" ((~/ "<({_}*)>{_}*" a b) (list a b)) (_ #f)))

(test-equal '("<em>Hello World</em>" "em")
  (match "<em>Hello World</em>" ((~/ (rx "<" ($ (*? any)) ">" (* any)) a b) (list a b)) (_ #f)))
(test-equal '("<em>Hello World</em>" "em")
  (match "<em>Hello World</em>" ((~/ "<({_}*?)>{_}*" a b) (list a b)) (_ #f)))

(test-equal '("foo")
  (match " foo " ((~/any (rx "foo") a) (list a)) (_ #f)))
(test-equal '("foo")
  (match " foo " ((~/any "foo" a) (list a)) (_ #f)))

(test-equal #f
  (match " foo " ((~/any (rx nwb "foo" nwb)) (list)) (_ #f)))
(test-equal #f
  (match " foo " ((~/any "\\Bfoo\\B") (list)) (_ #f)))

(test-equal '("foo")
  (match "xfoox" ((~/any (rx nwb "foo" nwb) a) (list a)) (_ #f)))
(test-equal '("foo")
  (match "xfoox" ((~/any "\\Bfoo\\B" a) (list a)) (_ #f)))

(test-equal '("beef")
  (match "beef" ((~/ (rx (* (/ "af"))) a) (list a)) (_ #f)))
(test-equal '("beef")
  (match "beef" ((~/ "[a-f]*" a) (list a)) (_ #f)))

(test-equal '("12345beef" "beef")
  (match "12345beef" ((~/ (rx (* numeric) ($ (* (/ "af")))) a b) (list a b)) (_ #f)))
(test-equal '("12345beef" "beef")
  (match "12345beef" ((~/ "\\d*([a-f]*)" a b) (list a b)) (_ #f)))

(test-equal '("12345BeeF" "BeeF")
  (match "12345BeeF" ((~/ (rx (* numeric) (w/nocase ($ (* (/ "af"))))) a b) (list a b)) (_ #f)))
(test-equal '("12345BeeF" "BeeF")
  (match "12345BeeF" ((~/ "\\d*(?i:([a-f]*))" a b) (list a b)) (_ #f)))

(test-equal #f
  (match "abcD" ((~/ (rx (* lower))) (list)) (_ #f)))
(test-equal #f
  (match "abcD" ((~/ "{l}*") (list)) (_ #f)))

(test-equal '("abcD")
  (match "abcD" ((~/ (rx (w/nocase (* lower))) a) (list a)) (_ #f)))
(test-equal '("abcD")
  (match "abcD" ((~/ "(?i){l}*" a) (list a)) (_ #f)))

(test-equal '("123" "456" "789")
  (match "abc123def456ghi789" ((~/extracted (rx (+ numeric)) l) l)))
(test-equal '("123" "456" "789")
  (match "abc123def456ghi789" ((~/extracted "{d}+" l) l)))

(test-equal '("123" "456" "789")
  (match "abc123def456ghi789" ((~/extracted (rx (* numeric)) l) l)))
(test-equal '("123" "456" "789")
  (match "abc123def456ghi789" ((~/extracted "[\\d]*" l) l)))

(test-equal '("abc" "def" "ghi" "")
  (match "abc123def456ghi789" ((~/split  (rx (* numeric)) l) l)))
(test-equal '("abc" "def" "ghi" "")
  (match "abc123def456ghi789" ((~/split  "{d}*" l) l)))

(test-equal '("abc" "def" "ghi" "")
  (match "abc123def456ghi789" ((~/split  (rx (+ numeric)) l) l)))
(test-equal '("abc" "def" "ghi" "")
  (match "abc123def456ghi789" ((~/split  "\\d+" l) l)))

(test-equal '("a" "b")
  (match "a b" ((~/split  (rx (+ whitespace)) l) l)))
(test-equal '("a" "b")
  (match "a b" ((~/split  "{s}+" l) l)))

(test-equal '("a" "" "b")
  (match "a,,b" ((~/split  (rx (",;")) l) l)))
(test-equal '("a" "" "b")
  (match "a,,b" ((~/split  "[,;]" l) l)))

(test-equal '("a" "" "b" "")
  (match "a,,b," ((~/split  (rx (",;")) l) l)))
(test-equal '("a" "" "b" "")
  (match "a,,b," ((~/split  "[,;]" l) l)))

(test-equal '("")
  (match "" ((~/partitioned (rx (* numeric)) l) l)))
(test-equal '("")
  (match "" ((~/partitioned "{d}*" l) l)))

(test-equal '("abc" "123" "def" "456" "ghi")
  (match "abc123def456ghi" ((~/partitioned (rx (* numeric)) l) l)))
(test-equal '("abc" "123" "def" "456" "ghi")
  (match "abc123def456ghi" ((~/partitioned "{d}*" l) l)))

(test-equal '("abc" "123" "def" "456" "ghi" "789")
  (match "abc123def456ghi789" ((~/partitioned (rx (* numeric)) l) l)))
(test-equal '("abc" "123" "def" "456" "ghi" "789")
  (match "abc123def456ghi789" ((~/partitioned "{d}*" l) l)))

;; SPDX-SnippetEnd

(let ((runner (test-runner-current)))
  (test-end)
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
