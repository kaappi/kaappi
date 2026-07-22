;; SRFI-153 (Ordered Sets) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi153.scm

(import (scheme base) (scheme process-context) (srfi 128) (srfi 153) (srfi 64))

(test-begin "srfi-153")

(define num-cmp (make-comparator number? = < #f))
(define str-cmp (make-comparator string? string=? string<? #f))

;;; --- constructors ---
(test-equal "oset->list: sorted" '(1 2 3 5) (oset->list (oset num-cmp 5 1 3 2)))
(test-equal "oset: dedup" '(1 2 3) (oset->list (oset num-cmp 1 2 2 3 1)))
(test-equal "oset/ordered" '(1 2 3) (oset->list (oset/ordered num-cmp 1 2 3)))
(test-equal "oset-unfold"
  '(0 1 2 3 4)
  (oset->list (oset-unfold (lambda (n) (> n 4)) values (lambda (n) (+ n 1)) 0 num-cmp)))

(let-values (((s tag) (oset-accumulate
                        (lambda (terminate i) (if (< i -3) (terminate 'finished) (values i (- i 1))))
                        num-cmp -1)))
  (test-equal "oset-accumulate: values" '(-3 -2 -1) (oset->list s))
  (test-equal "oset-accumulate: terminate tag" 'finished tag))

;; Regression: acc accumulates newest-generated-first; %build's keep-first?
;; only means "first generated" if acc is reversed back to generation order
;; first. Generates 1, then a duplicate-under-= 1.0, then 3 — the spec says
;; "the first such element prevails," so the surviving representative must
;; be the exact 1, not the later inexact 1.0.
(let-values (((s tag)
              (oset-accumulate
                (lambda (terminate seed)
                  (cond ((> seed 3) (terminate 'done))
                        ((= seed 2) (values 1.0 (+ seed 1)))
                        (else (values seed (+ seed 1)))))
                num-cmp 1)))
  (test-equal "oset-accumulate: first-generated duplicate representative wins" '(1 3) (oset->list s))
  (test-assert "oset-accumulate: preserved duplicate is the first-generated (exact) one"
    (exact? (oset-min-element s))))

;;; --- predicates ---
(test-assert "oset?: true" (oset? (oset num-cmp 1)))
(test-assert "oset-contains?: true" (oset-contains? (oset num-cmp 1 2 3) 2))
(test-assert "oset-contains?: false" (not (oset-contains? (oset num-cmp 1 2 3) 9)))
(test-assert "oset-empty?: true" (oset-empty? (oset num-cmp)))
(test-assert "oset-disjoint?: true" (oset-disjoint? (oset num-cmp 1 2) (oset num-cmp 3 4)))

;;; --- accessors ---
(test-equal "oset-member: found" 2 (oset-member (oset num-cmp 1 2 3) 2 'nope))
(test-equal "oset-member: default" 'nope (oset-member (oset num-cmp 1 2 3) 9 'nope))
(test-eq "oset-element-comparator" num-cmp (oset-element-comparator (oset num-cmp 1)))

;;; --- updaters ---
(test-equal "oset-adjoin" '(1 2 3) (oset->list (oset-adjoin (oset num-cmp 1 2) 3)))
(test-equal "oset-delete" '(1 3) (oset->list (oset-delete (oset num-cmp 1 2 3) 2)))
(test-equal "oset-delete-all" '(1) (oset->list (oset-delete-all (oset num-cmp 1 2 3) '(2 3))))

(let-values (((rest popped) (oset-pop (oset num-cmp 3 1 2))))
  (test-equal "oset-pop: smallest" 1 popped)
  (test-equal "oset-pop: remainder" '(2 3) (oset->list rest)))

(let-values (((rest popped) (oset-pop/reverse (oset num-cmp 3 1 2))))
  (test-equal "oset-pop/reverse: largest" 3 popped)
  (test-equal "oset-pop/reverse: remainder" '(1 2) (oset->list rest)))

;;; --- whole-oset operations ---
(test-equal "oset-size" 3 (oset-size (oset num-cmp 1 2 3)))
(test-equal "oset-find: found" 3 (oset-find (lambda (x) (> x 2)) (oset num-cmp 1 2 3 4) (lambda () 'none)))
(test-equal "oset-count" 2 (oset-count odd? (oset num-cmp 1 2 3 4)))
(test-assert "oset-any?: true" (oset-any? even? (oset num-cmp 1 2 3)))
(test-assert "oset-every?: true" (oset-every? positive? (oset num-cmp 1 2 3)))

;;; --- mapping and folding (spec's own example) ---
;; Matches the spec's own example: mapping out of an oset built on a
;; comparator with no ordering predicate (eq-comparator) — exercises the
;; "unordered source" fallback described in the library header.
(test-equal "oset-map"
  '("bar" "baz" "foo")
  (oset->list (oset-map str-cmp symbol->string (oset (make-eq-comparator) 'foo 'bar 'baz))))

;; Regression: duplicates are only guaranteed adjacent once sorted. The
;; unordered-comparator path must still dedup correctly even though it has
;; nothing to sort by.
(test-equal "oset: dedup over an unordered comparator, non-adjacent duplicate"
  2
  (oset-size (oset (make-eq-comparator) 'a 'b 'a)))
(test-equal "oset-fold" '(3 2 1) (oset-fold cons '() (oset num-cmp 1 2 3)))
(test-equal "oset-fold/reverse" '(1 2 3) (oset-fold/reverse cons '() (oset num-cmp 1 2 3)))
(test-equal "oset-filter" '(2 4) (oset->list (oset-filter even? (oset num-cmp 1 2 3 4))))
(test-equal "oset-remove" '(1 3) (oset->list (oset-remove even? (oset num-cmp 1 2 3 4))))
(let-values (((matching non-matching) (oset-partition even? (oset num-cmp 1 2 3 4))))
  (test-equal "oset-partition" '(2 4) (oset->list matching))
  (test-equal "oset-partition: rest" '(1 3) (oset->list non-matching)))

;;; --- conversion ---
(test-equal "list->oset" '(1 2 3) (oset->list (list->oset num-cmp '(3 1 2 1))))

;;; --- subset/comparison predicates ---
(test-assert "oset=?: equal" (oset=? (oset num-cmp 1 2 3) (oset num-cmp 3 2 1)))
(test-assert "oset<?: proper subset" (oset<? (oset num-cmp 1 2) (oset num-cmp 1 2 3)))
(test-assert "oset<=?: subset or equal" (oset<=? (oset num-cmp 1 2) (oset num-cmp 1 2)))
(test-assert "oset>?: proper superset" (oset>? (oset num-cmp 1 2 3) (oset num-cmp 1 2)))

;;; --- set-theoretic operations ---
(test-equal "oset-union" '(1 2 3 4) (oset->list (oset-union (oset num-cmp 1 2) (oset num-cmp 3 4))))
(test-equal "oset-intersection" '(2 3) (oset->list (oset-intersection (oset num-cmp 1 2 3) (oset num-cmp 2 3 4))))
(test-equal "oset-difference" '(1) (oset->list (oset-difference (oset num-cmp 1 2 3) (oset num-cmp 2 3))))
(test-equal "oset-xor" '(1 4) (oset->list (oset-xor (oset num-cmp 1 2 3) (oset num-cmp 2 3 4))))

;;; --- single-element operations ---
(test-equal "oset-min-element" 1 (oset-min-element (oset num-cmp 3 1 2)))
(test-equal "oset-max-element" 3 (oset-max-element (oset num-cmp 3 1 2)))
(test-equal "oset-element-predecessor" 2 (oset-element-predecessor (oset num-cmp 1 2 3) 3 (lambda () 'none)))
(test-equal "oset-element-successor" 3 (oset-element-successor (oset num-cmp 1 2 3) 2 (lambda () 'none)))
(test-equal "oset-element-predecessor: none" 'none (oset-element-predecessor (oset num-cmp 1 2 3) 1 (lambda () 'none)))

;;; --- dividing osets ---
(test-equal "oset-range=" '(5) (oset->list (oset-range= (oset num-cmp 2 3 5 7) 5)))
(test-equal "oset-range<" '(2 3) (oset->list (oset-range< (oset num-cmp 2 3 5 7) 5)))
(test-equal "oset-range>=" '(5 7) (oset->list (oset-range>= (oset num-cmp 2 3 5 7) 5)))

(let-values (((lt lte eq gte gt) (oset-split (oset num-cmp 2 3 5 7) 5)))
  (test-equal "oset-split: lt" '(2 3) (oset->list lt))
  (test-equal "oset-split: eq" '(5) (oset->list eq))
  (test-equal "oset-split: gt" '(7) (oset->list gt)))

(test-equal "oset-catenate"
  '(1 2 5 8 9)
  (oset->list (oset-catenate num-cmp (oset num-cmp 1 2) 5 (oset num-cmp 8 9))))

(let ((runner (test-runner-current)))
  (test-end "srfi-153")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
