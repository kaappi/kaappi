;; SRFI-132 (sort libraries) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi132.scm

(import (scheme base) (srfi 132) (srfi 64))

(test-begin "srfi-132")

;;; --- list-sorted? ---
(test-equal "list-sorted?: empty" #t (list-sorted? < '()))
(test-equal "list-sorted?: singleton" #t (list-sorted? < '(1)))
(test-equal "list-sorted?: sorted with dups" #t (list-sorted? < '(1 2 2 3)))
(test-equal "list-sorted?: unsorted" #f (list-sorted? < '(1 3 2)))

;;; --- vector-sorted? (with optional start/end) ---
(test-equal "vector-sorted?: empty" #t (vector-sorted? < #()))
(test-equal "vector-sorted?: sorted" #t (vector-sorted? < #(1 2 2 3)))
(test-equal "vector-sorted?: unsorted" #f (vector-sorted? < #(2 1)))
(test-equal "vector-sorted?: subrange sorted"
  #t (vector-sorted? < #(9 1 2 3 0) 1 4))
(test-equal "vector-sorted?: subrange unsorted"
  #f (vector-sorted? < #(1 2 3 0 5) 2 5))
(test-equal "vector-sorted?: start only"
  #t (vector-sorted? < #(9 1 2 3) 1))

;;; --- list-sort / list-stable-sort / list-sort! / list-stable-sort! ---
(test-equal "list-sort: empty" '() (list-sort < '()))
(test-equal "list-sort: singleton" '(1) (list-sort < '(1)))
(test-equal "list-sort: multiple" '(1 1 3 4 5 9) (list-sort < '(3 1 4 1 5 9)))
(test-equal "list-sort: reverse" '(9 5 4 3 1 1) (list-sort > '(3 1 4 1 5 9)))
(test-equal "list-sort: already sorted" '(1 2 3) (list-sort < '(1 2 3)))
(test-equal "list-sort!: basic" '(1 1 3 4 5 9) (list-sort! < (list 3 1 4 1 5 9)))
(test-equal "list-stable-sort!: basic"
  '(1 2 3) (list-stable-sort! < (list 3 1 2)))

;; non-destructive: input unchanged
(define src '(3 1 2))
(test-equal "list-sort: non-destructive result" '(1 2 3) (list-sort < src))
(test-equal "list-sort: non-destructive input" '(3 1 2) src)

;; stability: equal keys keep original relative order
(define recs '((2 . a) (1 . b) (2 . c) (1 . d)))
(test-equal "list-stable-sort: stability"
  '((1 . b) (1 . d) (2 . a) (2 . c))
  (list-stable-sort (lambda (x y) (< (car x) (car y))) recs))

;;; --- vector-sort / vector-stable-sort / vector-sort! / vector-stable-sort! ---
(test-equal "vector-sort: basic" #(1 1 3 4 5 9) (vector-sort < #(3 1 4 1 5 9)))
(test-equal "vector-sort: empty" #() (vector-sort < #()))

(define vsrc (vector 3 1 2))
(test-equal "vector-sort: non-destructive result" #(1 2 3) (vector-sort < vsrc))
(test-equal "vector-sort: non-destructive input" #(3 1 2) vsrc)

(vector-sort! < vsrc)
(test-equal "vector-sort!: mutates" #(1 2 3) vsrc)

;; start/end parameters
(test-equal "vector-sort: start/end"
  #(2 3 4) (vector-sort < #(9 4 3 2 9) 1 4))
(test-equal "vector-sort: start only"
  #(2 3 9) (vector-sort < #(5 9 3 2) 1))

(let ((v (vector 5 3 1 4 2)))
  (vector-sort! < v 1 4)
  (test-equal "vector-sort!: subrange" #(5 1 3 4 2) v))

;; stability
(test-equal "vector-stable-sort: stability"
  #((1 . b) (1 . d) (2 . a) (2 . c))
  (vector-stable-sort (lambda (x y) (< (car x) (car y)))
                      (vector '(2 . a) '(1 . b) '(2 . c) '(1 . d))))

(let ((v (vector 5 3 1 4 2)))
  (vector-stable-sort! < v)
  (test-equal "vector-stable-sort!: mutates" #(1 2 3 4 5) v))

;;; --- list-merge / list-merge! ---
(test-equal "list-merge: basic"
  '(1 2 3 4 5 6) (list-merge < '(1 3 5) '(2 4 6)))
(test-equal "list-merge: empty first"
  '(1 2 3) (list-merge < '() '(1 2 3)))
(test-equal "list-merge: empty second"
  '(1 2 3) (list-merge < '(1 2 3) '()))
(test-equal "list-merge: both empty"
  '() (list-merge < '() '()))
(test-equal "list-merge: duplicates"
  '(1 1 2 2 3 3) (list-merge < '(1 2 3) '(1 2 3)))
(test-equal "list-merge!: basic"
  '(1 2 3 4 5 6) (list-merge! < '(1 3 5) '(2 4 6)))

;; stability: on ties, first list's element comes first
(test-equal "list-merge: stability"
  '((1 . a) (1 . b) (2 . a) (2 . b))
  (list-merge (lambda (x y) (< (car x) (car y)))
              '((1 . a) (2 . a))
              '((1 . b) (2 . b))))

;;; --- vector-merge / vector-merge! ---
(test-equal "vector-merge: basic"
  #(1 2 3 4 5 6) (vector-merge < #(1 3 5) #(2 4 6)))
(test-equal "vector-merge: empty inputs"
  #() (vector-merge < #() #()))
(test-equal "vector-merge: one empty"
  #(1 2 3) (vector-merge < #(1 2 3) #()))
(test-equal "vector-merge: with subranges"
  #(2 3 4 5) (vector-merge < #(9 2 4 8) #(0 3 5 7) 1 3 1 3))

(let ((target (make-vector 6 0)))
  (vector-merge! < target #(1 3 5) #(2 4 6))
  (test-equal "vector-merge!: basic" #(1 2 3 4 5 6) target))

(let ((target (make-vector 8 0)))
  (vector-merge! < target #(1 3 5) #(2 4 6) 1)
  (test-equal "vector-merge!: with start offset" #(0 1 2 3 4 5 6 0) target))

;;; --- list-delete-neighbor-dups ---
(test-equal "list-delete-neighbor-dups: basic"
  '(1 2 3) (list-delete-neighbor-dups = '(1 1 2 2 3)))
(test-equal "list-delete-neighbor-dups: no dups"
  '(1 2 7 0 -2) (list-delete-neighbor-dups = '(1 2 7 0 -2)))
(test-equal "list-delete-neighbor-dups: all same"
  '(5) (list-delete-neighbor-dups = '(5 5 5 5)))
(test-equal "list-delete-neighbor-dups: empty"
  '() (list-delete-neighbor-dups = '()))
(test-equal "list-delete-neighbor-dups: singleton"
  '(1) (list-delete-neighbor-dups = '(1)))
(test-equal "list-delete-neighbor-dups: unsorted with neighbors"
  '(1 2 7 0 -2) (list-delete-neighbor-dups = '(1 1 2 7 7 7 0 -2 -2)))
(test-equal "list-delete-neighbor-dups!: basic"
  '(1 2 3) (list-delete-neighbor-dups! = '(1 1 2 2 3)))

;;; --- vector-delete-neighbor-dups ---
(test-equal "vector-delete-neighbor-dups: basic"
  #(1 2 7 0 -2) (vector-delete-neighbor-dups = #(1 1 2 7 7 7 0 -2 -2)))
(test-equal "vector-delete-neighbor-dups: empty"
  #() (vector-delete-neighbor-dups = #()))
(test-equal "vector-delete-neighbor-dups: no dups"
  #(1 2 3) (vector-delete-neighbor-dups = #(1 2 3)))
(test-equal "vector-delete-neighbor-dups: subrange"
  #(1 2 3) (vector-delete-neighbor-dups = #(0 1 1 2 2 3 3 9) 1 7))

;;; --- vector-delete-neighbor-dups! (returns end index) ---
(let ((v (vector 1 1 2 2 3 3)))
  (test-equal "vector-delete-neighbor-dups!: returns end index"
    3 (vector-delete-neighbor-dups! = v))
  (test-equal "vector-delete-neighbor-dups!: packed elements"
    1 (vector-ref v 0))
  (test-equal "vector-delete-neighbor-dups!: packed elements 2"
    2 (vector-ref v 1))
  (test-equal "vector-delete-neighbor-dups!: packed elements 3"
    3 (vector-ref v 2)))

(let ((v (vector 0 0 0 1 1 2 2 3 3 4 4 5 5 6 6)))
  (test-equal "vector-delete-neighbor-dups!: with start"
    9 (vector-delete-neighbor-dups! = v 3)))

(test-equal "vector-delete-neighbor-dups!: empty range"
  3 (vector-delete-neighbor-dups! = #(1 2 3) 3 3))

;;; --- vector-find-median / vector-find-median! ---
(test-equal "vector-find-median: odd count"
  3 (vector-find-median < #(5 1 3 4 2) 'empty))
(test-equal "vector-find-median: empty"
  'empty (vector-find-median < #() 'empty))
(test-equal "vector-find-median: singleton"
  42 (vector-find-median < #(42) 'empty))
(test-equal "vector-find-median: even count default mean"
  5/2 (vector-find-median < #(1 2 3 4) 'empty))
(test-equal "vector-find-median: custom mean"
  3 (vector-find-median < #(1 2 3 4) 'empty max))

(let ((v (vector 5 1 3 4 2)))
  (test-equal "vector-find-median!: odd count"
    3 (vector-find-median! < v 'empty))
  (test-equal "vector-find-median!: sorts in place"
    #(1 2 3 4 5) v))

;;; --- vector-select! ---
(test-equal "vector-select!: minimum"
  1 (vector-select! < (vector 5 3 1 4 2) 0))
(test-equal "vector-select!: median"
  3 (vector-select! < (vector 5 3 1 4 2) 2))
(test-equal "vector-select!: maximum"
  5 (vector-select! < (vector 5 3 1 4 2) 4))
(test-equal "vector-select!: subrange"
  2 (vector-select! < (vector 9 5 3 1 4 2 8) 1 1 6))

;;; --- vector-separate! ---
(let ((v (vector 5 3 1 4 2)))
  (vector-separate! < v 2)
  (test-equal "vector-separate!: smallest 2 in first positions"
    1 (vector-ref v 0))
  (test-equal "vector-separate!: smallest 2 in first positions (2)"
    2 (vector-ref v 1)))

(let ((runner (test-runner-current)))
  (test-end "srfi-132")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
