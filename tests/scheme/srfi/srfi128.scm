;; SRFI-128 (comparators) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi128.scm

(import (scheme base) (srfi 128) (scheme process-context) (srfi 64))

(test-begin "srfi-128")

;;; --- construction and accessors ---
(define num-cmp (make-comparator number? = < (lambda (x) (exact (abs (round x))))))
(test-equal #t (comparator? num-cmp))
(test-equal #f (comparator? 42))
(test-equal #t (comparator-ordered? num-cmp))
(test-equal #t (comparator-hashable? num-cmp))
(test-equal #t ((comparator-type-test-predicate num-cmp) 5))
(test-equal #f ((comparator-type-test-predicate num-cmp) 'x))
(test-equal #t ((comparator-equality-predicate num-cmp) 2 2))
(test-equal #t ((comparator-ordering-predicate num-cmp) 1 2))
(test-equal 3 ((comparator-hash-function num-cmp) 3))

;; #t as type test accepts everything; #t equality means equal?
(define univ (make-comparator #t #t #f #f))
(test-equal #t (comparator-test-type univ 'anything))
(test-equal #t ((comparator-equality-predicate univ) '(1 2) '(1 2)))
(test-equal #f (comparator-ordered? univ))
(test-equal #f (comparator-hashable? univ))

(test-equal #t (comparator-test-type num-cmp 1))
(test-equal #f (comparator-test-type num-cmp 'a))
(test-equal #t (comparator-check-type num-cmp 1))
(test-equal #t (guard (e (#t #t)) (comparator-check-type num-cmp 'a) #f))
(test-equal 4 (comparator-hash num-cmp 4))

;;; --- standard comparators ---
(test-equal #t (comparator? (make-eq-comparator)))
(test-equal #t (comparator? (make-eqv-comparator)))
(test-equal #t (comparator? (make-equal-comparator)))
(test-equal #t (=? (make-eq-comparator) 'a 'a))
(test-equal #t (=? (make-equal-comparator) '(1 2) '(1 2)))
(test-equal #f (=? (make-eq-comparator) '(1 2) '(1 2)))
(test-equal #t (comparator-hashable? (make-equal-comparator)))

;; eq/eqv comparators use default-hash so they must be hashable
(test-equal #t (comparator-hashable? (make-eq-comparator)))
(test-equal #t (comparator-hashable? (make-eqv-comparator)))

;;; --- default comparator: same-type ordering ---
(define dc (make-default-comparator))
(test-equal #t (=? dc 'a 'a))
(test-equal #t (<? dc 1 2))
(test-equal #t (<? dc "ab" "b"))
(test-equal #t (<? dc 'ant 'bee))
(test-equal #t (<? dc #\a #\b))
(test-equal #t (<? dc #f #t))
(test-equal #t (=? dc '(1 (2)) '(1 (2))))
(test-equal #t (=? dc #(1 2) #(1 2)))

;; pair ordering (lexicographic on car then cdr)
(test-equal #t (<? dc '(1 2) '(1 3)))
(test-equal #f (<? dc '(1 3) '(1 2)))
(test-equal #t (<? dc '(1) '(2)))
(test-equal #t (<? dc '(1 . 2) '(1 . 3)))
(test-equal #f (or (<? dc '(1 2) '(1 2)) (<? dc '(1 2) '(1 2))))

;; vector ordering (element-by-element, shorter first)
(test-equal #t (<? dc #(1) #(2)))
(test-equal #f (<? dc #(2) #(1)))
(test-equal #t (<? dc #(1 2) #(1 3)))
(test-equal #t (<? dc #() #(1)))
(test-equal #f (<? dc #(1) #()))
(test-equal #t (<? dc #(1) #(1 2)))

;; bytevector ordering
(test-equal #t (<? dc (bytevector 1) (bytevector 2)))
(test-equal #t (<? dc (bytevector) (bytevector 1)))
(test-equal #t (<? dc (bytevector 1 2) (bytevector 1 3)))

;; cross-type ordering (type-index determines order)
(test-equal #t (or (<? dc 'a "a") (<? dc "a" 'a)))
(test-equal #t (<? dc 42 "hello"))
(test-equal #t (<? dc #t 42))
(test-equal #t (<? dc #\z 0))
(test-equal #t (<? dc "abc" 'abc))
(test-equal #t (<? dc '(1) #(1)))

;;; --- comparison predicates ---
(test-equal #t (=? dc 3 3 3))
(test-equal #f (=? dc 3 3 4))
(test-equal #t (<? dc 1 2 3))
(test-equal #f (<? dc 1 3 2))
(test-equal #t (>? dc 3 2))
(test-equal #t (>? dc 3 2 1))
(test-equal #t (<=? dc 1 1 2))
(test-equal #f (<=? dc 2 1))
(test-equal #t (>=? dc 2 2 1))
(test-equal #f (>=? dc 1 2))

;;; --- comparator-if<=> ---
(test-equal 'less (comparator-if<=> dc 1 2 'less 'equal 'greater))
(test-equal 'equal (comparator-if<=> dc 2 2 'less 'equal 'greater))
(test-equal 'greater (comparator-if<=> dc 3 2 'less 'equal 'greater))
;; optional comparator (5-arg form uses default comparator)
(test-equal 'less (comparator-if<=> 1 2 'less 'equal 'greater))
(test-equal 'equal (comparator-if<=> 2 2 'less 'equal 'greater))
(test-equal 'greater (comparator-if<=> 3 2 'less 'equal 'greater))

;;; --- hash functions ---
(define (ok-hash? h) (and (exact-integer? h) (<= 0 h) (< h (hash-bound))))
(test-equal #t (ok-hash? (boolean-hash #t)))
(test-equal #t (ok-hash? (boolean-hash #f)))
(test-equal #t (ok-hash? (char-hash #\a)))
(test-equal #t (ok-hash? (string-hash "hello")))
(test-equal #t (ok-hash? (symbol-hash 'hello)))
(test-equal #t (ok-hash? (number-hash 42)))
(test-equal #t (ok-hash? (number-hash -42)))
(test-equal #t (ok-hash? (number-hash 3.7)))
;; pair/vector/bytevector hashes must be in [0, hash-bound)
(test-equal #t (ok-hash? (default-hash '(1 (2 . 3) #(4) "five"))))
(test-equal #t (ok-hash? (default-hash #(1 2 3))))
(test-equal #t (ok-hash? (default-hash (bytevector 1 2 3))))
(test-equal #t (ok-hash? (default-hash '(((((1))))))))
(test-equal (char-ci-hash #\A) (char-ci-hash #\a))
(test-equal (string-hash "abc") (string-ci-hash "ABC"))
;; equal objects hash equal
(test-equal (default-hash '(1 2)) (default-hash (list 1 2)))
(test-equal (default-hash #(1 2)) (default-hash (vector 1 2)))
(test-equal #t (and (exact-integer? (hash-bound)) (> (hash-bound) 0)))
(test-equal #t (and (exact-integer? (hash-salt)) (<= 0 (hash-salt)) (< (hash-salt) (hash-bound))))

;;; --- comparator-register-default! ---
(define-record-type <pt> (make-pt x) pt? (x pt-x))
(comparator-register-default!
  (make-comparator pt? (lambda (a b) (= (pt-x a) (pt-x b)))
                   (lambda (a b) (< (pt-x a) (pt-x b))) #f))
(test-equal #t (<? (make-default-comparator) (make-pt 1) (make-pt 2)))
(test-equal #f (<? (make-default-comparator) (make-pt 2) (make-pt 1)))
(test-equal #t (=? (make-default-comparator) (make-pt 3) (make-pt 3)))

;; registering an unordered comparator must not crash default ordering
(define-record-type <uq> (make-uq v) uq? (v uq-v))
(comparator-register-default!
  (make-comparator uq? (lambda (a b) (= (uq-v a) (uq-v b))) #f #f))
(test-equal #t (=? (make-default-comparator) (make-uq 1) (make-uq 1)))
(test-equal #f (<? (make-default-comparator) (make-uq 1) (make-uq 2)))

(let ((runner (test-runner-current)))
  (test-end "srfi-128")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
