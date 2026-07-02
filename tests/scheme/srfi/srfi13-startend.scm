;; SRFI-13 start/end index parameter tests
(import (scheme base) (scheme char) (scheme write) (srfi 13))

(define pass 0)
(define fail 0)
(define (check name expected actual)
  (if (equal? expected actual)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display name)
      (display " expected=") (write expected)
      (display " got=") (write actual)
      (newline))))

;; --- string-index with start/end ---
(check "string-index start"
  3 (string-index "abcdef" char-lower-case? 3))
(check "string-index start past match"
  3 (string-index "abc1ef" char-numeric? 0 5))
(check "string-index no match in range"
  #f (string-index "abcdef" char-numeric? 2 4))
(check "string-index start=end"
  #f (string-index "abcdef" char-lower-case? 3 3))
(check "string-index whole string"
  0 (string-index "hello" char-lower-case?))

;; --- string-index-right with start/end ---
(check "string-index-right start"
  4 (string-index-right "abc12def" char-numeric? 0 5))
(check "string-index-right range"
  3 (string-index-right "a1b2c" char-numeric? 1 4))

;; --- string-skip with start/end ---
(check "string-skip start"
  #f (string-skip "aaaaab" char-lower-case? 3))
(check "string-skip with start"
  3 (string-skip "111abc" char-numeric? 0 6))

;; --- string-skip-right with start/end ---
(check "string-skip-right start"
  2 (string-skip-right "abc111" char-numeric? 0 5))

;; --- string-count with start/end ---
(check "string-count full" 3 (string-count "a1b2c3" char-numeric?))
(check "string-count start" 2 (string-count "a1b2c3" char-numeric? 2))
(check "string-count start end" 1 (string-count "a1b2c3" char-numeric? 2 4))
(check "string-count empty range" 0 (string-count "a1b2c3" char-numeric? 3 3))

;; --- string-contains with start ---
(check "string-contains basic" 2 (string-contains "abcdef" "cd"))
(check "string-contains start" 4 (string-contains "xxabcd" "cd" 2))
(check "string-contains start end miss" #f (string-contains "abcdef" "ef" 0 4))

;; --- string-prefix? with start/end (SRFI-13: start1/end1 apply to s1) ---
(check "string-prefix? basic" #t (string-prefix? "ab" "abcdef"))
(check "string-prefix? s1 range" #t (string-prefix? "hello" "hell" 0 2))
(check "string-prefix? s1 skip" #t (string-prefix? "xxab" "abcdef" 2))

;; --- string-suffix? with start/end (SRFI-13: start1/end1 apply to s1) ---
(check "string-suffix? basic" #t (string-suffix? "ef" "abcdef"))
(check "string-suffix? s1 range" #t (string-suffix? "hello" "llo" 2))
(check "string-suffix? s1 end miss" #f (string-suffix? "xy" "abcdef" 0 1))

;; --- string-every with start/end ---
(check "string-every full" #t (string-every char-lower-case? "abc"))
(check "string-every start" #t (string-every char-numeric? "abc123" 3))
(check "string-every start end" #f (string-every char-numeric? "abc123" 1 4))

;; --- string-any with start/end ---
(check "string-any full" #t (string-any char-numeric? "abc1"))
(check "string-any start" #f (string-any char-numeric? "abc1def" 4))
(check "string-any start end" #t (string-any char-numeric? "a1b" 0 2))

;; --- string-filter with start/end ---
(check "string-filter full" "123" (string-filter char-numeric? "a1b2c3"))
(check "string-filter start" "23" (string-filter char-numeric? "a1b2c3" 2))
(check "string-filter start end" "2" (string-filter char-numeric? "a1b2c3" 2 4))

;; --- string-delete with start/end ---
(check "string-delete full" "abc" (string-delete char-numeric? "a1b2c3"))
(check "string-delete start" "bc" (string-delete char-numeric? "a1b2c3" 2))
(check "string-delete start end" "b" (string-delete char-numeric? "a1b2c3" 2 4))

;; --- string-reverse with start/end ---
(check "string-reverse full" "cba" (string-reverse "abc"))
(check "string-reverse start" "cba" (string-reverse "xxabc" 2))
(check "string-reverse start end" "cb" (string-reverse "abcde" 1 3))

;; --- string-titlecase with start/end ---
(check "string-titlecase full" "Hello World" (string-titlecase "hello world"))
(check "string-titlecase start" "World" (string-titlecase "hello world" 6))

;; --- string-trim with start/end ---
(check "string-trim basic" "hello  " (string-trim "  hello  "))
(check "string-trim pred+start"
  "lo" (string-trim "hello" char-upper-case? 3))

;; --- string-trim-right with start/end ---
(check "string-trim-right basic" "  hello" (string-trim-right "  hello  "))

;; --- string-trim-both with start/end ---
(check "string-trim-both basic" "hello" (string-trim-both "  hello  "))

;; --- Unicode start/end ---
(check "string-index unicode start"
  2 (string-index "αβγδ" char-lower-case? 2))
(check "string-count unicode range"
  2 (string-count "a1β2γ3" char-numeric? 1 5))

(display pass) (display " pass, ")
(display fail) (display " fail")
(newline)
(if (> fail 0) (exit 1))
