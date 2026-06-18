;;; R7RS String compliance tests
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "strings")

;; --- string constructor ---
(test-group "string constructor"
  (test-equal "string from chars" "abc" (string #\a #\b #\c))
  (test-equal "string from no chars" "" (string)))

;; --- make-string ---
(test-group "make-string"
  (test-eqv "make-string length" 5 (string-length (make-string 5)))
  (test-equal "make-string with fill char" "xxx" (make-string 3 #\x)))

;; --- string-ref ---
(test-group "string-ref"
  (test-eqv "string-ref first" #\h (string-ref "hello" 0))
  (test-eqv "string-ref last" #\o (string-ref "hello" 4)))

;; --- string-length ---
(test-group "string-length"
  (test-eqv "string-length non-empty" 5 (string-length "hello"))
  (test-eqv "string-length empty" 0 (string-length "")))

;; --- substring ---
(test-group "substring"
  (test-equal "substring first word" "hello" (substring "hello world" 0 5))
  (test-equal "substring last word" "world" (substring "hello world" 6 11))
  (test-equal "substring single char" "b" (substring "abc" 1 2)))

;; --- string-append ---
(test-group "string-append"
  (test-equal "string-append multiple" "hello world" (string-append "hello" " " "world"))
  (test-equal "string-append no args" "" (string-append)))

;; --- string-copy ---
(test-group "string-copy"
  (test-equal "string-copy whole" "hello" (string-copy "hello"))
  (test-equal "string-copy with range" "el" (string-copy "hello" 1 3)))

;; --- string->list ---
(test-group "string->list"
  (test-equal "string->list non-empty" '(#\a #\b #\c) (string->list "abc"))
  (test-equal "string->list empty" '() (string->list "")))

;; --- list->string ---
(test-group "list->string"
  (test-equal "list->string non-empty" "abc" (list->string '(#\a #\b #\c)))
  (test-equal "list->string empty" "" (list->string '())))

;; --- string->symbol ---
(test-group "string->symbol"
  (test-eqv "string->symbol value" 'hello (string->symbol "hello"))
  (test-assert "string->symbol returns symbol" (symbol? (string->symbol "test"))))

;; --- symbol->string ---
(test-group "symbol->string"
  (test-equal "symbol->string" "hello" (symbol->string 'hello)))

;; --- string comparisons ---
(test-group "string comparisons"
  (test-assert "string<? true" (string<? "abc" "abd"))
  (test-assert "string<? false" (not (string<? "abd" "abc")))
  (test-assert "string=? true" (string=? "abc" "abc"))
  (test-assert "string=? false" (not (string=? "abc" "abd")))
  (test-assert "string>? true" (string>? "abd" "abc"))
  (test-assert "string<=? equal" (string<=? "abc" "abc"))
  (test-assert "string>=? equal" (string>=? "abc" "abc")))

;; --- char->integer, integer->char ---
(test-group "char->integer, integer->char"
  (test-eqv "char->integer A" 65 (char->integer #\A))
  (test-eqv "char->integer a" 97 (char->integer #\a))
  (test-eqv "integer->char 65" #\A (integer->char 65))
  (test-eqv "integer->char 97" #\a (integer->char 97)))

;; --- char comparisons ---
(test-group "char comparisons"
  (test-assert "char<? true" (char<? #\a #\b))
  (test-assert "char=? true" (char=? #\a #\a))
  (test-assert "char>? true" (char>? #\b #\a)))

;; --- number->string ---
(test-group "number->string"
  (test-equal "number->string positive" "42" (number->string 42))
  (test-equal "number->string negative" "-7" (number->string -7)))

;; --- string->number ---
(test-group "string->number"
  (test-eqv "string->number valid" 42 (string->number "42"))
  (test-eqv "string->number invalid" #f (string->number "bad")))

;; --- string-set! ---
(test-group "string-set!"
  (test-equal "string-set! first char"
    "Hello"
    (let ((s (string-copy "hello")))
      (string-set! s 0 #\H)
      s)))

;; --- string-fill! ---
(test-group "string-fill!"
  (test-equal "string-fill! all"
    "zzz"
    (let ((sf (make-string 3 #\a)))
      (string-fill! sf #\z)
      sf)))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "strings")
(if (> %test-fail-count 0) (exit 1))
