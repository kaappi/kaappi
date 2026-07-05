;; SRFI-43 (vector library) conformance tests — audit Phase 3b
;; NOTE: Kaappi's (srfi 43) currently re-exports SRFI-133-style procedures;
;; the index-passing callback convention and 8 exports are missing (#1209).
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi43.scm

(import (scheme base) (srfi 43) (chibi test))

(test-begin "srfi-43")

;;; --- procedures whose semantics agree between SRFI-43 and SRFI-133 ---
(test #t (vector-empty? #()))
(test #f (vector-empty? #(1)))
(test #(1 2 3 4) (vector-append #(1 2) #(3 4)))
(test #(1 2 3 4) (vector-concatenate (list #(1 2) #(3 4))))
(test #(9 2 1) (let ((v (vector 1 2 9))) (vector-swap! v 0 2) v))
(test '(1 2 3) (vector->list #(1 2 3)))
(test #(1 2 3) (list->vector '(1 2 3)))
(test #(0 0) (make-vector 2 0))
(test #(7 7 7) (let ((v (vector 1 2 3))) (vector-fill! v 7) v))
(test #(1 2) (vector-copy #(1 2)))
(test #(5 6 3) (let ((v (vector 1 2 3))) (vector-copy! v 0 #(5 6)) v))

;; searching (SRFI-43 predicates receive elements, no index)
(test 1 (vector-index even? #(1 2 3)))
(test #f (vector-index even? #(1 3 5)))
(test 2 (vector-index-right even? #(2 1 4 5)))
(test 1 (vector-skip odd? #(1 2 3)))
(test #t (vector-any even? #(1 2 3)))
(test #f (vector-any even? #(1 3 5)))
(test #t (vector-every odd? #(1 3 5)))
(test #f (vector-every odd? #(1 2 5)))

;; vector-map! mutates in place (element-only callback agrees when arity 1
;; is used with a single vector under SRFI-133 style; SRFI-43 passes the
;; index — covered by the disabled tests below)
(test #(2 4 6) (let ((v (vector 1 2 3))) (vector-map! (lambda (x) (* 2 x)) v) v))

;;; --- SRFI-43 index-passing callback convention (spec-quoted in #1209) ---
;; FAIL: #1209 (SRFI-43 procedures use SRFI-133 semantics — no index arg)
;; (test #(10 11 12) (vector-map (lambda (i x) (+ i x)) #(10 10 10)))
;; FAIL: #1209 (SRFI-43 procedures use SRFI-133 semantics — no index arg)
;; (test '(c b a) (vector-fold (lambda (i state x) (cons x state)) '() #(a b c)))
;; FAIL: #1209 (SRFI-43 procedures use SRFI-133 semantics — no index arg)
;; (test '((0 . a) (1 . b))
;;       (let ((acc '()))
;;         (vector-for-each (lambda (i x) (set! acc (cons (cons i x) acc))) #(a b))
;;         (reverse acc)))
;; FAIL: #1209 (SRFI-43 procedures use SRFI-133 semantics — no index arg)
;; (test 2 (vector-count (lambda (i x) (even? x)) #(1 2 4)))

;;; --- missing SRFI-43 exports ---
;; FAIL: #1209 (vector-unfold, vector=, vector-binary-search, vector-reverse!,
;;              vector-reverse-copy!, reverse-vector->list, reverse-list->vector
;;              are not exported)
;; (test #(0 1 2) (vector-unfold (lambda (i) (values i)) 3))
;; (test #t (vector= eqv? #(1 2) #(1 2)))
;; (test '(3 2 1) (reverse-vector->list #(1 2 3)))

(test-end "srfi-43")
