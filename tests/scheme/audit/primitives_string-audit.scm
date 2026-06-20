(import (scheme base) (scheme write) (scheme char))
(import (chibi test))

(test-begin "primitives_string audit")

;;; string construction
(test "abc" (string #\a #\b #\c))
(test "" (string))
(test "aaa" (make-string 3 #\a))
(test "" (make-string 0 #\x))

;;; string-ref
(test #\b (string-ref "abc" 1))
(test #\a (string-ref "abc" 0))

;;; string-set!
(let ((s (string-copy "hello")))
  (string-set! s 0 #\H)
  (test "Hello" s))

;;; substring
(test "ell" (substring "hello" 1 4))
(test "" (substring "hello" 2 2))
(test "hello" (substring "hello" 0 5))

;;; string-copy with start/end
(test "hello" (string-copy "hello"))
(test "llo" (string-copy "hello" 2))
(test "ell" (string-copy "hello" 1 4))

;;; string-copy!
(let ((s (string-copy "abcde")))
  (string-copy! s 1 "XY")
  (test "aXYde" s))
(let ((s (string-copy "abcde")))
  (string-copy! s 0 "xyz" 1 3)
  (test "yzcde" s))

;;; string-fill! (no start/end args)
(let ((s (string-copy "hello")))
  (string-fill! s #\x)
  (test "xxxxx" s))

;;; string->list with start/end
(test '(#\a #\b #\c) (string->list "abc"))
(test '(#\b #\c) (string->list "abc" 1))
(test '(#\b) (string->list "abc" 1 2))

;;; list->string
(test "abc" (list->string '(#\a #\b #\c)))
(test "" (list->string '()))

;;; string->symbol / symbol->string
(test 'hello (string->symbol "hello"))

;;; UTF-8 conversion
(test #u8(104 101 108 108 111) (string->utf8 "hello"))
(test "hello" (utf8->string #u8(104 101 108 108 111)))

;;; string-for-each
(let ((r '()))
  (string-for-each (lambda (c) (set! r (cons c r))) "abc")
  (test '(#\c #\b #\a) r))
;; Multi-string
(let ((r '()))
  (string-for-each (lambda (a b) (set! r (cons (list a b) r))) "ab" "xy")
  (test 2 (length r)))

;;; string-map
(test "ABC" (string-map char-upcase "abc"))
(test "" (string-map char-upcase ""))
;; Multi-string
(test "ab" (string-map (lambda (a b) (if (char<? a b) a b)) "ab" "xy"))

;;; string comparisons
(test #t (string<? "abc" "abd"))
(test #t (string<=? "abc" "abc"))
(test #t (string=? "abc" "abc"))
(test #t (string>=? "abd" "abc"))
(test #t (string>? "abd" "abc"))
(test #f (string=? "abc" "abd"))

;;; char operations
(test 65 (char->integer #\A))
(test #\A (integer->char 65))
(test #t (char<? #\a #\b))
(test #t (char<=? #\a #\a))
(test #t (char=? #\a #\a))
(test #t (char>=? #\b #\a))
(test #t (char>? #\b #\a))

;;; Error paths — callback error in string-for-each
(test #t (guard (e (#t (error-object? e)))
  (string-for-each (lambda (c) (error "stop")) "abc")))
;;; Error paths — callback error in string-map
(test #t (guard (e (#t (error-object? e)))
  (string-map (lambda (c) (error "stop")) "abc")))
;;; Type errors
(test #t (guard (e (#t #t)) (string-ref 42 0)))
(test #t (guard (e (#t #t)) (string-ref "abc" -1)))

;;; string->vector with start/end
(test #(#\a #\b #\c) (string->vector "abc"))
(test #(#\b #\c) (string->vector "abc" 1))
(test #(#\b) (string->vector "abc" 1 2))

(test-end "primitives_string audit")
