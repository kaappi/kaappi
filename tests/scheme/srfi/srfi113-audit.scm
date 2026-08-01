;;; Audit: lib/srfi/113.sld (SRFI 113 — Sets and Bags)
;;; Systematic audit v2, Phase 3.9 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 113, https://srfi.schemers.org/srfi-113/srfi-113.html, plus its
;;; own reference implementation (scheme-requests-for-implementation/srfi-113,
;;; sets/sets-impl.scm) where the prose is silent. Every result below was also
;;; run under chibi-scheme 0.12.0, an independent SRFI 113 implementation.
;;;
;;; Two divergences from chibi are chibi's defects, not Kaappi's, and are
;;; asserted here in Kaappi's favour because the spec text settles them:
;;;
;;;   * bag-sum "the count of each unique element in the result is equal to
;;;     the sum of the counts of that element in the arguments" — chibi
;;;     doubles the count of an element present only in the second bag.
;;;   * bag-unfold — chibi collapses duplicate elements, producing a set.
;;;   * bag-replace / bag-search!'s update continuation — the reference's
;;;     sob-replace! writes the OLD count back (hash-table-set! ht element
;;;     value), and sob-search!'s update decrements then increments, so both
;;;     preserve multiplicity. chibi collapses to 1; Kaappi preserves.
;;;
;;; What this file deliberately does NOT assert: the two chibi divergences
;;; where the spec says only "it is an error" (an element failing the
;;; comparator's type test; two sets with different comparators combined),
;;; and bag-product with n=0, where retaining or dropping a zero-count entry
;;; is a representation choice no procedure in the SRFI can observe portably.
;;;
;;; Portability: sets and bags are unordered, so nothing asserts iteration
;;; order — every list result is sorted, and every bag result is compared as
;;; a sorted element/count alist.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi113-audit.scm

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 113) (srfi 128))

(test-begin "srfi113 audit")

(define cmp (make-default-comparator))
(define (S . e) (apply set cmp e))
(define (B . e) (apply bag cmp e))

