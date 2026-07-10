(import (scheme base) (scheme write) (scheme char))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_string audit")

;;; string construction
(test-equal "abc" (string #\a #\b #\c))
(test-equal "" (string))
(test-equal "aaa" (make-string 3 #\a))
(test-equal "" (make-string 0 #\x))

;;; string-ref
(test-equal #\b (string-ref "abc" 1))
(test-equal #\a (string-ref "abc" 0))

;;; string-set!
(let ((s (string-copy "hello")))
  (string-set! s 0 #\H)
  (test-equal "Hello" s))

;;; substring
(test-equal "ell" (substring "hello" 1 4))
(test-equal "" (substring "hello" 2 2))
(test-equal "hello" (substring "hello" 0 5))

;;; string-copy with start/end
(test-equal "hello" (string-copy "hello"))
(test-equal "llo" (string-copy "hello" 2))
(test-equal "ell" (string-copy "hello" 1 4))

;;; string-copy!
(let ((s (string-copy "abcde")))
  (string-copy! s 1 "XY")
  (test-equal "aXYde" s))
(let ((s (string-copy "abcde")))
  (string-copy! s 0 "xyz" 1 3)
  (test-equal "yzcde" s))

;;; string-fill! (no start/end args)
(let ((s (string-copy "hello")))
  (string-fill! s #\x)
  (test-equal "xxxxx" s))

;;; string->list with start/end
(test-equal '(#\a #\b #\c) (string->list "abc"))
(test-equal '(#\b #\c) (string->list "abc" 1))
(test-equal '(#\b) (string->list "abc" 1 2))

;;; list->string
(test-equal "abc" (list->string '(#\a #\b #\c)))
(test-equal "" (list->string '()))

;;; string->symbol / symbol->string
(test-equal 'hello (string->symbol "hello"))

;;; UTF-8 conversion
(test-equal #u8(104 101 108 108 111) (string->utf8 "hello"))
(test-equal "hello" (utf8->string #u8(104 101 108 108 111)))

;;; string-for-each
(let ((r '()))
  (string-for-each (lambda (c) (set! r (cons c r))) "abc")
  (test-equal '(#\c #\b #\a) r))
;; Multi-string
(let ((r '()))
  (string-for-each (lambda (a b) (set! r (cons (list a b) r))) "ab" "xy")
  (test-equal 2 (length r)))

;;; string-map
(test-equal "ABC" (string-map char-upcase "abc"))
(test-equal "" (string-map char-upcase ""))
;; Multi-string
(test-equal "ab" (string-map (lambda (a b) (if (char<? a b) a b)) "ab" "xy"))

;;; string comparisons
(test-equal #t (string<? "abc" "abd"))
(test-equal #t (string<=? "abc" "abc"))
(test-equal #t (string=? "abc" "abc"))
(test-equal #t (string>=? "abd" "abc"))
(test-equal #t (string>? "abd" "abc"))
(test-equal #f (string=? "abc" "abd"))

;;; char operations
(test-equal 65 (char->integer #\A))
(test-equal #\A (integer->char 65))
(test-equal #t (char<? #\a #\b))
(test-equal #t (char<=? #\a #\a))
(test-equal #t (char=? #\a #\a))
(test-equal #t (char>=? #\b #\a))
(test-equal #t (char>? #\b #\a))

;;; Error paths — callback error in string-for-each
(test-equal #t (guard (e (#t (error-object? e)))
  (string-for-each (lambda (c) (error "stop")) "abc")))
;;; Error paths — callback error in string-map
(test-equal #t (guard (e (#t (error-object? e)))
  (string-map (lambda (c) (error "stop")) "abc")))
;;; Type errors
(test-equal #t (guard (e (#t #t)) (string-ref 42 0)))
(test-equal #t (guard (e (#t #t)) (string-ref "abc" -1)))

;;; string->vector with start/end
(test-equal #(#\a #\b #\c) (string->vector "abc"))
(test-equal #(#\b #\c) (string->vector "abc" 1))
(test-equal #(#\b) (string->vector "abc" 1 2))

(let ((runner (test-runner-current)))
  (test-end "primitives_string audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
