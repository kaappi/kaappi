;; SRFI-95 (Sorting and Merging) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi95.scm

(import (scheme base) (scheme process-context) (srfi 95) (srfi 64))

(test-begin "srfi-95")

;;; --- sorted? on lists ---
(test-assert "sorted?: empty list" (sorted? '() <))
(test-assert "sorted?: single element" (sorted? '(1) <))
(test-assert "sorted?: sorted list" (sorted? '(1 2 3 4 5) <))
(test-assert "sorted?: unsorted list" (not (sorted? '(3 1 2) <)))
(test-assert "sorted?: equal elements" (sorted? '(1 1 1) <))
(test-assert "sorted?: descending with >" (sorted? '(5 4 3 2 1) >))
(test-assert "sorted?: two elements sorted" (sorted? '(1 2) <))
(test-assert "sorted?: two elements unsorted" (not (sorted? '(2 1) <)))

;;; --- sorted? on vectors ---
(test-assert "sorted?: empty vector" (sorted? #() <))
(test-assert "sorted?: single vector" (sorted? #(1) <))
(test-assert "sorted?: sorted vector" (sorted? #(1 2 3 4 5) <))
(test-assert "sorted?: unsorted vector" (not (sorted? #(3 1 2) <)))
(test-assert "sorted?: equal vector" (sorted? #(1 1 1) <))

;;; --- sorted? on strings ---
(test-assert "sorted?: sorted string" (sorted? "abcde" char<?))
(test-assert "sorted?: unsorted string" (not (sorted? "dcba" char<?)))
(test-assert "sorted?: empty string" (sorted? "" char<?))
(test-assert "sorted?: single char string" (sorted? "a" char<?))

;;; --- sorted? with key ---
(test-assert "sorted? with key on list"
  (sorted? '((1 . a) (2 . b) (3 . c)) < car))
(test-assert "sorted? with key on list unsorted"
  (not (sorted? '((3 . a) (1 . b) (2 . c)) < car)))
(test-assert "sorted? with key on vector"
  (sorted? #((1 . a) (2 . b) (3 . c)) < car))

;;; --- sort on lists ---
(test-equal "sort: empty list" '() (sort '() <))
(test-equal "sort: single element" '(1) (sort '(1) <))
(test-equal "sort: already sorted" '(1 2 3) (sort '(1 2 3) <))
(test-equal "sort: reverse sorted" '(1 2 3) (sort '(3 2 1) <))
(test-equal "sort: random order" '(1 1 3 4 5) (sort '(3 1 4 1 5) <=))
(test-equal "sort: duplicates" '(1 1 2 2 3 3) (sort '(3 1 2 1 3 2) <))
(test-equal "sort: negative numbers" '(-3 -2 -1 0 1 2 3)
  (sort '(3 -1 0 2 -3 1 -2) <))

;;; --- sort preserves original (non-destructive) ---
(let ((original (list 3 1 2)))
  (let ((result (sort original <)))
    (test-equal "sort: result is sorted" '(1 2 3) result)
    (test-equal "sort: original unchanged" '(3 1 2) original)))

;;; --- sort on vectors ---
(test-equal "sort: empty vector" #() (sort #() <))
(test-equal "sort: single vector" #(1) (sort #(1) <))
(test-equal "sort: vector" #(1 2 3 4 5) (sort #(5 3 1 4 2) <))
(test-equal "sort: vector with dups" #(1 1 2 3) (sort #(3 1 2 1) <))

;;; --- sort preserves original vector ---
(let ((original (vector 3 1 2)))
  (let ((result (sort original <)))
    (test-equal "sort: vector result sorted" #(1 2 3) result)
    (test-equal "sort: original vector unchanged" #(3 1 2) original)))

;;; --- sort on strings ---
(test-equal "sort: empty string" "" (sort "" char<?))
(test-equal "sort: string" "abcde" (sort "edcba" char<?))
(test-equal "sort: single char string" "a" (sort "a" char<?))

;;; --- sort with key ---
(test-equal "sort with key"
  '((1 . c) (2 . a) (3 . b))
  (sort '((3 . b) (1 . c) (2 . a)) < car))
(test-equal "sort with key on vector"
  #((1 . c) (2 . a) (3 . b))
  (sort #((3 . b) (1 . c) (2 . a)) < car))

;;; --- sort! on lists (destructive) ---
(let ((lst (list 3 1 2)))
  (let ((result (sort! lst <)))
    (test-equal "sort!: list sorted" '(1 2 3) result)
    (test-assert "sort!: returns same pair" (eq? result lst))))

;;; --- sort! on vectors (destructive) ---
(let ((vec (vector 3 1 2)))
  (let ((result (sort! vec <)))
    (test-equal "sort!: vector sorted" #(1 2 3) result)
    (test-assert "sort!: returns same vector" (eq? result vec))))

;;; --- sort! on empty ---
(test-equal "sort!: empty list" '() (sort! '() <))
(test-equal "sort!: empty vector" #() (sort! #() <))

;;; --- sort! with key ---
(let ((lst (list '(3 . b) '(1 . c) '(2 . a))))
  (test-equal "sort! with key"
    '((1 . c) (2 . a) (3 . b))
    (sort! lst < car)))

;;; --- merge ---
(test-equal "merge: both empty" '() (merge '() '() <))
(test-equal "merge: first empty" '(1 2 3) (merge '() '(1 2 3) <))
(test-equal "merge: second empty" '(1 2 3) (merge '(1 2 3) '() <))
(test-equal "merge: interleaved"
  '(1 2 3 4 5 6)
  (merge '(1 3 5) '(2 4 6) <))
(test-equal "merge: overlapping"
  '(1 2 2 3 4 5)
  (merge '(1 2 4) '(2 3 5) <))
(test-equal "merge: all same"
  '(1 1 1 1)
  (merge '(1 1) '(1 1) <))

;;; --- merge with key ---
(test-equal "merge with key"
  '((1 . a) (2 . b) (3 . c) (4 . d))
  (merge '((1 . a) (3 . c)) '((2 . b) (4 . d)) < car))

;;; --- merge! (destructive) ---
(let ((a (list 1 3 5))
      (b (list 2 4 6)))
  (test-equal "merge!: interleaved"
    '(1 2 3 4 5 6)
    (merge! a b <)))
(let ((a (list 1 2 4))
      (b (list 2 3 5)))
  (test-equal "merge!: overlapping"
    '(1 2 2 3 4 5)
    (merge! a b <)))
(test-equal "merge!: first empty" '(1 2) (merge! '() (list 1 2) <))
(test-equal "merge!: second empty" '(1 2) (merge! (list 1 2) '() <))

;;; --- merge! with key ---
(let ((a (list '(1 . a) '(3 . c)))
      (b (list '(2 . b) '(4 . d))))
  (test-equal "merge! with key"
    '((1 . a) (2 . b) (3 . c) (4 . d))
    (merge! a b < car)))

;;; --- larger sort ---
(test-equal "sort: 10 elements"
  '(0 1 2 3 4 5 6 7 8 9)
  (sort '(9 7 5 3 1 0 2 4 6 8) <))

;;; --- stability (sort is stable) ---
;; Elements with equal keys preserve their relative order.
(let ((data '((1 . a) (2 . b) (1 . c) (2 . d) (1 . e))))
  (let ((result (sort data < car)))
    (test-equal "sort: stability"
      '((1 . a) (1 . c) (1 . e) (2 . b) (2 . d))
      result)))

;;; --- string comparison via sort ---
(test-equal "sort: list of strings"
  '("apple" "banana" "cherry")
  (sort '("cherry" "apple" "banana") string<?))

(let ((runner (test-runner-current)))
  (test-end "srfi-95")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
