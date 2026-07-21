;; SRFI-118 (Simple Adjustable-Size Strings) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi118.scm

(import (scheme base) (scheme process-context) (srfi 118) (srfi 64))

(test-begin "srfi-118")

;;; --- string-append! ---
(let ((s "hello"))
  (string-append! s " world")
  (test-equal "string-append!: basic" "hello world" s))

(let ((s (make-string 0)))
  (string-append! s #\a #\b #\c)
  (test-equal "string-append!: chars only" "abc" s))

(let ((s "x"))
  (string-append! s "!" #\y "z")
  (test-equal "string-append!: mixed" "x!yz" s))

(let ((s (make-string 0)))
  (string-append! s "one")
  (string-append! s "-two")
  (string-append! s "-three")
  (test-equal "string-append!: repeated growth" "one-two-three" s))

;; Example from the SRFI text: accumulate into a fresh growable string.
(define (translate-space-to-newline str)
  (let ((result (make-string 0)))
    (string-for-each
     (lambda (ch)
       (cond ((char=? ch #\space) (string-append! result #\newline))
             ((char=? ch #\return))
             (else (string-append! result ch))))
     str)
    result))

(test-equal "string-append!: spec example"
  "a\nb\nc"
  (translate-space-to-newline "a b c"))

;;; --- string-replace! ---
(let ((s "abcde"))
  (string-replace! s 1 3 "XY")
  (test-equal "string-replace!: same-length replacement" "aXYde" s))

(let ((s "abcde"))
  (string-replace! s 1 3 "XYZ")
  (test-equal "string-replace!: grow" "aXYZde" s))

(let ((s "abcde"))
  (string-replace! s 1 4 "X")
  (test-equal "string-replace!: shrink" "aXe" s))

(let ((s "abcde"))
  (string-replace! s 1 1 "XY")
  (test-equal "string-replace!: insertion (start = end)" "aXYbcde" s))

(let ((s "abcde"))
  (string-replace! s 1 3 "")
  (test-equal "string-replace!: deletion (src empty)" "ade" s))

(let ((s "abcde"))
  (string-replace! s 1 3 "XYZ" 1)
  (test-equal "string-replace!: with src-start" "aYZde" s))

(let ((s "abcde"))
  (string-replace! s 1 3 "XYZ" 0 2)
  (test-equal "string-replace!: with src-start and src-end" "aXYde" s))

;; SRFI 118 equivalence: (string-append! dst value) == (string-replace! dst end end value)
(let ((s1 "abc") (s2 "abc"))
  (string-append! s1 "def")
  (string-replace! s2 (string-length s2) (string-length s2) "def")
  (test-equal "string-append!/string-replace! equivalence" s1 s2))

(let ((runner (test-runner-current)))
  (test-end "srfi-118")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
