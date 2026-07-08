;; Regression test for #1158: string-contains ignores start2/end2,
;; string-replace rejects them with arity error.
(import (scheme base) (scheme write) (scheme process-context) (srfi 13) (srfi 64))

(test-begin "srfi13-start2-end2")

;;; string-contains with start2/end2
(test-equal "contains: s2 sub-range matches"
  1 (string-contains "abc" "xbcx" 0 3 1 3))
(test-equal "contains: s2 sub-range no match"
  #f (string-contains "abc" "xbcx" 0 3 0 2))
(test-equal "contains: s2 sub-range empty"
  0 (string-contains "abc" "xbcx" 0 3 2 2))
(test-equal "contains: all six args"
  2 (string-contains "XXbcXX" "YYbcYY" 2 4 2 4))
(test-equal "contains: basic (no optional args)"
  2 (string-contains "abcdef" "cd"))
(test-equal "contains: start1/end1 only"
  3 (string-contains "abcdef" "de" 2))

;;; string-replace with start2/end2
(test-equal "replace: s2 sub-range"
  "aYd" (string-replace "abcd" "XYZ" 1 3 1 2))
(test-equal "replace: s2 sub-range full"
  "aXYZd" (string-replace "abcd" "XYZ" 1 3 0 3))
(test-equal "replace: s2 sub-range empty"
  "ad" (string-replace "abcd" "XYZ" 1 3 1 1))
(test-equal "replace: basic (no start2/end2)"
  "aXYd" (string-replace "abcd" "XY" 1 3))

(let ((runner (test-runner-current)))
  (test-end "srfi13-start2-end2")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
