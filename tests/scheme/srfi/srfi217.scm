;; SRFI-217 (Integer Sets) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi217.scm

(import (scheme base) (scheme process-context) (srfi 217) (srfi 64))

(test-begin "srfi-217")

;;; --- constructors (spec's own examples) ---
(test-equal "iset->list" '(2 3 5 7 11) (iset->list (iset 2 3 5 7 11)))
(test-equal "iset: dedupes and sorts" '(1 2 3) (iset->list (iset 3 1 2 1 3)))
(test-equal "iset-unfold"
  '(2 4 8 16 32 64)
  (iset->list (iset-unfold (lambda (n) (> n 64)) values (lambda (n) (* n 2)) 2)))
(test-equal "make-range-iset" '(-10 -4 2 8) (iset->list (make-range-iset -10 10 6)))
(test-equal "make-range-iset: default step" '(0 1 2 3) (iset->list (make-range-iset 0 4)))

;;; --- predicates ---
(test-assert "iset?: true" (iset? (iset 1 2)))
(test-assert "iset-contains?: true" (iset-contains? (iset 1 2 3) 2))
(test-assert "iset-contains?: false" (not (iset-contains? (iset 1 2 3) 9)))
(test-assert "iset-empty?: true" (iset-empty? (iset)))
(test-assert "iset-empty?: false" (not (iset-empty? (iset 1))))
(test-assert "iset-disjoint?: true" (iset-disjoint? (iset 1 2) (iset 3 4)))
(test-assert "iset-disjoint?: false" (not (iset-disjoint? (iset 1 2) (iset 2 3))))

;;; --- accessors ---
(test-equal "iset-member: found" 2 (iset-member (iset 1 2 3) 2 'nope))
(test-equal "iset-member: default" 'nope (iset-member (iset 1 2 3) 9 'nope))
(test-equal "iset-min" 1 (iset-min (iset 3 1 2)))
(test-equal "iset-max" 3 (iset-max (iset 3 1 2)))

;;; --- updaters ---
(test-equal "iset-adjoin" '(1 2 3 4) (iset->list (iset-adjoin (iset 1 2 3) 4)))
(test-equal "iset-adjoin: dedup" '(1 2 3) (iset->list (iset-adjoin (iset 1 2) 2 3)))
(test-equal "iset-delete" '(1 3) (iset->list (iset-delete (iset 1 2 3) 2)))
(test-equal "iset-delete: non-member ignored" '(1 2 3) (iset->list (iset-delete (iset 1 2 3) 9)))
(test-equal "iset-delete-all" '(1) (iset->list (iset-delete-all (iset 1 2 3) '(2 3))))

(let-values (((min rest) (iset-delete-min (iset 3 1 2))))
  (test-equal "iset-delete-min: removed value" 1 min)
  (test-equal "iset-delete-min: remainder" '(2 3) (iset->list rest)))

(let-values (((max rest) (iset-delete-max (iset 3 1 2))))
  (test-equal "iset-delete-max: removed value" 3 max)
  (test-equal "iset-delete-max: remainder" '(1 2) (iset->list rest)))

;;; --- iset-search ---
(let-values (((s obj) (iset-search (iset 1 2 3) 5
                                    (lambda (insert ignore) (insert 'inserted))
                                    (lambda (member update remove) (update member 'ignored)))))
  (test-equal "iset-search: insert on absence" '(1 2 3 5) (iset->list s))
  (test-equal "iset-search: insert result tag" 'inserted obj))

(let-values (((s obj) (iset-search (iset 1 2 3) 2
                                    (lambda (insert ignore) (insert 'ignored))
                                    (lambda (member update remove) (remove 'removed)))))
  (test-equal "iset-search: remove on presence" '(1 3) (iset->list s))
  (test-equal "iset-search: remove result tag" 'removed obj))

;;; --- whole-set operations ---
(test-equal "iset-size" 3 (iset-size (iset 1 2 3)))
(test-equal "iset-find: found" 3 (iset-find (lambda (x) (> x 2)) (iset 1 2 3 4) (lambda () 'none)))
(test-equal "iset-find: not found" 'none (iset-find (lambda (x) (> x 100)) (iset 1 2 3) (lambda () 'none)))
(test-equal "iset-count" 2 (iset-count odd? (iset 1 2 3 4)))
(test-assert "iset-any?: true" (iset-any? even? (iset 1 2 3)))
(test-assert "iset-any?: false" (not (iset-any? even? (iset 1 3 5))))
(test-assert "iset-every?: true" (iset-every? positive? (iset 1 2 3)))
(test-assert "iset-every?: false" (not (iset-every? positive? (iset -1 2 3))))

;;; --- mapping and folding ---
(test-equal "iset-map" '(2 4 6) (iset->list (iset-map (lambda (x) (* x 2)) (iset 1 2 3))))
(let ((sum 0))
  (iset-for-each (lambda (x) (set! sum (+ sum x))) (iset 1 2 3))
  (test-equal "iset-for-each" 6 sum))
(test-equal "iset-fold" '(11 7 5 3 2) (iset-fold cons '() (iset 2 3 5 7 11)))
(test-equal "iset-fold-right" '(2 3 5 7 11) (iset-fold-right cons '() (iset 2 3 5 7 11)))
(test-equal "iset-filter" '(2 4) (iset->list (iset-filter even? (iset 1 2 3 4))))
(test-equal "iset-remove" '(1 3) (iset->list (iset-remove even? (iset 1 2 3 4))))
(let-values (((evens odds) (iset-partition even? (iset 1 2 3 4))))
  (test-equal "iset-partition: matching" '(2 4) (iset->list evens))
  (test-equal "iset-partition: non-matching" '(1 3) (iset->list odds)))

;;; --- copying and conversion ---
(test-equal "iset-copy" '(1 2 3) (iset->list (iset-copy (iset 1 2 3))))
(test-equal "list->iset" '(1 2 3) (iset->list (list->iset '(3 1 2 1))))

;;; --- subset comparisons ---
(test-assert "iset=?: equal" (iset=? (iset 1 2 3) (iset 3 2 1)))
(test-assert "iset=?: unequal" (not (iset=? (iset 1 2) (iset 1 2 3))))
(test-assert "iset<?: proper subset" (iset<? (iset 1 2) (iset 1 2 3)))
(test-assert "iset<?: equal sets are not proper" (not (iset<? (iset 1 2) (iset 1 2))))
(test-assert "iset<=?: subset or equal" (iset<=? (iset 1 2) (iset 1 2)))
(test-assert "iset>?: proper superset" (iset>? (iset 1 2 3) (iset 1 2)))
(test-assert "iset>=?: superset or equal" (iset>=? (iset 1 2) (iset 1 2)))

;;; --- set theory operations ---
(test-equal "iset-union" '(1 2 3 4) (iset->list (iset-union (iset 1 2) (iset 3 4))))
(test-equal "iset-intersection" '(2 3) (iset->list (iset-intersection (iset 1 2 3) (iset 2 3 4))))
(test-equal "iset-difference" '(1) (iset->list (iset-difference (iset 1 2 3) (iset 2 3))))
(test-equal "iset-xor" '(1 4) (iset->list (iset-xor (iset 1 2 3) (iset 2 3 4))))

;;; --- intervals and ranges ---
(test-equal "iset-closed-interval" '(2 3 5 7) (iset->list (iset-closed-interval (iset 2 3 5 7 11) 2 7)))
(test-equal "iset-open-interval" '(3 5) (iset->list (iset-open-interval (iset 2 3 5 7 11) 2 7)))
(test-equal "iset-open-closed-interval" '(3 5 7) (iset->list (iset-open-closed-interval (iset 2 3 5 7 11) 2 7)))
(test-equal "iset-closed-open-interval" '(2 3 5) (iset->list (iset-closed-open-interval (iset 2 3 5 7 11) 2 7)))
(test-equal "isubset=" '(5) (iset->list (isubset= (iset 2 3 5 7) 5)))
(test-equal "isubset<" '(2 3) (iset->list (isubset< (iset 2 3 5 7) 5)))
(test-equal "isubset>=" '(5 7) (iset->list (isubset>= (iset 2 3 5 7) 5)))

(let ((runner (test-runner-current)))
  (test-end "srfi-217")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
