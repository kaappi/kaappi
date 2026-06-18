(import (scheme base) (scheme write) (srfi 128) (srfi 146))

(define cmp (make-default-comparator))
(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name) (newline))))

(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name) (newline))))

;;; Constructors and predicates
(let ((m (mapping cmp 1 'a 2 'b 3 'c)))
  (check-true "mapping?" (mapping? m))
  (check-false "mapping? on list" (mapping? '()))
  (check-true "contains 1" (mapping-contains? m 1))
  (check-true "contains 2" (mapping-contains? m 2))
  (check-false "contains 4" (mapping-contains? m 4))
  (check "size" (mapping-size m) 3)
  (check-false "empty?" (mapping-empty? m))
  (check-true "empty? on empty" (mapping-empty? (mapping cmp))))

;;; Accessors
(let ((m (mapping cmp 1 'a 2 'b 3 'c)))
  (check "ref" (mapping-ref m 2) 'b)
  (check "ref/default found" (mapping-ref/default m 1 'z) 'a)
  (check "ref/default not found" (mapping-ref/default m 99 'z) 'z)
  (check "ref with failure" (mapping-ref m 99 (lambda () 'missing)) 'missing)
  (check "ref with success" (mapping-ref m 2 (lambda () 'x) (lambda (v) (list 'got v))) '(got b))
  (check-true "key-comparator" (comparator? (mapping-key-comparator m))))

;;; Updaters
(let ((m (mapping cmp 1 'a 2 'b)))
  (let ((m2 (mapping-set m 3 'c 2 'B)))
    (check "set new" (mapping-ref m2 3) 'c)
    (check "set replace" (mapping-ref m2 2) 'B)
    (check "original unchanged" (mapping-ref m 2) 'b))
  (let ((m3 (mapping-adjoin m 3 'c 2 'B)))
    (check "adjoin new" (mapping-ref m3 3) 'c)
    (check "adjoin no replace" (mapping-ref m3 2) 'b))
  (let ((m4 (mapping-replace m 2 'B)))
    (check "replace existing" (mapping-ref m4 2) 'B))
  (check "replace missing" (mapping-ref (mapping-replace m 99 'z) 99 (lambda () 'nope)) 'nope)
  (let ((m5 (mapping-delete m 1)))
    (check "delete" (mapping-size m5) 1)
    (check-false "deleted key" (mapping-contains? m5 1)))
  (let ((m6 (mapping-delete-all m '(1 2))))
    (check-true "delete-all empty" (mapping-empty? m6))))

;;; Update/default
(let ((m (mapping cmp 1 10)))
  (let ((m2 (mapping-update/default m 1 (lambda (v) (+ v 1)) 0)))
    (check "update/default existing" (mapping-ref m2 1) 11))
  (let ((m3 (mapping-update/default m 2 (lambda (v) (+ v 1)) 0)))
    (check "update/default new" (mapping-ref m3 2) 1)))

;;; Intern
(let ((m (mapping cmp 1 'a)))
  (let-values (((m2 val) (mapping-intern m 1 (lambda () 'z))))
    (check "intern existing val" val 'a))
  (let-values (((m3 val) (mapping-intern m 2 (lambda () 'z))))
    (check "intern new val" val 'z)
    (check "intern new in map" (mapping-ref m3 2) 'z)))

;;; Pop
(let ((m (mapping cmp 1 'a 2 'b 3 'c)))
  (let-values (((m2 key val) (mapping-pop m)))
    (check "pop key" key 1)
    (check "pop val" val 'a)
    (check "pop size" (mapping-size m2) 2)))

;;; Keys/values/entries
(let ((m (mapping cmp 3 'c 1 'a 2 'b)))
  (check "keys sorted" (mapping-keys m) '(1 2 3))
  (check "values sorted" (mapping-values m) '(a b c)))

;;; Fold and for-each
(let ((m (mapping cmp 1 10 2 20 3 30)))
  (check "fold sum values" (mapping-fold (lambda (k v acc) (+ acc v)) 0 m) 60)
  (check "fold/reverse" (mapping-fold/reverse (lambda (k v acc) (cons k acc)) '() m) '(1 2 3)))

;;; Map
(let* ((m (mapping cmp 1 10 2 20))
       (m2 (mapping-map (lambda (k v) (values k (* v 2))) cmp m)))
  (check "map" (mapping-ref m2 1) 20)
  (check "map 2" (mapping-ref m2 2) 40))

;;; Map->list
(let ((m (mapping cmp 1 'a 2 'b)))
  (check "map->list" (mapping-map->list (lambda (k v) (cons k v)) m) '((1 . a) (2 . b))))

;;; Filter and remove
(let ((m (mapping cmp 1 'a 2 'b 3 'c 4 'd)))
  (let ((m2 (mapping-filter (lambda (k v) (even? k)) m)))
    (check "filter size" (mapping-size m2) 2)
    (check-true "filter has 2" (mapping-contains? m2 2))
    (check-true "filter has 4" (mapping-contains? m2 4)))
  (let ((m3 (mapping-remove (lambda (k v) (even? k)) m)))
    (check "remove size" (mapping-size m3) 2)))

;;; Partition
(let ((m (mapping cmp 1 'a 2 'b 3 'c)))
  (let-values (((yes no) (mapping-partition (lambda (k v) (odd? k)) m)))
    (check "partition yes" (mapping-size yes) 2)
    (check "partition no" (mapping-size no) 1)))

;;; Conversion
(let ((m (mapping cmp 1 'a 2 'b)))
  (check "->alist" (mapping->alist m) '((1 . a) (2 . b)))
  (let ((m2 (alist->mapping cmp '((3 . c) (1 . x)))))
    (check "alist->mapping" (mapping-ref m2 3) 'c)
    (check "alist->mapping first wins" (mapping-ref m2 1) 'x)))

;;; Copy
(let* ((m (mapping cmp 1 'a))
       (m2 (mapping-copy m)))
  (check "copy equal" (mapping-ref m2 1) 'a))

;;; Comparisons
(let ((m1 (mapping cmp 1 'a 2 'b))
      (m2 (mapping cmp 1 'a 2 'b))
      (m3 (mapping cmp 1 'a)))
  (check-true "=?" (mapping=? cmp m1 m2))
  (check-false "=? diff" (mapping=? cmp m1 m3))
  (check-true "<?" (mapping<? cmp m3 m1))
  (check-true "<=?" (mapping<=? cmp m3 m1))
  (check-true ">=?" (mapping>=? cmp m1 m3)))

;;; Set theory
(let ((m1 (mapping cmp 1 'a 2 'b))
      (m2 (mapping cmp 2 'B 3 'c)))
  (let ((u (mapping-union m1 m2)))
    (check "union size" (mapping-size u) 3)
    (check "union keeps first" (mapping-ref u 2) 'b))
  (let ((i (mapping-intersection m1 m2)))
    (check "intersection size" (mapping-size i) 1)
    (check "intersection key" (mapping-ref i 2) 'b))
  (let ((d (mapping-difference m1 m2)))
    (check "difference size" (mapping-size d) 1)
    (check-true "difference has 1" (mapping-contains? d 1)))
  (let ((x (mapping-xor m1 m2)))
    (check "xor size" (mapping-size x) 2)
    (check-false "xor no 2" (mapping-contains? x 2))))

;;; Disjoint
(check-true "disjoint" (mapping-disjoint? (mapping cmp 1 'a) (mapping cmp 2 'b)))
(check-false "not disjoint" (mapping-disjoint? (mapping cmp 1 'a) (mapping cmp 1 'b)))

;;; Ordered operations
(let ((m (mapping cmp 1 'a 2 'b 3 'c 4 'd 5 'e)))
  (check "min-key" (mapping-min-key m) 1)
  (check "max-key" (mapping-max-key m) 5)
  (check "min-value" (mapping-min-value m) 'a)
  (check "max-value" (mapping-max-value m) 'e)
  (check "predecessor" (mapping-key-predecessor m 3 (lambda () #f)) 2)
  (check "successor" (mapping-key-successor m 3 (lambda () #f)) 4)
  (let ((r< (mapping-range< m 3)))
    (check "range< size" (mapping-size r<) 2)
    (check "range< keys" (mapping-keys r<) '(1 2)))
  (let ((r> (mapping-range> m 3)))
    (check "range> keys" (mapping-keys r>) '(4 5)))
  (let ((r<= (mapping-range<= m 3)))
    (check "range<= keys" (mapping-keys r<=) '(1 2 3)))
  (let ((r>= (mapping-range>= m 3)))
    (check "range>= keys" (mapping-keys r>=) '(3 4 5)))
  (let ((r= (mapping-range= m 3)))
    (check "range= keys" (mapping-keys r=) '(3))))

;;; Unfold
(let ((m (mapping-unfold (lambda (s) (> s 3))
                         (lambda (s) (values s (* s 10)))
                         (lambda (s) (+ s 1))
                         1 cmp)))
  (check "unfold size" (mapping-size m) 3)
  (check "unfold ref" (mapping-ref m 2) 20))

;;; Any/every/count/find
(let ((m (mapping cmp 1 10 2 20 3 30)))
  (check-true "any?" (mapping-any? (lambda (k v) (> v 25)) m))
  (check-false "every?" (mapping-every? (lambda (k v) (> v 25)) m))
  (check "count" (mapping-count (lambda (k v) (even? k)) m) 1))

;;; Comparator
(check-true "mapping-comparator" (comparator? mapping-comparator))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 146 tests failed" fail))
