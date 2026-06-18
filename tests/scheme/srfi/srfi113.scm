(import (scheme base) (scheme write) (srfi 113) (srfi 128))

(define cmp (make-default-comparator))
(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (display expected)
        (display " got ") (display got)
        (newline))))

(define (check-true name val)
  (if val
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected true got ") (display val)
        (newline))))

(define (check-false name val)
  (if (not val)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected false got ") (display val)
        (newline))))

;;; Constructors and predicates
(let ((s (set cmp 1 2 3)))
  (check-true "set?" (set? s))
  (check-false "set? on list" (set? '(1 2 3)))
  (check-true "set-contains? 1" (set-contains? s 1))
  (check-true "set-contains? 2" (set-contains? s 2))
  (check-true "set-contains? 3" (set-contains? s 3))
  (check-false "set-contains? 4" (set-contains? s 4))
  (check "set-size" (set-size s) 3)
  (check-false "set-empty? non-empty" (set-empty? s))
  (check-true "set-empty? empty" (set-empty? (set cmp))))

(let ((b (bag cmp 'a 'a 'b 'c 'c 'c)))
  (check-true "bag?" (bag? b))
  (check-false "bag? on set" (bag? (set cmp)))
  (check-true "bag-contains? a" (bag-contains? b 'a))
  (check-true "bag-contains? b" (bag-contains? b 'b))
  (check-false "bag-contains? d" (bag-contains? b 'd))
  (check "bag-size" (bag-size b) 6)
  (check "bag-element-count a" (bag-element-count b 'a) 2)
  (check "bag-element-count b" (bag-element-count b 'b) 1)
  (check "bag-element-count c" (bag-element-count b 'c) 3)
  (check "bag-element-count d" (bag-element-count b 'd) 0)
  (check-false "bag-empty? non-empty" (bag-empty? b))
  (check-true "bag-empty? empty" (bag-empty? (bag cmp))))

;;; Set uniqueness
(let ((s (set cmp 1 1 2 2 3)))
  (check "set deduplicates" (set-size s) 3))

;;; Accessors
(let ((s (set cmp 1 2 3)))
  (check "set-member found" (set-member s 2 'nope) 2)
  (check "set-member not found" (set-member s 99 'nope) 'nope)
  (check-true "set-element-comparator" (comparator? (set-element-comparator s))))

(let ((b (bag cmp 'x 'y)))
  (check "bag-member found" (bag-member b 'x 'nope) 'x)
  (check "bag-member not found" (bag-member b 'z 'nope) 'nope)
  (check-true "bag-element-comparator" (comparator? (bag-element-comparator b))))

;;; Copy
(let* ((s1 (set cmp 1 2 3))
       (s2 (set-copy s1)))
  (check-true "copy is equal" (set=? s1 s2))
  (set-adjoin! s2 4)
  (check-false "copy is independent" (set=? s1 s2)))

;;; Conversion
(let ((s (set cmp 1 2 3)))
  (let ((lst (set->list s)))
    (check "set->list length" (length lst) 3)
    (check-true "set->list has 1" (member 1 lst))
    (check-true "set->list has 2" (member 2 lst))
    (check-true "set->list has 3" (member 3 lst))))

(let ((s (list->set cmp '(10 20 30 20))))
  (check "list->set size" (set-size s) 3)
  (check-true "list->set 10" (set-contains? s 10)))

(let ((b (bag cmp 'a 'a 'b)))
  (check "bag->list length" (length (bag->list b)) 3))

(let ((b (list->bag cmp '(x x y))))
  (check "list->bag size" (bag-size b) 3)
  (check "list->bag count x" (bag-element-count b 'x) 2))

;;; Updaters
(let* ((s (set cmp 1 2))
       (s2 (set-adjoin s 3 4)))
  (check "set-adjoin size" (set-size s2) 4)
  (check "original unchanged" (set-size s) 2))

(let* ((s (set cmp 1 2 3))
       (s2 (set-delete s 2)))
  (check "set-delete size" (set-size s2) 2)
  (check-false "set-delete removed" (set-contains? s2 2))
  (check "original unchanged" (set-size s) 3))

(let* ((s (set cmp 1 2 3))
       (s2 (set-delete-all s '(1 3))))
  (check "set-delete-all size" (set-size s2) 1)
  (check-true "set-delete-all kept 2" (set-contains? s2 2)))

(let* ((b (bag cmp 'a 'a 'b))
       (b2 (bag-adjoin b 'a 'c)))
  (check "bag-adjoin count a" (bag-element-count b2 'a) 3)
  (check "bag-adjoin count c" (bag-element-count b2 'c) 1)
  (check "bag original unchanged" (bag-element-count b 'a) 2))

(let* ((b (bag cmp 'a 'a 'b))
       (b2 (bag-delete b 'a)))
  (check "bag-delete count a" (bag-element-count b2 'a) 1)
  (check "bag original" (bag-element-count b 'a) 2))

;;; list->set!, list->bag!
(let ((s (set cmp 1 2)))
  (list->set! s '(3 4))
  (check "list->set! size" (set-size s) 4))

(let ((b (bag cmp 'a)))
  (list->bag! b '(a b))
  (check "list->bag! count a" (bag-element-count b 'a) 2)
  (check "list->bag! count b" (bag-element-count b 'b) 1))

;;; Unfold
(let ((s (set-unfold cmp (lambda (x) (> x 5)) values (lambda (x) (+ x 1)) 1)))
  (check "set-unfold size" (set-size s) 5)
  (check-true "set-unfold has 1" (set-contains? s 1))
  (check-true "set-unfold has 5" (set-contains? s 5)))

(let ((b (bag-unfold cmp (lambda (x) (> x 3)) values (lambda (x) (+ x 1)) 1)))
  (check "bag-unfold size" (bag-size b) 3))

;;; Disjoint
(check-true "disjoint" (set-disjoint? (set cmp 1 2) (set cmp 3 4)))
(check-false "not disjoint" (set-disjoint? (set cmp 1 2) (set cmp 2 3)))
(check-true "bag-disjoint" (bag-disjoint? (bag cmp 'a) (bag cmp 'b)))
(check-false "bag-not-disjoint" (bag-disjoint? (bag cmp 'a) (bag cmp 'a)))

;;; Whole set operations
(let ((s (set cmp 1 2 3 4 5)))
  (check "set-count even" (set-count even? s) 2)
  (check-true "set-any? even" (set-any? even? s))
  (check-false "set-every? even" (set-every? even? s))
  (check-true "set-every? positive" (set-every? positive? s))
  (let ((found (set-find even? s (lambda () #f))))
    (check-true "set-find even" (and (number? found) (even? found)))))

;;; Fold and for-each
(let ((s (set cmp 1 2 3)))
  (check "set-fold sum" (set-fold + 0 s) 6))

(let ((b (bag cmp 'a 'a 'b)))
  (let ((count 0))
    (bag-for-each (lambda (x) (set! count (+ count 1))) b)
    (check "bag-for-each visits count times" count 3)))

(let ((b (bag cmp 1 1 2)))
  (check "bag-fold sum" (bag-fold + 0 b) 4))

;;; Map
(let* ((s (set cmp 1 2 3))
       (s2 (set-map cmp (lambda (x) (* x 10)) s)))
  (check "set-map size" (set-size s2) 3)
  (check-true "set-map has 10" (set-contains? s2 10))
  (check-true "set-map has 20" (set-contains? s2 20)))

;;; Filter and remove
(let* ((s (set cmp 1 2 3 4 5))
       (s2 (set-filter even? s)))
  (check "set-filter size" (set-size s2) 2)
  (check-true "set-filter has 2" (set-contains? s2 2))
  (check-true "set-filter has 4" (set-contains? s2 4)))

(let* ((s (set cmp 1 2 3 4 5))
       (s2 (set-remove even? s)))
  (check "set-remove size" (set-size s2) 3)
  (check-true "set-remove has 1" (set-contains? s2 1)))

;;; Partition
(let ((s (set cmp 1 2 3 4 5)))
  (let-values (((yes no) (set-partition even? s)))
    (check "set-partition yes size" (set-size yes) 2)
    (check "set-partition no size" (set-size no) 3)))

;;; Comparison operators
(let ((s1 (set cmp 1 2 3))
      (s2 (set cmp 1 2 3))
      (s3 (set cmp 1 2))
      (s4 (set cmp 1 2 3 4)))
  (check-true "set=?" (set=? s1 s2))
  (check-false "set=? diff" (set=? s1 s3))
  (check-true "set<? subset" (set<? s3 s1))
  (check-false "set<? equal" (set<? s1 s2))
  (check-true "set>? superset" (set>? s4 s1))
  (check-true "set<=?" (set<=? s3 s1))
  (check-true "set<=? equal" (set<=? s1 s2))
  (check-true "set>=?" (set>=? s1 s3)))

;;; Set theory
(let ((s1 (set cmp 1 2 3))
      (s2 (set cmp 3 4 5)))
  (let ((u (set-union s1 s2)))
    (check "union size" (set-size u) 5))
  (let ((i (set-intersection s1 s2)))
    (check "intersection size" (set-size i) 1)
    (check-true "intersection has 3" (set-contains? i 3)))
  (let ((d (set-difference s1 s2)))
    (check "difference size" (set-size d) 2)
    (check-true "difference has 1" (set-contains? d 1))
    (check-true "difference has 2" (set-contains? d 2)))
  (let ((x (set-xor s1 s2)))
    (check "xor size" (set-size x) 4)
    (check-false "xor no 3" (set-contains? x 3))))

;;; Bag set theory
(let ((b1 (bag cmp 'a 'a 'b))
      (b2 (bag cmp 'a 'b 'b 'c)))
  (let ((u (bag-union b1 b2)))
    (check "bag-union count a" (bag-element-count u 'a) 2)
    (check "bag-union count b" (bag-element-count u 'b) 2)
    (check "bag-union count c" (bag-element-count u 'c) 1))
  (let ((i (bag-intersection b1 b2)))
    (check "bag-intersection count a" (bag-element-count i 'a) 1)
    (check "bag-intersection count b" (bag-element-count i 'b) 1)
    (check "bag-intersection count c" (bag-element-count i 'c) 0))
  (let ((d (bag-difference b1 b2)))
    (check "bag-difference count a" (bag-element-count d 'a) 1)
    (check "bag-difference count b" (bag-element-count d 'b) 0)))

;;; Bag sum and product
(let ((b1 (bag cmp 'a 'a))
      (b2 (bag cmp 'a 'b)))
  (let ((s (bag-sum b1 b2)))
    (check "bag-sum count a" (bag-element-count s 'a) 3)
    (check "bag-sum count b" (bag-element-count s 'b) 1)))

(let ((b (bag cmp 'a 'a 'b)))
  (let ((p (bag-product 3 b)))
    (check "bag-product count a" (bag-element-count p 'a) 6)
    (check "bag-product count b" (bag-element-count p 'b) 3)))

;;; Bag-specific
(let ((b (bag cmp 'a 'a 'b 'c 'c 'c)))
  (check "bag-unique-size" (bag-unique-size b) 3)
  (let ((total 0))
    (bag-for-each-unique (lambda (elem count) (set! total (+ total count))) b)
    (check "bag-for-each-unique total" total 6))
  (check "bag-fold-unique"
    (bag-fold-unique (lambda (elem count acc) (+ acc count)) 0 b) 6))

;;; bag-increment!/decrement!
(let ((b (bag cmp 'a)))
  (bag-increment! b 'a 2)
  (check "bag-increment!" (bag-element-count b 'a) 3)
  (bag-decrement! b 'a 1)
  (check "bag-decrement!" (bag-element-count b 'a) 2)
  (bag-decrement! b 'a 5)
  (check "bag-decrement! to zero" (bag-element-count b 'a) 0))

;;; Bag/set conversions
(let* ((b (bag cmp 'a 'a 'b))
       (s (bag->set b)))
  (check-true "bag->set is set" (set? s))
  (check "bag->set size" (set-size s) 2)
  (check-true "bag->set has a" (set-contains? s 'a)))

(let* ((s (set cmp 1 2 3))
       (b (set->bag s)))
  (check-true "set->bag is bag" (bag? b))
  (check "set->bag size" (bag-size b) 3)
  (check "set->bag count" (bag-element-count b 1) 1))

;;; bag->alist / alist->bag
(let* ((b (bag cmp 'x 'x 'y))
       (al (bag->alist b)))
  (check "bag->alist length" (length al) 2)
  (let ((b2 (alist->bag cmp al)))
    (check "alist->bag roundtrip x" (bag-element-count b2 'x) 2)
    (check "alist->bag roundtrip y" (bag-element-count b2 'y) 1)))

;;; Bag comparison operators
(let ((b1 (bag cmp 'a 'a 'b))
      (b2 (bag cmp 'a 'a 'b))
      (b3 (bag cmp 'a 'b)))
  (check-true "bag=?" (bag=? b1 b2))
  (check-false "bag=? diff" (bag=? b1 b3))
  (check-true "bag<=?" (bag<=? b3 b1))
  (check-true "bag>?" (bag>? b1 b3)))

;;; set-search!
(let ((s (set cmp 1 2 3)))
  (call-with-values
    (lambda ()
      (set-search! s 2
        (lambda (insert ignore) (insert 'inserted))
        (lambda (elem update remove) (remove 'removed))))
    (lambda (s2 obj)
      (check "search! remove obj" obj 'removed)
      (check-false "search! removed elem" (set-contains? s2 2)))))

(let ((s (set cmp 1 2 3)))
  (call-with-values
    (lambda ()
      (set-search! s 99
        (lambda (insert ignore) (insert 'inserted))
        (lambda (elem update remove) (remove 'found))))
    (lambda (s2 obj)
      (check "search! insert obj" obj 'inserted)
      (check-true "search! inserted elem" (set-contains? s2 99)))))

;;; Comparators
(check-true "set-comparator is comparator" (comparator? set-comparator))
(check-true "bag-comparator is comparator" (comparator? bag-comparator))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 113 tests failed" fail))
