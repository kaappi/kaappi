;; SRFI-128 (comparators) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi128.scm

(import (scheme base) (srfi 128) (chibi test))

(test-begin "srfi-128")

;;; --- construction and accessors ---
(define num-cmp (make-comparator number? = < (lambda (x) (exact (abs (round x))))))
(test #t (comparator? num-cmp))
(test #f (comparator? 42))
(test #t (comparator-ordered? num-cmp))
(test #t (comparator-hashable? num-cmp))
(test #t ((comparator-type-test-predicate num-cmp) 5))
(test #f ((comparator-type-test-predicate num-cmp) 'x))
(test #t ((comparator-equality-predicate num-cmp) 2 2))
(test #t ((comparator-ordering-predicate num-cmp) 1 2))
(test 3 ((comparator-hash-function num-cmp) 3))

;; #t as type test accepts everything; #t equality means equal?
(define univ (make-comparator #t #t #f #f))
(test #t (comparator-test-type univ 'anything))
(test #t ((comparator-equality-predicate univ) '(1 2) '(1 2)))
(test #f (comparator-ordered? univ))
(test #f (comparator-hashable? univ))

(test #t (comparator-test-type num-cmp 1))
(test #f (comparator-test-type num-cmp 'a))
(test #t (comparator-check-type num-cmp 1))
(test #t (guard (e (#t #t)) (comparator-check-type num-cmp 'a) #f))
(test 4 (comparator-hash num-cmp 4))

;;; --- standard comparators ---
(test #t (comparator? (make-eq-comparator)))
(test #t (comparator? (make-eqv-comparator)))
(test #t (comparator? (make-equal-comparator)))
(test #t (=? (make-eq-comparator) 'a 'a))
(test #t (=? (make-equal-comparator) '(1 2) '(1 2)))
(test #f (=? (make-eq-comparator) '(1 2) '(1 2)))
(test #t (comparator-hashable? (make-equal-comparator)))

;; eq/eqv comparators use default-hash so they must be hashable
(test #t (comparator-hashable? (make-eq-comparator)))
(test #t (comparator-hashable? (make-eqv-comparator)))

;;; --- default comparator: same-type ordering ---
(define dc (make-default-comparator))
(test #t (=? dc 'a 'a))
(test #t (<? dc 1 2))
(test #t (<? dc "ab" "b"))
(test #t (<? dc 'ant 'bee))
(test #t (<? dc #\a #\b))
(test #t (<? dc #f #t))
(test #t (=? dc '(1 (2)) '(1 (2))))
(test #t (=? dc #(1 2) #(1 2)))

;; pair ordering (lexicographic on car then cdr)
(test #t (<? dc '(1 2) '(1 3)))
(test #f (<? dc '(1 3) '(1 2)))
(test #t (<? dc '(1) '(2)))
(test #t (<? dc '(1 . 2) '(1 . 3)))
(test #f (or (<? dc '(1 2) '(1 2)) (<? dc '(1 2) '(1 2))))

;; vector ordering (element-by-element, shorter first)
(test #t (<? dc #(1) #(2)))
(test #f (<? dc #(2) #(1)))
(test #t (<? dc #(1 2) #(1 3)))
(test #t (<? dc #() #(1)))
(test #f (<? dc #(1) #()))
(test #t (<? dc #(1) #(1 2)))

;; bytevector ordering
(test #t (<? dc (bytevector 1) (bytevector 2)))
(test #t (<? dc (bytevector) (bytevector 1)))
(test #t (<? dc (bytevector 1 2) (bytevector 1 3)))

;; cross-type ordering (type-index determines order)
(test #t (or (<? dc 'a "a") (<? dc "a" 'a)))
(test #t (<? dc 42 "hello"))
(test #t (<? dc #t 42))
(test #t (<? dc #\z 0))
(test #t (<? dc "abc" 'abc))
(test #t (<? dc '(1) #(1)))

;;; --- comparison predicates ---
(test #t (=? dc 3 3 3))
(test #f (=? dc 3 3 4))
(test #t (<? dc 1 2 3))
(test #f (<? dc 1 3 2))
(test #t (>? dc 3 2))
(test #t (>? dc 3 2 1))
(test #t (<=? dc 1 1 2))
(test #f (<=? dc 2 1))
(test #t (>=? dc 2 2 1))
(test #f (>=? dc 1 2))

;;; --- comparator-if<=> ---
(test 'less (comparator-if<=> dc 1 2 'less 'equal 'greater))
(test 'equal (comparator-if<=> dc 2 2 'less 'equal 'greater))
(test 'greater (comparator-if<=> dc 3 2 'less 'equal 'greater))
;; optional comparator (5-arg form uses default comparator)
(test 'less (comparator-if<=> 1 2 'less 'equal 'greater))
(test 'equal (comparator-if<=> 2 2 'less 'equal 'greater))
(test 'greater (comparator-if<=> 3 2 'less 'equal 'greater))

;;; --- hash functions ---
(define (ok-hash? h) (and (exact-integer? h) (<= 0 h) (< h (hash-bound))))
(test #t (ok-hash? (boolean-hash #t)))
(test #t (ok-hash? (boolean-hash #f)))
(test #t (ok-hash? (char-hash #\a)))
(test #t (ok-hash? (string-hash "hello")))
(test #t (ok-hash? (symbol-hash 'hello)))
(test #t (ok-hash? (number-hash 42)))
(test #t (ok-hash? (number-hash -42)))
(test #t (ok-hash? (number-hash 3.7)))
;; pair/vector/bytevector hashes must be in [0, hash-bound)
(test #t (ok-hash? (default-hash '(1 (2 . 3) #(4) "five"))))
(test #t (ok-hash? (default-hash #(1 2 3))))
(test #t (ok-hash? (default-hash (bytevector 1 2 3))))
(test #t (ok-hash? (default-hash '(((((1))))))))
(test (char-ci-hash #\A) (char-ci-hash #\a))
(test (string-hash "abc") (string-ci-hash "ABC"))
;; equal objects hash equal
(test (default-hash '(1 2)) (default-hash (list 1 2)))
(test (default-hash #(1 2)) (default-hash (vector 1 2)))
(test #t (and (exact-integer? (hash-bound)) (> (hash-bound) 0)))
(test #t (and (exact-integer? (hash-salt)) (<= 0 (hash-salt)) (< (hash-salt) (hash-bound))))

;;; --- comparator-register-default! ---
(define-record-type <pt> (make-pt x) pt? (x pt-x))
(comparator-register-default!
  (make-comparator pt? (lambda (a b) (= (pt-x a) (pt-x b)))
                   (lambda (a b) (< (pt-x a) (pt-x b))) #f))
(test #t (<? (make-default-comparator) (make-pt 1) (make-pt 2)))
(test #f (<? (make-default-comparator) (make-pt 2) (make-pt 1)))
(test #t (=? (make-default-comparator) (make-pt 3) (make-pt 3)))

;; registering an unordered comparator must not crash default ordering
(define-record-type <uq> (make-uq v) uq? (v uq-v))
(comparator-register-default!
  (make-comparator uq? (lambda (a b) (= (uq-v a) (uq-v b))) #f #f))
(test #t (=? (make-default-comparator) (make-uq 1) (make-uq 1)))
(test #f (<? (make-default-comparator) (make-uq 1) (make-uq 2)))

(test-end "srfi-128")
