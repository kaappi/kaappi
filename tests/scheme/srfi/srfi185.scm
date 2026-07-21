;; SRFI-185 (Linear adjustable-length strings) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi185.scm

(import (scheme base) (scheme process-context) (srfi 185) (srfi 64))

(test-begin "srfi-185")

;;; --- string-append-linear! ---
(test-equal "string-append-linear!: strings"
  "hello world" (string-append-linear! "hello" " " "world"))
(test-equal "string-append-linear!: chars"
  "abc" (string-append-linear! "a" #\b "c"))
(test-equal "string-append-linear!: single"
  "hello" (string-append-linear! "hello"))
(test-equal "string-append-linear!: empty"
  "" (string-append-linear! ""))
(test-equal "string-append-linear!: mixed"
  "x!y" (string-append-linear! "x" #\! "y"))

;;; --- string-replace-linear! ---
(test-equal "string-replace-linear!: basic"
  "aXYde" (string-replace-linear! "abcde" 1 3 "XY"))
(test-equal "string-replace-linear!: with src-start"
  "aYde" (string-replace-linear! "abcde" 1 3 "XY" 1))
(test-equal "string-replace-linear!: with src-start and src-end"
  "aXde" (string-replace-linear! "abcde" 1 3 "XYZ" 0 1))
(test-equal "string-replace-linear!: empty replacement"
  "ade" (string-replace-linear! "abcde" 1 3 ""))
(test-equal "string-replace-linear!: insert"
  "aXYbcde" (string-replace-linear! "abcde" 1 1 "XY"))

;;; --- string-append! macro ---
(let ((s "hello"))
  (string-append! s " world")
  (test-equal "string-append!: basic mutation" "hello world" s))

(let ((s "a"))
  (string-append! s #\b #\c)
  (test-equal "string-append!: char args" "abc" s))

;;; --- string-replace! macro ---
(let ((s "abcde"))
  (string-replace! s 1 3 "XY")
  (test-equal "string-replace!: basic mutation" "aXYde" s))

(let ((s "abcde"))
  (string-replace! s 1 3 "XYZ" 0 2)
  (test-equal "string-replace!: with bounds" "aXYde" s))

(let ((runner (test-runner-current)))
  (test-end "srfi-185")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
