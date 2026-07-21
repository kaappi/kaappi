;; SRFI-228 (Composing Comparators) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi228.scm

(import (scheme base)
        (scheme write)
        (scheme process-context)
        (srfi 1)
        (srfi 128)
        (srfi 132)
        (srfi 162)
        (srfi 228)
        (srfi 64))

(test-begin "srfi-228")

;;; ---- comparator-one ----

(test-group "comparator-one"
  (test-assert "one: accepts anything (integer)"
    ((comparator-type-test-predicate comparator-one) 42))
  (test-assert "one: accepts anything (string)"
    ((comparator-type-test-predicate comparator-one) "hello"))
  (test-assert "one: accepts anything (list)"
    ((comparator-type-test-predicate comparator-one) '(1 2 3)))
  (test-assert "one: everything equal"
    ((comparator-equality-predicate comparator-one) 1 2))
  (test-assert "one: nothing ordered"
    (not ((comparator-ordering-predicate comparator-one) 1 2)))
  (test-equal "one: hash is 0"
    0
    ((comparator-hash-function comparator-one) 42))
  (test-equal "one: hash is 0 for string"
    0
    ((comparator-hash-function comparator-one) "hello"))
  (test-assert "one: comparator-ordered?"
    (comparator-ordered? comparator-one))
  (test-assert "one: comparator-hashable?"
    (comparator-hashable? comparator-one)))

;;; ---- comparator-zero ----

(test-group "comparator-zero"
  (test-assert "zero: rejects everything (integer)"
    (not ((comparator-type-test-predicate comparator-zero) 42)))
  (test-assert "zero: rejects everything (string)"
    (not ((comparator-type-test-predicate comparator-zero) "hello")))
  (test-assert "zero: rejects everything (list)"
    (not ((comparator-type-test-predicate comparator-zero) '(1 2 3)))))

;;; ---- make-wrapper-comparator ----

(test-group "make-wrapper-comparator"
  ;; Wrap a number with abs for comparison
  (let ((abs-comparator
         (make-wrapper-comparator number? abs
           (make-comparator number? = < default-hash))))
    (test-assert "wrapper: type test passes for numbers"
      ((comparator-type-test-predicate abs-comparator) 42))
    (test-assert "wrapper: type test fails for strings"
      (not ((comparator-type-test-predicate abs-comparator) "hi")))
    (test-assert "wrapper: equality through unwrap"
      (=? abs-comparator -3 3))
    (test-assert "wrapper: inequality"
      (not (=? abs-comparator 3 4)))
    (test-assert "wrapper: ordering through unwrap"
      (<? abs-comparator -2 3))
    (test-assert "wrapper: ordering false when equal"
      (not (<? abs-comparator -3 3)))
    (test-assert "wrapper: comparator-ordered?"
      (comparator-ordered? abs-comparator))
    (test-assert "wrapper: comparator-hashable?"
      (comparator-hashable? abs-comparator)))

  ;; Wrap with car to compare by first element
  (let ((car-comparator
         (make-wrapper-comparator pair? car
           (make-comparator number? = < default-hash))))
    (test-assert "wrapper-car: equal by first element"
      (=? car-comparator '(1 a) '(1 b)))
    (test-assert "wrapper-car: less by first element"
      (<? car-comparator '(1 a) '(2 b)))
    (test-assert "wrapper-car: not less when equal"
      (not (<? car-comparator '(2 a) '(2 b))))))

;;; ---- make-product-comparator ----

(test-group "make-product-comparator"
  ;; Empty product = comparator-one
  (let ((empty-product (make-product-comparator)))
    (test-assert "product-empty: accepts anything"
      ((comparator-type-test-predicate empty-product) 42))
    (test-assert "product-empty: everything equal"
      ((comparator-equality-predicate empty-product) 1 2)))

  ;; Single comparator product
  (let ((single (make-product-comparator
                 (make-comparator number? = < default-hash))))
    (test-assert "product-single: type test"
      ((comparator-type-test-predicate single) 5))
    (test-assert "product-single: type test fails for non-number"
      (not ((comparator-type-test-predicate single) "hi")))
    (test-assert "product-single: equal"
      (=? single 3 3))
    (test-assert "product-single: not equal"
      (not (=? single 3 4)))
    (test-assert "product-single: less"
      (<? single 3 4))
    (test-assert "product-single: not less"
      (not (<? single 4 3))))

  ;; Two comparators: compare pairs by car then cdr
  (let* ((car-cmp (make-wrapper-comparator pair? car
                    (make-comparator number? = < default-hash)))
         (cdr-cmp (make-wrapper-comparator pair? cdr
                    (make-comparator number? = < default-hash)))
         (pair-cmp (make-product-comparator car-cmp cdr-cmp)))
    (test-assert "product-pair: equal when both equal"
      (=? pair-cmp '(1 . 2) '(1 . 2)))
    (test-assert "product-pair: not equal when car differs"
      (not (=? pair-cmp '(1 . 2) '(2 . 2))))
    (test-assert "product-pair: not equal when cdr differs"
      (not (=? pair-cmp '(1 . 2) '(1 . 3))))
    (test-assert "product-pair: less by car"
      (<? pair-cmp '(1 . 9) '(2 . 0)))
    (test-assert "product-pair: less by cdr when car equal"
      (<? pair-cmp '(1 . 2) '(1 . 3)))
    (test-assert "product-pair: not less when equal"
      (not (<? pair-cmp '(1 . 2) '(1 . 2))))
    (test-assert "product-pair: not less when greater"
      (not (<? pair-cmp '(2 . 0) '(1 . 9))))))

;;; ---- make-sum-comparator ----

(test-group "make-sum-comparator"
  ;; Empty sum = comparator-zero
  (let ((empty-sum (make-sum-comparator)))
    (test-assert "sum-empty: rejects everything"
      (not ((comparator-type-test-predicate empty-sum) 42))))

  ;; Sum of number and string comparators
  (let ((num-cmp (make-comparator number? = < default-hash))
        (str-cmp (make-comparator string? string=? string<? default-hash)))
    (let ((sum-cmp (make-sum-comparator num-cmp str-cmp)))
      (test-assert "sum: accepts numbers"
        ((comparator-type-test-predicate sum-cmp) 42))
      (test-assert "sum: accepts strings"
        ((comparator-type-test-predicate sum-cmp) "hello"))
      (test-assert "sum: rejects lists"
        (not ((comparator-type-test-predicate sum-cmp) '(1 2))))
      (test-assert "sum: equal numbers"
        (=? sum-cmp 3 3))
      (test-assert "sum: unequal numbers"
        (not (=? sum-cmp 3 4)))
      (test-assert "sum: equal strings"
        (=? sum-cmp "abc" "abc"))
      (test-assert "sum: unequal strings"
        (not (=? sum-cmp "abc" "def")))
      ;; Different types are not equal
      (test-assert "sum: number vs string not equal"
        (not (=? sum-cmp 3 "3")))
      ;; Ordering: numbers come before strings (first in sum)
      (test-assert "sum: number < string (type ordering)"
        (<? sum-cmp 999 "aaa"))
      (test-assert "sum: string not < number"
        (not (<? sum-cmp "aaa" 999)))
      ;; Within same type, normal ordering
      (test-assert "sum: 3 < 4"
        (<? sum-cmp 3 4))
      (test-assert "sum: abc < def"
        (<? sum-cmp "abc" "def"))
      (test-assert "sum: comparator-ordered?"
        (comparator-ordered? sum-cmp))
      (test-assert "sum: comparator-hashable?"
        (comparator-hashable? sum-cmp)))))

;;; ---- Person record tests (from reference) ----

(define-record-type Person
  (make-person first-name last-name)
  person?
  (first-name person-first-name)
  (last-name person-last-name))

(define person-name-comparator
  (make-product-comparator
   (make-wrapper-comparator person? person-last-name string-ci-comparator)
   (make-wrapper-comparator person? person-first-name string-ci-comparator)))

(test-group "person-comparator"
  (test-assert "Cowan < Preston-Kendal"
    (<? person-name-comparator
        (make-person "John" "Cowan")
        (make-person "Daphne" "Preston-Kendal")))

  (test-assert "Tom Smith > John Smith"
    (>? person-name-comparator
        (make-person "Tom" "Smith")
        (make-person "John" "Smith")))

  (test-assert "same name equal"
    (=? person-name-comparator
        (make-person "John" "Smith")
        (make-person "John" "Smith")))

  (test-assert "case-insensitive equality"
    (=? person-name-comparator
        (make-person "John" "Smith")
        (make-person "john" "smith"))))

;;; ---- Hashing ----

(test-group "hashing"
  (test-assert "case-insensitive hash equality"
    (= (comparator-hash person-name-comparator (make-person "Tom" "Smith"))
       (comparator-hash person-name-comparator (make-person "Tom" "smith"))))
  (test-assert "comparator-one hash is always 0"
    (= 0 (comparator-hash comparator-one "anything")))
  ;; Hash of wrapper should be hash of unwrapped
  (let ((abs-cmp (make-wrapper-comparator number? abs
                   (make-comparator number? = < default-hash))))
    (test-assert "wrapper hash uses unwrap"
      (= (comparator-hash abs-cmp -5)
         (comparator-hash abs-cmp 5)))))

;;; ---- Nested comparators (Book/CD from reference) ----

(define-record-type Book
  (make-book author title)
  book?
  (author book-author)
  (title book-title))

(define book-comparator
  (make-product-comparator
   (make-wrapper-comparator book? book-author person-name-comparator)
   (make-wrapper-comparator book? book-title string-ci-comparator)))

(define-record-type CD
  (make-cd artist title)
  cd?
  (artist cd-artist)
  (title cd-title))

(define cd-comparator
  (make-product-comparator
   (make-wrapper-comparator cd? cd-artist person-name-comparator)
   (make-wrapper-comparator cd? cd-title string-ci-comparator)))

(define item-comparator
  (make-sum-comparator book-comparator cd-comparator))

(test-group "nested"
  (let* ((beatles (make-person "The" "Beatles"))
         (abbey-road (make-cd beatles "Abbey Road"))
         (deutsche-grammatik
          (make-book (make-person "Jacob" "Grimm") "Deutsche Grammatik"))
         (sonnets (make-book (make-person "William" "Shakespeare") "Sonnets"))
         (mnd (make-book (make-person "William" "Shakespeare")
                         "A Midsummer Night's Dream"))
         (bob (make-cd (make-person "Bob" "Dylan") "Blonde on Blonde"))
         (revolver (make-cd (make-person "The" "Beatles") "Revolver")))

    ;; Books before CDs (sum ordering)
    (test-assert "book < cd (type ordering)"
      (<? item-comparator deutsche-grammatik abbey-road))

    ;; Within books, by author then title
    (test-assert "Grimm < Shakespeare (book author ordering)"
      (<? item-comparator deutsche-grammatik sonnets))
    (test-assert "MND < Sonnets (same author, title ordering)"
      (<? item-comparator mnd sonnets))

    ;; Within CDs, by artist then title
    (test-assert "Abbey Road < Revolver (same artist, title ordering)"
      (<? item-comparator abbey-road revolver))
    (test-assert "Beatles < Dylan (CD artist ordering)"
      (<? item-comparator abbey-road bob))

    ;; Full sort test
    (test-equal "full sort"
      (list deutsche-grammatik
            mnd
            sonnets
            abbey-road
            revolver
            bob)
      (list-sort
       (lambda (a b) (<? item-comparator a b))
       (list abbey-road
             deutsche-grammatik
             sonnets
             mnd
             bob
             revolver)))))

;;; ---- Edge cases ----

(test-group "edge-cases"
  ;; Product with no ordering
  (let* ((no-order-cmp (make-comparator number? = #f default-hash))
         (product (make-product-comparator no-order-cmp)))
    (test-assert "product with unordered: not ordered"
      (not (comparator-ordered? product)))
    (test-assert "product with unordered: still hashable"
      (comparator-hashable? product))
    (test-assert "product with unordered: equality works"
      (=? product 3 3)))

  ;; Sum with no ordering
  (let* ((no-order-cmp (make-comparator number? = #f default-hash))
         (sum (make-sum-comparator no-order-cmp)))
    (test-assert "sum with unordered: not ordered"
      (not (comparator-ordered? sum)))
    (test-assert "sum with unordered: equality works"
      (=? sum 3 3)))

  ;; Product with no hash
  (let* ((no-hash-cmp (make-comparator number? = < #f))
         (product (make-product-comparator no-hash-cmp)))
    (test-assert "product with unhashable: not hashable"
      (not (comparator-hashable? product)))
    (test-assert "product with unhashable: still ordered"
      (comparator-ordered? product)))

  ;; Sum with no hash
  (let* ((no-hash-cmp (make-comparator number? = < #f))
         (sum (make-sum-comparator no-hash-cmp)))
    (test-assert "sum with unhashable: not hashable"
      (not (comparator-hashable? sum)))
    (test-assert "sum with unhashable: still ordered"
      (comparator-ordered? sum)))

  ;; Wrapper with unordered content
  (let ((wrapper (make-wrapper-comparator number? abs
                   (make-comparator number? = #f default-hash))))
    (test-assert "wrapper with unordered content: not ordered"
      (not (comparator-ordered? wrapper)))
    (test-assert "wrapper with unordered content: hashable"
      (comparator-hashable? wrapper))
    (test-assert "wrapper with unordered content: equality works"
      (=? wrapper -3 3)))

  ;; Wrapper with unhashable content
  (let ((wrapper (make-wrapper-comparator number? abs
                   (make-comparator number? = < #f))))
    (test-assert "wrapper with unhashable content: ordered"
      (comparator-ordered? wrapper))
    (test-assert "wrapper with unhashable content: not hashable"
      (not (comparator-hashable? wrapper)))))

;;; ---- Product hash xor ----

(test-group "product-hash"
  (let* ((num-cmp (make-comparator number? = < default-hash))
         (product (make-product-comparator num-cmp num-cmp)))
    ;; Hash of product should be xor of component hashes
    (let ((h (comparator-hash product 42)))
      (test-assert "product hash is integer"
        (integer? h))
      ;; xor of same hash = 0
      (test-equal "product of identical comparators xor to 0"
        0 h))))

;;; Done

(let ((runner (test-runner-current)))
  (test-end "srfi-228")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