(define (isort less l)
  (let loop ((in l) (out '()))
    (if (null? in) out
        (loop (cdr in)
              (let ins ((o out))
                (cond ((null? o) (list (car in)))
                      ((less (car in) (car o)) (cons (car in) o))
                      (else (cons (car o) (ins (cdr o))))))))))
(define (sl s) (isort < (set->list s)))
(define (bl b) (isort < (bag->list b)))
;; canonical bag shape: a sorted ((element . count) ...) alist
(define (ba b) (isort (lambda (x y) (< (car x) (car y))) (bag->alist b)))

(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k #t)) (lambda () (thunk) #f)))))

;;; ------------------------------------------------------------------
;;; Basic construction and predicates
;;; ------------------------------------------------------------------

(test-assert "set? on a set" (set? (S 1)))
(test-assert "set? on a bag is #f" (not (set? (B 1))))
(test-assert "set? on a non-collection is #f" (not (set? 1)))
(test-assert "bag? on a bag" (bag? (B 1)))
(test-assert "bag? on a set is #f" (not (bag? (S 1))))
(test-equal "a set collapses duplicates" '(1 2) (sl (S 1 2 1 2 1)))
(test-equal "a bag keeps duplicates" '(1 1 1 2 2) (bl (B 1 2 1 2 1)))
(test-equal "set-size counts unique elements" 3 (set-size (S 1 2 3)))
(test-equal "bag-size counts multiplicities" 3 (bag-size (B 1 1 2)))
(test-equal "bag-unique-size counts unique elements" 2 (bag-unique-size (B 1 1 2)))
(test-assert "set-empty? on the empty set" (set-empty? (S)))
(test-assert "set-empty? on a non-empty set" (not (set-empty? (S 1))))
(test-assert "bag-empty? on the empty bag" (bag-empty? (B)))
(test-assert "bag-empty? on a non-empty bag" (not (bag-empty? (B 1))))
(test-assert "set-contains? present" (set-contains? (S 1) 1))
(test-assert "set-contains? absent" (not (set-contains? (S 1) 2)))
(test-assert "bag-contains? present" (bag-contains? (B 1) 1))
(test-assert "bag-contains? absent" (not (bag-contains? (B 1) 2)))
(test-equal "set-member present" 1 (set-member (S 1) 1 'dflt))
(test-equal "set-member absent returns the default" 'dflt (set-member (S 1) 2 'dflt))
(test-equal "bag-member present" 1 (bag-member (B 1) 1 'dflt))
(test-equal "bag-member absent returns the default" 'dflt (bag-member (B 1) 2 'dflt))
(test-assert "set-element-comparator is the one it was built with"
             (eq? cmp (set-element-comparator (S 1))))
(test-assert "bag-element-comparator is the one it was built with"
             (eq? cmp (bag-element-comparator (B 1))))
(test-assert "set-comparator is a comparator" (comparator? set-comparator))
(test-assert "bag-comparator is a comparator" (comparator? bag-comparator))
(test-assert "set-comparator's equality ignores insertion order"
             ((comparator-equality-predicate set-comparator) (S 1 2) (S 2 1)))
(test-assert "bag-comparator's equality compares multiplicities"
             ((comparator-equality-predicate bag-comparator) (B 1 1) (B 1 1)))
(test-assert "bag-comparator's equality separates differing multiplicities"
             (not ((comparator-equality-predicate bag-comparator) (B 1 1) (B 1))))
(test-assert "set-comparator hashes to an exact integer"
             (exact-integer? ((comparator-hash-function set-comparator) (S 1 2))))
(test-assert "bag-comparator hashes to an exact integer"
             (exact-integer? ((comparator-hash-function bag-comparator) (B 1 1))))

;;; ------------------------------------------------------------------
;;; bag-element-count. "Returns the number of occurrences of element in bag."
;;; ------------------------------------------------------------------

(test-equal "bag-element-count of a present element" 2 (bag-element-count (B 1 1 2) 1))
(test-equal "bag-element-count of a singleton" 1 (bag-element-count (B 1 1 2) 2))
(test-equal "bag-element-count of an absent element is 0" 0 (bag-element-count (B 1 1 2) 9))
(test-equal "bag-element-count on the empty bag is 0" 0 (bag-element-count (B) 1))

;;; ------------------------------------------------------------------
;;; The pure set-theory operations must not touch either argument, must
;;; return a fresh object, and must compute the documented multiplicity.
;;; ------------------------------------------------------------------

(define (check-set-purity name op a b expected)
  (let* ((s1 (apply S a)) (s2 (apply S b))
         (before1 (sl s1)) (before2 (sl s2))
         (r (op s1 s2)))
    (test-equal (string-append name ": result") expected (sl r))
    (test-equal (string-append name ": first argument unchanged") before1 (sl s1))
    (test-equal (string-append name ": second argument unchanged") before2 (sl s2))
    (test-assert (string-append name ": result is not the first argument") (not (eq? r s1)))
    (test-assert (string-append name ": mutating the result does not reach the argument")
                 (begin (set-adjoin! r 99) (equal? before1 (sl s1))))))

(check-set-purity "set-union" set-union '(1 2 3) '(3 4 5) '(1 2 3 4 5))
(check-set-purity "set-intersection" set-intersection '(1 2 3) '(3 4 5) '(3))
(check-set-purity "set-difference" set-difference '(1 2 3) '(3 4 5) '(1 2))
(check-set-purity "set-xor" set-xor '(1 2 3) '(3 4 5) '(1 2 4 5))

(define (check-bag-purity name op a b expected)
  (let* ((b1 (apply B a)) (b2 (apply B b))
         (before1 (ba b1)) (before2 (ba b2))
         (r (op b1 b2)))
    (test-equal (string-append name ": result") expected (ba r))
    (test-equal (string-append name ": first argument unchanged") before1 (ba b1))
    (test-equal (string-append name ": second argument unchanged") before2 (ba b2))
    (test-assert (string-append name ": result is not the first argument") (not (eq? r b1)))
    (test-assert (string-append name ": mutating the result does not reach the argument")
                 (begin (bag-adjoin! r 99) (equal? before1 (ba b1))))))

;; "For bag-union, the number of equal elements in the result is the largest
;;  number of equal elements in any of the original bags."
(check-bag-purity "bag-union" bag-union '(1 1 1 2) '(1 2 2 3) '((1 . 3) (2 . 2) (3 . 1)))
;; "For bag-intersection, ... the smallest number ..."
(check-bag-purity "bag-intersection" bag-intersection '(1 1 1 2) '(1 2 2 3) '((1 . 1) (2 . 1)))
;; "For bag-difference, ... the number in the first bag, minus the number in
;;  the other bags (but not less than zero)."
(check-bag-purity "bag-difference" bag-difference '(1 1 1 2) '(1 2 2 3) '((1 . 2)))
(check-bag-purity "bag-xor" bag-xor '(1 1 1 2) '(1 2 2 3) '((1 . 2) (2 . 1) (3 . 1)))
;; "the count of each unique element in the result is equal to the sum of the
;;  counts of that element in the arguments"
(check-bag-purity "bag-sum" bag-sum '(1 1 1 2) '(1 2 2 3) '((1 . 4) (2 . 3) (3 . 1)))

(test-equal "bag-difference floors at zero, it does not go negative"
            '() (ba (bag-difference (B 1) (B 1 1 1))))
(test-equal "bag-difference subtracts every later bag"
            '((1 . 2)) (ba (bag-difference (B 1 1 1 1 1) (B 1) (B 1 1))))
(test-equal "bag-union takes the maximum across three bags"
            '((1 . 3)) (ba (bag-union (B 1) (B 1 1) (B 1 1 1))))
(test-equal "bag-intersection takes the minimum across three bags"
            '((1 . 1)) (ba (bag-intersection (B 1 1 1) (B 1 1) (B 1))))
(test-equal "bag-sum adds across three bags" '((1 . 3)) (ba (bag-sum (B 1) (B 1) (B 1))))
(test-equal "bag-xor of disjoint bags keeps both counts"
            '((1 . 2) (2 . 3)) (ba (bag-xor (B 1 1) (B 2 2 2))))
(test-equal "bag-xor of equal bags is empty" '() (ba (bag-xor (B 1 1) (B 1 1))))
(test-equal "set-union with no other sets copies" '(1 2) (sl (set-union (S 1 2))))
(test-equal "bag-union with no other bags copies" '((1 . 2)) (ba (bag-union (B 1 1))))

;; The `!` twins are linear-update: the spec permits, but does not require,
;; mutation, so only the RETURNED value is asserted.
(test-equal "set-union! returns the union" '(1 2 3) (sl (set-union! (S 1 2) (S 2 3))))
(test-equal "set-intersection! returns the intersection" '(2) (sl (set-intersection! (S 1 2) (S 2 3))))
(test-equal "set-difference! returns the difference" '(1) (sl (set-difference! (S 1 2) (S 2 3))))
(test-equal "set-xor! returns the symmetric difference" '(1 3) (sl (set-xor! (S 1 2) (S 2 3))))
(test-equal "bag-union! returns the maximum counts"
            '((1 . 3) (2 . 2) (3 . 1)) (ba (bag-union! (B 1 1 1 2) (B 1 2 2 3))))
(test-equal "bag-intersection! returns the minimum counts"
            '((1 . 1) (2 . 1)) (ba (bag-intersection! (B 1 1 1 2) (B 1 2 2 3))))
(test-equal "bag-difference! returns the floored difference"
            '((1 . 2)) (ba (bag-difference! (B 1 1 1 2) (B 1 2 2 3))))
(test-equal "bag-xor! returns the absolute differences"
            '((1 . 2) (2 . 1) (3 . 1)) (ba (bag-xor! (B 1 1 1 2) (B 1 2 2 3))))
(test-equal "bag-sum! returns the summed counts"
            '((1 . 4) (2 . 3) (3 . 1)) (ba (bag-sum! (B 1 1 1 2) (B 1 2 2 3))))

;;; ------------------------------------------------------------------
;;; bag-product. "the count of each unique element in the bag is equal to
;;; the count of that element in bag multiplied by n."
;;; ------------------------------------------------------------------

(test-equal "bag-product multiplies every count" '((1 . 6) (2 . 3)) (ba (bag-product 3 (B 1 1 2))))
(test-equal "bag-product 1 is the identity" '((1 . 2)) (ba (bag-product 1 (B 1 1))))
(test-equal "bag-product does not mutate its argument"
            '((1 . 2)) (let ((b (B 1 1))) (bag-product 3 b) (ba b)))
(test-equal "bag-product! returns the multiplied bag"
            '((1 . 6)) (ba (bag-product! 3 (B 1 1))))
(test-equal "bag-product on the empty bag is empty" '() (ba (bag-product 5 (B))))
(test-equal "bag-product then bag-size" 6 (bag-size (bag-product 3 (B 1 1))))
(test-equal "bag-product then bag->list length" 6 (length (bag->list (bag-product 3 (B 1 1)))))

;;; ------------------------------------------------------------------
;;; bag-increment! / bag-decrement!
;;; "Linear update procedures that return a bag with the same elements as
;;;  bag, but with the element count of element in bag increased or
;;;  decreased by the exact integer count (but not less than zero)."
;;; ------------------------------------------------------------------

(test-equal "bag-increment! on a present element"
            '((1 . 4)) (ba (bag-increment! (B 1) 1 3)))
(test-equal "bag-increment! on an absent element inserts it"
            '((1 . 1) (9 . 2)) (ba (bag-increment! (B 1) 9 2)))
(test-equal "bag-increment! by 0 is the identity" '((1 . 1)) (ba (bag-increment! (B 1) 1 0)))
(test-equal "bag-decrement! reduces the count" '((1 . 1)) (ba (bag-decrement! (B 1 1 1) 1 2)))
(test-equal "bag-decrement! to exactly zero removes the element"
            '() (ba (bag-decrement! (B 1 1) 1 2)))
(test-equal "bag-decrement! below zero removes the element rather than going negative"
            '() (ba (bag-decrement! (B 1) 1 5)))
(test-equal "bag-decrement! of an absent element changes nothing"
            '((1 . 1)) (ba (bag-decrement! (B 1) 9 1)))

;; FAIL: #2085 (bag-increment! with a negative count is not clamped at zero, and
;;              the resulting negative multiplicity makes bag->list, bag-fold and
;;              bag-for-each loop forever)
;; (test-equal "bag-increment! with a negative count is clamped at zero"
;;             0 (bag-element-count (bag-increment! (B 1 1) 1 -5) 1))
;; FAIL: #2085
;; (test-equal "a bag built by bag-increment! with a negative count still lists"
;;             0 (length (bag->list (bag-increment! (B 1 1) 1 -5))))
;; FAIL: #2085
;; (test-assert "bag-product with a negative n does not produce a negative count"
;;              (>= (bag-size (bag-product -1 (B 1 1))) 0))

;; Discriminating controls: the same loops terminate for zero and positive
;; multiplicities, so the non-termination is specific to a negative count.
(test-equal "bag->list terminates for a zero-count bag" 0 (length (bag->list (bag-product 0 (B 1)))))
(test-equal "bag->list terminates for a positive-count bag"
            3 (length (bag->list (bag-product 3 (B 1)))))
(test-equal "bag-fold terminates for a positive-count bag"
            3 (bag-fold (lambda (e a) (+ a 1)) 0 (bag-product 3 (B 1))))

;;; ------------------------------------------------------------------
;;; Set/bag conversions
;;; ------------------------------------------------------------------

(test-equal "bag->set drops multiplicities" '(1 2 3) (sl (bag->set (B 1 1 2 3 3 3))))
(test-equal "set->bag gives every element count 1"
            '((1 . 1) (2 . 1) (3 . 1)) (ba (set->bag (S 1 2 3))))
(test-equal "set->bag does not mutate the set" '(1 2) (let ((s (S 1 2))) (set->bag s) (sl s)))
(test-equal "set->bag! into an empty bag" '((1 . 1) (2 . 1)) (ba (set->bag! (B) (S 1 2))))

;; "The set->bag! procedure returns a bag containing the elements of both bag
;;  and set." The reference implementation is
;;      (hash-table-for-each (lambda (key value) (sob-increment! bag key value))
;;                           (sob-hash-table set))
;;  — every element of the set is ADDED to whatever count the bag already has.
;;  chibi-scheme 0.12.0 agrees with the reference here.
;; FAIL: #2086 (set->bag! leaves an element already in the bag at its old count)
;; (test-equal "set->bag! adds to the count of an element already in the bag"
;;             '((1 . 3) (2 . 1)) (ba (set->bag! (B 1 1) (S 1 2))))

;; Discriminating control: the element the bag does NOT already hold is added
;; correctly, so only the already-present branch is wrong.
(test-equal "set->bag! does add an element the bag did not have"
            1 (bag-element-count (set->bag! (B 1 1) (S 1 2)) 2))

(test-equal "bag->alist pairs each element with its count"
            '((1 . 2) (2 . 1)) (isort (lambda (x y) (< (car x) (car y))) (bag->alist (B 1 1 2))))
(test-equal "alist->bag reads element/count pairs"
            '((1 . 2) (2 . 1)) (ba (alist->bag cmp '((1 . 2) (2 . 1)))))
(test-equal "bag->list expands multiplicities" '(1 1 2) (bl (B 1 1 2)))
(test-equal "list->bag counts duplicates" '((1 . 2) (2 . 1)) (ba (list->bag cmp '(1 1 2))))
(test-equal "list->bag! adds to an existing bag"
            '((1 . 2) (2 . 1) (5 . 1)) (ba (list->bag! (B 5) '(1 1 2))))
(test-equal "set->list" '(1 2) (sl (S 1 2)))
(test-equal "list->set collapses duplicates" '(1 2) (sl (list->set cmp '(1 1 2))))
(test-equal "list->set! adds to an existing set" '(1 2 5) (sl (list->set! (S 5) '(1 1 2))))
(test-equal "set->bag! returns a bag" #t (bag? (set->bag! (B) (S 1))))

;;; ------------------------------------------------------------------
;;; adjoin / delete / replace
;;; ------------------------------------------------------------------

(test-equal "set-adjoin adds several elements" '(1 2 3) (sl (set-adjoin (S 1) 2 3)))
(test-equal "set-adjoin of a present element is a no-op" '(1) (sl (set-adjoin (S 1) 1)))
(test-equal "set-adjoin does not mutate its argument" '(1) (let ((s (S 1))) (set-adjoin s 2) (sl s)))
(test-equal "set-adjoin! adds in place" '(1 2 3) (sl (set-adjoin! (S 1) 2 3)))
(test-equal "bag-adjoin increments multiplicity" '((1 . 2) (2 . 1)) (ba (bag-adjoin (B 1) 1 2)))
(test-equal "bag-adjoin does not mutate its argument"
            '((1 . 1)) (let ((b (B 1))) (bag-adjoin b 1) (ba b)))
(test-equal "bag-adjoin! increments in place" '((1 . 2) (2 . 1)) (ba (bag-adjoin! (B 1) 1 2)))
(test-equal "set-delete removes an element" '(1 3) (sl (set-delete (S 1 2 3) 2)))
(test-equal "set-delete does not mutate its argument"
            '(1 2 3) (let ((s (S 1 2 3))) (set-delete s 2) (sl s)))
(test-equal "set-delete! removes in place" '(1 3) (sl (set-delete! (S 1 2 3) 2)))
(test-equal "set-delete of an absent element changes nothing" '(1) (sl (set-delete (S 1) 9)))
(test-equal "set-delete-all takes a list" '(2) (sl (set-delete-all (S 1 2 3) '(1 3))))
(test-equal "set-delete-all does not mutate its argument"
            '(1 2 3) (let ((s (S 1 2 3))) (set-delete-all s '(1 3)) (sl s)))
(test-equal "set-delete-all! removes in place" '(2) (sl (set-delete-all! (S 1 2 3) '(1 3))))
(test-equal "bag-delete removes one occurrence" '((1 . 1) (2 . 1)) (ba (bag-delete (B 1 1 2) 1)))
(test-equal "bag-delete does not mutate its argument"
            '((1 . 2) (2 . 1)) (let ((b (B 1 1 2))) (bag-delete b 1) (ba b)))
(test-equal "bag-delete! removes one occurrence in place"
            '((1 . 1) (2 . 1)) (ba (bag-delete! (B 1 1 2) 1)))
;; The reference's sob-delete-all! decrements each listed element by one, so a
;; bag loses ONE occurrence per list entry, not all of them. chibi agrees.
(test-equal "bag-delete-all removes one occurrence per list entry"
            '((1 . 1) (2 . 2)) (ba (bag-delete-all (B 1 1 2 2) '(1))))
(test-equal "bag-delete-all does not mutate its argument"
            '((1 . 2) (2 . 1)) (let ((b (B 1 1 2))) (bag-delete-all b '(1)) (ba b)))
(test-equal "bag-delete-all! removes one occurrence per list entry, in place"
            '((1 . 1) (2 . 2)) (ba (bag-delete-all! (B 1 1 2 2) '(1))))
(test-equal "bag-delete-all with a repeated element removes that many occurrences"
            '((2 . 2)) (ba (bag-delete-all (B 1 1 2 2) '(1 1))))

;; "If element is equal to an existing member of set, then that member is
;;  omitted and replaced by element." For a bag the reference writes the OLD
;;  count back, so multiplicity survives.
(test-equal "set-replace keeps the set the same size" '(1 2) (sl (set-replace (S 1 2) 2)))
(test-equal "set-replace does not mutate its argument"
            '(1 2) (let ((s (S 1 2))) (set-replace s 2) (sl s)))
(test-equal "set-replace! replaces in place" '(1 2) (sl (set-replace! (S 1 2) 2)))
(test-equal "set-replace of an absent element changes nothing" '(1) (sl (set-replace (S 1) 9)))
(test-equal "bag-replace preserves multiplicity"
            '((1 . 1) (2 . 2)) (ba (bag-replace (B 1 2 2) 2)))
(test-equal "bag-replace does not mutate its argument"
            '((1 . 1) (2 . 2)) (let ((b (B 1 2 2))) (bag-replace b 2) (ba b)))
(test-equal "bag-replace! preserves multiplicity in place"
            '((1 . 1) (2 . 2)) (ba (bag-replace! (B 1 2 2) 2)))

;;; ------------------------------------------------------------------
;;; set-search! / bag-search!
;;; ------------------------------------------------------------------

(test-equal "set-search! insert on an absent element"
            '((1 2 9) inserted)
            (call-with-values
             (lambda () (set-search! (S 1 2) 9
                                     (lambda (insert ignore) (insert 'inserted))
                                     (lambda (elt update remove) (update elt 'updated))))
             (lambda (s obj) (list (sl s) obj))))
(test-equal "set-search! ignore on an absent element"
            '((1 2) ignored)
            (call-with-values
             (lambda () (set-search! (S 1 2) 9
                                     (lambda (insert ignore) (ignore 'ignored))
                                     (lambda (elt update remove) (update elt 'updated))))
             (lambda (s obj) (list (sl s) obj))))
(test-equal "set-search! update on a present element"
            '((1 2) updated)
            (call-with-values
             (lambda () (set-search! (S 1 2) 2
                                     (lambda (insert ignore) (insert 'inserted))
                                     (lambda (elt update remove) (update elt 'updated))))
             (lambda (s obj) (list (sl s) obj))))
(test-equal "set-search! remove on a present element"
            '((1) removed)
            (call-with-values
             (lambda () (set-search! (S 1 2) 2
                                     (lambda (insert ignore) (insert 'inserted))
                                     (lambda (elt update remove) (remove 'removed))))
             (lambda (s obj) (list (sl s) obj))))
(test-equal "bag-search! insert on an absent element"
            '(((1 . 1) (9 . 1)) inserted)
            (call-with-values
             (lambda () (bag-search! (B 1) 9
                                     (lambda (insert ignore) (insert 'inserted))
                                     (lambda (elt update remove) (update elt 'updated))))
             (lambda (b obj) (list (ba b) obj))))
(test-equal "bag-search! update preserves multiplicity"
            '(((1 . 1) (2 . 2)) updated)
            (call-with-values
             (lambda () (bag-search! (B 1 2 2) 2
                                     (lambda (insert ignore) (insert 'inserted))
                                     (lambda (elt update remove) (update elt 'updated))))
             (lambda (b obj) (list (ba b) obj))))
;; The SRFI says only that remove "removes" the element; for a bag that is
;; ambiguous between one occurrence and all of them. Kaappi drops the element
;; entirely, and chibi-scheme 0.12.0 does the same -- the reference
;; implementation's sob-search! decrements by one instead. Pinned as observed,
;; with both readings recorded, rather than filed.
(test-equal "bag-search! remove drops the element entirely"
            '(((1 . 1)) removed)
            (call-with-values
             (lambda () (bag-search! (B 1 2 2) 2
                                     (lambda (insert ignore) (insert 'inserted))
                                     (lambda (elt update remove) (remove 'removed))))
             (lambda (b obj) (list (ba b) obj))))

;;; ------------------------------------------------------------------
;;; filter / remove / partition / map / fold / find
;;; ------------------------------------------------------------------

(test-equal "set-filter keeps matching elements" '(2 4) (sl (set-filter even? (S 1 2 3 4))))
(test-equal "set-filter does not mutate its argument"
            '(1 2 3 4) (let ((s (S 1 2 3 4))) (set-filter even? s) (sl s)))
(test-equal "set-filter! returns the filtered set" '(2 4) (sl (set-filter! even? (S 1 2 3 4))))
(test-equal "set-remove drops matching elements" '(1 3) (sl (set-remove even? (S 1 2 3 4))))
(test-equal "set-remove does not mutate its argument"
            '(1 2 3 4) (let ((s (S 1 2 3 4))) (set-remove even? s) (sl s)))
(test-equal "set-remove! returns the reduced set" '(1 3) (sl (set-remove! even? (S 1 2 3 4))))
(test-equal "bag-filter keeps multiplicities" '((2 . 2) (4 . 1)) (ba (bag-filter even? (B 1 2 2 3 4))))
(test-equal "bag-filter does not mutate its argument"
            '((1 . 1) (2 . 2) (3 . 1) (4 . 1)) (let ((b (B 1 2 2 3 4))) (bag-filter even? b) (ba b)))
(test-equal "bag-filter! returns the filtered bag"
            '((2 . 2) (4 . 1)) (ba (bag-filter! even? (B 1 2 2 3 4))))
(test-equal "bag-remove keeps multiplicities" '((1 . 1) (3 . 1)) (ba (bag-remove even? (B 1 2 2 3 4))))
(test-equal "bag-remove does not mutate its argument"
            '((1 . 1) (2 . 2) (3 . 1) (4 . 1)) (let ((b (B 1 2 2 3 4))) (bag-remove even? b) (ba b)))
(test-equal "bag-remove! returns the reduced bag"
            '((1 . 1) (3 . 1)) (ba (bag-remove! even? (B 1 2 2 3 4))))

(test-equal "set-partition splits into in and out"
            '((2 4) (1 3))
            (call-with-values (lambda () (set-partition even? (S 1 2 3 4)))
                              (lambda (a b) (list (sl a) (sl b)))))
(test-equal "set-partition does not mutate its argument"
            '(1 2 3 4) (let ((s (S 1 2 3 4))) (set-partition even? s) (sl s)))
(test-equal "set-partition! returns both halves"
            '((2 4) (1 3))
            (call-with-values (lambda () (set-partition! even? (S 1 2 3 4)))
                              (lambda (a b) (list (sl a) (sl b)))))
(test-equal "bag-partition keeps multiplicities in both halves"
            '(((2 . 2)) ((1 . 1) (3 . 1)))
            (call-with-values (lambda () (bag-partition even? (B 1 2 2 3)))
                              (lambda (a b) (list (ba a) (ba b)))))
(test-equal "bag-partition does not mutate its argument"
            '((1 . 1) (2 . 2) (3 . 1)) (let ((b (B 1 2 2 3))) (bag-partition even? b) (ba b)))
(test-equal "bag-partition! returns both halves"
            '(((2 . 2)) ((1 . 1) (3 . 1)))
            (call-with-values (lambda () (bag-partition! even? (B 1 2 2 3)))
                              (lambda (x y) (list (ba x) (ba y)))))

(test-equal "set-map" '(2 4 6) (sl (set-map cmp (lambda (x) (* 2 x)) (S 1 2 3))))
(test-equal "set-map collapses collisions" '(1) (sl (set-map cmp (lambda (x) 1) (S 1 2 3))))
(test-equal "bag-map keeps multiplicities" '((2 . 2) (4 . 1)) (ba (bag-map cmp (lambda (x) (* 2 x)) (B 1 1 2))))
(test-equal "bag-map accumulates collisions" '((1 . 3)) (ba (bag-map cmp (lambda (x) 1) (B 1 2 3))))
(test-equal "set-fold visits every element once" 6 (set-fold + 0 (S 1 2 3)))
(test-equal "bag-fold visits every occurrence" 4 (bag-fold + 0 (B 1 1 2)))
(test-equal "set-for-each visits every element once"
            6 (let ((n 0)) (set-for-each (lambda (x) (set! n (+ n x))) (S 1 2 3)) n))
(test-equal "bag-for-each visits every occurrence"
            4 (let ((n 0)) (bag-for-each (lambda (x) (set! n (+ n x))) (B 1 1 2)) n))
(test-equal "bag-for-each-unique visits each element once, with its count"
            4 (let ((n 0)) (bag-for-each-unique (lambda (e c) (set! n (+ n (* e c)))) (B 1 1 2)) n))
(test-equal "bag-fold-unique folds over element/count pairs"
            4 (bag-fold-unique (lambda (e c a) (+ a (* e c))) 0 (B 1 1 2)))
(test-equal "set-count counts matching elements" 2 (set-count even? (S 1 2 3 4)))
(test-equal "bag-count counts matching occurrences" 3 (bag-count even? (B 1 1 2 2 2 3)))
(test-equal "set-find returns a matching element" 2 (set-find even? (S 2) (lambda () 'none)))
(test-equal "set-find calls failure when nothing matches"
            'none (set-find even? (S 1 3) (lambda () 'none)))
(test-equal "bag-find returns a matching element" 2 (bag-find even? (B 2 2) (lambda () 'none)))
(test-equal "bag-find calls failure when nothing matches"
            'none (bag-find even? (B 1) (lambda () 'none)))
(test-assert "set-any? true" (set-any? even? (S 1 2)))
(test-assert "set-any? false" (not (set-any? even? (S 1 3))))
(test-assert "set-every? true" (set-every? even? (S 2 4)))
(test-assert "set-every? false" (not (set-every? even? (S 1 2))))
(test-assert "set-every? on the empty set is true" (set-every? even? (S)))
(test-assert "bag-any? true" (bag-any? even? (B 1 2)))
(test-assert "bag-any? false" (not (bag-any? even? (B 1 3))))
(test-assert "bag-every? true" (bag-every? even? (B 2 4)))
(test-assert "bag-every? false" (not (bag-every? even? (B 1 2))))

(test-equal "set-unfold builds a set from a seed"
            '(0 1 2 3 4)
            (sl (set-unfold cmp (lambda (s) (= s 5)) (lambda (s) s) (lambda (s) (+ s 1)) 0)))
(test-equal "set-unfold with an immediately-true stop predicate is empty"
            '() (sl (set-unfold cmp (lambda (s) #t) (lambda (s) s) (lambda (s) (+ s 1)) 0)))
(test-equal "bag-unfold accumulates duplicate mapped values"
            '((0 . 3) (1 . 2))
            (ba (bag-unfold cmp (lambda (s) (= s 5)) (lambda (s) (modulo s 2)) (lambda (s) (+ s 1)) 0)))

;;; ------------------------------------------------------------------
;;; Copies and comparisons
;;; ------------------------------------------------------------------

(test-assert "set-copy is a real copy"
             (let* ((s (S 1)) (c (set-copy s))) (set-adjoin! c 2) (equal? '(1) (sl s))))
(test-assert "bag-copy is a real copy"
             (let* ((b (B 1)) (c (bag-copy b))) (bag-adjoin! c 1) (equal? '((1 . 1)) (ba b))))
(test-assert "set=? ignores order" (set=? (S 1 2) (S 2 1)))
(test-assert "set=? on different sets" (not (set=? (S 1) (S 2))))
(test-assert "set=? of three equal sets" (set=? (S 1) (S 1) (S 1)))
(test-assert "set<? on a proper subset" (set<? (S 1) (S 1 2)))
(test-assert "set<? on an equal set is #f" (not (set<? (S 1) (S 1))))
(test-assert "set<? chained" (set<? (S 1) (S 1 2) (S 1 2 3)))
(test-assert "set<=? on an equal set" (set<=? (S 1) (S 1)))
(test-assert "set<=? on a superset is #f" (not (set<=? (S 1 2) (S 1))))
(test-assert "set>? on a proper superset" (set>? (S 1 2) (S 1)))
(test-assert "set>? on an equal set is #f" (not (set>? (S 1) (S 1))))
(test-assert "set>=? on an equal set" (set>=? (S 1) (S 1)))
(test-assert "set>=? on a subset is #f" (not (set>=? (S 1) (S 1 2))))
(test-assert "set-disjoint? on disjoint sets" (set-disjoint? (S 1) (S 2)))
(test-assert "set-disjoint? on overlapping sets" (not (set-disjoint? (S 1) (S 1))))
(test-assert "bag=? compares multiplicities" (bag=? (B 1 1) (B 1 1)))
(test-assert "bag=? separates differing multiplicities" (not (bag=? (B 1 1) (B 1))))
(test-assert "bag<? on a proper sub-bag" (bag<? (B 1) (B 1 1)))
(test-assert "bag<? on an equal bag is #f" (not (bag<? (B 1 1) (B 1 1))))
(test-assert "bag<=? on a sub-bag" (bag<=? (B 1) (B 1 1)))
(test-assert "bag<=? on a super-bag is #f" (not (bag<=? (B 1 1) (B 1))))
(test-assert "bag>? on a proper super-bag" (bag>? (B 1 1) (B 1)))
(test-assert "bag>? on an equal bag is #f" (not (bag>? (B 1) (B 1))))
(test-assert "bag>=? on an equal bag" (bag>=? (B 1 1) (B 1)))
(test-assert "bag>=? on a super-bag is #f" (not (bag>=? (B 1) (B 1 1))))
(test-assert "bag-disjoint? on disjoint bags" (bag-disjoint? (B 1) (B 2)))
(test-assert "bag-disjoint? on overlapping bags" (not (bag-disjoint? (B 1) (B 1))))

(let ((runner (test-runner-current)))
  (test-end "srfi113 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
