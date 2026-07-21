;; SRFI-224 (Integer Mappings / fxmappings) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi224.scm

(import (scheme base) (scheme process-context) (srfi 224) (srfi 64))

(test-begin "srfi-224")

;;; --- constructors ---
(test-equal "fxmapping->alist: sorted by key" '((1 . a) (2 . b) (3 . c)) (fxmapping->alist (fxmapping 3 'c 1 'a 2 'b)))
(test-equal "fxmapping: earlier duplicate key wins" 'first (fxmapping-ref (fxmapping 1 'first 1 'second) 1))
(test-equal "alist->fxmapping" '((1 . a) (2 . b)) (fxmapping->alist (alist->fxmapping '((2 . b) (1 . a)))))
(test-equal "alist->fxmapping: first association wins" 'a (fxmapping-ref (alist->fxmapping '((1 . a) (1 . b))) 1))
;; proc is (fixnum * * -> *): key first, then old/new values.
(test-equal "alist->fxmapping/combinator"
  6
  (fxmapping-ref (alist->fxmapping/combinator (lambda (k old new) (+ old new)) '((1 . 1) (1 . 2) (1 . 3))) 1))

(test-equal "fxmapping-unfold"
  '((0 . 0) (1 . 1) (2 . 4))
  (fxmapping->alist
    (fxmapping-unfold (lambda (n) (> n 2)) (lambda (n) (values n (* n n))) (lambda (n) (+ n 1)) 0)))

;;; --- predicates ---
(test-assert "fxmapping?: true" (fxmapping? (fxmapping)))
(test-assert "fxmapping-contains?: true" (fxmapping-contains? (fxmapping 1 'a) 1))
(test-assert "fxmapping-contains?: false" (not (fxmapping-contains? (fxmapping 1 'a) 2)))
(test-assert "fxmapping-empty?: true" (fxmapping-empty? (fxmapping)))
(test-assert "fxmapping-disjoint?: true" (fxmapping-disjoint? (fxmapping 1 'a) (fxmapping 2 'b)))

;;; --- accessors ---
(test-equal "fxmapping-ref: found" 'a (fxmapping-ref (fxmapping 1 'a) 1))
(test-equal "fxmapping-ref: failure" 'missing (fxmapping-ref (fxmapping 1 'a) 9 (lambda () 'missing)))
(test-equal "fxmapping-ref/default" 'z (fxmapping-ref/default (fxmapping 1 'a) 9 'z))

(let-values (((k v) (fxmapping-min (fxmapping 3 'c 1 'a 2 'b))))
  (test-equal "fxmapping-min: key" 1 k) (test-equal "fxmapping-min: value" 'a v))
(let-values (((k v) (fxmapping-max (fxmapping 3 'c 1 'a 2 'b))))
  (test-equal "fxmapping-max: key" 3 k) (test-equal "fxmapping-max: value" 'c v))

;;; --- updaters ---
(test-equal "fxmapping-adjoin: new key" '((1 . a) (2 . b)) (fxmapping->alist (fxmapping-adjoin (fxmapping 1 'a) 2 'b)))
(test-equal "fxmapping-adjoin: existing key keeps old value" 'a (fxmapping-ref (fxmapping-adjoin (fxmapping 1 'a) 1 'z) 1))
(test-equal "fxmapping-set: replaces" 'z (fxmapping-ref (fxmapping-set (fxmapping 1 'a) 1 'z) 1))
(test-equal "fxmapping-adjust" 2 (fxmapping-ref (fxmapping-adjust (fxmapping 1 1) 1 (lambda (k v) (+ v 1))) 1))
(test-equal "fxmapping-delete" '((1 . a)) (fxmapping->alist (fxmapping-delete (fxmapping 1 'a 2 'b) 2)))
(test-equal "fxmapping-delete-all" '() (fxmapping->alist (fxmapping-delete-all (fxmapping 1 'a 2 'b) '(1 2))))

(test-equal "fxmapping-update: replace"
  '((1 . z))
  (fxmapping->alist (fxmapping-update (fxmapping 1 'a) 1 (lambda (k v replace delete) (replace 'z)))))
(test-equal "fxmapping-update: delete"
  '()
  (fxmapping->alist (fxmapping-update (fxmapping 1 'a) 1 (lambda (k v replace delete) (delete)))))

(test-equal "fxmapping-alter: insert on absence"
  '((1 . new))
  (fxmapping->alist
    (fxmapping-alter (fxmapping) 1
                      (lambda (k insert ignore) (insert 'new))
                      (lambda (k v replace delete) (replace 'unused)))))
(test-equal "fxmapping-alter: ignore on absence"
  '()
  (fxmapping->alist
    (fxmapping-alter (fxmapping) 1
                      (lambda (k insert ignore) (ignore))
                      (lambda (k v replace delete) (replace 'unused)))))

(let-values (((rest-m) (fxmapping-delete-min (fxmapping 1 'a 2 'b))))
  (test-equal "fxmapping-delete-min" '((2 . b)) (fxmapping->alist rest-m)))
(let-values (((rest-m) (fxmapping-delete-max (fxmapping 1 'a 2 'b))))
  (test-equal "fxmapping-delete-max" '((1 . a)) (fxmapping->alist rest-m)))

(let-values (((k v m) (fxmapping-pop-min (fxmapping 1 'a 2 'b))))
  (test-equal "fxmapping-pop-min: key" 1 k)
  (test-equal "fxmapping-pop-min: remainder" '((2 . b)) (fxmapping->alist m)))
(let-values (((k v m) (fxmapping-pop-max (fxmapping 1 'a 2 'b))))
  (test-equal "fxmapping-pop-max: key" 2 k)
  (test-equal "fxmapping-pop-max: remainder" '((1 . a)) (fxmapping->alist m)))

;;; --- whole-fxmapping operations ---
(test-equal "fxmapping-size" 2 (fxmapping-size (fxmapping 1 'a 2 'b)))
(let-values (((k v) (fxmapping-find (lambda (k v) (> k 1)) (fxmapping 1 'a 2 'b 3 'c) (lambda () (values 'none 'none)))))
  (test-equal "fxmapping-find: least matching key" 2 k))
(test-equal "fxmapping-count" 2 (fxmapping-count (lambda (k v) (odd? k)) (fxmapping 1 'a 2 'b 3 'c)))
(test-assert "fxmapping-any?: true" (fxmapping-any? (lambda (k v) (even? k)) (fxmapping 1 'a 2 'b)))
(test-assert "fxmapping-every?: true" (fxmapping-every? (lambda (k v) (symbol? v)) (fxmapping 1 'a 2 'b)))

;;; --- traversal ---
(test-equal "fxmapping-map: values only" (list (cons 1 #\A) (cons 2 #\B)) (fxmapping->alist (fxmapping-map char-upcase (fxmapping 1 #\a 2 #\b))))
(let ((sum 0))
  (fxmapping-for-each (lambda (k v) (set! sum (+ sum k v))) (fxmapping 1 10 2 20))
  (test-equal "fxmapping-for-each" 33 sum))
(test-equal "fxmapping-fold" 33 (fxmapping-fold (lambda (k v acc) (+ acc k v)) 0 (fxmapping 1 10 2 20)))
(test-equal "fxmapping-fold-right" '((1 . a) (2 . b)) (fxmapping-fold-right (lambda (k v acc) (cons (cons k v) acc)) '() (fxmapping 1 'a 2 'b)))
(test-equal "fxmapping-map->list" '(a b) (fxmapping-map->list (lambda (k v) v) (fxmapping 1 'a 2 'b)))
(test-equal "fxmapping-relation-map"
  '((10 . a) (20 . b))
  (fxmapping->alist (fxmapping-relation-map (lambda (k v) (values (* k 10) v)) (fxmapping 1 'a 2 'b))))

;;; --- filter ---
(test-equal "fxmapping-filter" '((2 . b)) (fxmapping->alist (fxmapping-filter (lambda (k v) (even? k)) (fxmapping 1 'a 2 'b))))
(test-equal "fxmapping-remove" '((1 . a)) (fxmapping->alist (fxmapping-remove (lambda (k v) (even? k)) (fxmapping 1 'a 2 'b))))
(let-values (((yes no) (fxmapping-partition (lambda (k v) (even? k)) (fxmapping 1 'a 2 'b))))
  (test-equal "fxmapping-partition: matching" '((2 . b)) (fxmapping->alist yes))
  (test-equal "fxmapping-partition: rest" '((1 . a)) (fxmapping->alist no)))

;;; --- conversion ---
(test-equal "fxmapping->decreasing-alist" '((2 . b) (1 . a)) (fxmapping->decreasing-alist (fxmapping 1 'a 2 'b)))
(test-equal "fxmapping-keys" '(1 2) (fxmapping-keys (fxmapping 1 'a 2 'b)))
(test-equal "fxmapping-values" '(a b) (fxmapping-values (fxmapping 1 'a 2 'b)))

(test-equal "fxmapping->generator"
  '((1 . a) (2 . b))
  (let ((gen (fxmapping->generator (fxmapping 1 'a 2 'b))) (acc '()))
    (let loop ((v (gen)))
      (if (eof-object? v) (reverse acc) (begin (set! acc (cons v acc)) (loop (gen)))))))

;;; --- comparison ---
(test-assert "fxmapping=?: equal" (fxmapping=? eqv? (fxmapping 1 'a 2 'b) (fxmapping 2 'b 1 'a)))
(test-assert "fxmapping<?: proper subset of keys" (fxmapping<? eqv? (fxmapping 1 'a) (fxmapping 1 'a 2 'b)))
(test-assert "fxmapping<=?: subset" (fxmapping<=? eqv? (fxmapping 1 'a) (fxmapping 1 'a)))

;;; --- set theory operations ---
(test-equal "fxmapping-union" '((1 . a) (2 . b)) (fxmapping->alist (fxmapping-union (fxmapping 1 'a) (fxmapping 2 'b))))
(test-equal "fxmapping-union: first wins on conflict" 'a (fxmapping-ref (fxmapping-union (fxmapping 1 'a) (fxmapping 1 'z)) 1))
(test-equal "fxmapping-intersection" '((2 . b)) (fxmapping->alist (fxmapping-intersection (fxmapping 1 'a 2 'b) (fxmapping 2 'z))))
(test-equal "fxmapping-difference" '((1 . a)) (fxmapping->alist (fxmapping-difference (fxmapping 1 'a 2 'b) (fxmapping 2 'z))))
(test-equal "fxmapping-xor" '((1 . a) (3 . c)) (fxmapping->alist (fxmapping-xor (fxmapping 1 'a 2 'b) (fxmapping 2 'b 3 'c))))
(test-equal "fxmapping-union/combinator"
  30
  (fxmapping-ref (fxmapping-union/combinator (lambda (k a b) (+ a b)) (fxmapping 1 10) (fxmapping 1 20)) 1))

;;; --- submappings ---
(test-equal "fxmapping-closed-interval" '((2 . b) (3 . c)) (fxmapping->alist (fxmapping-closed-interval (fxmapping 1 'a 2 'b 3 'c 4 'd) 2 3)))
(test-equal "fxsubmapping=" '((2 . b)) (fxmapping->alist (fxsubmapping= (fxmapping 1 'a 2 'b 3 'c) 2)))
(test-equal "fxsubmapping<" '((1 . a)) (fxmapping->alist (fxsubmapping< (fxmapping 1 'a 2 'b 3 'c) 2)))
(test-equal "fxsubmapping>=" '((2 . b) (3 . c)) (fxmapping->alist (fxsubmapping>= (fxmapping 1 'a 2 'b 3 'c) 2)))

(let-values (((lo hi) (fxmapping-split (fxmapping 1 'a 2 'b 3 'c) 2)))
  (test-equal "fxmapping-split: <=" '((1 . a) (2 . b)) (fxmapping->alist lo))
  (test-equal "fxmapping-split: >" '((3 . c)) (fxmapping->alist hi)))

(let ((runner (test-runner-current)))
  (test-end "srfi-224")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
