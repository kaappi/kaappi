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

;; Extract
(check "extract" (regexp-extract '(+ alphabetic) "hello 42 world") '("hello" "world"))

;; Split
(check "split" (regexp-split " " "hello world foo") '("hello" "world" "foo"))
(check "split comma" (regexp-split ", " "a, b, c") '("a" "b" "c"))

;; Partition
(let ((p (regexp-partition '(+ numeric) "abc123def456")))
  (check "partition" p '("abc" "123" "def" "456" "")))

;; Replace
(check "replace" (regexp-replace "world" "hello world" "there") "hello there")
(check "replace-all" (regexp-replace-all "o" "foo boo" "0") "f00 b00")

;; Char ranges
(check-true "range az" (regexp-matches? '(+ (/ "az")) "hello"))
(check-false "range az fail" (regexp-matches? '(+ (/ "az")) "HELLO"))
(check-true "range AZaz" (regexp-matches? '(+ (/ "azAZ")) "helloWORLD"))

;; Complement
(check-true "compl" (regexp-matches? '(+ (~ numeric)) "hello"))

;; Look-ahead
(check-true "look" (regexp-matches? '(: (look-ahead "ab") "ab" "c") "abc"))
(check-false "neglook" (regexp-matches? '(: (neg-look-ahead "ab") "ab") "ab"))

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
