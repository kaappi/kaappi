;; SRFI-162 (Comparators sublibrary) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi162.scm

(import (scheme base) (scheme process-context) (srfi 128) (srfi 162) (srfi 64))

(test-begin "srfi-162")

;;; --- Pre-created comparators ---
(test-assert "default-comparator is comparator"
  (comparator? default-comparator))
(test-assert "boolean-comparator is comparator"
  (comparator? boolean-comparator))
(test-assert "real-comparator is comparator"
  (comparator? real-comparator))
(test-assert "char-comparator is comparator"
  (comparator? char-comparator))
(test-assert "char-ci-comparator is comparator"
  (comparator? char-ci-comparator))
(test-assert "string-comparator is comparator"
  (comparator? string-comparator))
(test-assert "string-ci-comparator is comparator"
  (comparator? string-ci-comparator))
(test-assert "pair-comparator is comparator"
  (comparator? pair-comparator))
(test-assert "list-comparator is comparator"
  (comparator? list-comparator))
(test-assert "vector-comparator is comparator"
  (comparator? vector-comparator))
(test-assert "eq-comparator is comparator"
  (comparator? eq-comparator))
(test-assert "eqv-comparator is comparator"
  (comparator? eqv-comparator))
(test-assert "equal-comparator is comparator"
  (comparator? equal-comparator))

;;; --- Type tests ---
(test-assert "boolean-comparator type test"
  (comparator-test-type boolean-comparator #t))
(test-assert "boolean-comparator rejects non-bool"
  (not (comparator-test-type boolean-comparator 42)))
(test-assert "real-comparator type test"
  (comparator-test-type real-comparator 3.14))
(test-assert "real-comparator rejects string"
  (not (comparator-test-type real-comparator "hi")))
(test-assert "char-comparator type test"
  (comparator-test-type char-comparator #\a))
(test-assert "string-comparator type test"
  (comparator-test-type string-comparator "hello"))

;;; --- Equality ---
(test-assert "boolean-comparator equality"
  (=? boolean-comparator #t #t))
(test-assert "boolean-comparator inequality"
  (not (=? boolean-comparator #t #f)))
(test-assert "real-comparator equality"
  (=? real-comparator 42 42))
(test-assert "string-comparator equality"
  (=? string-comparator "abc" "abc"))
(test-assert "string-ci-comparator case-insensitive"
  (=? string-ci-comparator "ABC" "abc"))
(test-assert "char-ci-comparator case-insensitive"
  (=? char-ci-comparator #\A #\a))

;;; --- Ordering ---
(test-assert "boolean ordering: #f < #t"
  (<? boolean-comparator #f #t))
(test-assert "boolean ordering: not #t < #f"
  (not (<? boolean-comparator #t #f)))
(test-assert "real ordering"
  (<? real-comparator 1 2))
(test-assert "char ordering"
  (<? char-comparator #\a #\b))
(test-assert "string ordering"
  (<? string-comparator "abc" "abd"))
(test-assert "string-ci ordering"
  (<? string-ci-comparator "abc" "ABD"))

;;; --- comparator-max / comparator-min ---
(test-equal "comparator-max: two values"
  5 (comparator-max real-comparator 3 5))
(test-equal "comparator-max: three values"
  9 (comparator-max real-comparator 3 9 1))
(test-equal "comparator-max: single value"
  7 (comparator-max real-comparator 7))
(test-equal "comparator-min: two values"
  3 (comparator-min real-comparator 3 5))
(test-equal "comparator-min: three values"
  1 (comparator-min real-comparator 3 9 1))
(test-equal "comparator-min: single value"
  7 (comparator-min real-comparator 7))

;;; --- comparator-max-in-list / comparator-min-in-list ---
(test-equal "comparator-max-in-list"
  "zebra" (comparator-max-in-list string-comparator '("apple" "zebra" "banana")))
(test-equal "comparator-min-in-list"
  "apple" (comparator-min-in-list string-comparator '("apple" "zebra" "banana")))

;;; --- Compound comparators ---
(test-assert "pair-comparator type test"
  (comparator-test-type pair-comparator '(1 . 2)))
(test-assert "list-comparator type test"
  (comparator-test-type list-comparator '(1 2 3)))
(test-assert "vector-comparator type test"
  (comparator-test-type vector-comparator #(1 2 3)))

(test-assert "list ordering: shorter < longer"
  (<? list-comparator '(1 2) '(1 2 3)))
(test-assert "list ordering: element comparison"
  (<? list-comparator '(1 2) '(1 3)))
(test-assert "vector ordering: shorter < longer"
  (<? vector-comparator #(1 2) #(1 2 3)))
(test-assert "vector ordering: element comparison"
  (<? vector-comparator #(1 2) #(1 3)))

(let ((runner (test-runner-current)))
  (test-end "srfi-162")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
