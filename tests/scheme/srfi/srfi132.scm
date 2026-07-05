;; SRFI-132 (sort libraries) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi132.scm

(import (scheme base) (srfi 132) (chibi test))

(test-begin "srfi-132")

;;; --- list-sorted? / vector-sorted? ---
(test #t (list-sorted? < '()))
(test #t (list-sorted? < '(1)))
(test #t (list-sorted? < '(1 2 2 3)))
(test #f (list-sorted? < '(1 3 2)))
(test #t (vector-sorted? < #()))
(test #t (vector-sorted? < #(1 2 2 3)))
(test #f (vector-sorted? < #(2 1)))

;;; --- list-sort / list-stable-sort / list-sort! ---
(test '() (list-sort < '()))
(test '(1) (list-sort < '(1)))
(test '(1 1 3 4 5 9) (list-sort < '(3 1 4 1 5 9)))
(test '(9 5 4 3 1 1) (list-sort > '(3 1 4 1 5 9)))
(test '(1 2 3) (list-sort < '(1 2 3)))
(test '(1 1 3 4 5 9) (list-sort! < (list 3 1 4 1 5 9)))

;; input list is not required to survive list-sort (non-destructive here),
;; but list-sort must not share structure changes with the input for the
;; plain variant
(define src '(3 1 2))
(test '(1 2 3) (list-sort < src))
(test '(3 1 2) src)

;; stability: equal keys keep their original relative order
(define recs '((2 . a) (1 . b) (2 . c) (1 . d)))
(test '((1 . b) (1 . d) (2 . a) (2 . c))
      (list-stable-sort (lambda (x y) (< (car x) (car y))) recs))

;;; --- vector-sort / vector-stable-sort / vector-sort! ---
(test #(1 1 3 4 5 9) (vector-sort < #(3 1 4 1 5 9)))
(define vsrc (vector 3 1 2))
(test #(1 2 3) (vector-sort < vsrc))
(test #(3 1 2) vsrc)                       ; input untouched
(vector-sort! < vsrc)
(test #(1 2 3) vsrc)                       ; in-place variant mutates

(test #((1 . b) (1 . d) (2 . a) (2 . c))
      (vector-stable-sort (lambda (x y) (< (car x) (car y)))
                          (vector '(2 . a) '(1 . b) '(2 . c) '(1 . d))))

;; SRFI-132: vector procedures accept optional start/end
;; FAIL: #1231 (vector-sort and friends lack start/end parameters)
;; (test #(2 3 4) (vector-sort < #(9 4 3 2 9) 1 4))
;; FAIL: #1231 (vector-sorted? lacks start/end parameters)
;; (test #t (vector-sorted? < #(9 1 2 3 0) 1 4))

;;; --- missing exports ---
;; FAIL: #1231 (list-merge, list-merge!, vector-merge, vector-merge!,
;;   list-delete-neighbor-dups (+!), vector-delete-neighbor-dups (+!),
;;   vector-find-median (+!), vector-select!, vector-separate!,
;;   list-stable-sort!, vector-stable-sort! not exported)
;; (test '(1 2 3 4 5 6) (list-merge < '(1 3 5) '(2 4 6)))
;; (test '(1 2 3) (list-delete-neighbor-dups = '(1 1 2 2 3)))
;; (test 3 (vector-find-median < #(5 1 3 4 2) 'unused))

(test-end "srfi-132")
