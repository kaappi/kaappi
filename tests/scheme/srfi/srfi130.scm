;; SRFI-130 (cursor-based string library) conformance tests — Phase 3e
;; Kaappi represents cursors as codepoint indexes, which SRFI-130 permits.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi130.scm

(import (scheme base) (srfi 130) (scheme process-context) (srfi 64))

(test-begin "srfi-130")

;;; --- cursor basics ---
(define s "hello")
(test-equal #t (string-cursor? (string-cursor-start s)))
(test-equal #t (string-cursor=? (string-cursor-start s) (string-index->cursor s 0)))
(test-equal 0 (string-cursor->index s (string-cursor-start s)))
(test-equal 5 (string-cursor->index s (string-cursor-end s)))

(let ((c (string-cursor-start s)))
  (test-equal #\h (string-cursor-ref s c))
  (test-equal #\e (string-cursor-ref s (string-cursor-next s c)))
  (test-equal 2 (string-cursor->index s (string-cursor-forward s c 2)))
  (test-equal #t (string-cursor<? c (string-cursor-next s c)))
  (test-equal #t (string-cursor<=? c c))
  (test-equal #t (string-cursor>=? (string-cursor-end s) c)))

(let ((e (string-cursor-end s)))
  (test-equal #\o (string-cursor-ref s (string-cursor-prev s e)))
  (test-equal 3 (string-cursor->index s (string-cursor-back s e 2))))

;;; --- substring/cursors ---
(test-equal "ell" (substring/cursors s (string-index->cursor s 1) (string-index->cursor s 4)))
(test-equal "" (substring/cursors s (string-cursor-start s) (string-cursor-start s)))

;;; --- searching ---
(test-equal 2 (string-cursor->index s (string-contains s "ll")))
(test-equal #f (string-contains s "xyz"))
(test-equal 0 (string-cursor->index s (string-contains s "")))
(test-equal 3 (string-cursor->index "abcabc" (string-contains-right "abcabc" "abc")))

;;; --- prefixes/suffixes ---
(test-equal #t (string-prefix? "he" s))
(test-equal #f (string-prefix? "lo" s))
(test-equal #t (string-suffix? "lo" s))
(test-equal #f (string-suffix? "he" s))
(test-equal #t (string-prefix? "" s))

;;; --- take/drop/count/filter/remove ---
(test-equal "he" (string-take s 2))
(test-equal "llo" (string-drop s 2))
(test-equal "lo" (string-take-right s 2))
(test-equal "hel" (string-drop-right s 2))
(test-equal 2 (string-count s (lambda (c) (char=? c #\l))))
(test-equal "ll" (string-filter (lambda (c) (char=? c #\l)) s))
(test-equal "heo" (string-remove (lambda (c) (char=? c #\l)) s))

;;; --- multibyte: cursors are codepoint positions ---
(define u "aλ𝄞b")
(test-equal 4 (string-cursor->index u (string-cursor-end u)))
(test-equal #\x3bb (string-cursor-ref u (string-cursor-next u (string-cursor-start u))))
(test-equal "λ𝄞" (substring/cursors u (string-index->cursor u 1) (string-index->cursor u 3)))
(test-equal 1 (string-cursor->index u (string-contains u "λ")))

(let ((runner (test-runner-current)))
  (test-end "srfi-130")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
