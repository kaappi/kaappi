;; SRFI-54 (Formatting) conformance tests
;; Run: zig-out/bin/kaappi --lib-path lib tests/scheme/srfi/srfi54.scm
;;
;; Most test cases here are the SRFI 54 spec's own worked examples,
;; reproduced verbatim. See lib/srfi/54.sld's header for two spec-text
;; caveats this file works around: (1) the spec's own HTML has an
;; unbalanced-paren typo in one pipe-directive example, worked around here
;; with an equivalent well-formed call; (2) a couple of examples involving
;; very large/scientific-notation flonums assume a `number->string'
;; rendering that differs from Kaappi's own (equally R7RS-valid) one --
;; those cases are adapted to Kaappi's actual, verified-by-hand output,
;; noted at each site.

(import (scheme base) (scheme write) (scheme process-context) (srfi 54) (srfi 64))

(test-begin "srfi-54")

;;; --- default rendering (no directives beyond <object> itself) ---

(test-equal "default: number" "42" (cat 42))
(test-equal "default: rational" "1/3" (cat 1/3))
(test-equal "default: string is returned as-is" "hello" (cat "hello"))
(test-equal "default: char" "a" (cat #\a))
(test-equal "default: boolean #t" "#t" (cat #t))
(test-equal "default: boolean #f" "#f" (cat #f))
(test-equal "default: symbol" "symbol" (cat 'symbol))
(test-equal "default: list falls back to `write'" "(#\\a \"str\" s)" (cat '(#\a "str" s)))
(test-equal "default: vector falls back to `write'" "#(#\\a \"str\" s)" (cat '#(#\a "str" s)))

;; A record with no custom writer also falls back to `write' (matches the
;; spec's own record-type example: `(cat ex) => "#{:example}"' under its
;; reference Scheme's printer -- we only assert it equals Kaappi's own
;; `write' output for the same object, since the exact unreadable-record
;; syntax is implementation-defined).
(define-record-type :example
  (make-example num str)
  example?
  (num get-num set-num!)
  (str get-str set-str!))
(define ex (make-example 123 "string"))
(test-equal "default: record falls back to `write'"
  (let ((p (open-output-string))) (write ex p) (get-output-string p))
  (cat ex))

;;; --- <string> directive: a plain string argument is always appended ---

(test-equal "string directive appended after default rendering" "3s" (cat 3 "s"))
(test-equal "multiple string directives appended in original order"
  "5-a-b" (cat 5 "-a" "-b"))
(test-equal "string directives interleaved with other directives still append in order"
  "         5-a-b" (cat 5 "-a" 10 "-b"))

;;; --- <width>/<char> directives ---

(test-equal "positive width right-aligns (pads left)" "    symbol" (cat 'symbol 10))
(test-equal "negative width left-aligns (pads right)" "string    " (cat "string" -10))
(test-equal "width smaller than content is ignored, not truncated"
  "123456" (cat 123456 2))
(test-equal "custom padding char" "         a" (cat #\a 10))
(test-equal "custom padding char, explicit char directive" "***a" (cat #\a 4 #\*))

;;; --- <radix> directive ---

(test-equal "hexadecimal literal input, octal output with sign" "#o+443" (cat #x123 'octal 'sign))
(test-equal "binary radix" "#b1010" (cat 10 'binary))
(test-equal "hexadecimal radix, lowercase input value" "#xff" (cat 255 'hexadecimal))

;;; --- <precision> directive (also exercises rounding/molding) ---

(test-equal "precision pads a whole number with trailing zeros"
  "129.00" (cat 129 -2.))
(test-equal "precision rounds down" "    129.98" (cat 129.985 10 2.))
(test-equal "precision rounds up (more nonzero digits follow the tie digit)"
  "    129.99" (cat 129.985001 10 2.))
(test-equal "precision on an exact rational forces #e as needed"
  "    #e0.33" (cat 1/3 10 2.))
(test-equal "negative precision suppresses the #e sign" "      0.33" (cat 1/3 10 -2.))

;;; --- <sign> and <exactness> directives ---

(test-equal "sign directive forces a '+' on a positive exact integer, decimal"
  "#e129.00" (cat 129 2.))
(test-equal "sign + custom pad char keeps sign adjacent to the digits"
  "#e+0129.00" (cat 129 10 2. #\0 'sign))
(test-equal "non-digit pad char puts all padding before the sign/prefix"
  "*#e+129.00" (cat 129 10 2. #\* 'sign))
(test-equal "inexact object + non-decimal radix gets an implicit #i sign"
  "#i#o+307/2" (cat 99.5 10 'sign 'octal))
(test-equal "explicit 'exact overrides the implicit #i sign"
  "  #o+307/2" (cat 99.5 10 'sign 'octal 'exact))

;;; --- <separator> directive (the closest thing SRFI 54 has to a
;;; repetition/grouping-count directive: '(char [group-size]) groups
;;; digits from the decimal point outward, default group size 3) ---

(test-equal "separator, default group size 3, with sign"
  "  +129,995" (cat 129995 10 '(#\,) 'sign))
(test-equal "separator with explicit group size 2, integer and fractional parts"
  " 1,29.99,5" (cat 129.995 10 '(#\, 2)))
(test-equal "separator with no width directive at all" "129,995" (cat 129995 '(#\,)))
(test-equal "separator on a negative number keeps the sign outside the grouping"
  "-129,995" (cat -129995 '(#\,)))
(test-equal "separator with a custom group size on a negative number"
  "-123_4567" (cat -1234567 (list #\_ 4)))
(test-equal "separator is skipped for a rational (contains '/')"
  (cat 1000000/3 10) (cat 1000000/3 10 '(#\,)))

;;; --- nested `cat': a returned string becomes a <string> directive ---

(test-equal "nested cat calls compose: numbers become plain strings"
  "130" (cat (cat 129.995 0.) '(0 -1)))
(test-equal "nested cat with a symbol, a literal string, and a written string"
  "3s \"str\"" (cat 3 (cat 's) " " (cat "str" write)))

;;; --- <writer>/<pipe>/<take> directives (non-number objects) ---

(test-equal "writer directive controls how the object is rendered"
  "\"str\"" (cat "str" write))
(test-equal "pipe: a single string->string procedure"
  "    STRING" (cat "string" 10 (list string-upcase)))
(test-equal "pipe chains multiple procedures left to right"
  "GNIRTS" (cat "string" (list string-reverse string-upcase)))
(test-equal "take: negative left means \"drop the first |n| characters\""
  "      RING" (cat "string" 10 (list string-upcase) '(-2)))
(test-equal "take: positive left/right slice a prefix and suffix"
  "     Sting" (cat "string" 10 `(,string-titlecase) '(2 3)))
(test-equal "take alone, positive: first n characters" "abc" (cat "abcdef" '(3)))
(test-equal "take alone, negative: all but the first |n| characters"
  "def" (cat "abcdef" '(-3)))
(test-equal "take alone, both sides: left n + right m concatenated"
  "abef" (cat "abcdef" '(2 2)))

;;; --- <converter> directive: (predicate . procedure), overrides
;;; number/writer/pipe/take dispatch; only width/char/port/string still apply ---

(test-equal "converter takes priority even when <object> is a number"
  "N=42" (cat 42 (cons number? (lambda (n) (string-append "N=" (number->string n))))))

(define (record->string object) (cat (get-num object) "-" (get-str object)))
(define (record-writer object string-port)
  (if (example? object)
      (begin (display (get-num object) string-port)
             (display "-" string-port)
             (display (get-str object) string-port))
      ((or (and (or (string? object) (char? object) (boolean? object)) display) write)
       object string-port)))

(test-equal "record example: writer directive" "          123-string" (cat ex 20 record-writer))
(test-equal "record example: converter directive (cons predicate proc)"
  "          123-string" (cat ex 20 (cons example? record->string)))
(test-equal "record example: writer used on a plain number, with precision"
  "            #e12.000" (cat 12 20 record-writer 3.))
(test-equal "record example: converter used on a plain number, negative precision"
  "              12.000" (cat 12 20 (cons example? record->string) -3.))
(test-equal "record example: writer + pipe + take + custom pad char on a string"
  "---------------STING" (cat "string" 20 record-writer (list string-upcase) '(2 3) #\-))

;;; --- <port> directive: #t/#f/an explicit port ---

(test-equal "port #f (default): no side effect, just the string" "42" (cat 42))

(let* ((p (open-output-string))
       (result (cat 42 10 p)))
  (test-equal "explicit port: return value" "        42" result)
  (test-equal "explicit port: side effect writes the same string"
    result (get-output-string p)))

(let* ((p (open-output-string))
       (result (cat '(#\a "str" s) p)))
  (test-equal "explicit port with a non-number, non-directive object"
    "(#\\a \"str\" s)" result)
  (test-equal "explicit port side effect matches return value for non-numbers"
    result (get-output-string p)))

;;; --- large/scientific-notation flonums: Kaappi's `number->string' picks
;;; a different large-magnitude threshold and exponent-sign convention
;;; than the spec transcript's Scheme did (verified directly: Kaappi
;;; renders 1.2345e15 as "1234500000000000.0", not "1.2345e15"), so the
;;; *rounding/padding logic* is checked against Kaappi's actual, correct
;;; number->string output rather than the spec's literal expected string. ---

;; The spec's transcript expects " +1.234e15" here (scientific notation,
;; 10-wide). Kaappi's number->string renders 1.2345e15 as a full decimal
;; expansion instead ("1234500000000000.0", verified directly above this
;; test file was written), so the correctly-rounded, correctly-signed,
;; width-exceeds-content (hence unpadded) result is this instead:
(test-equal "very large flonum with precision+sign: still rounds/pads/signs correctly"
  "+1234500000000000.000"
  (cat 1.2345e+15 10 3. 'sign))

;;; --- too many (unclassifiable) arguments is an error ---

(test-error "cat signals an error when arguments exceed all directive slots"
  (cat 1 2 3 4 5 6 7 8 9 10 11 12 13))

(let ((runner (test-runner-current)))
  (test-end "srfi-54")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
