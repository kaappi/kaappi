;; SRFI 44 (Collections) conformance tests.
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi44.scm
;;
;; Exercises the generic collection-*/bag-*/set-*/sequence-*/map-* API across
;; every concrete type Kaappi's (srfi 44) wires in (list, vector, string,
;; alist-map, (srfi 69) hash-table, (srfi 113) set and bag), plus the
;; concrete alist-map family in its own right.
;;
;; (srfi 44) and (srfi 113) both export bag?/bag-contains?/bag-delete*
;; (SRFI 44 intentionally broadens those exact names — see the header
;; comment in lib/srfi/44.sld) so, like any two libraries with overlapping
;; exports, combining them here requires excepting the overlap from one side.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 69) (srfi 128)
        (srfi 44)
        (except (srfi 113)
                bag? bag-contains? bag-delete bag-delete! bag-delete-all bag-delete-all!))

(test-begin "srfi-44")

(define cmp (make-default-comparator))

;;; ---------------------------------------------------------------------
;;; Base collection generics
;;; ---------------------------------------------------------------------

(test-assert "collection? true for a list" (collection? '(1 2 3)))
(test-assert "collection? true for a vector" (collection? (vector 1 2)))
(test-assert "collection? true for a string" (collection? "abc"))
(test-assert "collection? true for an alist-map" (collection? (make-alist-map)))
(test-assert "collection? true for a hash-table" (collection? (make-hash-table)))
(test-assert "collection? true for a (srfi 113) set" (collection? (set cmp 1 2)))
(test-assert "collection? true for a (srfi 113) bag" (collection? (bag cmp 1 1)))
(test-assert "collection? false for a non-collection" (not (collection? 42)))
(test-assert "collection? false for a procedure" (not (collection? car)))

(test-equal "collection-name: list" 'list (collection-name '(1 2 3)))
(test-equal "collection-name: vector" 'vector (collection-name (vector 1 2)))
(test-equal "collection-name: string" 'string (collection-name "abc"))
(test-equal "collection-name: alist-map" 'alist-map (collection-name (make-alist-map)))
(test-equal "collection-name: hash-table" 'hash-table (collection-name (make-hash-table)))
(test-equal "collection-name: set" 'set (collection-name (set cmp)))
(test-equal "collection-name: bag" 'bag (collection-name (bag cmp)))
(test-error "collection-name signals on a non-collection" (collection-name 42))

(test-equal "collection-size: list" 3 (collection-size '(1 2 3)))
(test-equal "collection-size: empty list" 0 (collection-size '()))
(test-equal "collection-size: vector" 2 (collection-size (vector 1 2)))
(test-equal "collection-size: string" 4 (collection-size "abcd"))
(test-equal "collection-size: alist-map" 2 (collection-size (alist-map (cons 1 'a) (cons 2 'b))))
(test-equal "collection-size: set" 3 (collection-size (set cmp 1 2 3)))
(test-equal "collection-size: bag counts multiplicity" 4 (collection-size (bag cmp 'a 'a 'b 'c)))

(test-assert "collection-empty? true for '()" (collection-empty? '()))
(test-assert "collection-empty? false for non-empty list" (not (collection-empty? '(1))))
(test-assert "collection-empty? true for an empty vector" (collection-empty? (vector)))
(test-assert "collection-empty? true for an empty set" (collection-empty? (set cmp)))

(test-equal "collection-count: list" 3 (collection-count '(1 2 1 3 1) 1))
(test-equal "collection-count: no matches" 0 (collection-count '(1 2 3) 99))
(test-equal "collection-count: vector" 2 (collection-count (vector 'a 'b 'a) 'a))
(test-equal "collection-count: string counts a character" 2 (collection-count "banana" #\n))
(test-equal "collection-count: map counts by value" 2
  (collection-count (alist-map (cons 1 'x) (cons 2 'y) (cons 3 'x)) 'x))
(test-equal "collection-count: bag uses element multiplicity" 2 (collection-count (bag cmp 'a 'a 'b) 'a))

(test-equal "collection-get-any: list returns an element" 9 (collection-get-any '(9 8 7)))
(test-error "collection-get-any signals by default on empty" (collection-get-any '()))
(test-equal "collection-get-any: custom absence-thunk" 'none (collection-get-any '() (lambda () 'none)))
(test-assert "collection-get-any: set returns a member"
  (set-contains? (set cmp 1 2 3) (collection-get-any (set cmp 1 2 3))))

(test-equal "collection->list: list is itself" '(1 2 3) (collection->list '(1 2 3)))
(test-equal "collection->list: vector" '(1 2 3) (collection->list (vector 1 2 3)))
(test-equal "collection->list: string" (list #\a #\b) (collection->list "ab"))
(test-equal "collection->list: alist-map yields pairs"
  '((1 . a) (2 . b)) (collection->list (alist-map (cons 1 'a) (cons 2 'b))))
(test-equal "collection->list: set length matches size"
  3 (length (collection->list (set cmp 1 2 3))))

(test-equal "collection-copy: list" '(1 2 3) (collection-copy '(1 2 3)))
(let* ((v (vector 1 2 3)) (v2 (collection-copy v)))
  (vector-set! v2 0 'changed)
  (test-equal "collection-copy: vector is independent" 1 (vector-ref v 0)))
(test-equal "collection-copy: set preserves membership"
  #t (set-contains? (collection-copy (set cmp 1 2)) 1))

(test-equal "collection-clear: list" '() (collection-clear '(1 2 3)))
(test-equal "collection-clear: vector" 0 (vector-length (collection-clear (vector 1 2 3))))
(test-equal "collection-clear: string" 0 (string-length (collection-clear "abc")))
(test-assert "collection-clear: set is empty" (set-empty? (collection-clear (set cmp 1 2))))

(test-assert "collection=: equal lists" (collection= = '(1 2 3) '(1 2 3)))
(test-assert "collection=: unequal lists" (not (collection= = '(1 2 3) '(1 2 4))))
(test-assert "collection=: different lengths" (not (collection= = '(1 2) '(1 2 3))))
(test-assert "collection=: vectors" (collection= = (vector 1 2) (vector 1 2)))
(test-assert "collection=: different kinds are unequal" (not (collection= = '(1 2) (vector 1 2))))
(test-assert "collection=: sets ignore element order"
  (collection= equal? (set cmp 1 2 3) (set cmp 3 2 1)))
(test-assert "collection=: alist-maps compare by association"
  (collection= = (alist-map (cons 1 2) (cons 3 4)) (alist-map (cons 3 4) (cons 1 2))))
(test-assert "collection=: alist-maps with different values are unequal"
  (not (collection= = (alist-map (cons 1 2)) (alist-map (cons 1 3)))))

;;; ---------------------------------------------------------------------
;;; Attribute markers
;;; ---------------------------------------------------------------------

(test-assert "ordered-collection? is always false (no ordered type is wired in)"
  (not (ordered-collection? '(1 2 3))))
(test-assert "directional-collection?: list is directional" (directional-collection? '(1 2 3)))
(test-assert "directional-collection?: vector is directional" (directional-collection? (vector 1)))
(test-assert "directional-collection?: hash-table is not directional"
  (not (directional-collection? (make-hash-table))))
(test-assert "directional-collection?: set is not directional" (not (directional-collection? (set cmp))))
(test-assert "limited-collection?: vector is limited" (limited-collection? (vector 1 2)))
(test-assert "limited-collection?: string is limited" (limited-collection? "ab"))
(test-assert "limited-collection?: list is not limited" (not (limited-collection? '(1 2))))
(test-assert "purely-mutable-collection?: vector is purely mutable"
  (purely-mutable-collection? (vector 1 2)))
(test-assert "purely-mutable-collection?: hash-table is purely mutable"
  (purely-mutable-collection? (make-hash-table)))
(test-assert "purely-mutable-collection?: list is not purely mutable"
  (not (purely-mutable-collection? '(1 2))))

;;; ---------------------------------------------------------------------
;;; Enumeration: the multi-seed, early-exit fold protocol
;;; ---------------------------------------------------------------------

(test-equal "collection-fold-left: sums a list"
  10 (call-with-values (lambda () (collection-fold-left '(1 2 3 4) (lambda (v acc) (values #t (+ v acc))) 0))
       (lambda (sum) sum)))

(test-equal "collection-fold-left: stops early when proceed is #f"
  3 (call-with-values
      (lambda ()
        (collection-fold-left '(1 2 3 4 5)
          (lambda (v acc) (if (= v 3) (values #f acc) (values #t (+ v acc))))
          0))
      (lambda (sum) sum)))

(test-equal "collection-fold-right: rebuilds original order"
  '(1 2 3) (call-with-values (lambda () (collection-fold-right '(1 2 3) (lambda (v acc) (values #t (cons v acc))) '()))
             (lambda (lst) lst)))

(test-equal "collection-fold-left: fold-function receives value before seeds"
  '(3 2 1) (call-with-values (lambda () (collection-fold-left '(1 2 3) (lambda (v acc) (values #t (cons v acc))) '()))
             (lambda (lst) lst)))

(call-with-values
  (lambda () (collection-fold-left '(1 2 3) (lambda (v sum count) (values #t (+ sum v) (+ count 1))) 0 0))
  (lambda (sum count)
    (test-equal "collection-fold-left: multiple seeds, sum" 6 sum)
    (test-equal "collection-fold-left: multiple seeds, count" 3 count)))

(test-equal "collection-fold-left: works over a vector"
  6 (call-with-values (lambda () (collection-fold-left (vector 1 2 3) (lambda (v acc) (values #t (+ v acc))) 0))
      (lambda (sum) sum)))
(test-equal "collection-fold-left: works over a string"
  3 (call-with-values (lambda () (collection-fold-left "abc" (lambda (c acc) (values #t (+ 1 acc))) 0))
      (lambda (n) n)))

(test-equal "collection-fold-keys-left: sequence keys are 0-based indices"
  '(0 1 2) (call-with-values
             (lambda () (collection-fold-keys-left (vector 'a 'b 'c) (lambda (k acc) (values #t (cons k acc))) '()))
             (lambda (ks) (reverse ks))))
(test-equal "collection-fold-keys-left: map keys are the stored keys"
  '(1 2) (call-with-values
           (lambda () (collection-fold-keys-left (alist-map (cons 1 'a) (cons 2 'b)) (lambda (k acc) (values #t (cons k acc))) '()))
           (lambda (ks) (reverse ks))))
;; fold-*-right enumerates right-to-left, so consing (with no explicit
;; reverse) naturally rebuilds the original left-to-right order — the same
;; pattern already checked above for collection-fold-right's values.
(test-equal "collection-fold-keys-right: consing rebuilds original key order"
  '(0 1 2) (call-with-values
             (lambda () (collection-fold-keys-right (vector 'a 'b 'c) (lambda (k acc) (values #t (cons k acc))) '()))
             (lambda (ks) ks)))
(test-error "collection-fold-keys-left: signals for a set (no keys)"
  (collection-fold-keys-left (set cmp 1 2) (lambda (k acc) (values #t acc)) '()))

;;; --- Kaappi extensions built on fold ---------------------------------

(test-equal "collection-for-each: visits every element"
  6 (let ((sum 0)) (collection-for-each (lambda (v) (set! sum (+ sum v))) '(1 2 3)) sum))
(test-equal "collection-for-each: works over a set"
  6 (let ((sum 0)) (collection-for-each (lambda (v) (set! sum (+ sum v))) (set cmp 1 2 3)) sum))

(test-equal "collection-find: first match" 4 (collection-find even? '(1 3 5 4 7)))
(test-equal "collection-find: absence-thunk on no match" 'none (collection-find even? '(1 3 5) (lambda () 'none)))
(test-assert "collection-find: default is #f on no match" (not (collection-find even? '(1 3 5))))
(test-equal "collection-find: correctly finds a genuine #f element"
  'z (collection-find (lambda (x) (eq? x 'z)) (list #f 'z) (lambda () 'not-found)))

(test-assert "collection-any?: true when some element matches" (collection-any? even? '(1 3 5 4)))
(test-assert "collection-any?: false when none match" (not (collection-any? even? '(1 3 5))))
(test-assert "collection-any?: false on an empty collection" (not (collection-any? even? '())))
(test-assert "collection-every?: true when all match" (collection-every? positive? '(1 2 3)))
(test-assert "collection-every?: false on first failure" (not (collection-every? positive? '(1 -2 3))))
(test-assert "collection-every?: vacuously true on empty" (collection-every? positive? '()))

;;; ---------------------------------------------------------------------
;;; Bag family: list, vector, string, (srfi 113) bag
;;; ---------------------------------------------------------------------

(test-assert "bag?: list is a bag" (bag? '(1 2 3)))
(test-assert "bag?: vector is a bag" (bag? (vector 1 2)))
(test-assert "bag?: string is a bag" (bag? "abc"))
(test-assert "bag?: a (srfi 113) bag is a bag" (bag? (bag cmp 'a 'a 'b)))
(test-assert "bag?: a set is not a bag" (not (bag? (set cmp 1 2))))
(test-assert "bag?: false for a non-collection" (not (bag? 42)))

(test-assert "bag-contains?: list" (bag-contains? '(1 2 3) 2))
(test-assert "bag-contains?: vector, absent" (not (bag-contains? (vector 1 2 3) 9)))
(test-assert "bag-contains?: string" (bag-contains? "abc" #\b))
(test-assert "bag-contains?: (srfi 113) bag" (bag-contains? (bag cmp 'a 'a 'b) 'a))

(test-equal "bag-add: list" '(1 2 3) (bag-add '(1 2) 3))
(test-equal "bag-add: vector" (vector 1 2 3) (bag-add (vector 1 2) 3))
(test-equal "bag-add: string" "abc" (bag-add "ab" #\c))
(test-equal "bag-add: (srfi 113) bag increases multiplicity"
  2 (bag-element-count (bag-add (bag cmp 'a) 'a) 'a))

(test-equal "bag-delete: list removes only one occurrence" '(1 2 3) (bag-delete '(1 2 2 3) 2))
(test-equal "bag-delete-all: list removes every occurrence" '(1 3) (bag-delete-all '(1 2 2 3) 2))
(test-equal "bag-delete: vector removes only one occurrence"
  (vector 1 2 3) (bag-delete (vector 1 2 2 3) 2))
(test-equal "bag-delete-all: string removes every occurrence"
  "ac" (bag-delete-all "abcb" #\b))
(let ((v (vector 1 2 2 3)))
  (bag-delete v 2)
  (test-equal "bag-delete: functional, does not mutate the vector argument" (vector 1 2 2 3) v))
(test-equal "bag-delete: (srfi 113) bag decrements multiplicity"
  1 (bag-element-count (bag-delete (bag cmp 'a 'a) 'a) 'a))

(test-equal "bag-equivalence-function: list uses equal?" equal? (bag-equivalence-function '(1 2)))
(test-assert "bag-equivalence-function: string uses char equality"
  ((bag-equivalence-function "ab") #\a #\a))

(test-equal "bag-add-from: merges a source bag's elements into a list"
  '(1 2 3 4) (bag-add-from '(1 2) '(3 4)))
(test-equal "bag-add-from!: merges in place for a (srfi 113) bag"
  4 (let ((b (bag cmp 'a))) (bag-add-from! b '(b c d)) (bag-size b)))
(test-equal "bag-delete-from: removes one occurrence per element in source"
  '(1 3) (bag-delete-from '(1 2 3 4) '(2 4)))
(test-equal "bag-delete-all-from: removes every occurrence of each element in source"
  '(2 2) (bag-delete-all-from '(1 1 2 2) '(1)))

;;; ---------------------------------------------------------------------
;;; Set family: (srfi 113) set — thin adapters
;;; ---------------------------------------------------------------------

(test-assert "set?: a (srfi 113) set is a set" (set? (set cmp 1 2)))
(test-assert "set?: a list is not a set" (not (set? '(1 2))))
(test-assert "set-equivalence-function returns a procedure" (procedure? (set-equivalence-function (set cmp 1))))
(test-assert "set-contains?" (set-contains? (set cmp 1 2 3) 2))
(test-assert "set-subset?: true" (set-subset? (set cmp 1 2) (set cmp 1 2 3)))
(test-assert "set-subset?: false" (not (set-subset? (set cmp 1 2 3) (set cmp 1 2))))
(test-assert "set-subset?: variadic, true against all"
  (set-subset? (set cmp 1) (set cmp 1 2) (set cmp 1 3)))
(test-equal "set-add: new element" 4 (set-size (set-add (set cmp 1 2 3) 4)))
(test-equal "set-add!: mutates in place" 3 (let ((s (set cmp 1 2))) (set-add! s 3) (set-size s)))
(test-equal "set-delete: removes an element" 2 (set-size (set-delete (set cmp 1 2 3) 3)))
(test-equal "set-union: combines sets" 4 (set-size (set-union (set cmp 1 2) (set cmp 3 4))))
(test-equal "set-intersection: keeps shared elements" 1 (set-size (set-intersection (set cmp 1 2) (set cmp 2 3))))
(test-equal "set-difference: keeps only left-only elements" 1 (set-size (set-difference (set cmp 1 2) (set cmp 2 3))))
(test-equal "set-symmetric-difference: elements in exactly one set"
  2 (set-size (set-symmetric-difference (set cmp 1 2 3) (set cmp 2 3 4))))
(test-equal "set-add-from: adds every element of a source collection"
  5 (set-size (set-add-from (set cmp 1 2) '(3 4 5))))
(test-equal "set-delete-from: removes every element of a source collection"
  1 (set-size (set-delete-from (set cmp 1 2 3) '(1 2))))

;;; ---------------------------------------------------------------------
;;; Sequence family: list, vector, string
;;; ---------------------------------------------------------------------

(test-assert "sequence?: list" (sequence? '(1 2 3)))
(test-assert "sequence?: vector" (sequence? (vector 1 2)))
(test-assert "sequence?: string" (sequence? "abc"))
(test-assert "sequence?: a set is not a sequence" (not (sequence? (set cmp 1 2))))
(test-assert "sequence?: an alist-map is not a sequence" (not (sequence? (make-alist-map))))

(test-equal "sequence-ref: list" 2 (sequence-ref '(1 2 3) 1))
(test-equal "sequence-ref: vector" 3 (sequence-ref (vector 1 2 3) 2))
(test-equal "sequence-ref: string" #\a (sequence-ref "abc" 0))
(test-error "sequence-ref: signals by default out of range" (sequence-ref '(1 2 3) 99))
(test-equal "sequence-ref: custom absence-thunk" 'oob (sequence-ref '(1 2 3) 99 (lambda () 'oob)))
(test-equal "sequence-ref: negative index also uses absence-thunk" 'oob (sequence-ref '(1 2 3) -1 (lambda () 'oob)))

(test-equal "sequence-get-left: first element" 1 (sequence-get-left '(1 2 3)))
(test-equal "sequence-get-right: last element of a list" 3 (sequence-get-right '(1 2 3)))
(test-equal "sequence-get-right: last element of a vector" 3 (sequence-get-right (vector 1 2 3)))
(test-error "sequence-get-left: signals on empty" (sequence-get-left '()))

(test-equal "sequence-set: list, functional" '(1 x 3) (sequence-set '(1 2 3) 1 'x))
(test-equal "sequence-set: original list is unaffected" '(1 2 3) (let ((l '(1 2 3))) (sequence-set l 1 'x) l))
(let* ((v (vector 1 2 3)) (result (sequence-set! v 1 'x)))
  (test-assert "sequence-set!: returns the same vector object (impure)" (eq? v result))
  (test-equal "sequence-set!: mutates in place" (vector 1 'x 3) v))

(test-equal "sequence-copy: list range" '(2 3) (sequence-copy '(1 2 3 4 5) 1 3))
(test-equal "sequence-copy: vector range" (vector 2 3) (sequence-copy (vector 1 2 3 4 5) 1 3))
(test-equal "sequence-copy: no range copies the whole sequence" '(1 2 3) (sequence-copy '(1 2 3)))

(test-equal "sequence-add: list" '(1 2 3) (sequence-add '(1 2) 3))
(test-equal "sequence-add: vector" (vector 1 2 3) (sequence-add (vector 1 2) 3))
(test-equal "sequence-add: string" "abc" (sequence-add "ab" #\c))

;;; ---------------------------------------------------------------------
;;; Flexible Sequence family: list
;;; ---------------------------------------------------------------------

(test-assert "flexible-sequence?: list" (flexible-sequence? '(1 2 3)))
(test-assert "flexible-sequence?: vector is not flexible" (not (flexible-sequence? (vector 1 2))))

(test-equal "flexible-sequence-insert: middle" '(1 x 2 3) (flexible-sequence-insert '(1 2 3) 1 'x))
(test-equal "flexible-sequence-insert: at the front" '(x 1 2 3) (flexible-sequence-insert '(1 2 3) 0 'x))
(test-equal "flexible-sequence-insert: at the end" '(1 2 3 x) (flexible-sequence-insert '(1 2 3) 3 'x))
(test-equal "flexible-sequence-delete-at: middle" '(1 3) (flexible-sequence-delete-at '(1 2 3) 1))
(test-equal "flexible-sequence-insert-left" '(x 1 2 3) (flexible-sequence-insert-left '(1 2 3) 'x))
(test-equal "flexible-sequence-insert-right" '(1 2 3 x) (flexible-sequence-insert-right '(1 2 3) 'x))

(call-with-values (lambda () (flexible-sequence-delete-left '(1 2 3)))
  (lambda (rest v)
    (test-equal "flexible-sequence-delete-left: remaining" '(2 3) rest)
    (test-equal "flexible-sequence-delete-left: removed value" 1 v)))
(call-with-values (lambda () (flexible-sequence-delete-right '(1 2 3)))
  (lambda (rest v)
    (test-equal "flexible-sequence-delete-right: remaining" '(1 2) rest)
    (test-equal "flexible-sequence-delete-right: removed value" 3 v)))
(test-error "flexible-sequence-delete-left: signals on empty" (flexible-sequence-delete-left '()))

;;; ---------------------------------------------------------------------
;;; Map family: alist-map, (srfi 69) hash-table
;;; ---------------------------------------------------------------------

(test-assert "map?: alist-map" (map? (alist-map (cons 1 'a))))
(test-assert "map?: hash-table" (map? (make-hash-table)))
(test-assert "map?: a list is not a map" (not (map? '(1 2))))

(test-assert "map-equivalence-function returns a procedure" (procedure? (map-equivalence-function (make-hash-table))))
(test-assert "map-key-equivalence-function returns a procedure"
  (procedure? (map-key-equivalence-function (alist-map))))

(test-assert "map-contains-key?: alist-map" (map-contains-key? (alist-map (cons 1 'a)) 1))
(test-assert "map-contains-key?: hash-table"
  (let ((ht (make-hash-table))) (hash-table-set! ht 'x 1) (map-contains-key? ht 'x)))
(test-equal "map-keys->list: alist-map" '(1 2) (map-keys->list (alist-map (cons 1 'a) (cons 2 'b))))

(test-equal "map-get: alist-map" 'a (map-get (alist-map (cons 1 'a)) 1))
(test-equal "map-get: hash-table"
  1 (let ((ht (make-hash-table))) (hash-table-set! ht 'x 1) (map-get ht 'x)))
(test-equal "map-get: custom absence-thunk" 'none (map-get (alist-map) 99 (lambda () 'none)))

(test-equal "map-put: alist-map replaces rather than duplicating"
  1 (length (alist-map-get-all (map-put (alist-map (cons 1 'a) (cons 2 'b)) 1 'A) 1)))
(test-equal "map-put: alist-map new value" 'A (map-get (map-put (alist-map (cons 1 'a)) 1 'A) 1))
(test-equal "map-put: original alist-map is unaffected"
  'a (let ((am (alist-map (cons 1 'a)))) (map-put am 1 'A) (map-get am 1)))
(test-equal "map-put!: mutates the alist-map in place"
  'A (let ((am (alist-map (cons 1 'a)))) (map-put! am 1 'A) (map-get am 1)))
(test-equal "map-put: hash-table" 99 (let ((ht (make-hash-table))) (hash-table-set! ht 'x 1) (map-get (map-put ht 'x 99) 'x)))
(test-equal "map-put: hash-table copy leaves the original untouched"
  1 (let ((ht (make-hash-table))) (hash-table-set! ht 'x 1) (map-put ht 'x 99) (hash-table-ref ht 'x)))
(test-equal "map-put!: hash-table mutates in place"
  99 (let ((ht (make-hash-table))) (hash-table-set! ht 'x 1) (map-put! ht 'x 99) (hash-table-ref ht 'x)))

(test-equal "map-update: applies the updater" 20 (map-get (map-update (alist-map (cons 1 10)) 1 (lambda (v) (* v 2))) 1))
(test-equal "map-update!: mutates in place"
  11 (let ((am (alist-map (cons 1 10)))) (map-update! am 1 (lambda (v) (+ v 1))) (map-get am 1)))
(test-error "map-update: signals by default when key absent" (map-update (alist-map) 99 (lambda (v) v)))

(test-assert "map-delete: removes the key" (not (map-contains-key? (map-delete (alist-map (cons 1 'a)) 1) 1)))
(test-assert "map-delete: original is unaffected"
  (let ((am (alist-map (cons 1 'a)))) (map-delete am 1) (map-contains-key? am 1)))
(test-assert "map-delete!: mutates in place"
  (let ((am (alist-map (cons 1 'a)))) (map-delete! am 1) (not (map-contains-key? am 1))))

(test-equal "map-add-from: merges another map's associations"
  3 (collection-size (map-add-from (alist-map (cons 1 'a)) (alist-map (cons 2 'b) (cons 3 'c)))))
(test-equal "map-add-from!: mutates in place"
  3 (let ((am (alist-map (cons 1 'a)))) (map-add-from! am (alist-map (cons 2 'b) (cons 3 'c))) (collection-size am)))
(test-equal "map-delete-from: removes every listed key"
  1 (collection-size (map-delete-from (alist-map (cons 1 'a) (cons 2 'b) (cons 3 'c)) '(1 3))))
(test-equal "map-delete-from!: mutates in place"
  1 (let ((am (alist-map (cons 1 'a) (cons 2 'b) (cons 3 'c)))) (map-delete-from! am '(1 3)) (collection-size am)))

;;; ---------------------------------------------------------------------
;;; Concrete: Association List Maps (a genuine multimap)
;;; ---------------------------------------------------------------------

(test-assert "alist-map?: a fresh alist-map" (alist-map? (make-alist-map)))
(test-assert "alist-map?: a list is not an alist-map" (not (alist-map? '())))
(test-assert "alist-map-empty?: fresh map is empty" (alist-map-empty? (make-alist-map)))
(test-equal "alist-map-size" 3 (alist-map-size (alist-map (cons 1 'a) (cons 2 'b) (cons 3 'c))))

(test-assert "alist-map-contains-key?: present" (alist-map-contains-key? (alist-map (cons 2 'b)) 2))
(test-assert "alist-map-contains-key?: absent" (not (alist-map-contains-key? (alist-map (cons 2 'b)) 99)))
(test-equal "alist-map-get: present" 'b (alist-map-get (alist-map (cons 2 'b)) 2))
(test-error "alist-map-get: signals by default when absent" (alist-map-get (alist-map) 99))
(test-equal "alist-map-get: custom absence-thunk" 'none (alist-map-get (alist-map) 99 (lambda () 'none)))
(test-equal "alist-map->list" '((1 . a) (2 . b)) (alist-map->list (alist-map (cons 1 'a) (cons 2 'b))))
(test-equal "alist-map-keys->list" '(1 2 3) (alist-map-keys->list (alist-map (cons 1 'a) (cons 2 'b) (cons 3 'c))))

;; alist-map-put!/put are a genuine multimap: prepend, never overwrite.
(let* ((am (alist-map (cons 1 'a) (cons 2 'b))))
  (call-with-values (lambda () (alist-map-put! am 2 'B))
    (lambda (m v)
      (test-equal "alist-map-put!: returns the value inserted" 'B v)
      (test-equal "alist-map-put!: prepends rather than replacing"
        '((2 . B) (1 . a) (2 . b)) (alist-map->list m))))
  (test-equal "alist-map-get-all: sees both associations for the key"
    '(B b) (alist-map-get-all am 2)))

(let ((am (alist-map (cons 1 'a))))
  (call-with-values (lambda () (alist-map-put am 2 'b))
    (lambda (am2 v)
      (test-equal "alist-map-put: functional, grows the copy" 2 (alist-map-size am2))
      (test-equal "alist-map-put: original is unaffected" 1 (alist-map-size am))
      (test-equal "alist-map-put: returns the inserted value" 'b v))))

;; alist-map-delete (one) vs alist-map-delete-all (every occurrence).
(let ((am (alist-map (cons 1 'a) (cons 1 'A) (cons 2 'b))))
  (test-equal "alist-map-delete: removes only the first occurrence"
    2 (alist-map-size (alist-map-delete am 1)))
  (test-equal "alist-map-delete-all: removes every occurrence"
    1 (alist-map-size (alist-map-delete-all am 1)))
  (test-equal "alist-map-delete: original is unaffected" 3 (alist-map-size am)))
(let ((am (alist-map (cons 1 'a) (cons 1 'A))))
  (alist-map-delete! am 1)
  (test-equal "alist-map-delete!: mutates in place, one occurrence left" 1 (alist-map-size am)))
(let ((am (alist-map (cons 1 'a) (cons 1 'A))))
  (alist-map-delete-all! am 1)
  (test-assert "alist-map-delete-all!: mutates in place, all occurrences gone" (alist-map-empty? am)))

(let ((am (alist-map (cons 1 'a))) )
  (test-assert "alist-map-copy: independent from the original"
    (let ((copy (alist-map-copy am)))
      (alist-map-put! copy 2 'b)
      (= 1 (alist-map-size am)))))

;; fold
(define am-fold (alist-map (cons 1 10) (cons 2 20) (cons 3 30)))
(test-equal "alist-map-fold-left: sums values"
  60 (call-with-values (lambda () (alist-map-fold-left am-fold (lambda (kv acc) (values #t (+ (cdr kv) acc))) 0))
       (lambda (sum) sum)))
(test-equal "alist-map-fold-right: sums values regardless of direction"
  60 (call-with-values (lambda () (alist-map-fold-right am-fold (lambda (kv acc) (values #t (+ (cdr kv) acc))) 0))
       (lambda (sum) sum)))
(test-equal "alist-map-fold-keys-left: collects keys in order"
  '(1 2 3) (call-with-values (lambda () (alist-map-fold-keys-left am-fold (lambda (k acc) (values #t (cons k acc))) '()))
             (lambda (ks) (reverse ks))))
(test-equal "alist-map-fold-keys-right: consing rebuilds original key order"
  '(1 2 3) (call-with-values (lambda () (alist-map-fold-keys-right am-fold (lambda (k acc) (values #t (cons k acc))) '()))
             (lambda (ks) ks)))

(test-assert "alist-map-clear: functional, returns an empty map" (alist-map-empty? (alist-map-clear am-fold)))
(test-equal "alist-map-clear: original is unaffected" 3 (alist-map-size am-fold))
(let ((am (alist-map (cons 1 'a))))
  (alist-map-clear! am)
  (test-assert "alist-map-clear!: mutates in place" (alist-map-empty? am)))

(test-assert "alist-map=: same associations, different order"
  (alist-map= = (alist-map (cons 1 2) (cons 3 4)) (alist-map (cons 3 4) (cons 1 2))))
(test-assert "alist-map=: different values are unequal"
  (not (alist-map= = (alist-map (cons 1 2)) (alist-map (cons 1 3)))))
(test-assert "alist-map=: different sizes are unequal"
  (not (alist-map= = (alist-map (cons 1 2)) (alist-map (cons 1 2) (cons 3 4)))))

;; make-alist-map / alist-map with a custom equivalence function
(let ((ci-am (make-alist-map string-ci=?)))
  (alist-map-put! ci-am "Hello" 1)
  (test-assert "make-alist-map: custom equivalence used for lookup"
    (alist-map-contains-key? ci-am "HELLO"))
  (test-assert "make-alist-map: custom equivalence rejects a genuine mismatch"
    (not (alist-map-contains-key? ci-am "bye"))))
(test-equal "make-alist-map: default equivalence is eqv?"
  eqv? (alist-map-equivalence-function (make-alist-map)))

;; alist-map's optional leading equivalence-function argument
(let ((am (alist-map string=? (cons "a" 1) (cons "b" 2))))
  (test-assert "alist-map: leading equivalence-function is recognized"
    (alist-map-contains-key? am "a"))
  (test-equal "alist-map: pairs after the equivalence function are stored"
    2 (alist-map-size am)))

(let ((runner (test-runner-current)))
  (test-end "srfi-44")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
