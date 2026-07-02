;; Regression tests for #855 (char literal semicolon) and #829 (string-prefix?/suffix?)

;; #855: write of control chars should not emit trailing semicolon
(let* ((p (open-output-string))
       (_ (write (list #\x05 1 2) p))
       (s (get-output-string p)))
  (display (equal? (read (open-input-string s)) (list #\x05 1 2)))
  (newline))

;; #829: string-prefix? optional args apply to s1, not s2
(import (srfi 13))
(display (string-prefix? "hello" "hell" 0 2))  ; s1[0:2]="he" is prefix of "hell" => #t
(newline)
(display (string-suffix? "hello" "llo" 2))      ; s1[2:]="llo" is suffix of "llo" => #t
(newline)
(display (string-prefix? "abc" "abcdef"))        ; basic: "abc" is prefix of "abcdef" => #t
(newline)
(display (string-prefix? "xyz" "abcdef"))        ; basic: "xyz" is NOT prefix => #f
(newline)
