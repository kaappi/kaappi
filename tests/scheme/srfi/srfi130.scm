;; SRFI-130 (cursor-based string library) conformance tests — Phase 3e
;; Kaappi represents cursors as codepoint indexes, which SRFI-130 permits.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi130.scm

(import (scheme base) (srfi 130) (chibi test))

(test-begin "srfi-130")

;;; --- cursor basics ---
(define s "hello")
(test #t (string-cursor? (string-cursor-start s)))
(test #t (string-cursor=? (string-cursor-start s) (string-index->cursor s 0)))
(test 0 (string-cursor->index s (string-cursor-start s)))
(test 5 (string-cursor->index s (string-cursor-end s)))

(let ((c (string-cursor-start s)))
  (test #\h (string-cursor-ref s c))
  (test #\e (string-cursor-ref s (string-cursor-next s c)))
  (test 2 (string-cursor->index s (string-cursor-forward s c 2)))
  (test #t (string-cursor<? c (string-cursor-next s c)))
  (test #t (string-cursor<=? c c))
  (test #t (string-cursor>=? (string-cursor-end s) c)))

(let ((e (string-cursor-end s)))
  (test #\o (string-cursor-ref s (string-cursor-prev s e)))
  (test 3 (string-cursor->index s (string-cursor-back s e 2))))

;;; --- substring/cursors ---
(test "ell" (substring/cursors s (string-index->cursor s 1) (string-index->cursor s 4)))
(test "" (substring/cursors s (string-cursor-start s) (string-cursor-start s)))

;;; --- searching ---
(test 2 (string-cursor->index s (string-contains s "ll")))
(test #f (string-contains s "xyz"))
(test 0 (string-cursor->index s (string-contains s "")))
(test 3 (string-cursor->index "abcabc" (string-contains-right "abcabc" "abc")))

;;; --- prefixes/suffixes ---
(test #t (string-prefix? "he" s))
(test #f (string-prefix? "lo" s))
(test #t (string-suffix? "lo" s))
(test #f (string-suffix? "he" s))
(test #t (string-prefix? "" s))

;;; --- take/drop/count/filter/remove ---
(test "he" (string-take s 2))
(test "llo" (string-drop s 2))
(test "lo" (string-take-right s 2))
(test "hel" (string-drop-right s 2))
(test 2 (string-count s (lambda (c) (char=? c #\l))))
(test "ll" (string-filter (lambda (c) (char=? c #\l)) s))
(test "heo" (string-remove (lambda (c) (char=? c #\l)) s))

;;; --- multibyte: cursors are codepoint positions ---
(define u "aλ𝄞b")
(test 4 (string-cursor->index u (string-cursor-end u)))
(test #\x3bb (string-cursor-ref u (string-cursor-next u (string-cursor-start u))))
(test "λ𝄞" (substring/cursors u (string-index->cursor u 1) (string-index->cursor u 3)))
(test 1 (string-cursor->index u (string-contains u "λ")))

(test-end "srfi-130")
