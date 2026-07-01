;;; Regression test for #645: string-for-each/string-map desync byte cursor
;;; when callback mutates an iterated string, silently skipping characters.

(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check name expected actual)
  (if (equal? expected actual)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display name) (newline)
      (display "  expected: ") (display expected) (newline)
      (display "  actual:   ") (display actual) (newline))))

;; Shrink mutation: multi-byte to ASCII behind the cursor
(define s1 (string-copy "中bcde"))
(define chars1 '())
(string-for-each
  (lambda (c)
    (set! chars1 (cons c chars1))
    (when (char=? c #\b)
      (string-set! s1 0 #\x)))
  s1)
(check "string-for-each sees all 5 codepoints"
  5
  (length chars1))

;; string-map with mutation behind cursor
(define s2 (string-copy "中bcd"))
(define mapped
  (string-map
    (lambda (c)
      (when (char=? c #\b)
        (string-set! s2 0 #\x))
      (char-upcase c))
    s2))
(check "string-map produces correct length"
  4
  (string-length mapped))

;; No mutation: normal case still works
(define chars3 '())
(string-for-each
  (lambda (c) (set! chars3 (cons c chars3)))
  "hello")
(check "string-for-each normal case"
  '(#\o #\l #\l #\e #\h)
  chars3)

;; string-map normal case
(check "string-map normal case"
  "HELLO"
  (string-map char-upcase "hello"))

(display pass) (display " pass, ") (display fail) (display " fail") (newline)
(when (> fail 0) (exit 1))
